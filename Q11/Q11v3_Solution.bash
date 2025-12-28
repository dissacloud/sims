#!/usr/bin/env bash
# Q11 v3 Solution — Upgrade compute-0 to match control plane (exam-style)
# Run on controlplane.
#
# What it does:
# 1) Cordon + drain compute-0
# 2) SSH to compute-0 and install/upgrade kubeadm+kubelet(+kubectl) to the control-plane minor (latest patch available in apt)
# 3) Restart kubelet
# 4) Uncordon compute-0
#
# Notes:
# - Assumes compute-0 is Ubuntu/Debian with apt and Kubernetes packages configured.
# - If your environment pins a specific patch, set TARGET_VERSION explicitly.
#
# Optional env overrides:
#   WORKER=compute-0
#   TARGET_MINOR=1.34           # force a minor regardless of detected control plane
#   TARGET_VERSION=1.34.3-1.1   # exact apt version string (if known)
#   DRAIN_EXTRA="--force"       # additional drain flags if needed

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="${WORKER:-compute-0}"
DRAIN_EXTRA="${DRAIN_EXTRA:-}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need kubectl
need ssh

echo "== Q11 v3 Solution (Upgrade worker) =="
echo "Date: $(date -Is)"
echo "Worker: ${WORKER}"
echo

# Determine target minor from control plane (unless overridden)
if [[ -z "${TARGET_MINOR:-}" ]]; then
  CP_VER="$(kubectl version --short 2>/dev/null | awk -F': ' '/Server Version/ {gsub(/^v/,"",$2); print $2}' | head -n1)"
  if [[ -z "${CP_VER}" ]]; then
    echo "ERROR: Unable to detect control-plane Server Version."
    kubectl version --short || true
    exit 2
  fi
  TARGET_MINOR="$(echo "${CP_VER}" | awk -F. '{print $1"."$2}')"
fi

echo "Target minor: ${TARGET_MINOR}"
echo

echo "[1/4] Cordon ${WORKER}"
kubectl cordon "${WORKER}"

echo
echo "[2/4] Drain ${WORKER}"
kubectl drain "${WORKER}" --ignore-daemonsets --delete-emptydir-data ${DRAIN_EXTRA}

echo
echo "[3/4] Upgrade kubeadm/kubelet on ${WORKER}"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER}" bash -s -- "${TARGET_MINOR}" "${TARGET_VERSION:-}" <<'EOSSH'
set -euo pipefail
TARGET_MINOR="$1"
TARGET_VERSION="${2:-}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need sudo
need apt-get
need apt-cache
need systemctl

echo "Worker: $(hostname)"
echo "Before:"
kubelet --version 2>/dev/null || true
kubeadm version 2>/dev/null || true
echo

sudo apt-get update -y

# Unhold in case packages were held
sudo apt-mark unhold kubelet kubeadm kubectl >/dev/null 2>&1 || true

if [[ -n "${TARGET_VERSION}" ]]; then
  echo "Installing exact versions: ${TARGET_VERSION}"
  sudo apt-get install -y "kubeadm=${TARGET_VERSION}" "kubelet=${TARGET_VERSION}" "kubectl=${TARGET_VERSION}"
else
  # Choose the latest patch for the target minor from the repo
  pick_ver() {
    local pkg="$1"
    apt-cache madison "$pkg" | awk '{print $3}' | grep -E "^${TARGET_MINOR}\." | head -n1 || true
  }
  KUBELET_VER="$(pick_ver kubelet)"
  KUBEADM_VER="$(pick_ver kubeadm)"
  KUBECTL_VER="$(pick_ver kubectl)"

  if [[ -z "${KUBELET_VER}" || -z "${KUBEADM_VER}" ]]; then
    echo "ERROR: Could not find target minor ${TARGET_MINOR}.x in apt repo for kubelet/kubeadm."
    echo "kubelet candidates:"
    apt-cache madison kubelet | head -n 20 || true
    echo "kubeadm candidates:"
    apt-cache madison kubeadm | head -n 20 || true
    exit 3
  fi

  echo "Selected apt versions:"
  echo "  kubeadm: ${KUBEADM_VER}"
  echo "  kubelet: ${KUBELET_VER}"
  echo "  kubectl: ${KUBECTL_VER:-<skip>}"
  echo

  sudo apt-get install -y "kubeadm=${KUBEADM_VER}" "kubelet=${KUBELET_VER}" ${KUBECTL_VER:+ "kubectl=${KUBECTL_VER}"}
fi

# Hold to prevent drift (optional)
sudo apt-mark hold kubelet kubeadm kubectl >/dev/null 2>&1 || true

echo "Restarting kubelet..."
sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo
echo "After:"
kubelet --version 2>/dev/null || true
kubeadm version 2>/dev/null || true
EOSSH

echo
echo "[4/4] Uncordon ${WORKER}"
kubectl uncordon "${WORKER}"

echo
echo "✅ Done. Current nodes:"
kubectl get nodes -o wide
