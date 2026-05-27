# sh.bang sales pitch

`sh.bang` makes plain old SSH feel like a structured runbook engine.

The trick is simple:

```text
.shbang playbook
   -> parse readable steps
   -> expand context variables
   -> queue command events
   -> dispatch ssh/scp/local commands
   -> stream output back in one readable console
```

For a playbook line like:

```shbang
| @${host}:${path} run tar xvf file.tar.gz
```

`sh.bang` turns it into the boring command you would have written by hand:

```bash
ssh deploy@trading-host1 "cd /some/path && tar xvf file.tar.gz"
```

SSH already gives us the magic: remote stdout and stderr flow back over the
connection naturally. `sh.bang` wraps that stream with labels, indentation, color,
context expansion, and sequencing.

So the terminal shows not just random remote output, but output attached to the
step that produced it:

```text
[ Pull rdat archive from prod and unpack to txn-log ]
├─ ssh -> @trading-host1:/opt/trading/shard_1/...  tar xvf ...
│  ./
│  ./log.rdat.out
```

Local commands work the same way. A captured local step:

```shbang
| @local run java ... -> debugTrace
```

is effectively:

```bash
bash -c "java ..." 2>&1 | tee "$tmp" | sed 's/^/│  /'
```

That means one command can do both:

1. stream live output to the operator
2. capture the full output into a variable for later steps

The result feels bigger than "just a bunch of SSH commands" because the runbook
owns the structure:

- context-driven hosts, paths, and debug settings
- readable labels for each phase
- local, SSH, and SCP steps in one sequence
- dry-run and event hooks
- capture variables for later use
- repeatable workflows across shards and environments

But the implementation stays honest. Bash executes the leaves. SSH/SCP/Java/tar do
their normal jobs. `sh.bang` owns the orchestration, context, and output shape.

That is the pitch:

```text
Keep the tools boring.
Make the runbook readable.
Let the output tell the story.
```
