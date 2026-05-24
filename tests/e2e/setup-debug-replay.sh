#!/usr/bin/env bash
# Setup script for the debug-replay scenario.
# Builds the full Blackbird layout on each target host, drops in rdat fixtures,
# and creates debug start scripts with JDWP enabled (suspend=n).
#
# Usage:
#   setup-debug-replay.sh [ssh_key]
#
# Hosts and shards are hardcoded to match docker-compose.yml:
#   trading-host1 — shard_1 (jdwp: 5005)  shard_2 (jdwp: 5006)
#   trading-host2 — shard_3 (jdwp: 5005)  shard_4 (jdwp: 5006)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/bbStruct.sh"

INSTALL_BASE="/opt/trading"
SSH_KEY="${1:-/root/.ssh/e2e_test_key}"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/debug-replay"
BLACKBIRD_JAR="$ROOT/tools/blackbird-stub/blackbird-stub.jar"

[[ -f $BLACKBIRD_JAR ]] || {
  echo "ERROR: blackbird-stub.jar not found at $BLACKBIRD_JAR" >&2
  echo "       Build via: docker compose run --rm e2e" >&2
  exit 1
}

echo "=== setup: debug-replay ==="

declare -A SHARD_HOST=( [shard_1]=trading-host1 [shard_2]=trading-host1
                        [shard_3]=trading-host2 [shard_4]=trading-host2 )
declare -A SHARD_PORT=( [shard_1]=5005 [shard_2]=5006
                        [shard_3]=5005 [shard_4]=5006 )

for shard in shard_1 shard_2 shard_3 shard_4; do
  host="${SHARD_HOST[$shard]}"
  port="${SHARD_PORT[$shard]}"

  echo "--- $shard @ $host  jdwp=*:$port ---"

  bb_create_shard_layout    "$host" "$INSTALL_BASE" "$shard" "$SSH_KEY"
  bb_create_debug_binaries  "$host" "$INSTALL_BASE" "$shard" "$BLACKBIRD_JAR" "$port" "$SSH_KEY"
  bb_create_rdat            "$host" "$INSTALL_BASE" "$shard" \
                            "$FIXTURE_DIR/trading.rdat.in" \
                            "$FIXTURE_DIR/trading.rdat.out" \
                            "$SSH_KEY"
done

echo ""
echo "=== debug-replay ready ==="
echo ""
echo "Start the app on any shard:"
echo "  ssh deploy@trading-host1  # port 2221 from host"
echo "  cd /opt/trading/shard_1/trading/app/trading/bin && ./start"
echo ""
echo "Attach IntelliJ debugger (from host machine):"
echo "  shard_1  localhost:5005"
echo "  shard_2  localhost:5006"
echo "  shard_3  localhost:5007"
echo "  shard_4  localhost:5008"
echo ""
echo "The app will load static data, replay rdat.in through OrderEventHandler,"
echo "then wait for live messages. Set a breakpoint on:"
echo "  OrderEventHandler.process()  condition: orderId.equals(\"ORD-12345\")"
