#!/usr/bin/env bash
# replay-debug-nojq.sh
#
# Replicates the exact operations of replay.shbang as raw shell — no sh.bang
# framework, no jq, no repo file dependencies.  Fully self-contained: copy
# this single file to any jump host and run it.
#
# Usage:
#   bash replay-debug-nojq.sh /path/to/replay-stub.jar
#
# Optional env vars (set by 'source bin/playground', or manually):
#   SHBANG_SSH_KEY     — path to SSH private key
#   SHBANG_SSH_CONFIG  — path to SSH config file (provides host → port mapping)

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  printf 'usage: %s /path/to/replay-stub.jar\n' "$(basename "$0")" >&2
  exit 1
fi

REPLAY_JAR="$1"
[[ -f $REPLAY_JAR ]] || { printf 'ERROR: jar not found: %s\n' "$REPLAY_JAR" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Config — all values hardcoded; change here to match your environment
# ---------------------------------------------------------------------------
INSTALL_BASE="/opt/trading"
JAVA="/usr/bin/java"
DATE_TAG="20250522"
DEPLOY_USER="deploy"

# Trade IDs to replay (one per line, no trailing comma needed)
TRADE_FILTER="trade_001,trade_002,trade_003,trade_004,trade_005"

# Shard list and host mapping
declare -a SHARDS=(shard_1 shard_2 shard_3 shard_4)
declare -A SHARD_HOST=(
  [shard_1]=trading-host1
  [shard_2]=trading-host1
  [shard_3]=trading-host2
  [shard_4]=trading-host2
)

# ---------------------------------------------------------------------------
# SSH options — built as an array to avoid word-splitting on paths with spaces
# ControlMaster omitted deliberately: debug scripts should show every connection
# ---------------------------------------------------------------------------
SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o BatchMode=yes
  -o KexAlgorithms=ecdh-sha2-nistp256
)

[[ -n ${SHBANG_SSH_KEY:-}    ]] && SSH_OPTS+=(-i "$SHBANG_SSH_KEY")    || printf 'WARN: SHBANG_SSH_KEY not set\n'    >&2
[[ -n ${SHBANG_SSH_CONFIG:-} ]] && SSH_OPTS+=(-F "$SHBANG_SSH_CONFIG") || printf 'WARN: SHBANG_SSH_CONFIG not set\n' >&2

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_hdr()     { printf '\n\e[1;36m[ %s ]\e[0m\n' "$*"; }
_scp_up()  { printf '├─ \e[1;34mscp ↑\e[0m  \e[1;32m@%s\e[0m\e[2;3m:%s\e[0m  %s\n' "$1" "$2" "$3"; }
_ssh_run() { printf '├─ \e[1;35mssh →\e[0m  \e[1;32m@%s\e[0m\e[2;3m:%s\e[0m  %s\n' "$1" "$2" "$3"; }

# ---------------------------------------------------------------------------
# Step 1: confirm trade filter
# ---------------------------------------------------------------------------
_hdr "Trade filter"
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
