# Handoff Note

**Branch:** `feature/e2e-replay` (PR #5 open, not merged yet)
**Base:** `main`
**Tests:** 26 passed, 0 failed

---

## Where we are

Design and docs are solid. Engine handles the replay playbook end-to-end in dry-run.
The next session goal is getting `docker compose run --rm e2e` green.

---

## What was built this session

### Engine changes
- `lib/parser.sh` — skips `#!` labels, skips `resources {}` block, parses `$ run cmd -> varName`
- `lib/expand.sh` — table-driven handlers, `expand_local` runs local cmd and stores in `SHBANG_RT`,
  `render_vars` falls back: shard node → full context JSON → SHBANG_RT (for tradeFilter etc.),
  selector auto-`[]` fix (was mangling named keys like `[primary]`), MSYS_NO_PATHCONV on jq calls
- `lib/events.sh` — `parser.local` console formatter added
- `lib/dispatch.sh` — jq `// empty` fallbacks, no more error noise

### Replay example
- `examples/replay/replay.shbang` — full playbook with `$ local` + `for_each`
- `examples/replay/environment.json` — JSON context, 4 shards across 2 hosts (target1/target2)
- `examples/replay/environment.conf` — HOCON version (needs HOCON jar, only works at work)
- `examples/replay/trades.csv` — trade_001..trade_005
- `examples/replay/trading1.hocon` + `trading2.hocon` — prod/SIT reference formats (keep these)

### Fake replay Java stub
- `tools/replay-stub/ReplayStub.java` — reads rdat file, prints `Replayed X` or `Skipped X`
- `tools/replay-stub/build.sh` — compile with javac + jar
- `tools/replay-stub/replay-stub.jar` — pre-built with JDK25 locally

### e2e infrastructure
- `tests/e2e/fixtures/shard_{1..4}/log.rdat.out` — 2 matching trades + 8 others per shard
- `tests/e2e/setup-target.sh` — tars fixtures, SCPs to target hosts, creates dirs
- `tests/e2e/run-e2e.sh` — full runner: setup → build jar → run playbook → assert output
- `docker-compose.yml` — target1, target2 (Fedora+sshd), e2e service
- `Dockerfile.server` — SSH key injection via entrypoint
- `docker/server-entrypoint.sh` — injects SSH_PUBKEY env var into authorized_keys, starts sshd

---

## What needs to happen next session

### 1. SSH keypair for e2e
Generate a keypair for the e2e test:
```bash
ssh-keygen -t ed25519 -f tests/e2e/e2e_key -N ""
```
Pass to docker compose via env:
```bash
SSH_PUBKEY=$(cat tests/e2e/e2e_key.pub) SSH_PRIVKEY=tests/e2e/e2e_key docker compose run --rm e2e
```
Add `tests/e2e/e2e_key*` to `.gitignore`.

### 2. Verify docker compose builds
```bash
docker compose build target1 target2 e2e
```
Check Dockerfile.server installs sshd correctly on ubi9.

### 3. Wire SSH key into e2e runner
`tests/e2e/run-e2e.sh` accepts `SSH_PRIVKEY` env var already.
`setup-target.sh` accepts it as third arg already.
Just needs the keypair generated (step 1).

### 4. Run e2e
```bash
SSH_PUBKEY=$(cat tests/e2e/e2e_key.pub) \
SSH_PRIVKEY=/path/to/e2e_key \
docker compose run --rm e2e
```

### 5. Merge PR #5 once e2e is green

---

## Known issues / deferred

- **MSYS path mangling** — dry-run shows Windows paths for Linux paths (e.g. `/usr/bin/java` →
  `C:/Program Files/Git/usr/bin/java`). Only affects dry-run display on Windows, not actual execution.
  Not worth fixing now.
- **`resources {}` block** — parsed but not resolved. `${trades}` path is hardcoded in playbook for now.
  Resource resolution (download to `.shbang-resources/`) is a future sprint.
- **Nested `for_each`** — not implemented in parser. Depth-first execution deferred.
- **HOCON jar** — only available at work via Nexus. Use JSON context locally.
- **`$` local subject** — implemented for `$ run -> capture` but not `$ send` etc.

---

## Key design decisions (don't forget)

- `@` = one-shot SSH under the hood (not interactive session) — engine builds `ssh -J` chains
- `#` and `$` reserved for future use (one-shot explicit, local)
- `:path` = implicit `cd` — engine handles it, playbook author never writes `cd`
- `resources {}` block resolved as preflight before any `for_each`
- `$ run cmd -> varName` captures local stdout into `SHBANG_RT[varName]`
- HOCON alias trick: `shard = ${trading.instances}` makes both prod/SIT formats work with same selector
- Nested `for_each` walks network path — each level is an SSH hop from previous context
- Depth-first execution order = put nested block before pipes you want to run last
- Hop mechanism (`ssh -J`) is swappable — many corp environments block ProxyJump
- `conf` not `env` for context resource keyword (PowerShell conflict)
