#!/usr/bin/env bash
# Setup script — runs before e2e tests.
# Creates the standard Blackbird shard layout and populates fixture data
# on a target host using the bbStruct library.
#
# Usage:
#   setup-target.sh <target_host> <shard_list> [ssh_key]
# Example:
#   setup-target.sh trading-host1 "shard_1 shard_2"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/bbStruct.sh"

FIXTURE_DIR="$SCRIPT_DIR/fixtures"
INSTALL_BASE="/opt/trading"
DATE_TAG="20250522"

TARGET_HOST=$1
SHARDS=$2
SSH_KEY="${3:-/root/.ssh/e2e_test_key}"

echo "[setup] configuring $TARGET_HOST with shards: $SHARDS"

for shard in $SHARDS; do
  echo "[setup] $shard"
  bb_create_shard_layout "$TARGET_HOST" "$INSTALL_BASE" "$shard" "$SSH_KEY"
  bb_create_binaries     "$TARGET_HOST" "$INSTALL_BASE" "$shard" "$SSH_KEY"
  bb_create_archive      "$TARGET_HOST" "$INSTALL_BASE" "$shard" "$DATE_TAG" "$FIXTURE_DIR/$shard" "$SSH_KEY"
done

echo "[setup] $TARGET_HOST done."
