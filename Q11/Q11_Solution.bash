#!/usr/bin/env bash
# Q11 Solution Script — Upgrade worker node compute-0 to match control plane version
#
# Run this on the controlplane node.
#
# What it does (exam-aligned):
#  - Detects the control-plane Kubernetes version (major.minor.patch)
#  - Cordon + drain compute-0 (no workload edits; only eviction)
#  - SSH into compute-0 and upgrades kubeadm/kubelet/kubectl to match control plane
#  - Runs 'kubeadm upgrade node' on compute-0
#  - Restarts kubelet and returns
#  - Uncordon compute-0
#
# Notes:
#  - Assumes Debian/Ubuntu style packaging (apt) and passwordless SSH: ssh compute-0
#  - Uses KUBECONFIG=/etc/kubernetes/admin.conf
#  - If your environment uses yum/dnf, adapt the package install section accordingly.

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

WORKER_NODE="compute-0"

echo "== Q11 Solution — Worker Upgrade =="
echo "Controlplane: $(hostname)"
echo "Target worker: ${WORKER_NODE}"
echo

need_bin() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing required binary: $1"; exit 1; }
}

need_bin kubectl
need_bin ssh

# 1) Determine control plane version (e.g. v1.34.3 -> 1.34.3)
CP_VERSION="$(kubectl version -o json 2>/dev/null | grep -oE '"gitVersion":"v[0-9]+\.[0-9]+\.[0-9]+"' | head -n1 | sed -E 's/.*"gitVersion":"v([^"]+)".*/\1/')"
if [[ -z "${CP_VERSION}" ]]; then
  # Fallback: parse --short output
  CP_VERSION="$(kubectl version --short 2>/dev/null | awk -F': ' '/Server Version/ {gsub(/^v/,"",$2); print $2}' | head -n1)"
fi

if [[ -z "${CP_VERSION}" ]]; then
  echo "ERROR: Could not determine control plane (server) version."
  echo "Try: kubectl version --short"
  exit 1
fi

echo "Target version (control plane): v${CP_VERSION}"
echo

# 2) Confirm worker node exists
if ! kubectl get node "${WORKER_NODE}" >/dev/null 2>&1; then
  echo "ERROR: Node '${WORKER_NODE}' not found."
  echo "Available nodes:"
  kubectl get nodes -o wide || true
  exit 1
fi

echo "Current node versions:"
kubectl get nodes -o wide
echo

# 3) Cordon + drain worker (safe, exam-style)
echo "-> Cordoning ${WORKER_NODE}..."
kubectl cordon "${WORKER_NODE}" >/dev/null

echo "-> Draining ${WORKER_NODE} (ignore daemonsets; delete emptyDir data)..."
kubectl drain "${WORKER_NODE}" --ignore-daemonsets --delete-emptydir-data --grace-period=60 --timeout=5m

echo
echo "-> Upgrading packages on ${WORKER_NODE} via SSH..."
echo "   (This may take a moment depending on repo/cache.)"
echo

# 4) Upgrade worker via SSH
# IMPORTANT: serviceAccount/workloads are not modified; only node packages + kubeadm node upgrade.
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER_NODE}" bash -s -- "${CP_VERSION}" <<'EOSSH'
set -euo pipefail
TARGET_VERSION="${1}"

echo "== On $(hostname) — upgrading to v${TARGET_VERSION} =="

need_bin() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need_bin sudo

# Debian/Ubuntu (apt) path
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y

  # Hold management: unhold -> install exact -> hold
  sudo apt-mark unhold kubeadm kubelet kubectl >/dev/null 2>&1 || true

  # Install kubeadm first (best practice)
  sudo apt-get install -y "kubeadm=${TARGET_VERSION}-*" || sudo apt-get install -y "kubeadm=${TARGET_VERSION}*"

  # kubeadm upgrade node (for worker)
  sudo kubeadm upgrade node

  # Install kubelet + kubectl matching version
  sudo apt-get install -y "kubelet=${TARGET_VERSION}-*" "kubectl=${TARGET_VERSION}-*" ||         sudo apt-get install -y "kubelet=${TARGET_VERSION}*" "kubectl=${TARGET_VERSION}*"

  # Re-hold to avoid unintended upgrades
  sudo apt-mark hold kubeadm kubelet kubectl >/dev/null 2>&1 || true

  # Restart kubelet
  sudo systemctl daemon-reload
  sudo systemctl restart kubelet

  echo
  echo "Versions after upgrade:"
  kubeadm version || true
  kubelet --version || true
  kubectl version --client --short || true
  echo "== Worker upgrade complete =="
  exit 0
fi

echo "ERROR: apt-get not found on this node. This script currently supports Debian/Ubuntu only."
echo "If your node uses yum/dnf, upgrade kubeadm/kubelet/kubectl to ${TARGET_VERSION} accordingly, then run: sudo kubeadm upgrade node"
exit 2
EOSSH

echo
echo "-> Waiting for ${WORKER_NODE} to become Ready..."
kubectl wait --for=condition=Ready "node/${WORKER_NODE}" --timeout=5m

echo "-> Uncordoning ${WORKER_NODE}..."
kubectl uncordon "${WORKER_NODE}" >/dev/null

echo
echo "Final node status:"
kubectl get nodes -o wide
echo
echo "Q11 solution complete."
