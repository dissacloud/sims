#!/usr/bin/env bash
# Q11 (APT-based) Worker Setup — create kubelet/kubectl skew via apt pinning.
#
# What it does:
# - Records currently installed kubeadm/kubelet/kubectl versions (backup file)
# - Ensures Kubernetes apt repo is configured (pkgs.k8s.io)
# - Downgrades kubelet + kubectl to a previous minor version (default: 1.33.x)
#   leaving the control-plane untouched.
#
# Usage (on WORKER):
#   sudo bash Q11_Apt_LabSetUp_worker.bash
#   sudo TARGET_MINOR=1.33 bash Q11_Apt_LabSetUp_worker.bash
#   sudo TARGET_VERSION=1.33.3-1.1 bash Q11_Apt_LabSetUp_worker.bash   # exact apt version string
#
# Notes:
# - This script requires outbound internet to fetch repo metadata and packages.
# - If the repo does not contain the requested minor, the script exits with a clear error.

set -euo pipefail

TARGET_MINOR="${TARGET_MINOR:-1.33}"
TARGET_VERSION="${TARGET_VERSION:-}"  # optional exact apt version (e.g. 1.33.3-1.1)

NODE_NAME="$(hostname -s 2>/dev/null || hostname)"
TS="$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="/root/cis-q11-apt-backups-${TS}"
mkdir -p "${BACKUP_DIR}"

echo "== Q11 APT Worker Setup (skew creation) =="
echo "Date: $(date -Is)"
echo "Node: ${NODE_NAME}"
echo "Target minor: ${TARGET_MINOR}"
echo "Backup dir: ${BACKUP_DIR}"
echo

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need apt-get
need awk
need grep
need sed

echo "[0] Recording current package versions..."
dpkg-query -W -f='${Package} ${Version}
' kubeadm kubelet kubectl 2>/dev/null | tee "${BACKUP_DIR}/dpkg_versions.before.txt" || true
echo

echo "[1] Ensuring Kubernetes apt repo configured (pkgs.k8s.io)..."
# Repo keyring path
KEYRING="/etc/apt/keyrings/kubernetes-archive-keyring.gpg"
sudo mkdir -p /etc/apt/keyrings

# Install prerequisites
sudo apt-get update -y >/dev/null
sudo apt-get install -y ca-certificates curl gnupg >/dev/null

# Add key if missing
if [[ ! -f "${KEYRING}" ]]; then
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o "${KEYRING}"
fi

# Add repo list (we use v1.34 channel; it typically contains multiple patch versions of that minor.
# We still *downgrade* by selecting an older minor if present in the repo metadata; if not present, we fail clearly.)
LIST_FILE="/etc/apt/sources.list.d/kubernetes.list"
if [[ ! -f "${LIST_FILE}" ]]; then
  echo "deb [signed-by=${KEYRING}] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" | sudo tee "${LIST_FILE}" >/dev/null
fi

sudo apt-get update -y >/dev/null
echo "✅ Repo ready."
echo

echo "[2] Resolving target versions from apt metadata..."
# Helper: list candidate versions for a package
list_versions(){
  local pkg="$1"
  apt-cache madison "${pkg}" 2>/dev/null | awk '{print $3}' | sed 's/^v//' | head -n 50
}

# Determine exact versions for kubelet + kubectl
if [[ -n "${TARGET_VERSION}" ]]; then
  KUBELET_VER="${TARGET_VERSION}"
  KUBECTL_VER="${TARGET_VERSION}"
else
  # Pick the highest patch version for the requested minor, from available apt versions.
  # apt version strings vary; we match prefix like 1.33. or 1.33.0 etc.
  pick_minor(){
    local minor="$1"
    local pkg="$2"
    list_versions "${pkg}" | grep -E "^${minor//./\.}\." | head -n1 || true
  }
  KUBELET_VER="$(pick_minor "${TARGET_MINOR}" kubelet)"
  KUBECTL_VER="$(pick_minor "${TARGET_MINOR}" kubectl)"
fi

if [[ -z "${KUBELET_VER}" || -z "${KUBECTL_VER}" ]]; then
  echo "ERROR: Could not find kubelet/kubectl versions for minor ${TARGET_MINOR} in apt metadata."
  echo "Diagnostics (top candidates):"
  echo "kubelet:"; list_versions kubelet | head -n 10 || true
  echo "kubectl:"; list_versions kubectl | head -n 10 || true
  echo
  echo "Remediation options:"
  echo "  A) Choose a minor that exists in this repo channel (set TARGET_MINOR=...)."
  echo "  B) Provide an exact apt version string via TARGET_VERSION=... (from apt-cache madison)."
  exit 2
fi

echo "Selected versions:"
echo "  kubelet=${KUBELET_VER}"
echo "  kubectl=${KUBECTL_VER}"
echo

echo "[3] Holding kubeadm (leave as-is) and installing older kubelet/kubectl..."
# Hold kubeadm to avoid accidental changes
sudo apt-mark hold kubeadm >/dev/null 2>&1 || true

# Install requested versions
sudo apt-get install -y --allow-downgrades \
  kubelet="${KUBELET_VER}" \
  kubectl="${KUBECTL_VER}" >/dev/null

sudo apt-mark hold kubelet kubectl >/dev/null 2>&1 || true

echo "[4] Restarting kubelet..."
sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo
echo "[5] Post-checks:"
dpkg-query -W -f='${Package} ${Version}
' kubeadm kubelet kubectl 2>/dev/null | tee "${BACKUP_DIR}/dpkg_versions.after.txt" || true
echo
echo "kubelet --version:"
kubelet --version || true

echo
echo "✅ Worker skew created (apt-based)."
echo "Next: On control plane, perform the standard kubeadm/apt upgrade flow to bring worker back to match control-plane."
