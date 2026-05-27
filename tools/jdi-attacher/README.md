# jdi-attacher

Connects to a running JVM via JDWP and arms a conditional breakpoint. Built for the
`debug-replay` scenario: replay a transaction log, break on the exact event you care
about, then hand off to IntelliJ for interactive debugging — without touching prod.

## What it does

1. Attaches to the JDWP port on the target host.
2. If the target class is not yet loaded, registers a ClassPrepare listener so the
   breakpoint is armed the moment the class appears (safe for lazy-loaded handlers).
3. Sets a breakpoint at the first line of the target method.
4. Evaluates the `--condition` expression client-side on every hit — frames that
   don't match are resumed immediately and silently (no visible noise).
5. On a matching hit, prints the thread, source location, and all visible local
   variables.
6. In `--hand-off` mode: detaches after the hit, leaving the JVM suspended at the
   breakpoint line. Connect IntelliJ to the same host:port to walk in.

## Usage

```
java --add-modules jdk.jdi -jar jdi-attacher.jar <host> \
     [--class <Class>] [--method <method>] [--condition <expr>=<value>] [--hand-off]
```

Requires a JDK (not just a JRE) — `com.sun.jdi` is in the `jdk.jdi` module.

The JDWP port is fixed at **5005**. This is standardised across all Bluebird staging
environments: shard_1 on trading-host1 always uses 5005, and the start script always
opens `*:5005`.

## Options

| Flag | Description |
|------|-------------|
| `--class <Class>` | Required. Fully-qualified (or simple) class name to break on. |
| `--method <method>` | Method name. Omit to break on class load only. |
| `--condition <expr>=<value>` | Local variable condition. Requires `--method`. |
| `--hand-off` | Arm breakpoint, resume VM, wait for hit, print locals, detach (JVM stays suspended). |

## Condition expressions

The `--condition` flag evaluates a dot-separated path against the current stack frame:

```
orderId=ORD-12345              # local variable / parameter
m.tradeId=TRD-99              # field on a local object
m.order.instrumentId=TSLA     # arbitrarily deep field chain
```

Comparison is by string equality (`toString()` for primitives). If the expression
cannot be evaluated (e.g. variable not in scope), the hit is allowed through.

## Examples

```bash
# Break every time OrderEventHandler.process() is entered
java --add-modules jdk.jdi -jar jdi-attacher.jar trading-host1 \
     --class OrderEventHandler --method process

# Break only when orderId is ORD-12345, then hand off to IntelliJ
java --add-modules jdk.jdi -jar jdi-attacher.jar trading-host1 \
     --class OrderEventHandler --method process \
     --condition orderId=ORD-12345 \
     --hand-off

# Break on class load (no method needed)
java --add-modules jdk.jdi -jar jdi-attacher.jar trading-host1 \
     --class OrderEventHandler
```

## Normal output (--hand-off mode)

```
[jdi] connected: OpenJDK 64-Bit Server VM (JVM 17.0.19)
[jdi] OrderEventHandler not yet loaded — will report on class prepare and arm breakpoint
[jdi] class loaded: OrderEventHandler
[jdi] breakpoint armed: OrderEventHandler.process()  condition: orderId=ORD-12345
[jdi] waiting for hit...
[jdi] *** BREAKPOINT HIT ***
[jdi]   thread:   main
[jdi]   location: OrderEventHandler:23
[jdi]   java.lang.String orderId = "ORD-12345"
[jdi]   java.lang.String payload = "side=BUY qty=500 price=150.00 instrument=product_005"
[jdi]
[jdi] app suspended — attach your debugger:
[jdi]   host : trading-host1
[jdi]   port : 5005
[jdi]   IntelliJ: Run > Attach to Process > trading-host1:5005
[jdi] detaching (app remains suspended)...
```

## Build

```bash
# From repo root
javac --release 17 tools/jdi-attacher/JdiAttacher.java -d /tmp/jdi-build
jar cfe tools/jdi-attacher/jdi-attacher.jar JdiAttacher -C /tmp/jdi-build .
```

The jar has no external dependencies — `com.sun.jdi` is part of the JDK.

## Used by

- `examples/debug-replay/debug-replay.shbang` — the main debug-replay playbook
- `bin/playground --debug-replay` — quick manual trigger (bypasses the shebang)
