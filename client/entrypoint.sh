#!/usr/bin/env bash
set -euo pipefail

mkdir -p /demo/client /home/demo/.ssh
touch /demo/client/known_hosts /demo/client/config

ln -sf /demo/client/known_hosts /home/demo/.ssh/known_hosts
ln -sf /demo/client/config /home/demo/.ssh/config

chown -h demo:demo /home/demo/.ssh/known_hosts /home/demo/.ssh/config || true
chmod 0700 /home/demo/.ssh
chmod 0644 /demo/client/known_hosts /demo/client/config

exec tail -f /dev/null
