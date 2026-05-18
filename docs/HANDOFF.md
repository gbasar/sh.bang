# Handoff Notes

Date: 2026-05-16

## Current State

Project path:

```txt
/Users/gregb/devhobme/sh.bang
```

The project has been created with docs, examples, a tiny parser CLI, tests, and a first pass at a JSON/spec-driven router.

Current files of interest:

```txt
bin/sh.bang
lib/router.sh
lib/events.sh
lib/parser.sh
lib/log.sh
spec/cli.json
tests/run-tests
docs/
examples/
```

## User Preferences To Preserve

The user strongly dislikes case-heavy Bash and old positional shell style.

Code should be readable to a Java programmer who dislikes Bash programming:

```txt
tables over case blocks
named functions over shell tricks
runtime/command/event maps over loose globals
JSON specs where they remove shell branching
jq helpers where one jq query replaces lots of Bash
```

Current desired style:

```txt
Bash >= 5.1
jq >= 1.6
associative arrays
local -n namerefs
runtime singleton/map passed through routing
event handlers for output/logging
no mutable globals except constants and explicit handler tables
```

## Architecture Direction

CLI and run flow should look like:

```txt
runtime_init
route_cli
route_flags via handler tables
dispatch command via command table
parse playbook
emit parser/command events
event handlers decide console/file behavior
```

Do not scatter dry-run or logging checks everywhere. Long-term, all executable actions should go through one command router that checks:

```txt
dry_run
verbosity
event handlers
error policy
remote compatibility
```

Initial event handlers:

```txt
console  human-readable output
file     JSONL event file
```

## Syntax Decisions

Symbols:

```txt
$ = root/local context data
@ = remote file/location context
# = remote SSH execution context
```

Variables use braces:

```txt
${host}
${install.dir}
${resources.replayJar}
```

Main playbook block:

```txt
for_each ${topology.shards[*]}
| @${host}:${install.dir}/datadir/archive send ${resources.replayJar}
| #${host}:${install.dir}/datadir/archive run ${java} -jar replay.jar
```

Selector ideas:

```txt
${topology.shards[*]}             all map values or array items
${topology.shards[shard3]}        one map value as a one-item loop
${topology.shards[*].hosts[*]}    flattened traversal instead of nested loops
```

No comma selectors for v1.

## HOCON Decision

HOCON is allowed as an input/resource because the company uses it.

Execution should not operate on HOCON directly:

```txt
HOCON resource -> converted/rendered JSON -> context node
```

After conversion, playbooks only see nodes:

```txt
${topology.shards[*]}
${expand.from.hocon}
```

## Current Code Status

The CLI was initially implemented, then redone toward the preferred architecture.

Known recent issue:

```txt
Nameref circular reference warnings appeared in lib/router.sh.
```

Fixes were applied by renaming internal nameref variables in:

```txt
route_flags
parse_run_args
handle_flag_verbosity
handle_flag_version
handle_flag_help
handle_run_ctx
handle_run_dry_run
```

Tests were **not rerun after the final nameref fix** because the user paused for the night.

## Next Commands

Run these first when resuming:

```bash
cd /Users/gregb/devhobme/sh.bang
./tests/run-tests
./bin/sh.bang -vvvv run examples/replay.shbang --ctx examples/context.json --dry-run
rg -n 'case | esac|case "|case \$' .
```

Expected:

```txt
tests pass
dry-run parser output prints for_each and pipe events
no case dispatch remains
```

If tests still fail, inspect:

```txt
lib/router.sh
```

especially nameref parameter names. Avoid naming a local nameref the same as the variable passed into it.

## Disk Note

Disk was tight but not failing:

```txt
about 8.8 GiB free on /System/Volumes/Data
```

The out-of-space concern was not the cause of failures. The failures were permission bits after file replacement and then Bash nameref bugs.

## User Is Pausing

The user is going to look for examples of pretty Bash and will return with style references. Do not make more changes until they resume.
