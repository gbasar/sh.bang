#!/usr/bin/env bash
# replay-debug-jq.sh
#
# Replicates replay.shbang as a plain shell script, driven by environment.conf.
#
# PURPOSE: side-by-side comparison with replay.shbang.
#   This version derives hosts and shards dynamically from the config file,
#   which is closer to what sh.bang does.  But notice: the outer loop is still
#   hosts (a structural decision baked into this script), whereas sh.bang's
#   playbook is shard-centric — you describe one shard's operations and the
#   framework handles grouping.  sh.bang also gives dry-run, structured error
#   logging, and ControlMaster muxing for free.
#
# Steps:
#   0. Convert environment.conf (HOCON) -> JSON via hocon.jar
#   1. Derive host list and shard-per-host mapping from JSON
#   2. Build trade filter from trades.csv
#   3. For each host: scp jar, then one SSH session for all shards
#
# Usage:
#   bash examples/replay/replay-debug-jq.sh /path/to/replay-stub.jar
#
# Optional env vars:
#   SHBANG_SSH_KEY     -- path to SSH private key
#   SHBANG_SSH_CONFIG  -- SSH config file mapping hostnames to ports
#   HOCON_JAR          -- path to hocon.jar  (default: /usr/local/lib/hocon.jar)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
# Locate hocon.jar
# ---------------------------------------------------------------------------
HOCON_JAR="${HOCON_JAR:-/usr/local/lib/hocon.jar}"
if [[ ! -f $HOCON_JAR ]]; then
  echo "ERROR: hocon.jar not found at $HOCON_JAR" >&2
  echo "       Set HOCON_JAR=/path/to/hocon.jar or build via: docker compose run --rm test" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 0: HOCON -> JSON
# In sh.bang this is handled transparently by the resources {} block.
# ---------------------------------------------------------------------------
echo ""
echo "=== Converting environment.conf -> JSON ==="
echo "hocon.jar : $HOCON_JAR"
echo "conf      : $SCRIPT_DIR/environment.conf"

ENV_JSON=$(java -jar "$HOCON_JAR" "$SCRIPT_DIR/environment.conf")

echo "OK  (${#ENV_JSON} bytes)"

# ---------------------------------------------------------------------------
# Config derived from JSON
# ---------------------------------------------------------------------------
DEPLOY_USER="deploy"
DATE_TAG="20250522"
JAVA=$(jq -r '.runtime.javaHome' <<< "$ENV_JSON")

# Unique host list, derived from JSON — no hardcoding
# In sh.bang: for_each iterates shards; sh.bang tracks which host each maps to
mapfile -t HOSTS < <(jq -r '.trading.shard | to_entries[].value.host' <<< "$ENV_JSON" | sort -u)

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
# In sh.bang: $ run cat trades.csv | tr -d '\r' | tr '\n' ',' ... -> tradeFilter
# ---------------------------------------------------------------------------
echo ""
echo "=== Prepare trade filter ==="

TRADE_FILTER=$(
  cat "$SCRIPT_DIR/trades.csv" \
    | tr -d '\r' \
    | tr '\n' ',' \
    | sed 's/,$//'
)

echo "tradeFilter = $TRADE_FILTER"

# ---------------------------------------------------------------------------
# Step 2: per-host loop — one scp, one SSH session
# In sh.bang the playbook is shard-centric; sh.bang groups by host internally.
# Here we have to express that grouping explicitly.
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

  # Build remote script — all shards for this host, derived from JSON
  remote_script=""
  while IFS= read -r shard_json; do
    shard=$(jq -r '.shard'             <<< "$shard_json")
    install_dir=$(jq -r '.install.directory' <<< "$shard_json")
    replay_dir="/tmp/replay-${shard}"
    remote_script+="
echo '--- $shard ---'
cd ${install_dir}/data && mkdir -p ${replay_dir} && tar xvf ${DATE_TAG}*.tar.gz -C ${replay_dir}
cd ${replay_dir} && ${JAVA} -jar /tmp/replay-stub.jar --rdat log.rdat.out --filter 'tradeId in (${TRADE_FILTER})'
"
  done < <(jq -c --arg host "$host" '.trading.shard | to_entries[].value | select(.host == $host)' <<< "$ENV_JSON")

  echo "ssh $DEPLOY_USER@$host  (all shards on this host)"
  ssh "${SSH_OPTS[@]}" \
    "${DEPLOY_USER}@${host}" \
    "$remote_script" \
    2>&1 | sed 's/^/  | /'
done

echo ""
echo "=== done ==="
