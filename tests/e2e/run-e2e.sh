#!/usr/bin/env bash
# e2e test runner for sh.bang replay scenario.
# Expects target1 and target2 to be reachable via SSH as deploy@<host>.
#
# Usage:
#   ./run-e2e.sh                     # uses defaults (target1, target2)
#   ./run-e2e.sh --inline             # stream output live (default: buffered)
#   TARGET1=myhost1 ./run-e2e.sh     # override hosts
#
# SSH auth: uses baked-in e2e test key (/root/.ssh/e2e_test_key in the e2e image)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
E2E="$ROOT/tests/e2e"
BIN="$ROOT/bin/sh.bang"

STREAM=false
while [[ ${1:-} == -* ]]; do
  case $1 in
    --inline) STREAM=true ;;
    *)        printf 'unknown flag: %s\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

TARGET1="${TARGET1:-target1}"
TARGET2="${TARGET2:-target2}"
SSH_KEY="/root/.ssh/e2e_test_key"
SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -i $SSH_KEY"
export SHBANG_SSH_KEY="$SSH_KEY"

PASS=0
FAIL=0

pass() { PASS=$(( PASS + 1 )); printf '  [pass] %s\n' "$*"; }
fail() { FAIL=$(( FAIL + 1 )); printf '  [FAIL] %s\n' "$*" >&2; }

assert_contains() {
  local label=$1 haystack=$2 needle=$3
  [[ $haystack == *"$needle"* ]] && pass "$label" || fail "$label — missing: $needle"
}

assert_not_contains() {
  local label=$1 haystack=$2 needle=$3
  [[ $haystack != *"$needle"* ]] && pass "$label" || fail "$label — should not contain: $needle"
}

summary() {
  if (( FAIL == 0 )); then
    printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  else
    printf '\n\e[1;31m ___ _  _ _ _____   ___  ___   ___  __  __ \n' >&2
    printf '/ __| || / |_   _| | _ )/ _ \ / _ \|  \/  |\n' >&2
    printf '\__ \ __ | | | |   | _ \ (_) | (_) | |\/| |\n' >&2
    printf '|___/_||_|_| |_|   |___/\___/ \___/|_|  |_|\n' >&2
    printf '\e[0m\n' >&2
    printf '\e[1;31m%d passed, %d failed\e[0m\n' "$PASS" "$FAIL"
    return 1
  fi
}

echo "=== sh.bang e2e: replay ==="
echo "target1=$TARGET1  target2=$TARGET2"
echo

# ---------- build replay-stub.jar if needed ----------

if [[ ! -f "$ROOT/tools/replay-stub/replay-stub.jar" ]]; then
  echo "[e2e] building replay-stub.jar..."
  cd "$ROOT/tools/replay-stub"
  javac ReplayStub.java
  jar cfe replay-stub.jar ReplayStub ReplayStub.class
  rm -f ReplayStub.class
  cd "$ROOT"
fi

# ---------- setup targets ----------

echo "--- setup ---"
bash "$E2E/setup-target.sh" "$TARGET1" "shard_1 shard_2" "$SSH_KEY"
bash "$E2E/setup-target.sh" "$TARGET2" "shard_3 shard_4" "$SSH_KEY"

# Copy replay stub jar to targets
# shellcheck disable=SC2086
scp $SSH_OPTS "$ROOT/tools/replay-stub/replay-stub.jar" deploy@"$TARGET1":/tmp/replay-stub.jar
# shellcheck disable=SC2086
scp $SSH_OPTS "$ROOT/tools/replay-stub/replay-stub.jar" deploy@"$TARGET2":/tmp/replay-stub.jar

# ---------- run playbook ----------

echo
echo "--- running playbook ---"
_LOG=$(mktemp)
if [[ $STREAM == true ]]; then
  "$BIN" run "$ROOT/examples/replay/replay.shbang" \
    --ctx "$ROOT/examples/replay/environment.json" 2>&1 | tee "$_LOG"
  OUTPUT=$(cat "$_LOG")
else
  OUTPUT=$("$BIN" run "$ROOT/examples/replay/replay.shbang" \
    --ctx "$ROOT/examples/replay/environment.json" 2>&1)
  echo "$OUTPUT"
fi
rm -f "$_LOG"

# ---------- assert ----------

echo
echo "--- assertions ---"

# shard_1: trade_001, trade_002
assert_contains "shard_1: trade_001 replayed" "$OUTPUT" "Replayed trade_001"
assert_contains "shard_1: trade_002 replayed" "$OUTPUT" "Replayed trade_002"

# shard_2: trade_003, trade_004
assert_contains "shard_2: trade_003 replayed" "$OUTPUT" "Replayed trade_003"
assert_contains "shard_2: trade_004 replayed" "$OUTPUT" "Replayed trade_004"

# shard_3: trade_005, trade_001
assert_contains "shard_3: trade_005 replayed" "$OUTPUT" "Replayed trade_005"
assert_contains "shard_3: trade_001 replayed" "$OUTPUT" "Replayed trade_001"

# shard_4: trade_002, trade_003
assert_contains "shard_4: trade_002 replayed" "$OUTPUT" "Replayed trade_002"
assert_contains "shard_4: trade_003 replayed" "$OUTPUT" "Replayed trade_003"

# skips should appear
assert_contains "skips present" "$OUTPUT" "Skipped"

summary
