
#!/usr/bin/env bash
# Q11 Worker Setup — create kubelet version skew (exam-safe)

set -euo pipefail

KUBELET_TAG="${KUBELET_TAG:-v1.33.3}"
ARCH="amd64"
BACKUP_DIR="/root/cis-q11-backups"

BIN_URL="https://dl.k8s.io/release/${KUBELET_TAG}/bin/linux/${ARCH}/kubelet"
TMP_BIN="/tmp/kubelet-${KUBELET_TAG}"
DEST_BIN="/usr/bin/kubelet"

echo "== Q11 Worker Setup =="
echo "Node: $(hostname)"
echo "Target kubelet: ${KUBELET_TAG}"
echo

mkdir -p "${BACKUP_DIR}"

echo "[1] Backing up kubelet"
cp -a "${DEST_BIN}" "${BACKUP_DIR}/kubelet.original"

echo "[2] Stopping kubelet"
systemctl stop kubelet
sleep 1

echo "[3] Downloading kubelet"
curl -fL "${BIN_URL}" -o "${TMP_BIN}"
chmod +x "${TMP_BIN}"
"${TMP_BIN}" --version

echo "[4] Installing kubelet"
cp "${TMP_BIN}" "${DEST_BIN}"
chmod 0755 "${DEST_BIN}"

echo "[5] Starting kubelet"
systemctl daemon-reload
systemctl start kubelet

echo
kubelet --version
echo "✅ Q11 worker skew applied"
