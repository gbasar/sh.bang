# Handoff Note

**Branch:** `arch/lean-runtime`  
**Base:** `main` (merged PR from `fixes-to-test`)  
**Tests:** 57 passed, 0 failed (native Windows + Docker)

---

## Commits on this branch so far

1. `26dbbb0` — global SHBANG_RT (nameref threading gone, declare -gA everywhere)
2. `b9a28ea` — verbs.json (send/fetch/run as config, dry-run labels)
3. `6cc8e78` — sh.bang.svg logo (comic censor burst, green on black)

---

## Two steps remaining before merge

### Step 3 — `event_to_json` pure bash (`lib/events.sh`)
Replace the `jq -cn` call in `event_to_json()` with bash string building.
No jq subprocess per event written to file.

Current code (bottom of `lib/events.sh`):
```bash
event_to_json() {
  local -n etj_event=$1
  local -a jq_args=()
  local filter='{'
  ...
  jq -cn "${jq_args[@]}" "$filter"   # ← kill this
}
```

Replace with pure bash JSON serialisation — iterate keys, escape values,
build the JSON string directly. The `review` branch already has this done.

### Step 4 — `dispatch_queue` field-by-field jq extraction (`lib/dispatch.sh`)
Replace the `to_entries[] | "\(.key)=\(.value)"` pattern (fragile, \r risk)
with direct per-field extraction:
```bash
type=$(jq -r .type  <<< "$entry")
user=$(jq -r .user  <<< "$entry")
host=$(jq -r .host  <<< "$entry")
path=$(jq -r .path  <<< "$entry")
verb=$(jq -r .verb  <<< "$entry")
args=$(jq -r .args  <<< "$entry")
```
Then assign directly to `dq_event` without the key=value parse loop.

---

## After steps 3 + 4

- Run `bash tests/run-tests` — expect 57 passed, 0 failed
- Commit each step separately
- Push `arch/lean-runtime` and open PR into `main`

---

## Other open items (not this branch)

- GitLab mirror — user will provide details
- HOCON jar Nexus URL — user will supply for Dockerfile
- Live Docker end-to-end test (needs `docker compose up`)
- Parallel dispatch (`wait -p`) — deferred until core is solid
