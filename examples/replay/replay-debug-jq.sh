#!/usr/bin/env bash
# replay-debug-jq.sh
#
# Replicates the exact operations of replay.shbang as raw shell, driven
# entirely by environment.conf (HOCON) — no hardcoded shard list or paths.
#
# Step 0: converts environment.conf → JSON via hocon.jar (Lightbend Config).
# Step 1: reads all config dynamically with jq.
# Step 2+: identical SSH/SCP operations to replay-debug-nojq.sh.
#
# Use this to validate that sh.bang and raw shell produce the same result
# against the live config, and to confirm the HOCON → JSON pipeline works.
#
# Prerequisites:
#   source bin/playground          # sets SHBANG_SSH_KEY + SHBANG_SSH_CONFIG
#   export HOCON_JAR=/path/to/hocon.jar   # default: /usr/local/lib/hocon.jar
#
# Usage:
#   bash examples/replay/replay-debug-jq.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# Locate hocon.jar
# ---------------------------------------------------------------------------
HOCON_JAR="${HOCON_JAR:-/usr/local/lib/hocon.jar}"

if [[ ! -f $HOCON_JAR ]]; then
  printf 'ERROR: hocon.jar not found at %s\n' "$HOCON_JAR" >&2
  printf '       Set HOCON_JAR=/path/to/hocon.jar or build via Docker:\n' >&2
  printf '         docker compose run --rm test\n' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 0: HOCON → JSON
# ---------------------------------------------------------------------------
printf '\e[1;36m[ Converting environment.conf → JSON ]\e[0m\n'
printf '├─ \e[2mhocon.jar: %s\e[0m\n' "$HOCON_JAR"
printf '├─ \e[2mconf:      %s\e[0m\n' "$SCRIPT_DIR/environment.conf"

ENV_JSON=$(java -jar "$HOCON_JAR" "$SCRIPT_DIR/environment.conf")

printf '└─ \e[1;32mOK\e[0m  (%d bytes)\n' "${#ENV_JSON}"

# ---------------------------------------------------------------------------
# Config derived from ENV_JSON via jq
# ---------------------------------------------------------------------------
DEPLOY_USER="deploy"
INSTALL_BASE="/opt/trading"
JAVA=$(jq -r '.runtime.javaHome' <<< "$ENV_JSON")
DATE_TAG="20250522"
REPLAY_JAR="$REPO_ROOT/tools/replay-stub/replay-stub.jar"

# Shard IDs in sorted order (keys of .trading.shard)
mapfile -t SHARD_IDS < <(jq -r '.trading.shard | keys[]' <<< "$ENV_JSON")

# ---------------------------------------------------------------------------
# SSH options
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

for id in "${SHARD_IDS[@]}"; do
  shard=$(jq -r --arg id "$id" '.trading.shard[$id].shard'            <<< "$ENV_JSON")
  host=$(jq -r  --arg id "$id" '.trading.shard[$id].host'             <<< "$ENV_JSON")
  install_dir=$(jq -r --arg id "$id" '.trading.shard[$id].install.directory' <<< "$ENV_JSON")
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
