#!/usr/bin/env bash
# Setup script — runs before e2e tests.
# Creates shard directories and packages rdat fixtures into tar.gz on each target host.
#
# Usage: setup-target.sh <target_host> <shard_list> [ssh_key]
# Example: setup-target.sh target1 "shard_1 shard_2" ~/.ssh/id_rsa

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_DIR="$SCRIPT_DIR/fixtures"
INSTALL_BASE="/opt/trading"
DATE_TAG="20250522"

TARGET_HOST=$1
SHARDS=$2
SSH_KEY="${3:-$HOME/.ssh/id_rsa}"
SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -i $SSH_KEY"

echo "[setup] configuring $TARGET_HOST with shards: $SHARDS"

for shard in $SHARDS; do
  echo "[setup] setting up $shard on $TARGET_HOST"

  # Create remote dirs
  # shellcheck disable=SC2086
  ssh $SSH_OPTS deploy@"$TARGET_HOST" \
    "mkdir -p $INSTALL_BASE/$shard/data $INSTALL_BASE/$shard/app $INSTALL_BASE/$shard/log"

  # Package fixture rdat into tar.gz and push
  local_tar=$(mktemp --suffix=.tar.gz)
  tar czf "$local_tar" -C "$FIXTURE_DIR/$shard" log.rdat.out
  # shellcheck disable=SC2086
  scp $SSH_OPTS "$local_tar" \
    deploy@"$TARGET_HOST":"$INSTALL_BASE/$shard/data/${DATE_TAG}_rdat.tar.gz"
  rm -f "$local_tar"

  echo "[setup] $shard ready on $TARGET_HOST"
done

echo "[setup] $TARGET_HOST done."
