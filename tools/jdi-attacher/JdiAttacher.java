import com.sun.jdi.*;
import com.sun.jdi.connect.*;
import com.sun.jdi.event.*;
import com.sun.jdi.request.*;

import java.util.*;

/**
 * JdiAttacher — connects to a running JVM via JDWP and arms a conditional breakpoint.
 *
 * Stays connected and waits for hits. On each hit that satisfies the condition,
 * prints the thread, location, and local variables, then resumes. Ctrl+C detaches.
 *
 * Usage:
 *   java --add-modules jdk.jdi -jar jdi-attacher.jar <host:port> \
 *        [--class <class>] [--method <method>] [--condition <expr>=<value>] [--hand-off]
 *
 * Examples:
 *   # break on class load
 *   jdi-attacher localhost:5005 --class OrderEventHandler
 *
 *   # break on method entry
 *   jdi-attacher localhost:5005 --class OrderEventHandler --method process
 *
 *   # conditional — local variable
 *   jdi-attacher localhost:5005 --class OrderEventHandler --method process \
 *                --condition orderId=ORD-12345
 *
 *   # conditional — field on object parameter
 *   jdi-attacher localhost:5005 --class TradeEventHandler --method process \
 *                --condition m.tradeId=TRD-12345
 *
 *   # conditional — deep field chain
 *   jdi-attacher localhost:5005 --class TradeEventHandler --method process \
 *                --condition m.order.instrumentId=TSLA
 *
 * Notes:
 *   - Requires JDK (not just JRE) — com.sun.jdi is in the jdk.jdi module.
 *   - The target JVM must be started with suspend=n JDWP so it runs while we attach.
 *   - If the target class is not yet loaded when we attach, the breakpoint is deferred
 *     and armed automatically when the class is prepared.
 *   - Condition is evaluated client-side: breakpoint fires on every call, hits that
 *     don't match the condition are resumed immediately and silently.
 */
public class JdiAttacher {

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("Usage: JdiAttacher <host:port> [--class <class>] [--method <method>] [--condition <expr>=<value>]");
            System.exit(1);
        }

        String[] hostPort    = args[0].split(":", 2);
        String host          = hostPort[0];
        int    port          = Integer.parseInt(hostPort[1]);
        String  targetClass   = null;
        String  targetMethod  = null;
        String  condExpr      = null;
        String  condValue     = null;
        boolean handOff       = false;

        for (int i = 1; i < args.length; i++) {
            switch (args[i]) {
                case "--class"     -> targetClass  = args[++i];
                case "--method"    -> targetMethod = args[++i];
                case "--condition" -> {
                    String[] kv = args[++i].split("=", 2);
                    condExpr  = kv[0];
                    condValue = kv.length > 1 ? kv[1] : "";
                }
                case "--hand-off"  -> handOff = true;
            }
        }

        if (targetClass == null) {
            System.err.println("[jdi] error: --class is required");
            System.exit(1);
        }
        if (condExpr != null && targetMethod == null) {
            System.err.println("[jdi] error: --condition requires --method");
            System.exit(1);
        }

        final String  fCondExpr  = condExpr;
        final String  fCondValue = condValue;
        final boolean fHandOff   = handOff;

        // ---- connect --------------------------------------------------------
        AttachingConnector connector = Bootstrap.virtualMachineManager()
            .attachingConnectors().stream()
            .filter(c -> c.name().equals("com.sun.jdi.SocketAttach"))
            .findFirst()
            .orElseThrow(() -> new RuntimeException("SocketAttach connector not found — is jdk.jdi available?"));

        Map<String, Connector.Argument> params = connector.defaultArguments();
        params.get("hostname").setValue(host);
        params.get("port").setValue(String.valueOf(port));


        VirtualMachine vm = connector.attach(params);
        System.out.println("[jdi] connected: " + vm.name() + " (JVM " + vm.version() + ")");

        // ---- register ClassPrepare so we can arm the breakpoint if the class
        //      loads after we attach (common for lazy-loaded handlers) ----------
        EventRequestManager erm = vm.eventRequestManager();
        ClassPrepareRequest cpr = erm.createClassPrepareRequest();
        cpr.addClassFilter(targetClass);
        cpr.setSuspendPolicy(EventRequest.SUSPEND_ALL);
        cpr.enable();

        // ---- arm immediately if class already loaded -------------------------
        BreakpointRequest[] bpr = {null};
        List<ReferenceType> loaded = vm.classesByName(targetClass);
        if (!loaded.isEmpty()) {
            if (targetMethod != null) {
                bpr[0] = armBreakpoint(erm, loaded.get(0), targetMethod, condExpr, condValue);
            } else {
                System.out.println("[jdi] class already loaded: " + loaded.get(0).name());
            }
        } else {
            System.out.println("[jdi] " + targetClass + " not yet loaded — will report on class prepare"
                    + (targetMethod != null ? " and arm breakpoint" : ""));
        }

        vm.resume();

        // ---- shutdown hook: detach cleanly on Ctrl+C ------------------------
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.out.println("\n[jdi] detaching...");
            try { vm.dispose(); } catch (Exception ignored) {}
        }));

        // ---- event loop -----------------------------------------------------
        EventQueue eq = vm.eventQueue();
        while (true) {
            EventSet events;
            try {
                events = eq.remove();
            } catch (InterruptedException | VMDisconnectedException e) {
                System.out.println("[jdi] disconnected");
                return;
            }

            for (Event e : events) {
                if (e instanceof ClassPrepareEvent cpe) {
                    System.out.println("[jdi] class loaded: " + cpe.referenceType().name());
                    if (targetMethod != null && bpr[0] == null) {
                        bpr[0] = armBreakpoint(erm, cpe.referenceType(), targetMethod, condExpr, condValue);
                    }

                } else if (e instanceof BreakpointEvent be) {
                    if (fCondExpr != null && !conditionMet(be.thread(), fCondExpr, fCondValue)) {
                        // condition not satisfied — resume silently
                    } else {
                        printHit(be, fHandOff, host, port);
                        if (fHandOff) {
                            vm.dispose();
                            return;
                        }
                    }

                } else if (e instanceof VMDeathEvent || e instanceof VMDisconnectEvent) {
                    System.out.println("[jdi] VM terminated");
                    return;
                }
            }
            events.resume();
        }
    }

    // -------------------------------------------------------------------------

    private static BreakpointRequest armBreakpoint(EventRequestManager erm,
                                                    ReferenceType rt,
                                                    String methodName,
                                                    String condExpr,
                                                    String condValue) {
        List<Method> methods = rt.methodsByName(methodName);
        if (methods.isEmpty()) {
            System.err.println("[jdi] method not found: " + rt.name() + "." + methodName + "()");
            return null;
        }
        Location loc = methods.get(0).location();
        BreakpointRequest bpr = erm.createBreakpointRequest(loc);
        bpr.setSuspendPolicy(EventRequest.SUSPEND_EVENT_THREAD);
        bpr.enable();

        String cond = condExpr != null ? "  condition: " + condExpr + "=" + condValue : "";
        System.out.println("[jdi] breakpoint armed: " + rt.name() + "." + methodName + "()" + cond);
        System.out.println("[jdi] waiting for hit...");
        return bpr;
    }

    /**
     * Evaluates a condition of the form "expr=value" against the current frame.
     *
     * expr can be:
     *   orderId              — local variable / parameter (String or primitive)
     *   m.tradeId            — field on a local object parameter
     *   m.order.instrumentId — arbitrarily deep field chain
     */
    private static boolean conditionMet(ThreadReference thread, String expr, String expected) {
        try {
            StackFrame frame = thread.frame(0);
            String[] parts = expr.split("\\.", -1);

            // resolve the root local variable
            LocalVariable lv = frame.visibleVariableByName(parts[0]);
            if (lv == null) return false;
            Value val = frame.getValue(lv);

            // walk any remaining field segments
            for (int i = 1; i < parts.length; i++) {
                if (!(val instanceof ObjectReference obj)) return false;
                Field field = obj.referenceType().fieldByName(parts[i]);
                if (field == null) return false;
                val = obj.getValue(field);
            }

            String actual = val instanceof StringReference sr ? sr.value() : String.valueOf(val);
            return expected.equals(actual);
        } catch (Exception ex) {
            return true; // can't evaluate — let it through
        }
    }

    private static void printHit(BreakpointEvent be, boolean handOff,
                                  String host, int port) throws Exception {
        ThreadReference thread = be.thread();
        StackFrame frame = thread.frame(0);

        System.out.println("[jdi] *** BREAKPOINT HIT ***");
        System.out.println("[jdi]   thread:   " + thread.name());
        System.out.println("[jdi]   location: " + frame.location());
        try {
            for (LocalVariable lv : frame.visibleVariables()) {
                Value v = frame.getValue(lv);
                String display = v instanceof StringReference sr
                    ? "\"" + sr.value() + "\""
                    : String.valueOf(v);
                System.out.println("[jdi]   " + lv.typeName() + " " + lv.name() + " = " + display);
            }
        } catch (AbsentInformationException ex) {
            System.out.println("[jdi]   (no variable info — recompile target with javac -g)");
        }

        if (handOff) {
            System.out.println("[jdi]");
            System.out.println("[jdi] app suspended — attach your debugger:");
            System.out.println("[jdi]   host : " + host);
            System.out.println("[jdi]   port : " + port);
            System.out.println("[jdi]   IntelliJ: Run > Attach to Process > " + host + ":" + port);
            System.out.println("[jdi] detaching (app remains suspended)...");
        } else {
            System.out.println("[jdi] resuming — waiting for next hit... (Ctrl+C to detach)");
        }
    }
}
