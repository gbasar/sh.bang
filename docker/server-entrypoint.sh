#!/usr/bin/env bash
# Inject SSH_PUBKEY into deploy user's authorized_keys then start sshd
set -euo pipefail

if [[ -n ${SSH_PUBKEY:-} ]]; then
  mkdir -p /home/deploy/.ssh
  echo "$SSH_PUBKEY" > /home/deploy/.ssh/authorized_keys
  chmod 700 /home/deploy/.ssh
  chmod 600 /home/deploy/.ssh/authorized_keys
  chown -R deploy:deploy /home/deploy/.ssh
fi

exec /usr/sbin/sshd -D -e
