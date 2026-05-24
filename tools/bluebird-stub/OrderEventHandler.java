/**
 * OrderEventHandler — processes inbound order events during recovery and live trading.
 *
 * This is the class a developer would set a JDI breakpoint on when investigating
 * order processing bugs. The process() method is called for every event in the
 * transaction log during recovery, and for every live inbound message thereafter.
 *
 * To break on a specific order:
 *   SetBreakpoint --class OrderEventHandler --method process --condition "orderId.equals(\"ORD-12345\")"
 */
public class OrderEventHandler {

    private int processedCount = 0;

    /**
     * Process a single order event.
     * This is the primary breakpoint target for debugging order issues.
     *
     * @param orderId  the order identifier (e.g. "ORD-12345")
     * @param payload  the raw event payload from the transaction log
     */
    public void process(String orderId, String payload) {
        processedCount++;
        // In the real app this is where order state is built/updated.
        // Developers set breakpoints here with orderId conditions to
        // isolate specific orders without stepping through thousands of others.
    }

    public int getProcessedCount() {
        return processedCount;
    }
}
