# replay-stub

Fake replay engine for the `solace-replay` e2e tests. Reads a flat rdat file (one
trade ID per line) and prints `Replayed <id>` or `Skipped <id>` based on a filter
list. The tests assert on those lines to verify the playbook delivered the right
filter expression.

## Usage

```bash
java -jar replay-stub.jar --rdat <file> --filter "tradeId in (A,B,C)"
```

| Argument | Description |
|----------|-------------|
| `--rdat <file>` | Path to the rdat file. One ID per line. |
| `--filter "<expr>"` | Filter expression in the form `tradeId in (ID1,ID2,...)`. |

## rdat file format

One record ID per line. Blank lines are ignored.

```
trade_001
other_101
trade_002
other_102
```

## Output

```
[replay-stub] rdat:   /opt/trading/shard_1/txn-log/log.rdat.out
[replay-stub] filter: tradeId in (trade_001,trade_002)
[replay-stub] ids:    [trade_001, trade_002]

Replayed trade_001
Skipped  other_101
Replayed trade_002
Skipped  other_102

[replay-stub] done.
```

## Build

```bash
javac tools/replay-stub/ReplayStub.java -d /tmp/rs-build
jar cfe tools/replay-stub/replay-stub.jar ReplayStub -C /tmp/rs-build .
```

No external dependencies.

## Used by

- `examples/solace-replay/replay.shbang` — SSH step runs the jar on each target shard
- `tests/e2e/` — e2e tests for the solace-replay scenario
- `bin/playground` — copies the jar to `/tmp/replay-stub.jar` on trading-host1/2 at
  startup
