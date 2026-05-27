package com.bluebird.trading;

/**
 * OrderEventMessage — parsed representation of a NewOrderSingle event.
 *
 * Created from the raw rdat payload by BluebirdStub before dispatch to
 * OrderEventHandler. Fields are public-final so jdi-attacher --render fields
 * shows them all at the breakpoint without invoking any methods.
 */
public class OrderEventMessage {

    public final String orderId;
    public final String instrument;
    public final String side;
    public final int    qty;
    public final double price;

    public OrderEventMessage(String orderId, String instrument, String side, int qty, double price) {
        this.orderId    = orderId;
        this.instrument = instrument;
        this.side       = side;
        this.qty        = qty;
        this.price      = price;
    }

    public static OrderEventMessage parse(String orderId, String payload) {
        return new OrderEventMessage(
            orderId,
            parseField(payload, "instrument"),
            parseField(payload, "side"),
            parseInt(parseField(payload, "qty")),
            parseDouble(parseField(payload, "price"))
        );
    }

    @Override
    public String toString() {
        return "OrderEventMessage{orderId=" + orderId + ", instrument=" + instrument
             + ", side=" + side + ", qty=" + qty + ", price=" + price + "}";
    }

    private static String parseField(String payload, String key) {
        for (String token : payload.split(" ")) {
            if (token.startsWith(key + "=")) return token.substring(key.length() + 1);
        }
        return "";
    }

    private static int parseInt(String s) {
        try { return Integer.parseInt(s); } catch (NumberFormatException e) { return 0; }
    }

    private static double parseDouble(String s) {
        try { return Double.parseDouble(s); } catch (NumberFormatException e) { return 0.0; }
    }
}
