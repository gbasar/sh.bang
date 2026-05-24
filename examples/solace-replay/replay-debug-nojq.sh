#!/usr/bin/env bash
# replay-debug-nojq.sh
#
# Replicates replay.shbang as a plain shell script — no sh.bang framework,
# no jq, no repo dependencies.  Copy this single file to any jump host.
#
# PURPOSE: side-by-side comparison with replay.shbang.
#   Here the outer loop is hosts, and all shard commands run inside a single
#   SSH session per host.  In sh.bang the playbook is shard-centric — you
#   describe what happens to each shard and sh.bang handles the connection
#   topology via ControlMaster.  Moving a shard to a different host means
#   one line in environment.conf; here it means restructuring this script.
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
# Config — all values hardcoded; edit here to match your environment
# ---------------------------------------------------------------------------
INSTALL_BASE="/opt/trading"
JAVA="/usr/bin/java"
DATE_TAG="20250522"
DEPLOY_USER="deploy"

TRADE_FILTER="trade_001,trade_002,trade_003,trade_004,trade_005"

# Host list — outer loop
declare -a HOSTS=(trading-host1 trading-host2)

# Shards per host — edit this when a shard moves
declare -A HOST_SHARDS=(
  [trading-host1]="shard_1 shard_2"
  [trading-host2]="shard_3 shard_4"
)

# ---------------------------------------------------------------------------
# SSH options
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
# ---------------------------------------------------------------------------
echo ""
echo "=== Trade filter ==="
echo "tradeFilter = $TRADE_FILTER"

# ---------------------------------------------------------------------------
# Step 2: per-host loop — one scp, one ssh session
# ---------------------------------------------------------------------------
echo ""
echo "=== Send jar and run replay on all shards ==="

for host in "${HOSTS[@]}"; do
  echo ""
  echo "--- $host ---"

  # scp: upload replay jar once per host
  echo "scp $REPLAY_JAR -> $DEPLOY_USER@$host:/tmp"
  scp "${SSH_OPTS[@]}" \
    "$REPLAY_JAR" \
    "${DEPLOY_USER}@${host}:/tmp" \
    2>&1 | sed 's/^/  | /'

  # Build the remote script — all shards for this host in one SSH session
  remote_script=""
  for shard in ${HOST_SHARDS[$host]}; do
    install_dir="$INSTALL_BASE/$shard"
    replay_dir="/tmp/replay-${shard}"
    remote_script+="
echo '--- $shard ---'
mkdir -p ${replay_dir} && tar xvf ${DATE_TAG}*.tar.gz -C ${replay_dir}  # extract
cd ${install_dir}/data
${JAVA} -jar /tmp/replay-stub.jar --rdat log.rdat.out --filter 'tradeId in (${TRADE_FILTER})'
"
  done

  echo "ssh $DEPLOY_USER@$host  (all shards: ${HOST_SHARDS[$host]})"
  ssh "${SSH_OPTS[@]}" \
    "${DEPLOY_USER}@${host}" \
    "$remote_script" \
    2>&1 | sed 's/^/  | /'
done

echo ""
echo "=== done ==="
