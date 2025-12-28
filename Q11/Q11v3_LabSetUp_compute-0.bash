#!/usr/bin/env bash
# Q11 v3 Lab Setup (compute-0) — create version skew by swapping kubelet binary to previous minor.
# Default: download kubelet v1.33.3 (linux/amd64) and replace /usr/bin/kubelet (backup first).
#
# Run ON compute-0 as root (or with sudo).
#
# Env overrides:
#   KUBELET_TAG=v1.33.3   (or any v1.33.x / v1.32.x)
#   ARCH=amd64            (default)
#   BACKUP_DIR=/root/cis-q11v3-backups-<timestamp>

set -euo pipefail

KUBELET_TAG="${KUBELET_TAG:-v1.33.3}"
ARCH="${ARCH:-amd64}"
BACKUP_DIR="${BACKUP_DIR:-/root/cis-q11v3-backups-20251228204456}"
BIN_URL="https://dl.k8s.io/release/${KUBELET_TAG}/bin/linux/${ARCH}/kubelet"
TMP_BIN="/tmp/kubelet-${KUBELET_TAG}-${ARCH}"

echo "🚀 Q11 v3 Worker Setup — kubelet binary skew"
echo "Node: $(hostname)"
echo "Kubelet tag: $KUBELET_TAG"
echo "Download: $BIN_URL"
echo "Backup dir: $BACKUP_DIR"
echo

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need sudo
need curl
need systemctl

sudo mkdir -p "$BACKUP_DIR"

echo "Recording current versions..."
{
  kubelet --version 2>/dev/null || true
  kubeadm version 2>/dev/null || true
  kubectl version --client --short 2>/dev/null || true
} | tee "$BACKUP_DIR/versions.before.txt" >/dev/null

# Backup existing kubelet binary
if [[ -x /usr/bin/kubelet ]]; then
  sudo cp -a /usr/bin/kubelet "$BACKUP_DIR/kubelet.original"
  echo "Backed up /usr/bin/kubelet -> $BACKUP_DIR/kubelet.original"
else
  echo "ERROR: /usr/bin/kubelet not found or not executable"
  exit 2
fi

echo "Downloading kubelet binary..."
curl -fL "$BIN_URL" -o "$TMP_BIN"
chmod +x "$TMP_BIN"

echo "Downloaded kubelet version:"
"$TMP_BIN" --version || true

echo "Swapping kubelet binary..."
sudo cp -a "$TMP_BIN" /usr/bin/kubelet
sudo chmod 0755 /usr/bin/kubelet

echo "Restarting kubelet..."
sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo "Recording versions after swap..."
{
  kubelet --version 2>/dev/null || true
} | tee "$BACKUP_DIR/versions.after.txt" >/dev/null

echo
echo "✅ Q11 v3 skew applied. Kubelet should now report ${KUBELET_TAG}."
echo "   To restore, run: /tmp/Q11v3_Cleanup_Reset_compute-0.bash (or the provided cleanup script)."
