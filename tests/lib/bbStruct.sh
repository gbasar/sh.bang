#!/usr/bin/env bash
# tests/lib/bbStruct.sh
#
# Blackbird fixture library — sourceable helper functions for building and
# tearing down the standard Blackbird shard directory structure on a remote
# host over SSH.
#
# Usage:
#   source tests/lib/bbStruct.sh
#   bb_create_shard_layout trading-host1 /opt/trading shard_1
#   bb_create_archive      trading-host1 /opt/trading shard_1 20260520 tests/e2e/fixtures/shard_1
#   bb_create_rdat         trading-host1 /opt/trading shard_1 fixtures/rdat.in fixtures/rdat.out
#   bb_destroy_shard       trading-host1 /opt/trading shard_1
#
# SSH key resolution (in order):
#   1. explicit [ssh_key] argument
#   2. $E2E_SSH_KEY env var
#   3. /root/.ssh/e2e_test_key (default in e2e Docker image)
#
# SSH config (optional):
#   $E2E_SSH_CONFIG env var — if set, passed as -F to all ssh/scp calls
#   Useful for playground where hosts resolve via a local SSH config file

set -euo pipefail

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_bb_ssh_opts() {
  local key="${1:-${E2E_SSH_KEY:-/root/.ssh/e2e_test_key}}"
  local cfg="${E2E_SSH_CONFIG:-}"
  local opts="-o StrictHostKeyChecking=no -o BatchMode=yes -o KexAlgorithms=ecdh-sha2-nistp256 -i ${key}"
  [[ -n $cfg ]] && opts="-F ${cfg} ${opts}"
  printf -- '%s' "$opts"
}

_bb_ssh() {
  local host=$1 key=$2
  shift 2
  local opts
  read -r -a opts <<< "$(_bb_ssh_opts "$key")"
  ssh "${opts[@]}" "deploy@${host}" "$@"
}

_bb_scp() {
  local src=$1 dst=$2 key=$3
  local opts
  read -r -a opts <<< "$(_bb_ssh_opts "$key")"
  scp "${opts[@]}" "$src" "$dst"
}

# ---------------------------------------------------------------------------
# bb_create_shard_layout <host> <install_dir> <shard> [ssh_key]
#
# Creates the full standard Blackbird directory tree for one shard:
#
#   install_dir/shard/trading/
#     app/trading/{bin,lib}
#     config/
#     data/trading/{archive,txn-log}
#     log/trading/archive
# ---------------------------------------------------------------------------
bb_create_shard_layout() {
  local host=$1 install_dir=$2 shard=$3 key="${4:-}"
  local base="${install_dir}/${shard}/trading"

  echo "[bbStruct] create layout: deploy@${host}:${base}"
  _bb_ssh "$host" "$key" "mkdir -p \
    ${base}/app/trading/bin \
    ${base}/app/trading/lib \
    ${base}/config \
    ${base}/data/trading/archive \
    ${base}/data/trading/txn-log \
    ${base}/log/trading/archive"
}

# ---------------------------------------------------------------------------
# bb_create_config <host> <install_dir> <shard> <local_conf> [ssh_key]
#
# Copies a local environment.conf into the shard config directory.
# ---------------------------------------------------------------------------
bb_create_config() {
  local host=$1 install_dir=$2 shard=$3 local_conf=$4 key="${5:-}"
  local dst="deploy@${host}:${install_dir}/${shard}/trading/config/environment.conf"

  echo "[bbStruct] create config: ${dst}"
  _bb_scp "$local_conf" "$dst" "$key"
}

# ---------------------------------------------------------------------------
# bb_create_binaries <host> <install_dir> <shard> [ssh_key]
#
# Writes stub start / stop / restart scripts into app/trading/bin/.
# start:   prints "starting <shard>" and sleeps briefly to simulate startup
# stop:    prints "stopping <shard>"
# restart: stop then start
# ---------------------------------------------------------------------------
bb_create_binaries() {
  local host=$1 install_dir=$2 shard=$3 key="${4:-}"
  local bin="${install_dir}/${shard}/trading/app/trading/bin"

  echo "[bbStruct] create binaries: deploy@${host}:${bin}"
  _bb_ssh "$host" "$key" "
    cat > ${bin}/start <<'SCRIPT'
#!/usr/bin/env bash
echo \"starting ${shard}\"
sleep 1
echo \"${shard} started\"
SCRIPT

    cat > ${bin}/stop <<'SCRIPT'
#!/usr/bin/env bash
echo \"stopping ${shard}\"
SCRIPT

    cat > ${bin}/restart <<'SCRIPT'
#!/usr/bin/env bash
\$(dirname \$0)/stop
\$(dirname \$0)/start
SCRIPT

    chmod +x ${bin}/start ${bin}/stop ${bin}/restart
  "
}

# ---------------------------------------------------------------------------
# bb_create_debug_binaries <host> <install_dir> <shard> <jar_path> <jdwp_port> [ssh_key]
#
# Like bb_create_binaries but start injects JDWP (suspend=n) and runs the
# given jar.  The app starts normally and the debugger can attach at any time.
# Use with bluebird-stub.jar for the debug-replay scenario.
# ---------------------------------------------------------------------------
bb_create_debug_binaries() {
  local host=$1 install_dir=$2 shard=$3 jar_path=$4 jdwp_port=$5 key="${6:-}"
  local bin="${install_dir}/${shard}/trading/app/trading/bin"
  local lib="${install_dir}/${shard}/trading/app/trading/lib"
  local txn_log="${install_dir}/${shard}/trading/data/trading/txn-log"

  echo "[bbStruct] create debug binaries: deploy@${host}:${bin}  jdwp=*:${jdwp_port}"

  # upload the jar into lib/
  _bb_scp "$jar_path" "deploy@${host}:${lib}/bluebird-stub.jar" "$key"

  _bb_ssh "$host" "$key" "
    cat > ${bin}/start <<SCRIPT
#!/usr/bin/env bash
echo \"[start] ${shard} starting with JDWP on port ${jdwp_port}\"
exec java \\
  -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:${jdwp_port} \\
  -jar ${lib}/bluebird-stub.jar \\
  ${txn_log}
SCRIPT

    cat > ${bin}/stop <<'SCRIPT'
#!/usr/bin/env bash
pkill -f bluebird-stub.jar || true
echo \"stopped\"
SCRIPT

    cat > ${bin}/restart <<'SCRIPT'
#!/usr/bin/env bash
\$(dirname \$0)/stop
sleep 1
\$(dirname \$0)/start
SCRIPT

    chmod +x ${bin}/start ${bin}/stop ${bin}/restart
  "
}

# ---------------------------------------------------------------------------
# bb_create_archive <host> <install_dir> <shard> <date_tag> <local_fixture_dir> [ssh_key]
#
# Packages <local_fixture_dir> into a dated tar.gz, uploads to
# data/trading/archive/, and writes a dummy .md5 alongside.
#
# Naming: trading-data-<date_tag>-001200.tar.gz
# ---------------------------------------------------------------------------
bb_create_archive() {
  local host=$1 install_dir=$2 shard=$3 date_tag=$4 fixture_dir=$5 key="${6:-}"
  local archive_name="trading-data-${date_tag}-001200.tar.gz"
  local remote_dir="${install_dir}/${shard}/trading/data/trading/archive"
  local tmp_tar
  tmp_tar=$(mktemp --suffix=.tar.gz)

  echo "[bbStruct] create archive: ${archive_name} -> deploy@${host}:${remote_dir}"
  tar czf "$tmp_tar" -C "$fixture_dir" .
  _bb_scp "$tmp_tar" "deploy@${host}:${remote_dir}/${archive_name}" "$key"
  rm -f "$tmp_tar"

  # dummy md5 alongside
  _bb_ssh "$host" "$key" \
    "md5sum ${remote_dir}/${archive_name} > ${remote_dir}/trading-data-${date_tag}-001200.md5"
}

# ---------------------------------------------------------------------------
# bb_create_rdat <host> <install_dir> <shard> <local_rdat_in> <local_rdat_out> [ssh_key]
#
# Copies rdat files directly into data/trading/txn-log/.
# Use when the scenario reads live txn-log files rather than unpacking an archive.
# ---------------------------------------------------------------------------
bb_create_rdat() {
  local host=$1 install_dir=$2 shard=$3 local_in=$4 local_out=$5 key="${6:-}"
  local txn_log="${install_dir}/${shard}/trading/data/trading/txn-log"

  echo "[bbStruct] create rdat: deploy@${host}:${txn_log}"
  _bb_scp "$local_in"  "deploy@${host}:${txn_log}/trading.rdat.in"  "$key"
  _bb_scp "$local_out" "deploy@${host}:${txn_log}/trading.rdat.out" "$key"
}

# ---------------------------------------------------------------------------
# bb_destroy_shard <host> <install_dir> <shard> [ssh_key]
#
# Removes the entire shard tree. Use in test teardown.
# ---------------------------------------------------------------------------
bb_destroy_shard() {
  local host=$1 install_dir=$2 shard=$3 key="${4:-}"

  echo "[bbStruct] destroy shard: deploy@${host}:${install_dir}/${shard}"
  _bb_ssh "$host" "$key" "rm -rf ${install_dir}/${shard}"
}
