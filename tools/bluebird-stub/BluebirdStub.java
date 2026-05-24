import java.io.*;
import java.nio.file.*;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * BluebirdStub — simulates the Bluebird trading application startup sequence.
 *
 * In Bluebird everything arrives via messages — even static reference data.
 * All startup events are read from trading.rdat.in in order:
 *
 *   Phase 1 — Static data load
 *     StaticData lines processed by StaticDataHandler (sleeps briefly per record
 *     to simulate the real app's load time — go get coffee)
 *
 *   Phase 2 — Event sourcing recovery
 *     NewOrderSingle → OrderEventHandler
 *     ExecutionReport → TradeEventHandler
 *     (no outbound messages during recovery — state is rebuilt silently)
 *
 *   Phase 3 — Ready
 *     App waits for live inbound messages. JDWP is open; attach debugger at leisure.
 *     The breakpoint on OrderEventHandler.process() will fire on the very next order.
 *
 * JDWP is NOT baked in. Inject via the start script:
 *   java -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005 \
 *        -jar bluebird-stub.jar [txn-log-dir]
 *
 * Args:
 *   [0] optional path to txn-log directory (default: ./data/trading/txn-log)
 */
public class BluebirdStub {

    private static final long STATIC_DATA_DELAY_MS = 500;
    private static final long HEARTBEAT_INTERVAL_S = 10;

    public static void main(String[] args) throws Exception {
        String txnLogDir = args.length > 0 ? args[0] : "data/trading/txn-log";

        System.out.println("[bluebird-stub] starting up");
        System.out.println("[bluebird-stub] txn-log: " + txnLogDir);

        StaticDataHandler staticHandler = new StaticDataHandler();
        OrderEventHandler orderHandler  = new OrderEventHandler();
        TradeEventHandler tradeHandler  = new TradeEventHandler();

        recover(txnLogDir, staticHandler, orderHandler, tradeHandler);

        ready();
    }

    // -------------------------------------------------------------------------
    // Recovery: reads rdat.in top-to-bottom.
    //   StaticData lines    -> StaticDataHandler  (with artificial delay)
    //   ExecutionReport     -> TradeEventHandler
    //   everything else     -> OrderEventHandler
    // -------------------------------------------------------------------------
    private static void recover(String txnLogDir,
                                StaticDataHandler staticHandler,
                                OrderEventHandler orderHandler,
                                TradeEventHandler tradeHandler) throws Exception {
        Path rdatIn = Paths.get(txnLogDir, "trading.rdat.in");

        if (!Files.exists(rdatIn)) {
            System.out.println("[bluebird-stub] no rdat.in found — clean startup");
            return;
        }

        System.out.println("[bluebird-stub] rdat.in detected — replaying transaction log...");
        System.out.println("[bluebird-stub] loading static data (grab a coffee)...");

        int orders = 0, trades = 0;
        boolean staticDone = false;

        try (BufferedReader reader = Files.newBufferedReader(rdatIn)) {
            String line;
            while ((line = reader.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty()) continue;

                String[] parts   = line.split("\\s+", 3);
                String id        = parts[0];
                String msgType   = parts.length > 1 ? parts[1] : "";
                String payload   = parts.length > 2 ? parts[2] : "";

                if (msgType.equals("StaticData")) {
                    staticHandler.load(id, payload);
                    Thread.sleep(STATIC_DATA_DELAY_MS);
                } else {
                    if (!staticDone) {
                        System.out.println("[bluebird-stub] static data loaded ("
                                + staticHandler.getLoadedCount() + " records)");
                        System.out.println("[bluebird-stub] recovering order/trade state...");
                        System.out.println("[bluebird-stub] note: no outbound messages sent during recovery");
                        staticDone = true;
                    }
                    System.out.println("  replayed: " + line);
                    if (msgType.startsWith("ExecutionReport")) {
                        tradeHandler.process(id, payload);
                        trades++;
                    } else {
                        orderHandler.process(id, payload);
                        orders++;
                    }
                }
            }
        }

        if (!staticDone) {
            // rdat.in contained only static data (or was empty after trim)
            System.out.println("[bluebird-stub] static data loaded ("
                    + staticHandler.getLoadedCount() + " records)");
        }

        System.out.println("[bluebird-stub] recovery complete ("
                + orders + " orders, " + trades + " trades)");
    }

    // -------------------------------------------------------------------------
    // Phase 3: Ready — waiting for live inbound messages
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
