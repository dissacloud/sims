#!/usr/bin/env bash
# Q11 v6 Worker Setup — create kubelet version skew safely (handles 'Text file busy').
# Run ON the worker node as root (or via sudo).
#
# Change vs v5:
# - Stops kubelet before swapping /usr/bin/kubelet to avoid 'Text file busy'
# - Uses atomic move: install to /usr/bin/kubelet.new then mv -f
# - Verifies kubelet is stopped before replace

set -euo pipefail

KUBELET_TAG="${KUBELET_TAG:-v1.33.3}"
ARCH="${ARCH:-amd64}"
BACKUP_DIR="${BACKUP_DIR:-/root/cis-q11v6-backups-20251228222950}"

BIN_URL="https://dl.k8s.io/release/${KUBELET_TAG}/bin/linux/${ARCH}/kubelet"
TMP_BIN="/tmp/kubelet-${KUBELET_TAG}-${ARCH}"
NEW_BIN="/usr/bin/kubelet.new"
DEST_BIN="/usr/bin/kubelet"

echo "== Q11 v6 Worker Setup (kubelet skew) =="
echo "Date: $(date -Is)"
echo "Node: $(hostname)"
echo "Kubelet tag: $KUBELET_TAG"
echo "Download: $BIN_URL"
echo "Backup dir: $BACKUP_DIR"
echo

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need curl
need systemctl
need mv
need chmod
need cp

mkdir -p "$BACKUP_DIR"

echo "Recording versions before..."
{
  kubelet --version 2>/dev/null || true
  kubeadm version 2>/dev/null || true
} | tee "$BACKUP_DIR/versions.before.txt" >/dev/null

if [[ ! -x "$DEST_BIN" ]]; then
  echo "ERROR: $DEST_BIN not found or not executable"
  exit 2
fi

cp -a "$DEST_BIN" "$BACKUP_DIR/kubelet.original"
echo "Backed up $DEST_BIN -> $BACKUP_DIR/kubelet.original"

echo
echo "Stopping kubelet to avoid 'Text file busy'..."
systemctl stop kubelet || true

# Wait briefly for kubelet process to exit
for i in {1..10}; do
  if pgrep -x kubelet >/dev/null 2>&1; then
    sleep 0.5
  else
    break
  fi
done

if pgrep -x kubelet >/dev/null 2>&1; then
  echo "WARNING: kubelet process still running; attempting replace anyway may fail."
  echo "If it fails again, run: sudo pkill -x kubelet ; sudo systemctl stop kubelet"
fi

echo
echo "Downloading kubelet..."
curl -fL "$BIN_URL" -o "$TMP_BIN"
chmod +x "$TMP_BIN"

echo "Downloaded kubelet reports:"
"$TMP_BIN" --version || true
echo

echo "Installing new kubelet atomically..."
cp -a "$TMP_BIN" "$NEW_BIN"
chmod 0755 "$NEW_BIN"
mv -f "$NEW_BIN" "$DEST_BIN"
chmod 0755 "$DEST_BIN"

echo "Starting kubelet..."
systemctl daemon-reload
systemctl start kubelet

echo "Recording versions after..."
kubelet --version 2>/dev/null | tee "$BACKUP_DIR/versions.after.txt" >/dev/null || true

echo
echo "✅ Skew applied. kubelet should now report $KUBELET_TAG."
echo "   Backup: $BACKUP_DIR"
