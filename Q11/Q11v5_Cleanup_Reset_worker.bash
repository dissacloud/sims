#!/usr/bin/env bash
# Q11 v5 Cleanup (worker) — restore kubelet binary from the backup created by Worker Setup.

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/root/cis-q11v5-backups-20251228220353}"

echo "== Q11 v5 Cleanup (restore kubelet) =="
echo "Date: $(date -Is)"
echo "Node: $(hostname)"
echo "Backup dir: ${BACKUP_DIR}"
echo

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need systemctl

if [[ ! -f "$BACKUP_DIR/kubelet.original" ]]; then
  echo "ERROR: Backup kubelet not found at $BACKUP_DIR/kubelet.original"
  echo "If you used a different BACKUP_DIR during setup, export it and re-run:"
  echo "  BACKUP_DIR=/root/<your-backup-dir> bash $0"
  exit 2
fi

cp -a "$BACKUP_DIR/kubelet.original" /usr/bin/kubelet
chmod 0755 /usr/bin/kubelet

systemctl daemon-reload
systemctl restart kubelet

echo "Current kubelet:"
kubelet --version || true
echo "✅ Restored."
