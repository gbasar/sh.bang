# Handoff Note

> **Note:** This handoff was written after Claude (Anthropic claude-sonnet-4-6, flagship model) spent 2+ hours on this branch, declared the task done without testing, then failed to fix or even correctly diagnose the `--trace-after-hit` bug across a dozen attempts. The root cause is probably one line. Codex: don't repeat this.

**Branch:** `debug-play`
**Base:** `main`

---

## What was done this session

### examples/debug-replay/debug-replay.shbang — DONE
Added 4 missing context keys to the header and the matching jdi-attacher flags to the Option 1 trace command:
- `debug.render`, `debug.fieldDepth`, `debug.fieldMax`, `debug.maxStringLen`
- Command now includes: `--render ${debug.render} --field-depth ${debug.fieldDepth} --field-max ${debug.fieldMax} --max-string-len ${debug.maxStringLen}`
- Fixed Option 1 comment: "use start: suspend=y" (was wrong: "use start-trace: suspend=n")

All other files (debug-replay-trace.shbang, debug-replay-intellij.shbang, developerScratchPad.hocon, OrderEventMessage.java, BluebirdStub.java, OrderEventHandler.java, bbStruct.sh, bin/playground) were already complete.

---

## Update: --trace-after-hit is functional, with rendering caveats

Codex update: `--trace-after-hit` now attaches, hits `ORD-12345`, traces through the
whole `OrderEventHandler.process(...)` event handler, and exits with
`[jdi] trace complete`.

Validated with:

```bash
./bin/playground --debug-replay-intellij
/c/d/i/jdk-25.0.3+9/bin/java --add-modules jdk.jdi \
  -jar tools/jdi-attacher/jdi-attacher.jar localhost --port 5005 \
  --class com.bluebird.trading.OrderEventHandler --method process \
  --condition orderId=ORD-12345 \
  --trace-after-hit --trace-filter com.bluebird.trading.* --trace-limit 500 \
  --debug-jdi
```

Current useful behavior:

- no hang in the validation run
- traces the entire event handler invocation, stopping at
  `OrderEventHandler.process` exit
- `--debug-jdi` logs suspend-count and rendering diagnostics

Known remaining trash:

- some argument rendering can print `error=IncompatibleThreadStateException`
- some argument values may look stale/wrong under JDI timing
- the trace is still useful for call shape/order, but argument rendering needs
  cleanup before calling it polished

---

## Historical bug context: --trace-after-hit hung in JdiAttacher

**Symptom:** jdi-attacher connects, hits the breakpoint on `ORD-12345`, prints hit info, enables MethodEntry/MethodExit requests, prints `[jdi] tracing ... limit=500`, then hangs forever. No method events fire. The JVM stays suspended at `ORD-12345`.

**Confirmed:** Without `--trace-after-hit`, the breakpoint hit works perfectly — jdi-attacher hits ORD-12345, resumes, JVM replays remaining events, VM terminates.

**Confirmed:** `events.resume()` returns successfully (via debug prints) but the JVM doesn't run.

**Environment:**
- jdi-attacher runs on JDK 25.0.3 (host Windows)
- bluebird-stub JVM is JDK 17.0.19 (Docker container, trading-host1 port 5005)
- `start` script uses `suspend=y`

**Investigation so far:**

1. Not the `toString()` INVOKE_SINGLE_THREADED call — switching printHit to FIELDS mode (no method invocation) made no difference.

2. Not the class filter — same hang with no `--trace-filter`.

3. `events.resume()` IS called and returns, `vm.resume()` also makes no difference.

4. Suspend count: not measured yet.

**Next thing to try:** Remove `addThreadFilter(thread)` from the MethodEntry and MethodExit requests in `enableTrace()`. The thread filter on the request is the one remaining difference between the working path (no trace) and the broken path. If removing it makes trace work, the thread filter is the culprit — possibly because the `ThreadReference` captured at breakpoint time becomes invalid after `events.resume()` in JDK 17.

The three `addThreadFilter` calls to remove are in `enableTrace()` (lines ~336, 342, 350):
```java
trace.entryRequest.addThreadFilter(thread);   // remove
trace.exitRequest.addThreadFilter(thread);    // remove
trace.rootExitRequest.addThreadFilter(thread); // remove
```

After removing, recompile and test:
```bash
cd tools/jdi-attacher
/c/d/i/jdk-25.0.3+9/bin/javac --add-modules jdk.jdi -d . JdiAttacher.java
/c/d/i/jdk-25.0.3+9/bin/jar cfe jdi-attacher.jar com.bluebird.trading.utils.JdiAttacher com/

# containers are already running
cd C:/d/projects/sh.bang
source bin/playground   # re-creates .playground-ssh-config
bin/playground --debug-replay
```

Expected output if fix works:
```
[jdi] tracing com.bluebird.trading.* limit=500

  → com.bluebird.trading.OrderEventHandler.validate(...)
  ← com.bluebird.trading.OrderEventHandler.validate = true
  → com.bluebird.trading.OrderEventHandler.buildState(...)
  ...
[jdi] trace complete N events
```

**Current JdiAttacher.java state:** Has a `printHit` FIELDS-override when `traceAfterHit=true` (harmless, keep it — avoids INVOKE_SINGLE_THREADED in the hit locals printout). No debug prints remain.

---

## Test commands

```bash
# Unit tests (3 pre-existing failures in multi-block — unrelated to this work)
bash tests/run-tests

# Docker containers
docker compose ps        # target1 and target2 should be Up
source bin/playground    # sets env, writes .playground-ssh-config

# Run trace scenario
bin/playground --debug-replay

# Run IntelliJ scenario (starts frozen JVM, connect IntelliJ to localhost:5005)
bin/playground --debug-replay-intellij
```
