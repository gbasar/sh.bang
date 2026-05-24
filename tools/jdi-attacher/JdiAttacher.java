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
 *   java --add-modules jdk.jdi -jar jdi-attacher.jar \
 *        <host:port> <class> <method> [--condition <var>=<value>]
 *
 * Example:
 *   java --add-modules jdk.jdi -jar jdi-attacher.jar \
 *        localhost:5005 OrderEventHandler process --condition orderId=ORD-12345
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
        if (args.length < 3) {
            System.err.println("Usage: JdiAttacher <host:port> <class> <method> [--condition <var>=<value>]");
            System.err.println("Example: JdiAttacher localhost:5005 OrderEventHandler process --condition orderId=ORD-12345");
            System.exit(1);
        }

        String[] hostPort    = args[0].split(":", 2);
        String host          = hostPort[0];
        int    port          = Integer.parseInt(hostPort[1]);
        String targetClass   = args[1];
        String targetMethod  = args[2];
        String condVar       = null;
        String condValue     = null;

        for (int i = 3; i < args.length - 1; i++) {
            if ("--condition".equals(args[i])) {
                String[] kv = args[i + 1].split("=", 2);
                condVar   = kv[0];
                condValue = kv.length > 1 ? kv[1] : "";
            }
        }

        final String fCondVar   = condVar;
        final String fCondValue = condValue;

        // ---- connect --------------------------------------------------------
        AttachingConnector connector = Bootstrap.virtualMachineManager()
            .attachingConnectors().stream()
            .filter(c -> c.name().equals("com.sun.jdi.SocketAttach"))
            .findFirst()
            .orElseThrow(() -> new RuntimeException("SocketAttach connector not found — is jdk.jdi available?"));

        Map<String, Connector.Argument> params = connector.defaultArguments();
        params.get("host").setValue(host);
        params.get("port").setValue(String.valueOf(port));

        System.out.println("[jdi] connecting to " + args[0] + "...");
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
            bpr[0] = armBreakpoint(erm, loaded.get(0), targetMethod, condVar, condValue);
        } else {
            System.out.println("[jdi] " + targetClass + " not yet loaded — breakpoint will arm on class prepare");
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
                    if (bpr[0] == null) {
                        bpr[0] = armBreakpoint(erm, cpe.referenceType(), targetMethod, condVar, condValue);
                    }

                } else if (e instanceof BreakpointEvent be) {
                    if (fCondVar != null && !conditionMet(be.thread(), fCondVar, fCondValue)) {
                        // condition not satisfied — resume silently
                    } else {
                        printHit(be);
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
                                                    String condVar,
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

        String cond = condVar != null ? "  condition: " + condVar + "=" + condValue : "";
        System.out.println("[jdi] breakpoint armed: " + rt.name() + "." + methodName + "()" + cond);
        System.out.println("[jdi] waiting for hit...");
        return bpr;
    }

    private static boolean conditionMet(ThreadReference thread, String varName, String expected) {
        try {
            StackFrame frame = thread.frame(0);
            LocalVariable lv = frame.visibleVariableByName(varName);
            if (lv == null) return false;
            Value val = frame.getValue(lv);
            String actual = val instanceof StringReference sr ? sr.value() : String.valueOf(val);
            return expected.equals(actual);
        } catch (Exception ex) {
            return true; // can't evaluate — let it through
        }
    }

    private static void printHit(BreakpointEvent be) throws Exception {
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
        System.out.println("[jdi] resuming — waiting for next hit... (Ctrl+C to detach)");
    }
}
