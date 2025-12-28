#!/usr/bin/env bash
# Q11 v6 Cleanup (worker) — restore kubelet binary from the backup created by Worker Setup.

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/root/cis-q11v6-backups-20251228222950}"
DEST_BIN="/usr/bin/kubelet"

echo "== Q11 v6 Cleanup (restore kubelet) =="
echo "Date: $(date -Is)"
echo "Node: $(hostname)"
echo "Backup dir: $BACKUP_DIR"
echo

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need systemctl
need mv
need chmod
need cp

if [[ ! -f "$BACKUP_DIR/kubelet.original" ]]; then
  echo "ERROR: Backup kubelet not found at $BACKUP_DIR/kubelet.original"
  echo "If you used a different BACKUP_DIR during setup, export it and re-run:"
  echo "  BACKUP_DIR=/root/<your-backup-dir> bash $0"
  exit 2
fi

echo "Stopping kubelet..."
systemctl stop kubelet || true
sleep 1

echo "Restoring kubelet..."
cp -a "$BACKUP_DIR/kubelet.original" "$DEST_BIN"
chmod 0755 "$DEST_BIN"

echo "Starting kubelet..."
systemctl daemon-reload
systemctl start kubelet

echo "Current kubelet:"
kubelet --version || true
echo "✅ Restored."
