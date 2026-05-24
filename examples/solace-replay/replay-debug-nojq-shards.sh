#!/usr/bin/env bash
# replay-debug-nojq-shards.sh
#
# Replicates replay.shbang as a plain shell script — no sh.bang framework,
# no jq, no repo dependencies.  Copy this single file to any jump host.
#
# PURPOSE: shows the shard-centric approach — one SSH connection per command.
#   Compare with replay-debug-nojq.sh (host-centric, one SSH session per host)
#   and replay.shbang (sh.bang handles connection topology automatically).
#   In sh.bang you edit the playbook to add a shard, change a host, or swap
#   the trade filter.  Here every one of those things requires editing this
#   script, finding the right variable, and re-deploying it.  sh.bang also
#   gives you dry-run, structured error logging, and ControlMaster SSH muxing
#   out of the box — none of that is here.
#
# Usage:
#   bash replay-debug-nojq.sh /path/to/replay-stub.jar
#
# Optional env vars (set by 'source bin/playground', or export manually):
#   SHBANG_SSH_KEY     -- path to SSH private key
#   SHBANG_SSH_CONFIG  -- SSH config file mapping hostnames to ports

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "usage: $(basename "$0") /path/to/replay-stub.jar" >&2
  exit 1
fi

REPLAY_JAR="$1"
[[ -f $REPLAY_JAR ]] || { echo "ERROR: jar not found: $REPLAY_JAR" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Config
# To add a shard or change a host you must edit this script and redeploy it.
# In sh.bang you would update environment.conf and re-run the playbook.
# ---------------------------------------------------------------------------
INSTALL_BASE="/opt/trading"
JAVA="/usr/bin/java"
DATE_TAG="20250522"
DEPLOY_USER="deploy"

# Trade filter — hardcoded here.
# In sh.bang this is captured at runtime from trades.csv via a local $ command.
TRADE_FILTER="trade_001,trade_002,trade_003,trade_004,trade_005"

# Shard list — hardcoded here.
# In sh.bang: 'for_each ${trading.shard[*]}' iterates context JSON at runtime.
declare -a SHARDS=(shard_1 shard_2 shard_3 shard_4)
declare -A SHARD_HOST=(
  [shard_1]=trading-host1
  [shard_2]=trading-host1
  [shard_3]=trading-host2
  [shard_4]=trading-host2
)

# ---------------------------------------------------------------------------
# SSH options
# In sh.bang these are built once in dispatch.sh and applied to every command.
# ControlMaster omitted here intentionally — shows each connection explicitly.
# ---------------------------------------------------------------------------
SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o BatchMode=yes
  -o KexAlgorithms=ecdh-sha2-nistp256
)

[[ -n ${SHBANG_SSH_KEY:-}    ]] && SSH_OPTS+=(-i "$SHBANG_SSH_KEY")    || echo "WARN: SHBANG_SSH_KEY not set"    >&2
[[ -n ${SHBANG_SSH_CONFIG:-} ]] && SSH_OPTS+=(-F "$SHBANG_SSH_CONFIG") || echo "WARN: SHBANG_SSH_CONFIG not set" >&2

# ---------------------------------------------------------------------------
# Step 1: trade filter
# In sh.bang: $ run cat trades.csv | tr -d '\r' | tr '\n' ',' ... -> tradeFilter
# Here it is just a hardcoded string above — no capture, no live CSV.
# ---------------------------------------------------------------------------
echo ""
echo "=== Trade filter ==="
echo "tradeFilter = $TRADE_FILTER"

# ---------------------------------------------------------------------------
# Step 2: per-shard operations
# In sh.bang: for_each expands the shard list from context JSON.
# Here: a plain bash for loop over a hardcoded array.
# ---------------------------------------------------------------------------
echo ""
echo "=== Send jar and run replay on all shards ==="

for shard in "${SHARDS[@]}"; do
  host="${SHARD_HOST[$shard]}"
  install_dir="$INSTALL_BASE/$shard"
  replay_dir="/tmp/replay-${shard}"

  echo ""
  echo "--- $shard @ $host ---"

  # scp: upload replay jar
  # In sh.bang: | @${host}:/tmp send ${replayJar}
  echo "scp $REPLAY_JAR -> $DEPLOY_USER@$host:/tmp"
  scp "${SSH_OPTS[@]}" \
    "$REPLAY_JAR" \
    "${DEPLOY_USER}@${host}:/tmp" \
    2>&1 | sed 's/^/  | /'

  # ssh: mkdir + tar extract
  # In sh.bang: | @${host}:${install.directory}/data run mkdir -p ... && tar xvf ...
  remote_cmd_extract="mkdir -p ${replay_dir} && tar xvf ${DATE_TAG}*.tar.gz -C ${replay_dir}"
  echo "ssh $DEPLOY_USER@$host cd ${install_dir}/data && $remote_cmd_extract"
  ssh "${SSH_OPTS[@]}" \
    "${DEPLOY_USER}@${host}" \
    "cd ${install_dir}/data && ${remote_cmd_extract}" \
    2>&1 | sed 's/^/  | /'

  # ssh: run replay
  # In sh.bang: | @${host}:/tmp/replay-${shard} run ${runtime.javaHome} -jar ...
  remote_cmd_replay="${JAVA} -jar /tmp/replay-stub.jar --rdat log.rdat.out --filter \"tradeId in (${TRADE_FILTER})\""
  echo "ssh $DEPLOY_USER@$host cd ${replay_dir} && $remote_cmd_replay"
  ssh "${SSH_OPTS[@]}" \
    "${DEPLOY_USER}@${host}" \
    "cd ${replay_dir} && ${remote_cmd_replay}" \
    2>&1 | sed 's/^/  | /'
done

echo ""
echo "=== done ==="
