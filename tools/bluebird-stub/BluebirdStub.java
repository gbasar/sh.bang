import java.io.*;
import java.nio.file.*;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * BluebirdStub — simulates the Bluebird trading application startup sequence.
 *
 * In Bluebird everything arrives via messages — even static reference data.
 * Startup phases (same order as the real app):
 *
 *   1. Static data load  — StaticDataHandler processes product/instrument records
 *   2. Event sourcing recovery — reads trading.rdat.in if present, replays through
 *      OrderEventHandler and TradeEventHandler to rebuild state (no outbound messages)
 *   3. Ready — waits for live inbound messages (NewOrderSingle, ExecutionReport, etc.)
 *
 * JDWP is NOT baked in. Inject via the start script:
 *   java -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005 \
 *        -jar bluebird-stub.jar [txn-log-dir]
 *
 * Args:
 *   [0] optional path to txn-log directory (default: ./data/trading/txn-log)
 */
public class BluebirdStub {

    private static final int STATIC_DATA_PRODUCTS = 20;
    private static final long STATIC_DATA_DELAY_MS = 50;
    private static final long HEARTBEAT_INTERVAL_S = 10;

    public static void main(String[] args) throws Exception {
        String txnLogDir = args.length > 0 ? args[0] : "data/trading/txn-log";

        System.out.println("[bluebird-stub] starting up");
        System.out.println("[bluebird-stub] txn-log: " + txnLogDir);

        // Phase 1 — static data load (all via messages in the real app)
        loadStaticData();

        // Phase 2 — event sourcing recovery
        OrderEventHandler orderHandler = new OrderEventHandler();
        TradeEventHandler tradeHandler = new TradeEventHandler();
        recover(txnLogDir, orderHandler, tradeHandler);

        // Phase 3 — ready, wait for live messages
        ready();
    }

    // -------------------------------------------------------------------------
    // Phase 1: Static data load — all product/instrument data arrives as messages
    // -------------------------------------------------------------------------
    private static void loadStaticData() throws InterruptedException {
        StaticDataHandler handler = new StaticDataHandler();
        System.out.println("[bluebird-stub] loading static data...");
        for (int i = 1; i <= STATIC_DATA_PRODUCTS; i++) {
            String productId = String.format("product_%03d", i);
            handler.load(productId, "type=EQUITY exchange=LSE");
            Thread.sleep(STATIC_DATA_DELAY_MS);
        }
        System.out.println("[bluebird-stub] static data loaded ("
                + handler.getLoadedCount() + " products)");
    }

    // -------------------------------------------------------------------------
    // Phase 2: Event sourcing recovery from rdat.in
    // Orders go to OrderEventHandler, execution reports to TradeEventHandler.
    // -------------------------------------------------------------------------
    private static void recover(String txnLogDir,
                                OrderEventHandler orderHandler,
                                TradeEventHandler tradeHandler) throws IOException {
        Path rdatIn = Paths.get(txnLogDir, "trading.rdat.in");

        if (!Files.exists(rdatIn)) {
            System.out.println("[bluebird-stub] no rdat.in found — clean startup");
            return;
        }

        System.out.println("[bluebird-stub] rdat.in detected — recovering state from transaction log...");
        System.out.println("[bluebird-stub] note: no outbound messages sent during recovery");

        int count = 0;
        try (BufferedReader reader = Files.newBufferedReader(rdatIn)) {
            String line;
            while ((line = reader.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty()) continue;

                String[] parts = line.split("\\s+", 3);
                String id      = parts[0];
                String msgType = parts.length > 1 ? parts[1] : "";
                String payload = parts.length > 2 ? parts[2] : "";

                System.out.println("  replayed: " + line);
                if (msgType.startsWith("ExecutionReport")) {
                    tradeHandler.process(id, payload);
                } else {
                    // NewOrderSingle and anything else
                    orderHandler.process(id, payload);
                }
                count++;
            }
        }

        System.out.println("[bluebird-stub] recovery complete ("
                + count + " events — "
                + orderHandler.getProcessedCount() + " orders, "
                + tradeHandler.getProcessedCount() + " trades)");
    }

    // -------------------------------------------------------------------------
    // Phase 3: Ready — simulate waiting for live inbound messages
    // -------------------------------------------------------------------------
    private static void ready() throws InterruptedException {
        System.out.println("[bluebird-stub] waiting for messages (NewOrderSingle, ExecutionReport, etc.)...");
        System.out.println("[bluebird-stub] attach debugger on configured JDWP port if needed");

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
