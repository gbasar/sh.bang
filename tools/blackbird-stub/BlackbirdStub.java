import java.io.*;
import java.nio.file.*;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * BlackbirdStub — simulates the Blackbird trading application startup sequence.
 *
 * Startup phases (same order as the real app):
 *   1. Static data load  — simulates loading products, instruments, etc.
 *   2. Event sourcing recovery — reads trading.rdat.in if present, replays
 *      through OrderEventHandler to rebuild state (no outbound messages sent)
 *   3. Ready — waits for live inbound messages (NewOrderSingle, etc.)
 *
 * JDWP is NOT baked in. Inject via the start script:
 *   java -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005 \
 *        -jar blackbird-stub.jar [txn-log-dir]
 *
 * Args:
 *   [0] optional path to txn-log directory (default: ./data/trading/txn-log)
 */
public class BlackbirdStub {

    private static final int STATIC_DATA_PRODUCTS = 20;
    private static final long STATIC_DATA_DELAY_MS = 50;
    private static final long HEARTBEAT_INTERVAL_S = 10;

    public static void main(String[] args) throws Exception {
        String txnLogDir = args.length > 0 ? args[0] : "data/trading/txn-log";

        System.out.println("[blackbird-stub] starting up");
        System.out.println("[blackbird-stub] txn-log: " + txnLogDir);

        // Phase 1 — static data load
        loadStaticData();

        // Phase 2 — event sourcing recovery
        OrderEventHandler handler = new OrderEventHandler();
        recover(txnLogDir, handler);

        // Phase 3 — ready, wait for live messages
        ready();
    }

    // -------------------------------------------------------------------------
    // Phase 1: Static data load
    // -------------------------------------------------------------------------
    private static void loadStaticData() throws InterruptedException {
        System.out.println("[blackbird-stub] loading static data...");
        for (int i = 1; i <= STATIC_DATA_PRODUCTS; i++) {
            System.out.printf("  loaded product_%03d%n", i);
            Thread.sleep(STATIC_DATA_DELAY_MS);
        }
        System.out.println("[blackbird-stub] static data loaded ("
                + STATIC_DATA_PRODUCTS + " products)");
    }

    // -------------------------------------------------------------------------
    // Phase 2: Event sourcing recovery from rdat.in
    // -------------------------------------------------------------------------
    private static void recover(String txnLogDir, OrderEventHandler handler) throws IOException {
        Path rdatIn = Paths.get(txnLogDir, "trading.rdat.in");

        if (!Files.exists(rdatIn)) {
            System.out.println("[blackbird-stub] no rdat.in found — clean startup");
            return;
        }

        System.out.println("[blackbird-stub] rdat.in detected — recovering state from transaction log...");
        System.out.println("[blackbird-stub] note: no outbound messages sent during recovery");

        int count = 0;
        try (BufferedReader reader = Files.newBufferedReader(rdatIn)) {
            String line;
            while ((line = reader.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty()) continue;

                // Extract orderId — expect lines like "ORD-12345 <payload>"
                // or just a bare orderId for simple fixtures
                String[] parts = line.split("\\s+", 2);
                String orderId = parts[0];
                String payload = parts.length > 1 ? parts[1] : "";

                // This is the breakpoint target — developers stop here
                // with a condition like: orderId.equals("ORD-12345")
                handler.process(orderId, payload);
                count++;
            }
        }

        System.out.println("[blackbird-stub] recovery complete ("
                + count + " events replayed, state rebuilt)");
    }

    // -------------------------------------------------------------------------
    // Phase 3: Ready — simulate waiting for live inbound messages
    // -------------------------------------------------------------------------
    private static void ready() throws InterruptedException {
        System.out.println("[blackbird-stub] waiting for messages (NewOrderSingle, etc.)...");
        System.out.println("[blackbird-stub] attach debugger on configured JDWP port if needed");

        AtomicInteger tick = new AtomicInteger(0);
        while (true) {
            Thread.sleep(1000);
            int t = tick.incrementAndGet();
            if (t % HEARTBEAT_INTERVAL_S == 0) {
                System.out.println("  [heartbeat] shard alive  uptime=" + t + "s");
            }
        }
    }
}
