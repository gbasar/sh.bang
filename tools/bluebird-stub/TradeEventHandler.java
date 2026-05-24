/**
 * TradeEventHandler — processes trade execution events during recovery and live trading.
 *
 * Handles ExecutionReport messages — fills, partial fills, cancellations.
 * Called alongside OrderEventHandler during rdat.in recovery and for
 * live inbound messages once the app is running.
 *
 * Breakpoint target for debugging trade processing issues:
 *   SetBreakpoint --class TradeEventHandler --method process
 *   --condition "tradeId.equals(\"TRD-12345\")"
 */
public class TradeEventHandler {

    private int processedCount = 0;

    /**
     * Process a single trade execution event.
     *
     * @param tradeId  the trade/execution identifier
     * @param payload  the raw event payload
     */
    public void process(String tradeId, String payload) {
        processedCount++;
    }

    public int getProcessedCount() {
        return processedCount;
    }
}
