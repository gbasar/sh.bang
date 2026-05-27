package com.bluebird.trading.utils;

import com.sun.jdi.*;
import com.sun.jdi.connect.AttachingConnector;
import com.sun.jdi.connect.Connector;
import com.sun.jdi.connect.IllegalConnectorArgumentsException;
import com.sun.jdi.event.*;
import com.sun.jdi.request.*;

import java.io.IOException;
import java.util.*;

public final class JdiAttacher {
    private static final int DEFAULT_PORT = 5005;
    private static final int DEFAULT_TRACE_LIMIT = 1000;
    private static final int DEFAULT_MAX_STRING_LEN = 1000;
    private static final int DEFAULT_FIELD_DEPTH = 2;
    private static final int DEFAULT_FIELD_MAX = 50;

    enum RenderMode {
        ID,
        STRING,
        FIELDS
    }

    static final class Options {
        String host;
        int port = DEFAULT_PORT;

        String targetClass;
        String targetMethod;

        String conditionExpr;
        String conditionValue;

        boolean traceAfterHit;
        String traceFilter;
        int traceLimit = DEFAULT_TRACE_LIMIT;
        boolean debugJdi;

        RenderMode renderMode = RenderMode.STRING;
        int maxStringLen = DEFAULT_MAX_STRING_LEN;
        int fieldDepth = DEFAULT_FIELD_DEPTH;
        int fieldMax = DEFAULT_FIELD_MAX;

        static Options parse(String[] args) {
            if (args.length < 1) {
                usageAndExit();
            }
            if ("--help".equals(args[0]) || "-h".equals(args[0])) {
                usageAndExit();
            }

            Options o = new Options();
            o.host = args[0];

            for (int i = 1; i < args.length; i++) {
                String arg = args[i];

                switch (arg) {
                    case "--port"           -> o.port          = parseInt(next(args, ++i, arg), arg);
                    case "--class"          -> o.targetClass   = next(args, ++i, arg);
                    case "--method"         -> o.targetMethod  = next(args, ++i, arg);
                    case "--condition"      -> {
                        String raw = next(args, ++i, arg);
                        String[] kv = raw.split("=", 2);
                        o.conditionExpr  = kv[0];
                        o.conditionValue = kv.length == 2 ? kv[1] : "";
                    }
                    case "--trace-after-hit" -> o.traceAfterHit = true;
                    case "--trace-filter"    -> o.traceFilter   = next(args, ++i, arg);
                    case "--trace-limit"     -> o.traceLimit    = parseInt(next(args, ++i, arg), arg);
                    case "--debug-jdi"       -> o.debugJdi      = true;
                    case "--render"          -> {
                        String mode = next(args, ++i, arg).toLowerCase(Locale.ROOT);
                        o.renderMode = switch (mode) {
                            case "id"     -> RenderMode.ID;
                            case "string" -> RenderMode.STRING;
                            case "fields" -> RenderMode.FIELDS;
                            default -> throw new IllegalArgumentException("bad --render: " + mode);
                        };
                    }
                    case "--no-stringify"    -> o.renderMode   = RenderMode.ID;
                    case "--max-string-len"  -> o.maxStringLen = parseInt(next(args, ++i, arg), arg);
                    case "--field-depth"     -> o.fieldDepth   = parseInt(next(args, ++i, arg), arg);
                    case "--field-max"       -> o.fieldMax     = parseInt(next(args, ++i, arg), arg);
                    case "--help", "-h"      -> usageAndExit();
                    default -> throw new IllegalArgumentException("unknown arg: " + arg);
                }
            }

            if (o.targetClass == null || o.targetClass.isBlank())
                throw new IllegalArgumentException("--class is required");
            if (o.conditionExpr != null && o.targetMethod == null)
                throw new IllegalArgumentException("--condition requires --method");
            if (o.traceLimit <= 0)
                throw new IllegalArgumentException("--trace-limit must be > 0");
            if (o.maxStringLen < 0)
                throw new IllegalArgumentException("--max-string-len must be >= 0");
            if (o.fieldDepth < 0)
                throw new IllegalArgumentException("--field-depth must be >= 0");
            if (o.fieldMax < 0)
                throw new IllegalArgumentException("--field-max must be >= 0");

            return o;
        }

        private static String next(String[] args, int i, String flag) {
            if (i >= args.length)
                throw new IllegalArgumentException(flag + " requires a value");
            return args[i];
        }

        private static int parseInt(String raw, String flag) {
            try {
                return Integer.parseInt(raw);
            } catch (NumberFormatException e) {
                throw new IllegalArgumentException(flag + " requires an integer: " + raw, e);
            }
        }

        private static void usageAndExit() {
            System.err.println("""
                Usage:
                  java --add-modules jdk.jdi -jar jdi-attacher.jar <host> \\
                    --class <class> [--method <method>] [--condition <expr>=<value>] \\
                    [--trace-after-hit [--trace-filter <pattern>] [--trace-limit <n>]] \\
                    [--render id|string|fields] [--field-depth <n>] [--field-max <n>] \\
                    [--debug-jdi]

                Examples:
                  jdi-attacher trading-host1 --class OrderEventHandler --method process \\
                    --condition orderId=ORD-12345

                  jdi-attacher trading-host1 --class OrderEventHandler --method process \\
                    --condition orderId=ORD-12345 \\
                    --trace-after-hit --trace-filter com.bluebird.trading.* --render fields
                """);
            System.exit(2);
        }
    }

    static final class TraceState {
        int count;
        int baseDepth = -1;
        ThreadReference thread;
        MethodEntryRequest entryRequest;
        MethodExitRequest exitRequest;
        MethodExitRequest rootExitRequest;

        boolean active() { return thread != null; }

        void disable() {
            safeDisable(entryRequest);
            safeDisable(exitRequest);
            safeDisable(rootExitRequest);
            thread = null;
        }

        private static void safeDisable(EventRequest request) {
            try { if (request != null) request.disable(); } catch (Exception ignored) {}
        }
    }

    public static void main(String[] args) throws Exception {
        System.setOut(new java.io.PrintStream(System.out, true));

        Options options;
        try {
            options = Options.parse(args);
        } catch (Exception e) {
            System.err.println("[jdi] error: " + e.getMessage());
            System.exit(2);
            return;
        }

        VirtualMachine vm = attach(options);
        System.out.println("[jdi] connected: " + vm.name() + " JVM " + vm.version());
        System.out.println("[jdi] render mode: " + options.renderMode.name().toLowerCase(Locale.ROOT));

        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.out.println("\n[jdi] detaching...");
            try { vm.dispose(); } catch (Exception ignored) {}
        }));

        EventRequestManager erm = vm.eventRequestManager();
        BreakpointRequest[] breakpoint = new BreakpointRequest[1];

        ClassPrepareRequest classPrepare = erm.createClassPrepareRequest();
        classPrepare.addClassFilter(options.targetClass);
        classPrepare.setSuspendPolicy(EventRequest.SUSPEND_ALL);
        classPrepare.enable();

        List<ReferenceType> loaded = vm.classesByName(options.targetClass);
        if (!loaded.isEmpty()) {
            if (options.targetMethod != null)
                breakpoint[0] = armBreakpoint(erm, loaded.get(0), options);
            else
                System.out.println("[jdi] class already loaded: " + loaded.get(0).name());
        } else {
            System.out.println("[jdi] " + options.targetClass + " not yet loaded"
                + (options.targetMethod != null ? " — will arm breakpoint on class prepare" : ""));
        }

        vm.resume();
        debug(options, "initial vm.resume() called");

        TraceState trace = new TraceState();
        EventQueue queue = vm.eventQueue();
        boolean shouldExit = false;

        while (!shouldExit) {
            EventSet events;
            try {
                events = queue.remove();
            } catch (InterruptedException | VMDisconnectedException e) {
                System.out.println("[jdi] disconnected");
                return;
            }

            boolean resumedInside = false;

            for (Event event : events) {
                if (event instanceof ClassPrepareEvent cpe) {
                    System.out.println("[jdi] class loaded: " + cpe.referenceType().name());
                    if (options.targetMethod != null && breakpoint[0] == null)
                        breakpoint[0] = armBreakpoint(erm, cpe.referenceType(), options);

                } else if (event instanceof BreakpointEvent be) {
                    if (options.conditionExpr != null
                            && !conditionMet(be.thread(), options.conditionExpr, options.conditionValue))
                        continue;

                    printHit(be, options);

                    if (options.traceAfterHit) {
                        if (breakpoint[0] != null) breakpoint[0].disable();
                        enableTrace(erm, trace, be.thread(), options);
                        debug(options, "after enableTrace: thread=%s suspendCount=%s",
                            threadName(be.thread()), suspendCount(be.thread()));
                        System.out.println("[jdi] tracing "
                            + (options.traceFilter == null ? "all classes" : options.traceFilter)
                            + " limit=" + options.traceLimit);
                        System.out.println();
                        events.resume();
                        debug(options, "breakpoint EventSet.resume() returned; suspendCount=%s",
                            suspendCount(trace.thread));
                        try {
                            resumeEventThread(trace.thread);
                        } catch (RuntimeException e) {
                            debug(options, "resumeEventThread at breakpoint failed: %s: %s",
                                e.getCause().getClass().getName(), e.getCause().getMessage());
                        }
                        debug(options, "after resumeEventThread at breakpoint; suspendCount=%s",
                            suspendCount(trace.thread));
                        resumedInside = true;
                        break;
                    }

                } else if (event instanceof MethodEntryEvent me) {
                    if (!trace.active()) continue;
                    if (!sameThread(me.thread(), trace.thread)) continue;
                    int depth = frameDepth(me.thread(), trace.baseDepth);
                    Method method = me.method();
                    System.out.println(indent(depth)
                        + "→ " + method.declaringType().name() + "." + method.name()
                        + formatArgs(me.thread(), options));
                    if (++trace.count >= options.traceLimit) {
                        System.out.println("[jdi] trace limit reached " + options.traceLimit);
                        trace.disable();
                        events.resume();
                        resumedInside = true;
                        shouldExit = true;
                        break;
                    }

                } else if (event instanceof MethodExitEvent mxe) {
                    if (!trace.active()) continue;
                    if (!sameThread(mxe.thread(), trace.thread)) continue;
                    int depth = frameDepth(mxe.thread(), trace.baseDepth);
                    Method method = mxe.method();
                    boolean inFilter = options.traceFilter == null
                        || classInFilter(method.declaringType().name(), options.traceFilter);
                    if (inFilter) {
                        System.out.println(indent(depth)
                            + "← " + method.declaringType().name() + "." + method.name()
                            + " = " + formatReturnValue(mxe, options));
                        trace.count++;
                    }
                    if (isTargetMethodExit(method, options)) {
                        System.out.println();
                        System.out.println("[jdi] trace complete " + trace.count + " events");
                        trace.disable();
                        events.resume();
                        resumedInside = true;
                        shouldExit = true;
                        break;
                    }
                    if (trace.count >= options.traceLimit) {
                        System.out.println("[jdi] trace limit reached " + options.traceLimit);
                        trace.disable();
                        events.resume();
                        resumedInside = true;
                        shouldExit = true;
                        break;
                    }

                } else if (event instanceof VMDeathEvent || event instanceof VMDisconnectEvent) {
                    System.out.println("[jdi] VM terminated");
                    return;
                }
            }

            if (!resumedInside) {
                events.resume();
                if (trace.active()) {
                    debug(options, "EventSet.resume() returned after trace event; suspendCount=%s",
                        suspendCount(trace.thread));
                    try {
                        resumeEventThread(trace.thread);
                    } catch (RuntimeException e) {
                        debug(options, "resumeEventThread after trace event failed: %s: %s",
                            e.getCause().getClass().getName(), e.getCause().getMessage());
                    }
                    debug(options, "after resumeEventThread trace event; suspendCount=%s",
                        suspendCount(trace.thread));
                }
            }
        }
    }

    // -------------------------------------------------------------------------

    private static VirtualMachine attach(Options options)
            throws IOException, IllegalConnectorArgumentsException {
        AttachingConnector connector = Bootstrap.virtualMachineManager()
            .attachingConnectors().stream()
            .filter(c -> c.name().equals("com.sun.jdi.SocketAttach"))
            .findFirst()
            .orElseThrow(() -> new IllegalStateException(
                "SocketAttach connector not found — is jdk.jdi available?"));
        Map<String, Connector.Argument> params = connector.defaultArguments();
        params.get("hostname").setValue(options.host);
        params.get("port").setValue(String.valueOf(options.port));
        return connector.attach(params);
    }

    private static BreakpointRequest armBreakpoint(
            EventRequestManager erm, ReferenceType type, Options options) {
        List<Method> methods = type.methodsByName(options.targetMethod);
        if (methods.isEmpty()) {
            System.err.println("[jdi] method not found: " + type.name() + "." + options.targetMethod + "()");
            return null;
        }
        BreakpointRequest req = erm.createBreakpointRequest(methods.get(0).location());
        req.setSuspendPolicy(EventRequest.SUSPEND_EVENT_THREAD);
        req.enable();
        String cond = options.conditionExpr == null ? ""
            : "  condition: " + options.conditionExpr + "=" + options.conditionValue;
        System.out.println("[jdi] breakpoint armed: " + type.name() + "." + options.targetMethod + "()" + cond);
        System.out.println("[jdi] waiting for hit...");
        return req;
    }

    private static void enableTrace(
            EventRequestManager erm, TraceState trace,
            ThreadReference thread, Options options) throws IncompatibleThreadStateException {
        trace.thread    = thread;
        trace.baseDepth = thread.frameCount();
        trace.count     = 0;
        debug(options, "enableTrace: baseDepth=%d thread=%s suspendCount=%s",
            trace.baseDepth, threadName(thread), suspendCount(thread));

        trace.entryRequest = erm.createMethodEntryRequest();
        if (options.traceFilter != null) trace.entryRequest.addClassFilter(options.traceFilter);
        trace.entryRequest.setSuspendPolicy(EventRequest.SUSPEND_EVENT_THREAD);
        trace.entryRequest.enable();

        trace.exitRequest = erm.createMethodExitRequest();
        if (options.traceFilter != null) trace.exitRequest.addClassFilter(options.traceFilter);
        trace.exitRequest.setSuspendPolicy(EventRequest.SUSPEND_EVENT_THREAD);
        trace.exitRequest.enable();

        // root class not in filter — watch its exit separately for depth==0 detection
        if (options.traceFilter != null && !classInFilter(options.targetClass, options.traceFilter)) {
            trace.rootExitRequest = erm.createMethodExitRequest();
            trace.rootExitRequest.addClassFilter(options.targetClass);
            trace.rootExitRequest.setSuspendPolicy(EventRequest.SUSPEND_EVENT_THREAD);
            trace.rootExitRequest.enable();
        }
    }

    private static void resumeEventThread(ThreadReference thread) {
        try {
            int guard = 0;
            while (thread.suspendCount() > 0 && guard++ < 4) {
                thread.resume();
            }
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private static boolean sameThread(ThreadReference actual, ThreadReference expected) {
        return expected == null || actual.uniqueID() == expected.uniqueID();
    }

    private static boolean isTargetMethodExit(Method method, Options options) {
        return method.name().equals(options.targetMethod)
            && (method.declaringType().name().equals(options.targetClass)
                || method.declaringType().name().endsWith("." + options.targetClass));
    }

    private static String suspendCount(ThreadReference thread) {
        try {
            return String.valueOf(thread.suspendCount());
        } catch (Exception e) {
            return "error(" + e.getClass().getSimpleName() + ":" + e.getMessage() + ")";
        }
    }

    private static String threadName(ThreadReference thread) {
        try {
            return thread.name() + "#" + thread.uniqueID();
        } catch (Exception e) {
            return "unknown(" + e.getClass().getSimpleName() + ":" + e.getMessage() + ")";
        }
    }

    private static void debug(Options options, String format, Object... args) {
        if (options != null && options.debugJdi) {
            System.err.println("[jdi:debug] " + String.format(Locale.ROOT, format, args));
        }
    }

    private static boolean conditionMet(ThreadReference thread, String expr, String expected) {
        try {
            StackFrame frame = thread.frame(0);
            String[] parts = expr.split("\\.", -1);
            LocalVariable local = frame.visibleVariableByName(parts[0]);
            if (local == null) return false;
            Value value = frame.getValue(local);
            for (int i = 1; i < parts.length; i++) {
                if (!(value instanceof ObjectReference object)) return false;
                Field field = object.referenceType().fieldByName(parts[i]);
                if (field == null) return false;
                value = object.getValue(field);
            }
            String actual = value instanceof StringReference sr ? sr.value() : String.valueOf(value);
            return expected.equals(actual);
        } catch (Exception e) {
            return true;
        }
    }

    private static void printHit(BreakpointEvent event, Options options) throws Exception {
        ThreadReference thread = event.thread();
        StackFrame frame = thread.frame(0);
        System.out.println("[jdi] *** BREAKPOINT HIT ***");
        System.out.println("[jdi]   thread:   " + thread.name());
        System.out.println("[jdi]   location: " + frame.location());
        // When tracing, avoid INVOKE_SINGLE_THREADED (toString()) for hit locals.
        // toString() via JDI leaves the thread with an elevated suspend count in JDK 17,
        // preventing vm.resume() from fully unblocking it. Use FIELDS instead.
        RenderMode hitRender = options.traceAfterHit ? RenderMode.FIELDS : options.renderMode;
        Options hitOptions = options;
        if (hitRender != options.renderMode) {
            hitOptions = new Options();
            hitOptions.host         = options.host;
            hitOptions.port         = options.port;
            hitOptions.targetClass  = options.targetClass;
            hitOptions.targetMethod = options.targetMethod;
            hitOptions.conditionExpr  = options.conditionExpr;
            hitOptions.conditionValue = options.conditionValue;
            hitOptions.traceAfterHit  = options.traceAfterHit;
            hitOptions.traceFilter    = options.traceFilter;
            hitOptions.traceLimit     = options.traceLimit;
            hitOptions.renderMode     = hitRender;
            hitOptions.maxStringLen   = options.maxStringLen;
            hitOptions.fieldDepth     = options.fieldDepth;
            hitOptions.fieldMax       = options.fieldMax;
        }
        try {
            for (LocalVariable variable : frame.visibleVariables()) {
                Value value = frame.getValue(variable);
                System.out.println("[jdi]   " + variable.typeName() + " " + variable.name()
                    + " = " + formatValue(value, thread, hitOptions, new HashSet<>(), hitOptions.fieldDepth));
            }
        } catch (AbsentInformationException e) {
            System.out.println("[jdi]   no variable info — recompile with javac -g");
        }
        System.out.println();
        if (!options.traceAfterHit)
            System.out.println("[jdi] resuming — waiting for next hit... (Ctrl+C to detach)");
    }

    private static String formatArgs(ThreadReference thread, Options options) {
        try {
            StackFrame frame = thread.frame(0);
            List<LocalVariable> params = frame.location().method().arguments();
            if (params.isEmpty()) return "()";
            StringBuilder sb = new StringBuilder("(");
            for (int i = 0; i < params.size(); i++) {
                if (i > 0) sb.append(", ");
                LocalVariable p = params.get(i);
                sb.append(p.name()).append("=")
                  .append(formatValue(frame.getValue(p), thread, options, new HashSet<>(), options.fieldDepth));
            }
            return sb.append(")").toString();
        } catch (AbsentInformationException e) {
            return "(?)";
        } catch (Exception e) {
            debug(options, "formatArgs failed: %s: %s", e.getClass().getName(), e.getMessage());
            return "(error=" + e.getClass().getSimpleName() + ")";
        }
    }

    private static String formatReturnValue(MethodExitEvent event, Options options) {
        try {
            return formatValue(event.returnValue(), event.thread(), options, new HashSet<>(), options.fieldDepth);
        } catch (UnsupportedOperationException e) {
            debug(options, "formatReturnValue unavailable: %s: %s", e.getClass().getName(), e.getMessage());
            return "(return value unavailable)";
        } catch (Exception e) {
            debug(options, "formatReturnValue failed: %s: %s", e.getClass().getName(), e.getMessage());
            return "(error=" + e.getClass().getSimpleName() + ")";
        }
    }

    private static String formatValue(Value value, ThreadReference thread, Options options,
                                      Set<Long> seen, int depth) {
        if (value == null)                         return "null";
        if (value instanceof VoidValue)            return "(void)";
        if (value instanceof StringReference sr)   return quote(limit(sr.value(), options.maxStringLen));
        if (value instanceof PrimitiveValue)       return value.toString();
        if (value instanceof ArrayReference arr)   return formatArray(arr, thread, options, seen, depth);
        if (value instanceof ObjectReference obj)  return switch (options.renderMode) {
            case ID     -> objectId(obj);
            case STRING -> formatObjectString(obj, thread, options);
            case FIELDS -> formatObjectFields(obj, thread, options, seen, depth);
        };
        return String.valueOf(value);
    }

    private static String formatArray(ArrayReference array, ThreadReference thread,
                                      Options options, Set<Long> seen, int depth) {
        if (!seen.add(array.uniqueID())) return array.referenceType().name() + "@cycle";
        int size = array.length();
        int lim  = Math.min(size, options.fieldMax);
        StringBuilder sb = new StringBuilder(array.referenceType().name())
            .append("[len=").append(size).append("]");
        if (depth <= 0) return sb.toString();
        sb.append("{");
        for (int i = 0; i < lim; i++) {
            if (i > 0) sb.append(", ");
            sb.append(formatValue(array.getValue(i), thread, options, seen, depth - 1));
        }
        if (size > lim) sb.append(", …");
        return sb.append("}").toString();
    }

    private static String formatObjectString(ObjectReference obj, ThreadReference thread, Options options) {
        String s = tryInvokeToString(obj, thread, options);
        return s != null ? limit(s, options.maxStringLen) : objectId(obj);
    }

    private static String formatObjectFields(ObjectReference obj, ThreadReference thread,
                                             Options options, Set<Long> seen, int depth) {
        if (isEnum(obj)) { String n = enumName(obj); if (n != null) return obj.referenceType().name() + "." + n; }
        if (!seen.add(obj.uniqueID())) return obj.referenceType().name() + "@cycle";
        if (depth <= 0) return objectId(obj);
        List<Field> fields = obj.referenceType().allFields();
        StringBuilder sb = new StringBuilder(obj.referenceType().name()).append("{");
        int written = 0;
        for (Field f : fields) {
            if (f.isStatic()) continue;
            try { if (f.isSynthetic()) continue; } catch (Exception ignored) {}
            if (written >= options.fieldMax) { sb.append(written == 0 ? "…" : ", …"); break; }
            if (written > 0) sb.append(", ");
            try {
                sb.append(f.name()).append("=")
                  .append(formatValue(obj.getValue(f), thread, options, seen, depth - 1));
            } catch (Exception e) {
                debug(options, "formatObjectFields failed field %s.%s: %s: %s",
                    obj.referenceType().name(), f.name(), e.getClass().getName(), e.getMessage());
                sb.append(f.name()).append("=<").append(e.getClass().getSimpleName()).append(">");
            }
            written++;
        }
        return sb.append("}").toString();
    }

    private static String tryInvokeToString(ObjectReference obj, ThreadReference thread, Options options) {
        try {
            if (!(obj.referenceType() instanceof ClassType ct)) return null;
            Method toString = ct.allMethods().stream()
                .filter(m -> m.name().equals("toString") && m.signature().equals("()Ljava/lang/String;") && !m.isAbstract())
                .findFirst().orElse(null);
            if (toString == null) return null;
            Value result = obj.invokeMethod(thread, toString, Collections.emptyList(), ObjectReference.INVOKE_SINGLE_THREADED);
            return result instanceof StringReference sr ? sr.value() : null;
        } catch (Exception e) {
            debug(options, "tryInvokeToString failed for %s: %s: %s",
                obj.referenceType().name(), e.getClass().getName(), e.getMessage());
            return null;
        }
    }

    private static boolean isEnum(ObjectReference obj) {
        ReferenceType type = obj.referenceType();
        while (type instanceof ClassType ct) {
            if ("java.lang.Enum".equals(ct.name())) return true;
            try { type = ct.superclass(); } catch (Exception e) { return false; }
        }
        return false;
    }

    private static String enumName(ObjectReference obj) {
        try {
            Field f = obj.referenceType().fieldByName("name");
            if (f == null) return null;
            Value v = obj.getValue(f);
            return v instanceof StringReference sr ? sr.value() : null;
        } catch (Exception e) { return null; }
    }

    private static int frameDepth(ThreadReference thread, int baseDepth) {
        try { return Math.max(0, thread.frameCount() - baseDepth); } catch (Exception e) { return 0; }
    }

    private static boolean classInFilter(String className, String filter) {
        if (filter.endsWith(".*")) {
            String pkg = filter.substring(0, filter.length() - 2);
            return className.equals(pkg) || className.startsWith(pkg + ".");
        }
        return className.equals(filter);
    }

    private static String objectId(ObjectReference obj) {
        return obj.referenceType().name() + "@" + Long.toHexString(obj.uniqueID());
    }

    private static String indent(int depth) { return "  ".repeat(Math.max(0, depth)); }

    private static String quote(String s) {
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"")
                        .replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t") + "\"";
    }

    private static String limit(String s, int max) {
        if (max < 0 || s.length() <= max) return s;
        return s.substring(0, max) + "…";
    }

    private JdiAttacher() {}
}
