# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Runtime Requirements

- **Bash 5.1+** — uses `local -n` namerefs and associative arrays. On Windows use Git Bash (`C:\Program Files\Git\bin\bash.exe`), not WSL's `bash.exe`.
- **jq 1.6+** — used for CLI spec lookups and event serialisation.

## Commands

```bash
# Run tests
bash tests/run-tests

# Run tests in Docker (lean image, no Java)
docker compose run --rm test

# Run tests in Docker (work image, JDK17 + HOCON jar)
HOCON_JAR_URL=https://... docker compose run --rm test

# Smoke-run a playbook
./bin/sh.bang run examples/replay.shbang --ctx examples/context.json --dry-run

# Full verbosity
./bin/sh.bang -vvvv run examples/replay.shbang --ctx examples/context.json --dry-run
```

## Architecture

### Data flow

```
main → runtime_init → route_cli → route_flags (global)
                               → cmd_run → parse_run_args → route_flags (run)
                                        → emit_kv (run.loaded)
                                        → parse_playbook → emit_kv (parser.for_each / parser.pipe)
```

The **runtime** is a single `declare -A` associative array passed by nameref through every function. It holds verbosity, dry_run, cli_spec path, event handlers, etc.

### Nameref convention

Every function that receives the runtime or an event map by nameref must use a **unique local variable name** — never `rt` or `event` — to avoid Bash's name-based circular reference detection. Convention: prefix with the function name (e.g. `emit_kv` uses `kv_rt`, `parse_playbook` uses `pp_rt`, `event_console` uses `ec_rt`/`ec_event`).

### CLI routing (`lib/router.sh`)

No `case` blocks. Dispatch is table-driven:

- `SHBANG_COMMANDS` maps command names → handler functions (`cmd_run`)
- `GLOBAL_FLAG_HANDLERS` / `RUN_FLAG_HANDLERS` map flag kinds → handler functions
- Flag metadata (kind, level, takesValue) lives in `spec/cli.json` and is queried with `jq`
- `route_flags` loops over tokens, looks up each in the spec, calls the handler

### Event bus (`lib/events.sh`)

All output goes through `emit_kv rt <type> key val ...`. Handlers are registered in `EVENT_HANDLERS` (`console`, `file`). Console output is further dispatched via `CONSOLE_EVENT_FORMATTERS` keyed by event type. Adding a new output target means adding an entry to `EVENT_HANDLERS` and a handler function — nothing else changes.

### Playbook syntax

```
// comment
for_each ${selector}         ← jq path into context JSON
| @host:path verb args       ← @ = file/scp subject
| #host:path verb args       ← # = ssh subject
```

`for_each` and pipe lines are parsed by regex in `lib/parser.sh`. The parser emits events but does **not** expand selectors, interpolate `${vars}`, or execute anything — that is all future work.

### What is not implemented yet

- Selector expansion (`topology.shards[*]` → actual nodes via jq)
- Variable interpolation (`${host}`, `${install.dir}`)
- Execution dispatch (`@` → scp, `#` → ssh)
- HOCON → JSON conversion (planned: `java -jar hocon.jar`, downloaded from Nexus into `Dockerfile`)

### Docker

- `Dockerfile` — client image (ubi9, bash+jq+JDK17+curl, optional HOCON jar via `ARG HOCON_JAR_URL`)
- `Dockerfile.server` — server image (ubi9, JDK17+sshd, `deploy` user, `/opt/blackbird/` dirs)
- `docker-compose.yml` — `test`/`run` use the client image; `server` is the remote execution target

### Test suite (`tests/run-tests`)

Framework: pass/fail counter, named assertions, labelled sections, exits non-zero on any failure. Fixtures in `tests/fixtures/`. Run a single logical group by reading the section labels in the file — there is no per-test selector.
