#!/usr/bin/env bash
# Q11 v3 Cleanup/Reset (compute-0) — restore original kubelet binary backed up by setup script.
#
# Run ON compute-0 as root (or with sudo).
#
# Env overrides:
#   BACKUP_DIR=/root/cis-q11v3-backups-<timestamp>

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/root/cis-q11v3-backups-20251228204456}"

echo "🧹 Q11 v3 Cleanup — restore kubelet"
echo "Node: $(hostname)"
echo "Backup dir: $BACKUP_DIR"
echo

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need sudo
need systemctl

if [[ ! -f "$BACKUP_DIR/kubelet.original" ]]; then
  echo "ERROR: Backup kubelet not found at $BACKUP_DIR/kubelet.original"
  echo "If you used a different BACKUP_DIR during setup, export it and re-run:"
  echo "  BACKUP_DIR=/root/<your-backup-dir> bash $0"
  exit 2
fi

echo "Restoring kubelet binary..."
sudo cp -a "$BACKUP_DIR/kubelet.original" /usr/bin/kubelet
sudo chmod 0755 /usr/bin/kubelet

echo "Restarting kubelet..."
sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo "Current kubelet version:"
kubelet --version || true

echo "✅ Cleanup complete."
