#!/usr/bin/env bash
# Q11 (APT-based) Worker Cleanup — restore repo + align kubelet/kubectl via apt (v3)
#
# Fix vs v2:
# - gpg runs non-interactively (no /dev/tty) using --batch/--yes/--no-tty.
#
# Usage:
#   sudo RESTORE_MINOR=1.34 bash /tmp/Q11_Apt_Cleanup_Reset_worker.bash

set -euo pipefail

RESTORE_MINOR="${RESTORE_MINOR:-1.34}"
TARGET_VERSION="${TARGET_VERSION:-}"

NODE_NAME="$(hostname -s 2>/dev/null || hostname)"
TS="$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="/root/cis-q11-apt-cleanup-${TS}"
mkdir -p "${BACKUP_DIR}"

echo "== Q11 APT Worker Cleanup v3 =="
echo "Date: $(date -Is)"
echo "Node: ${NODE_NAME}"
echo "Restore minor repo: ${RESTORE_MINOR}"
echo "Target version (optional): ${TARGET_VERSION:-<auto (latest in repo)>}"
echo "Backup dir: ${BACKUP_DIR}"
echo

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need apt-get
need awk
need curl
need gpg

sudo mkdir -p /etc/apt/keyrings
sudo apt-get update -y >/dev/null
sudo apt-get install -y ca-certificates curl gnupg >/dev/null

KEYRING="/etc/apt/keyrings/kubernetes-archive-keyring.gpg"
LIST_FILE="/etc/apt/sources.list.d/kubernetes.list"

[[ -f "${LIST_FILE}" ]] && cp -a "${LIST_FILE}" "${BACKUP_DIR}/kubernetes.list.bak" || true
[[ -f "${KEYRING}" ]] && cp -a "${KEYRING}" "${BACKUP_DIR}/kubernetes-archive-keyring.gpg.bak" || true

REPO_MINOR="v${RESTORE_MINOR}"
REPO_URL="https://pkgs.k8s.io/core:/stable:/${REPO_MINOR}/deb/"
REPO_KEY_URL="${REPO_URL}Release.key"

curl -fsSL "${REPO_KEY_URL}" | sudo gpg --dearmor --batch --yes --no-tty -o "${KEYRING}"
echo "deb [signed-by=${KEYRING}] ${REPO_URL} /" | sudo tee "${LIST_FILE}" >/dev/null

sudo apt-get update -y >/dev/null
echo "✅ Repo set to: ${REPO_URL}"
echo

echo "[0] Unholding kubelet/kubectl (if held)..."
sudo apt-mark unhold kubelet kubectl >/dev/null 2>&1 || true

list_versions(){ apt-cache madison "$1" 2>/dev/null | awk '{print $3}' | head -n 50; }

if [[ -n "${TARGET_VERSION}" ]]; then
  KUBELET_VER="${TARGET_VERSION}"
  KUBECTL_VER="${TARGET_VERSION}"
else
  KUBELET_VER="$(list_versions kubelet | head -n1)"
  KUBECTL_VER="$(list_versions kubectl | head -n1)"
fi

if [[ -z "${KUBELET_VER}" || -z "${KUBECTL_VER}" ]]; then
  echo "ERROR: Could not resolve restore versions from apt metadata for ${REPO_MINOR}."
  echo "kubelet:"; list_versions kubelet | head -n 10 || true
  echo "kubectl:"; list_versions kubectl | head -n 10 || true
  exit 2
fi

echo "Restoring:"
echo "  kubelet=${KUBELET_VER}"
echo "  kubectl=${KUBECTL_VER}"
echo

sudo apt-get install -y --allow-downgrades   kubelet="${KUBELET_VER}"   kubectl="${KUBECTL_VER}" >/dev/null

sudo systemctl daemon-reload
sudo systemctl restart kubelet

dpkg-query -W -f='${Package} ${Version}\n' kubeadm kubelet kubectl 2>/dev/null | tee "${BACKUP_DIR}/dpkg_versions.after.txt" || true
kubelet --version || true

echo
echo "✅ Worker cleanup complete."
