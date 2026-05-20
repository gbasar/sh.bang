#!/usr/bin/env bash
# replay.sh — run a replay against every shard
# Usage: ./replay.sh context.json [--dry-run]
set -euo pipefail

CTX=${1:?usage: replay.sh context.json [--dry-run]}
DRY_RUN=${2:-}

# ---------- helpers ----------

die()  { printf '[error] %s\n' "$*" >&2; exit 1; }
log()  { printf '[replay] %s\n' "$*"; }
dry()  { [[ $DRY_RUN == --dry-run ]]; }

jq_ctx() { jq -r "$1" "$CTX"; }

ssh_run() {
  local user=$1 host=$2 cmd=$3
  dry && { log "DRY-RUN ssh $user@$host: $cmd"; return; }
  ssh -o StrictHostKeyChecking=no \
      -o BatchMode=yes \
      -o ControlMaster=auto \
      -o ControlPath="/tmp/.shbang-ctl/${user}@${host}:22" \
      -o ControlPersist=30s \
      "$user@$host" "$cmd"
}

scp_send() {
  local user=$1 host=$2 src=$3 dest=$4
  dry && { log "DRY-RUN scp $src → $user@$host:$dest"; return; }
  scp -o StrictHostKeyChecking=no \
      -o BatchMode=yes \
      -o ControlMaster=auto \
      -o ControlPath="/tmp/.shbang-ctl/${user}@${host}:22" \
      -o ControlPersist=30s \
      "$src" "$user@$host:$dest"
}

# ---------- per-shard steps (add/remove/reorder freely) ----------

step_send_jar() {
  local user=$1 host=$2
  local jar; jar=$(jq_ctx '.resources.replayJar')
  local dest; dest=$(jq_ctx '.install.dir')
  log "$host: sending $jar"
  scp_send "$user" "$host" "$jar" "$dest"
}

step_run_replay() {
  local user=$1 host=$2
  local java; java=$(jq_ctx '.resources.java')
  local dir;  dir=$(jq_ctx '.install.dir')
  log "$host: running replay"
  ssh_run "$user" "$host" "cd $dir && $java -jar replay.jar"
}

# ---------- main ----------

mkdir -p /tmp/.shbang-ctl

SHARDS=$(jq_ctx '.topology.shards | keys[]')
[[ -n $SHARDS ]] || die "no shards in $CTX"

for shard in $SHARDS; do
  host=$(jq_ctx ".topology.shards.${shard}.host")
  user=$(jq_ctx ".topology.shards.${shard}.user.name // \"deploy\"")
  log "--- $shard ($host) ---"

  step_send_jar  "$user" "$host"
  step_run_replay "$user" "$host"
done

log "done"
