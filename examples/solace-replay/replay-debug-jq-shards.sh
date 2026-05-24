#!/usr/bin/env bash
# replay-debug-jq-shards.sh
#
# Replicates replay.shbang as a plain shell script, driven by environment.conf.
#
# PURPOSE: shows the shard-centric approach — one SSH connection per command.
#   Compare with replay-debug-jq.sh (host-centric, one SSH session per host)
#   and replay.shbang (sh.bang handles connection topology automatically).
#   This version is closer to what sh.bang does internally — it reads the real
#   config file and iterates shards dynamically.  But notice what is still
#   missing compared to sh.bang: no dry-run mode, no structured error logging,
#   no ControlMaster SSH muxing, and any change to the operation sequence
#   (a new step, a different jar name, a new host) means editing this script.
#   In sh.bang those changes are a one-line edit to the playbook.
#
# Steps:
#   0. Convert environment.conf (HOCON) -> JSON via hocon.jar
#   1. Build trade filter from trades.csv
#   2. For each shard (read from JSON): scp jar, ssh extract, ssh replay
#
# Usage:
#   bash examples/solace-replay/replay-debug-jq.sh /path/to/replay-stub.jar
#
# Optional env vars (set by 'source bin/playground', or export manually):
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
# Here we do it explicitly so we can see exactly what comes out.
# ---------------------------------------------------------------------------
echo ""
echo "=== Converting environment.conf -> JSON ==="
echo "hocon.jar : $HOCON_JAR"
echo "conf      : $SCRIPT_DIR/environment.conf"

ENV_JSON=$(java -jar "$HOCON_JAR" "$SCRIPT_DIR/environment.conf")

echo "OK  (${#ENV_JSON} bytes)"

# ---------------------------------------------------------------------------
# Config derived from ENV_JSON via jq
# In sh.bang these are interpolated at playbook parse time from context JSON.
# Here we call jq explicitly for every value we need.
# ---------------------------------------------------------------------------
DEPLOY_USER="deploy"
DATE_TAG="20250522"
JAVA=$(jq -r '.runtime.javaHome' <<< "$ENV_JSON")

# Shard IDs from JSON — no hardcoded list.
# In sh.bang: for_each ${trading.shard[*]}
mapfile -t SHARD_IDS < <(jq -r '.trading.shard | keys[]' <<< "$ENV_JSON")

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
# Step 2: per-shard operations
# In sh.bang: for_each expands the shard list and runs the pipe block for each.
# Here: a plain bash for loop — same operations, but no error aggregation,
# no dry-run, and no way to skip a single shard without editing the script.
# ---------------------------------------------------------------------------
echo ""
echo "=== Send jar and run replay on all shards ==="

for id in "${SHARD_IDS[@]}"; do
  shard=$(jq -r       --arg id "$id" '.trading.shard[$id].shard'             <<< "$ENV_JSON")
  host=$(jq -r        --arg id "$id" '.trading.shard[$id].host'              <<< "$ENV_JSON")
  install_dir=$(jq -r --arg id "$id" '.trading.shard[$id].install.directory' <<< "$ENV_JSON")
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
  echo "ssh $DEPLOY_USER@$host  cd ${install_dir}/data && $remote_cmd_extract"
  ssh "${SSH_OPTS[@]}" \
    "${DEPLOY_USER}@${host}" \
    "cd ${install_dir}/data && ${remote_cmd_extract}" \
    2>&1 | sed 's/^/  | /'

  # ssh: run replay
  # In sh.bang: | @${host}:/tmp/replay-${shard} run ${runtime.javaHome} -jar ...
  remote_cmd_replay="${JAVA} -jar /tmp/replay-stub.jar --rdat log.rdat.out --filter \"tradeId in (${TRADE_FILTER})\""
  echo "ssh $DEPLOY_USER@$host  cd ${replay_dir} && $remote_cmd_replay"
  ssh "${SSH_OPTS[@]}" \
    "${DEPLOY_USER}@${host}" \
    "cd ${replay_dir} && ${remote_cmd_replay}" \
    2>&1 | sed 's/^/  | /'
done

echo ""
echo "=== done ==="
