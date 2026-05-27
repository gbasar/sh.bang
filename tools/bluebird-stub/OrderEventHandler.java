package com.bluebird.trading;

/**
 * OrderEventHandler — processes inbound order events during recovery and live trading.
 *
 * This is the class a developer would set a JDI breakpoint on when investigating
 * order processing bugs. The process() method is called for every event in the
 * transaction log during recovery, and for every live inbound message thereafter.
 */
public class OrderEventHandler {

    private int processedCount = 0;

    /**
     * Process a single order event.
     * Primary breakpoint target — orderId is kept as an explicit first param so
     * jdi-attacher --condition orderId=ORD-12345 matches a local variable directly.
     *
     * @param orderId  the order identifier (e.g. "ORD-12345")
     * @param msg      the fully parsed order event
     */
    public void process(String orderId, OrderEventMessage msg) {
        processedCount++;
        if (!validate(msg)) return;
        buildState(msg);
    }

    private boolean validate(OrderEventMessage msg) {
        if (msg.orderId == null || msg.orderId.isEmpty()) return false;
        if (!"BUY".equals(msg.side) && !"SELL".equals(msg.side)) return false;
        if (msg.qty <= 0)   return false;
        if (msg.price <= 0) return false;
        return true;
    }

    private void buildState(OrderEventMessage msg) {
        double notional = computeNotional(msg.qty, msg.price);
        checkRisk(msg.orderId, notional);
    }

    private double computeNotional(int qty, double price) {
        return qty * price;
    }

    private void checkRisk(String orderId, double notional) {
        // placeholder: real app checks position limits here
    }

    public int getProcessedCount() { return processedCount; }
}
