#!/usr/bin/env bash
# Q11 v5 Worker Setup — create version skew by replacing kubelet binary with a previous minor.
# Run ON the worker node as root (or via sudo).
#
# Defaults:
#   KUBELET_TAG=v1.33.3
#   ARCH=amd64
#
# Restores via the paired cleanup script.

set -euo pipefail

KUBELET_TAG="${KUBELET_TAG:-v1.33.3}"
ARCH="${ARCH:-amd64}"
BACKUP_DIR="${BACKUP_DIR:-/root/cis-q11v5-backups-20251228220353}"
BIN_URL="https://dl.k8s.io/release/${KUBELET_TAG}/bin/linux/${ARCH}/kubelet"
TMP_BIN="/tmp/kubelet-${KUBELET_TAG}-${ARCH}"

echo "== Q11 v5 Worker Setup (kubelet skew) =="
echo "Date: $(date -Is)"
echo "Node: $(hostname)"
echo "Kubelet tag: ${KUBELET_TAG}"
echo "Download: ${BIN_URL}"
echo "Backup dir: ${BACKUP_DIR}"
echo

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need curl
need systemctl

mkdir -p "$BACKUP_DIR"

echo "Recording versions before..."
{
  kubelet --version 2>/dev/null || true
  kubeadm version 2>/dev/null || true
} | tee "$BACKUP_DIR/versions.before.txt" >/dev/null

if [[ ! -x /usr/bin/kubelet ]]; then
  echo "ERROR: /usr/bin/kubelet not found or not executable"
  exit 2
fi

cp -a /usr/bin/kubelet "$BACKUP_DIR/kubelet.original"
echo "Backed up /usr/bin/kubelet -> $BACKUP_DIR/kubelet.original"

echo "Downloading kubelet..."
curl -fL "$BIN_URL" -o "$TMP_BIN"
chmod +x "$TMP_BIN"

echo "Downloaded kubelet reports:"
"$TMP_BIN" --version || true
echo

echo "Swapping kubelet binary..."
cp -a "$TMP_BIN" /usr/bin/kubelet
chmod 0755 /usr/bin/kubelet

echo "Restarting kubelet..."
systemctl daemon-reload
systemctl restart kubelet

echo "Recording versions after..."
{
  kubelet --version 2>/dev/null || true
} | tee "$BACKUP_DIR/versions.after.txt" >/dev/null

echo
echo "✅ Skew applied. kubelet should now report ${KUBELET_TAG}."
echo "   Backup: ${BACKUP_DIR}"
