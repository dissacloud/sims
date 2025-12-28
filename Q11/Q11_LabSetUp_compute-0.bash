#!/usr/bin/env bash
# Q11 Lab Setup (compute-0) — force worker to previous minor so an upgrade is required.
# Goal: create a clean mismatch such as 1.33.x -> 1.34.x (or 1.32.x -> 1.33.x),
# while leaving the control plane untouched.
#
# Run this ON compute-0 (worker) as root (or with sudo available).
#
# Safety:
# - Only changes kubeadm/kubelet/kubectl packages via apt (Debian/Ubuntu)
# - Creates backups + records current versions
# - Holds packages after change to prevent surprise upgrades

set -euo pipefail

BACKUP="/root/cis-q11-backups-worker-20251228194020"
mkdir -p "${BACKUP}"

echo "🚀 Q11 Worker Setup — forcing compute-0 to previous minor (apt-based)"
echo "Backup dir: $BACKUP"
echo

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need sudo
need apt-get
need apt-cache

echo "Recording current versions..."
{
  kubelet --version 2>/dev/null || true
  kubeadm version 2>/dev/null || true
  kubectl version --client --short 2>/dev/null || true
} | tee "${BACKUP}/versions.before.txt" >/dev/null

# Accept optional env TARGET_MINOR (e.g., 1.34). If not set, infer:
# Prefer creating mismatch 1.33 when 1.34 exists; else 1.32 when 1.33 exists.
TARGET_MINOR="${TARGET_MINOR:-}"

# Discover available minors for kubelet
madison="$(apt-cache madison kubelet 2>/dev/null || true)"
if [[ -z "${madison}" ]]; then
  echo "ERROR: apt-cache madison kubelet returned nothing. Check Kubernetes apt repo configuration."
  exit 2
fi

has_134="$(echo "${madison}" | grep -Eo '1\.34\.[0-9]+' | head -n1 || true)"
has_133="$(echo "${madison}" | grep -Eo '1\.33\.[0-9]+' | head -n1 || true)"
has_132="$(echo "${madison}" | grep -Eo '1\.32\.[0-9]+' | head -n1 || true)"

if [[ -z "${TARGET_MINOR}" ]]; then
  if [[ -n "${has_134}" && -n "${has_133}" ]]; then
    TARGET_MINOR="1.34"
  elif [[ -n "${has_133}" && -n "${has_132}" ]]; then
    TARGET_MINOR="1.33"
  else
    echo "ERROR: Could not find adjacent minor versions to construct a mismatch."
    echo "Found: 1.34='${has_134}' 1.33='${has_133}' 1.32='${has_132}'"
    echo "Set TARGET_MINOR manually, e.g.: TARGET_MINOR=1.34 bash $0"
    exit 3
  fi
fi

if [[ "${TARGET_MINOR}" == "1.34" ]]; then
  FROM_MINOR="1.33"
elif [[ "${TARGET_MINOR}" == "1.33" ]]; then
  FROM_MINOR="1.32"
else
  echo "ERROR: Unsupported TARGET_MINOR='${TARGET_MINOR}'. Use 1.34 or 1.33."
  exit 4
fi

echo "Target control-plane minor assumed: ${TARGET_MINOR}"
echo "Forcing this worker to previous minor: ${FROM_MINOR}"
echo

# Pick latest patch for FROM_MINOR from madison output (madison lists newest first)
FROM_VER="$(echo "${madison}" | awk '{print $3}' | grep -E "^${FROM_MINOR}\." | head -n1 || true)"
if [[ -z "${FROM_VER}" ]]; then
  echo "ERROR: Could not find a kubelet package version for ${FROM_MINOR}.x"
  echo "Available versions (first 20):"
  echo "${madison}" | head -n 20
  exit 5
fi

pick_pkg_ver() {
  local pkg="$1"
  apt-cache madison "$pkg" | awk '{print $3}' | grep -E "^${FROM_MINOR}\." | head -n1 || true
}
KUBEADM_VER="$(pick_pkg_ver kubeadm)"
KUBECTL_VER="$(pick_pkg_ver kubectl)"

echo "Selected versions:"
echo "  kubelet: $FROM_VER"
echo "  kubeadm: ${KUBEADM_VER:-<not available, will keep current>}"
echo "  kubectl: ${KUBECTL_VER:-<not available, will keep current>}"
echo

echo "Unholding packages (best-effort)..."
sudo apt-mark unhold kubelet kubeadm kubectl >/dev/null 2>&1 || true

echo "Installing kubelet previous minor..."
sudo apt-get update -y

sudo apt-get install -y "kubelet=${FROM_VER}"

if [[ -n "${KUBEADM_VER}" ]]; then
  sudo apt-get install -y "kubeadm=${KUBEADM_VER}"
fi
if [[ -n "${KUBECTL_VER}" ]]; then
  sudo apt-get install -y "kubectl=${KUBECTL_VER}"
fi

echo "Holding packages to keep the mismatch stable..."
sudo apt-mark hold kubelet kubeadm kubectl >/dev/null 2>&1 || true

echo "Restarting kubelet..."
sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo
echo "Recording versions after setup..."
{
  kubelet --version 2>/dev/null || true
  kubeadm version 2>/dev/null || true
  kubectl version --client --short 2>/dev/null || true
} | tee "${BACKUP}/versions.after.txt" >/dev/null

echo
echo "✅ Worker setup complete."
echo "   This node should now be on ${FROM_MINOR}.x so you can practice upgrading to ${TARGET_MINOR}.x"
