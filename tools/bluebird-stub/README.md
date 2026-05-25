# bluebird-stub

Simulates the Bluebird trading application's startup and recovery sequence. Used by
`debug-replay` e2e tests and playground sessions so developers can exercise the
JDI/JDWP debugging workflow without a real Bluebird instance.

## What it simulates

Real Bluebird starts by reading its transaction log (`trading.rdat.in`) from top to
bottom. bluebird-stub faithfully reproduces the three startup phases:

**Phase 1 — Static data load**
Lines tagged `StaticData` are dispatched to `StaticDataHandler`. Each record sleeps
briefly to simulate real load time (go get coffee). When complete the stub logs a
count of records loaded.

**Phase 2 — Event sourcing recovery**
`NewOrderSingle` lines → `OrderEventHandler.process()`
`ExecutionReport` lines → `TradeEventHandler.process()`
No outbound messages during recovery — state is rebuilt silently, exactly as the
real app does it. Every replayed event is logged to stdout.

**Phase 3 — Ready**
The stub enters an infinite heartbeat loop, printing `[heartbeat] shard alive` every
10 seconds. JDWP is open; a developer attaches their debugger at any time. The
breakpoint on `OrderEventHandler.process()` fires on the very next order that arrives.

## rdat.in format

```
<id> <msgType> <payload fields...>
```

| msgType | Handler | Notes |
|---------|---------|-------|
| `StaticData` | `StaticDataHandler` | Reference data — products, exchanges |
| `NewOrderSingle` | `OrderEventHandler` | Order events |
| `ExecutionReport` | `TradeEventHandler` | Fill/cancel notifications |

See `tests/e2e/fixtures/debug-replay/trading.rdat.in` for a worked example.

## Usage

JDWP is **not** baked in — inject it via the start script:

```bash
# suspend=y: JVM blocks until a debugger attaches (used in debug-replay)
java -agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=*:5005 \
     -jar bluebird-stub.jar /opt/trading/shard_1/trading/data/trading/txn-log

# suspend=n: JVM starts immediately, debugger can attach at any time
java -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005 \
     -jar bluebird-stub.jar /opt/trading/shard_1/trading/data/trading/txn-log
```

The optional argument is the path to the `txn-log` directory.  
Default: `./data/trading/txn-log`

## OrderEventHandler — the breakpoint target

`OrderEventHandler.process(String orderId, String payload)` is where a developer
sets their breakpoint when investigating an order processing issue. jdi-attacher
targets this method by default, filtering to a specific `orderId` via `--condition`.

To break on `ORD-12345`:
```
jdi-attacher trading-host1 \
  --class OrderEventHandler \
  --method process \
  --condition orderId=ORD-12345 \
  --hand-off
```

The target class is compiled with `javac -g` (full debug info) so all local variables
are visible in the JDI frame.

## Build

```bash
# From repo root
javac tools/bluebird-stub/*.java -d /tmp/bb-build
jar cfe tools/bluebird-stub/bluebird-stub.jar BluebirdStub -C /tmp/bb-build .
```

Or via Docker (recommended — matches the target JDK):
```bash
docker compose build e2e
```
The `e2e` image copies the pre-built jar to `tools/bluebird-stub/bluebird-stub.jar`.

## Used by

- `tests/lib/bbStruct.sh` — `bb_create_debug_binaries` uploads this jar to the target
  host and writes a `start` script that injects JDWP
- `tests/e2e/fixtures/debug-replay/` — fixture rdat files that drive the stub's
  recovery sequence
- `bin/playground` — installs the jar on trading-host1 for playground sessions
