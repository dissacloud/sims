#!/usr/bin/env bash
# Q11 (APT-based) Worker Setup — create kubelet/kubectl skew via apt repo for TARGET_MINOR (v2)
#
# Key change vs v1:
# - Configures the Kubernetes apt repo channel dynamically from TARGET_MINOR:
#     https://pkgs.k8s.io/core:/stable:/v${TARGET_MINOR}/deb/
#   so minor downgrades (e.g., 1.33) are actually available.
#
# Usage:
#   sudo bash /tmp/Q11_Apt_LabSetUp_worker.bash
#   sudo TARGET_MINOR=1.33 bash /tmp/Q11_Apt_LabSetUp_worker.bash
#   sudo TARGET_MINOR=1.33 TARGET_VERSION=1.33.3-1.1 bash /tmp/Q11_Apt_LabSetUp_worker.bash

set -euo pipefail

TARGET_MINOR="${TARGET_MINOR:-1.33}"
TARGET_VERSION="${TARGET_VERSION:-}"  # optional exact apt version string (e.g. 1.33.3-1.1)

NODE_NAME="$(hostname -s 2>/dev/null || hostname)"
TS="$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="/root/cis-q11-apt-backups-${TS}"
mkdir -p "${BACKUP_DIR}"

echo "== Q11 APT Worker Setup (skew creation) v2 =="
echo "Date: $(date -Is)"
echo "Node: ${NODE_NAME}"
echo "Target minor: ${TARGET_MINOR}"
echo "Target version (optional): ${TARGET_VERSION:-<auto>}"
echo "Backup dir: ${BACKUP_DIR}"
echo

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need apt-get
need awk
need grep
need sed
need curl
need gpg

echo "[0] Recording current package versions..."
dpkg-query -W -f='${Package} ${Version}\n' kubeadm kubelet kubectl 2>/dev/null | tee "${BACKUP_DIR}/dpkg_versions.before.txt" || true
echo

echo "[1] Ensuring Kubernetes apt repo configured for TARGET_MINOR=${TARGET_MINOR} (pkgs.k8s.io)..."
sudo mkdir -p /etc/apt/keyrings
sudo apt-get update -y >/dev/null
sudo apt-get install -y ca-certificates curl gnupg >/dev/null

KEYRING="/etc/apt/keyrings/kubernetes-archive-keyring.gpg"
LIST_FILE="/etc/apt/sources.list.d/kubernetes.list"

# Backup existing repo list (if any)
if [[ -f "${LIST_FILE}" ]]; then
  cp -a "${LIST_FILE}" "${BACKUP_DIR}/kubernetes.list.bak"
fi
if [[ -f "${KEYRING}" ]]; then
  cp -a "${KEYRING}" "${BACKUP_DIR}/kubernetes-archive-keyring.gpg.bak"
fi

REPO_MINOR="v${TARGET_MINOR}"
REPO_URL="https://pkgs.k8s.io/core:/stable:/${REPO_MINOR}/deb/"
REPO_KEY_URL="${REPO_URL}Release.key"

# Install key for this channel
curl -fsSL "${REPO_KEY_URL}" | sudo gpg --dearmor -o "${KEYRING}"

# Configure repo list for this channel
echo "deb [signed-by=${KEYRING}] ${REPO_URL} /" | sudo tee "${LIST_FILE}" >/dev/null

sudo apt-get update -y >/dev/null
echo "✅ Repo set to: ${REPO_URL}"
echo

echo "[2] Resolving target versions from apt metadata..."
list_versions(){
  local pkg="$1"
  apt-cache madison "${pkg}" 2>/dev/null | awk '{print $3}' | head -n 50
}

if [[ -n "${TARGET_VERSION}" ]]; then
  KUBELET_VER="${TARGET_VERSION}"
  KUBECTL_VER="${TARGET_VERSION}"
else
  # Choose the newest available version in this minor channel.
  KUBELET_VER="$(list_versions kubelet | head -n1)"
  KUBECTL_VER="$(list_versions kubectl | head -n1)"
fi

if [[ -z "${KUBELET_VER}" || -z "${KUBECTL_VER}" ]]; then
  echo "ERROR: Could not resolve kubelet/kubectl versions from apt metadata for ${REPO_MINOR}."
  echo "Diagnostics:"
  echo "kubelet:"; list_versions kubelet | head -n 10 || true
  echo "kubectl:"; list_versions kubectl | head -n 10 || true
  exit 2
fi

echo "Selected versions:"
echo "  kubelet=${KUBELET_VER}"
echo "  kubectl=${KUBECTL_VER}"
echo

echo "[3] Holding kubeadm (leave as-is) and installing older kubelet/kubectl..."
sudo apt-mark hold kubeadm >/dev/null 2>&1 || true

sudo apt-get install -y --allow-downgrades   kubelet="${KUBELET_VER}"   kubectl="${KUBECTL_VER}" >/dev/null

sudo apt-mark hold kubelet kubectl >/dev/null 2>&1 || true

echo "[4] Restarting kubelet..."
sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo
echo "[5] Post-checks:"
dpkg-query -W -f='${Package} ${Version}\n' kubeadm kubelet kubectl 2>/dev/null | tee "${BACKUP_DIR}/dpkg_versions.after.txt" || true
echo "kubelet --version:"
kubelet --version || true

echo
echo "✅ Worker skew created (apt-based)."
echo "Note: repo is now pinned to ${REPO_MINOR}. Your solution should switch repo back to control-plane minor when upgrading."
