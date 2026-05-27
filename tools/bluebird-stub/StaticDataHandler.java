package com.bluebird.trading;

/**
 * StaticDataHandler — processes static data messages during startup.
 *
 * In the real Bluebird app all data arrives via messages — even static
 * reference data (products, instruments, counterparties) is received as
 * inbound events and processed here before the app accepts live orders.
 *
 * Breakpoint target for debugging static data loading issues:
 *   SetBreakpoint --class StaticDataHandler --method load
 *   --condition "productId.equals(\"PROD-999\")"
 */
public class StaticDataHandler {

    private int loadedCount = 0;

    /**
     * Load a single static data record.
     *
     * @param productId  the product/instrument identifier
     * @param payload    the raw static data payload
     */
    public void load(String productId, String payload) {
        loadedCount++;
        System.out.println("  loaded " + productId);
    }

    public int getLoadedCount() {
        return loadedCount;
    }
}
