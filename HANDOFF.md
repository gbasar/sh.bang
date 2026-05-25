# Handoff Note

**Branch:** `debug-play`
**Base:** `main`
**Tests:** e2e green (9/9), solace-replay scenario working

---

## Where we are

The `debug-replay` scenario is fully built and smoke-tested end-to-end.
`bin/sh.bang run` with dispatch works — `@` routes to scp/ssh based on verb.
Next: run `debug-replay.shbang` as an actual playbook and clean up `#` vs `@` subject syntax.

---

## What was built this session

### tools/bluebird-stub/
Fake Bluebird trading app for the debug-replay demo.
- `BluebirdStub.java` — three-phase startup: static data → recovery → ready/heartbeat
- `StaticDataHandler.java` — processes `StaticData` lines (500ms delay each, simulates load)
- `OrderEventHandler.java` — processes `NewOrderSingle` lines, **primary JDI breakpoint target**
- `TradeEventHandler.java` — processes `ExecutionReport` lines
- All events flow from `trading.rdat.in` in order (StaticData first, then orders/trades)
- Built with `-g` (debug info) so local variable names are visible via JDI
- JDWP injected via `start` script, not baked in

### tools/jdi-attacher/
JDI client that connects to a running JVM and arms a conditional breakpoint.
- `--class` / `--method` / `--condition` named flags
- `--condition` supports dot notation: `orderId=ORD-12345` or `m.tradeId=TRD-99`
- `--hand-off` mode: on hit, prints locals + attach banner, detaches **without resuming** —
  app stays suspended, IntelliJ connects and walks in at the exact line
- Requires JDK (not JRE) — `java --add-modules jdk.jdi -jar jdi-attacher.jar`
- Connector arg is `"hostname"` not `"host"` (already fixed)

### tests/lib/bbStruct.sh
Sourceable fixture library for building Bluebird shard layouts over SSH.
- `bb_create_shard_layout` / `bb_create_debug_binaries` / `bb_create_rdat` / `bb_destroy_shard`
- `bb_create_debug_binaries` uploads `bluebird-stub.jar`, writes `start` (suspend=n) and
  `start-intellij` (suspend=y — app waits for debugger before running)
- Honours `E2E_SSH_KEY` and `E2E_SSH_CONFIG` env vars

### tests/e2e/setup-debug-replay.sh
Sets up all 4 shards on trading-host1/2 for the debug-replay scenario.

### tests/e2e/fixtures/debug-replay/trading.rdat.in
8 StaticData records + 6 orders + 2 trades. `ORD-12345` is the target order.

### examples/debug-replay/
- `debug-replay.shbang` — the playbook (parser-clean, no stray `#` comments)
- `environment.conf` — shared team config: shard topology + `include "developerScratchPad.hocon"`
- `developerScratchPad.hocon` — developer's session config: staging host, archive date, debug block

### bin/playground
Added `--debug-replay [shard] [class] [method] [condition]` mode:
- Auto-sets up debug fixtures if missing
- Starts bluebird-stub with JDWP
- Runs jdi-attacher with `--hand-off`
- Prints IntelliJ attach instructions on hit

---

## Smoke test (verified working)

```bash
docker compose up -d target1 target2
docker compose run --rm e2e tests/e2e/setup-debug-replay.sh

# start app + arm breakpoint + hand off to IntelliJ:
docker compose run --rm e2e -c "
  ssh ... deploy@trading-host1 'nohup ./start > /tmp/bluebird.log 2>&1 &'
  java --add-modules jdk.jdi -jar tools/jdi-attacher/jdi-attacher.jar \
    trading-host1:5005 \
    --class OrderEventHandler --method process \
    --condition orderId=ORD-12345 --hand-off
"
# → prints locals, prints attach banner, detaches
```

---

## Immediate next steps

1. **Run `debug-replay.shbang` as actual playbook** — dispatch is implemented, playbook should work
2. **Drop `#` subject prefix** — `@` with `run` verb already goes to SSH, `#` is redundant.
   Decide: remove `#` from language, or keep as alias?
3. **Multiple `--ctx` files** — `--ctx environment.conf --ctx developerScratchPad.hocon`
   so the `include` hack in environment.conf goes away
4. **PR / merge** — `debug-play` branch into `main`

---

## Key facts to remember

- `@host:path run cmd` → SSH; `@host:path fetch dst` → SCP fetch; `@host:path send src` → SCP send
- `#host:path run cmd` → SSH (redundant with `@` for `run`, keep for now)
- bluebird-stub needs `static data delay = 500ms × 8 products = 4s` window to attach jdi-attacher
- jdi-attacher uses `"hostname"` (not `"host"`) for the SocketAttachingConnector arg
- bluebird-stub compiled with `-g` — required for `visibleVariableByName()` to find `orderId`
- JDWP ports: shard_1=5005, shard_2=5006, shard_3=5007(→5005 on host2), shard_4=5008(→5006 on host2)
- `suspend=n` for jdi-attacher flow; `suspend=y` (start-intellij) for direct IntelliJ attach
