#!/usr/bin/env bash
# Q11 v4 Lab Setup (controlplane) — create version skew by swapping kubelet binary on a worker node.
# This does NOT change the control plane.
#
# Improvements vs v3:
# - Auto-detects the worker node if WORKER not provided.
# - Validates SSH connectivity and provides a clear fallback path.
#
# Usage:
#   bash Q11v4_LabSetUp_controlplane.bash
#   WORKER=node01 KUBELET_TAG=v1.33.3 bash Q11v4_LabSetUp_controlplane.bash
#
# Prereqs:
# - SSH + SCP available on controlplane
# - Either passwordless SSH to worker, OR you run the worker setup script manually on the worker.
# - internet access from worker to dl.k8s.io (unless you pre-stage a kubelet binary)

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
KUBELET_TAG="${KUBELET_TAG:-v1.33.3}"
WORKER="${WORKER:-}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need kubectl
need ssh
need scp

# Auto-detect a worker if not provided
if [[ -z "${WORKER}" ]]; then
  # Prefer a node that is not labeled control-plane
  WORKER="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}'     | awk '$2=="" {print $1}' | head -n1 || true)"
fi

CP_VERSION="$(kubectl version --short 2>/dev/null | awk -F': ' '/Server Version/ {gsub(/^v/,"",$2); print $2}' | head -n1)"

echo "🚀 Q11 v4 Setup — kubelet binary skew on worker"
echo "Control-plane server version: v${CP_VERSION:-<unknown>}"
echo "Worker: ${WORKER}"
echo "Worker kubelet tag to install: ${KUBELET_TAG}"
echo

if [[ -z "${WORKER}" ]]; then
  echo "ERROR: Could not auto-detect a worker node."
  echo "Remediation: set WORKER explicitly, e.g.:"
  echo "  WORKER=node01 bash $0"
  exit 2
fi

# Quick SSH connectivity test (non-interactive)
if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$WORKER" "true" >/dev/null 2>&1; then
  echo "✅ SSH connectivity to $WORKER confirmed (BatchMode)."
else
  echo "⚠️  Cannot SSH to $WORKER in BatchMode (passwordless SSH not configured)."
  echo
  echo "Fallback options:"
  echo "  A) Configure passwordless SSH, then re-run this script."
  echo "  B) Run the worker setup manually on the worker:"
  echo "     1) Copy scripts:"
  echo "        scp /mnt/data/Q11v3_LabSetUp_compute-0.bash $WORKER:/tmp/Q11v3_LabSetUp_worker.bash"
  echo "        scp /mnt/data/Q11v3_Cleanup_Reset_compute-0.bash $WORKER:/tmp/Q11v3_Cleanup_Reset_worker.bash"
  echo "     2) SSH to the worker and run:"
  echo "        sudo KUBELET_TAG=$KUBELET_TAG bash /tmp/Q11v3_LabSetUp_worker.bash"
  exit 3
fi

# Push scripts to worker (rename for clarity on the worker)
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /mnt/data/Q11v3_LabSetUp_compute-0.bash "$WORKER:/tmp/Q11v3_LabSetUp_worker.bash" >/dev/null
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /mnt/data/Q11v3_Cleanup_Reset_compute-0.bash "$WORKER:/tmp/Q11v3_Cleanup_Reset_worker.bash" >/dev/null

# Execute setup on worker
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$WORKER" bash -s -- "$KUBELET_TAG" <<'EOSSH'
set -euo pipefail
KUBELET_TAG="$1"
chmod +x /tmp/Q11v3_LabSetUp_worker.bash /tmp/Q11v3_Cleanup_Reset_worker.bash
sudo KUBELET_TAG="${KUBELET_TAG}" bash /tmp/Q11v3_LabSetUp_worker.bash
EOSSH

echo
echo "Checking node versions (may take ~30-60s for kubeletVersion to reflect)..."
kubectl get nodes -o wide || true

echo
echo "✅ Skew created. Now complete the upgrade task: bring ${WORKER} up to match control-plane v${CP_VERSION}."
