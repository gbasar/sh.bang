# sh.bang

`sh.bang` is a tiny Bash runbook runner for turning readable playbooks into
dry-run output now, and safer execution later.

The current proof of concept parses:

- `for_each` blocks over context selectors
- pipe-style command lines with `@` file/location subjects
- pipe-style command lines with `#` remote execution subjects

It also has a small CLI router, verbosity flags, JSON-backed help text, and an
event-style output path so logging, dry-runs, and future execution can stay in
one tidy little lane.

## Quick Taste

Example playbook:

```bash
for_each ${topology.shards[shard3]}
| @${host}:${install.dir}/datadir/archive send ${resources.replayJar}
| \#${host}:${install.dir}/datadir/archive run ${java} -jar replay.jar --vpn ${vpn} --user ${user.name}
```

Dry-run it:

```bash
./bin/sh.bang run examples/replay.shbang --ctx examples/context.json --dry-run
```

Turn the lights all the way up:

```bash
./bin/sh.bang -vvvv run examples/replay.shbang --ctx examples/context.json --dry-run
```

## Windows Setup: Use Git Bash

On Windows, use **Git Bash** for this project.

Recommended Bash:

```text
C:\Program Files\Git\bin\bash.exe
```

Avoid this one:

```text
C:\Windows\System32\bash.exe
```

That Windows `bash.exe` is the WSL launcher. If no WSL Linux distro is
installed, it fails before the project even gets a turn. Git Bash gives this
project the Bash environment it expects.

Check the right Bash:

```bash
"C:\Program Files\Git\bin\bash.exe" --version
```

## PyCharm Run Configuration

Create a **Shell Script** run configuration.

Use these fields:

```text
Interpreter path:
C:\Program Files\Git\bin\bash.exe

Script path:
C:\d\i\py1\devprojects\sh.bang\bin\sh.bang

Working directory:
C:\d\i\py1\devprojects\sh.bang
```

First smoke test:

```text
Script options:
--version
```

Expected output:

```text
0.1.0
```

Then try the parser dry-run:

```text
Script options:
run examples/replay.shbang --ctx examples/context.json --dry-run
```

For maximum parser chatter:

```text
Script options:
-vvvv run examples/replay.shbang --ctx examples/context.json --dry-run
```

## Command-Line Testing

From the repo root:

```bash
./bin/sh.bang --version
./bin/sh.bang run examples/replay.shbang --ctx examples/context.json --dry-run
./bin/sh.bang -vvvv run examples/replay.shbang --ctx examples/context.json --dry-run
./tests/run-tests
```

## Current POC Notes

This is still early proof-of-concept code. If the PyCharm/Git Bash setup is
correct but tests fail, check these known local blockers first:

- `jq` may not be available inside Git Bash.
- The Bash router may still have a circular nameref issue around argument
  handling.

Those are project/runtime issues, not PyCharm configuration issues.

## Project Shape

```text
bin/sh.bang          CLI entrypoint
lib/router.sh        CLI and flag routing
lib/parser.sh        playbook parser
lib/events.sh        console/file event handling
lib/log.sh           verbosity-aware logging
spec/cli.json        CLI help and flag metadata
examples/            sample playbook and context
tests/run-tests      smoke test harness
docs/                design notes and handoff context
```
