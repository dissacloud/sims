#!/usr/bin/env bash
# Q11 Worker Cleanup — restore original kubelet

set -euo pipefail

BACKUP_DIR="/root/cis-q11-backups"
DEST_BIN="/usr/bin/kubelet"

echo "== Q11 Worker Cleanup =="
echo "Node: $(hostname)"
echo

systemctl stop kubelet
sleep 1

cp -a "${BACKUP_DIR}/kubelet.original" "${DEST_BIN}"
chmod 0755 "${DEST_BIN}"

systemctl daemon-reload
systemctl start kubelet

echo
kubelet --version
echo "✅ Q11 cleanup complete"
