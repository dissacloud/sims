#!/usr/bin/env bash
# Q11 (APT-based) Worker Cleanup — restore kubelet/kubectl holds and align to control-plane version.
#
# Usage (on WORKER):
#   sudo bash Q11_Apt_Cleanup_Reset_worker.bash
#   sudo TARGET_VERSION=1.34.3-1.1 bash Q11_Apt_Cleanup_Reset_worker.bash

set -euo pipefail

TARGET_VERSION="${TARGET_VERSION:-}"  # optional exact apt version to restore
NODE_NAME="$(hostname -s 2>/dev/null || hostname)"
TS="$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="/root/cis-q11-apt-cleanup-${TS}"
mkdir -p "${BACKUP_DIR}"

echo "== Q11 APT Worker Cleanup =="
echo "Date: $(date -Is)"
echo "Node: ${NODE_NAME}"
echo "Target version (optional): ${TARGET_VERSION:-<auto (latest in repo)>}"
echo "Backup dir: ${BACKUP_DIR}"
echo

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need apt-get
need awk
need sed

echo "[0] Unholding kubelet/kubectl (if held)..."
sudo apt-mark unhold kubelet kubectl >/dev/null 2>&1 || true

echo "[1] Ensuring repo metadata present..."
sudo apt-get update -y >/dev/null

echo "[2] Selecting restore versions..."
list_versions(){
  local pkg="$1"
  apt-cache madison "${pkg}" 2>/dev/null | awk '{print $3}' | head -n 50
}

if [[ -n "${TARGET_VERSION}" ]]; then
  KUBELET_VER="${TARGET_VERSION}"
  KUBECTL_VER="${TARGET_VERSION}"
else
  # Restore to newest available in repo for each package
  KUBELET_VER="$(list_versions kubelet | head -n1)"
  KUBECTL_VER="$(list_versions kubectl | head -n1)"
fi

if [[ -z "${KUBELET_VER}" || -z "${KUBECTL_VER}" ]]; then
  echo "ERROR: Could not resolve restore versions from apt metadata."
  echo "Remediation: provide TARGET_VERSION explicitly."
  exit 2
fi

echo "Restoring:"
echo "  kubelet=${KUBELET_VER}"
echo "  kubectl=${KUBECTL_VER}"
echo

echo "[3] Installing restore versions..."
sudo apt-get install -y --allow-downgrades \
  kubelet="${KUBELET_VER}" \
  kubectl="${KUBECTL_VER}" >/dev/null

echo "[4] Restarting kubelet..."
sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo
echo "[5] Post-checks:"
dpkg-query -W -f='${Package} ${Version}
' kubeadm kubelet kubectl 2>/dev/null | tee "${BACKUP_DIR}/dpkg_versions.after.txt" || true
echo "kubelet --version:"
kubelet --version || true

echo
echo "✅ Worker cleanup complete."
