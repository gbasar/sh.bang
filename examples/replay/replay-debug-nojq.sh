#!/usr/bin/env bash
# replay-debug-nojq.sh
#
# Replicates the exact operations of replay.shbang as raw shell — no sh.bang
# framework, no jq.  All config values are hardcoded from environment.json.
#
# Use this to isolate whether a failure is in sh.bang or in the underlying
# SSH/SCP/Java commands themselves.  Easy to set -x, comment out a step, or
# paste onto a jump host with nothing installed.
#
# Prerequisites:
#   source bin/playground      # sets SHBANG_SSH_KEY + SHBANG_SSH_CONFIG
#   (or export them manually)
#
# Usage:
#   bash examples/replay/replay-debug-nojq.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# Config — hardcoded from environment.json / environment.conf
# ---------------------------------------------------------------------------
INSTALL_BASE="/opt/trading"
JAVA="/usr/bin/java"
REPLAY_JAR="$REPO_ROOT/tools/replay-stub/replay-stub.jar"
DATE_TAG="20250522"
DEPLOY_USER="deploy"

# Shard list and host mapping
declare -a SHARDS=(shard_1 shard_2 shard_3 shard_4)
declare -A SHARD_HOST=(
  [shard_1]=trading-host1
  [shard_2]=trading-host1
  [shard_3]=trading-host2
  [shard_4]=trading-host2
)

# ---------------------------------------------------------------------------
# SSH options — array to avoid word-splitting issues with paths that have spaces
# ---------------------------------------------------------------------------
SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o BatchMode=yes
  -o KexAlgorithms=ecdh-sha2-nistp256
)
# ControlMaster omitted deliberately — debug scripts should show every connection

if [[ -n ${SHBANG_SSH_KEY:-} ]]; then
  SSH_OPTS+=(-i "$SHBANG_SSH_KEY")
else
  printf 'WARN: SHBANG_SSH_KEY not set — using default key\n' >&2
fi

if [[ -n ${SHBANG_SSH_CONFIG:-} ]]; then
  SSH_OPTS+=(-F "$SHBANG_SSH_CONFIG")
else
  printf 'WARN: SHBANG_SSH_CONFIG not set — hostname resolution may fail\n' >&2
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_hdr() { printf '\n\e[1;36m[ %s ]\e[0m\n' "$*"; }
_scp_up()  { printf '├─ \e[1;34mscp ↑\e[0m  \e[1;32m@%s\e[0m\e[2;3m:%s\e[0m  %s\n' "$1" "$2" "$3"; }
_ssh_run() { printf '├─ \e[1;35mssh →\e[0m  \e[1;32m@%s\e[0m\e[2;3m:%s\e[0m  %s\n' "$1" "$2" "$3"; }

# ---------------------------------------------------------------------------
# Step 1: build trade filter from CSV
# ---------------------------------------------------------------------------
_hdr "Prepare trade filter"

TRADE_FILTER=$(
  cat "$SCRIPT_DIR/trades.csv" \
    | tr -d '\r' \
    | tr '\n' ',' \
    | sed 's/,$//'
)

printf '├─ \e[1;32m$\e[0m localhost  trades.csv → tradeFilter\n'
printf '│  tradeFilter = %s\n' "$TRADE_FILTER"

# ---------------------------------------------------------------------------
# Step 2: per-shard operations
# ---------------------------------------------------------------------------
_hdr "Send jar and run replay on all shards"

for shard in "${SHARDS[@]}"; do
  host="${SHARD_HOST[$shard]}"
  install_dir="$INSTALL_BASE/$shard"
  replay_dir="/tmp/replay-${shard}"

  printf '\n\e[2m--- %s @ %s ---\e[0m\n' "$shard" "$host"

  # -- 2a: upload replay jar --------------------------------------------------
  _scp_up "$host" "/tmp" "$REPLAY_JAR"
  scp "${SSH_OPTS[@]}" \
    "$REPLAY_JAR" \
    "${DEPLOY_USER}@${host}:/tmp" \
    2>&1 | sed 's/^/│  /'

  # -- 2b: mkdir + tar extract ------------------------------------------------
  remote_cmd_extract="mkdir -p ${replay_dir} && tar xvf ${DATE_TAG}*.tar.gz -C ${replay_dir}"
  _ssh_run "$host" "${install_dir}/data" "$remote_cmd_extract"
  ssh "${SSH_OPTS[@]}" \
    "${DEPLOY_USER}@${host}" \
    "cd ${install_dir}/data && ${remote_cmd_extract}" \
    2>&1 | sed 's/^/│  /'

  # -- 2c: run replay ---------------------------------------------------------
  remote_cmd_replay="${JAVA} -jar /tmp/replay-stub.jar --rdat log.rdat.out --filter \"tradeId in (${TRADE_FILTER})\""
  _ssh_run "$host" "$replay_dir" "$remote_cmd_replay"
  ssh "${SSH_OPTS[@]}" \
    "${DEPLOY_USER}@${host}" \
    "cd ${replay_dir} && ${remote_cmd_replay}" \
    2>&1 | sed 's/^/│  /'
done

printf '\n\e[1;32m[ done ]\e[0m\n'
