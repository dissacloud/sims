#!/usr/bin/env bash
# Q11 v3 Lab Setup (controlplane) — create version skew by swapping kubelet binary on compute-0.
# This does NOT change the control plane.
#
# Defaults to downloading kubelet v1.33.3 on compute-0. Override with:
#   KUBELET_TAG=v1.33.3 bash Q11v3_LabSetUp_controlplane.bash
#
# Prereqs:
# - passwordless SSH to compute-0 (or run the compute-0 script manually on compute-0)
# - internet access from compute-0 to dl.k8s.io

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="compute-0"
KUBELET_TAG="${KUBELET_TAG:-v1.33.3}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need kubectl
need ssh
need scp

CP_VERSION="$(kubectl version --short 2>/dev/null | awk -F': ' '/Server Version/ {gsub(/^v/,"",$2); print $2}' | head -n1)"
echo "🚀 Q11 v3 Setup — kubelet binary skew on worker"
echo "Control-plane server version: v${CP_VERSION:-<unknown>}"
echo "Worker: ${WORKER}"
echo "Worker kubelet tag to install: ${KUBELET_TAG}"
echo

# Push scripts to worker
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /mnt/data/Q11v3_LabSetUp_compute-0.bash "${WORKER}:/tmp/Q11v3_LabSetUp_compute-0.bash" >/dev/null
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /mnt/data/Q11v3_Cleanup_Reset_compute-0.bash "${WORKER}:/tmp/Q11v3_Cleanup_Reset_compute-0.bash" >/dev/null

# Execute setup on worker
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER}" bash -s -- "${KUBELET_TAG}" <<'EOSSH'
set -euo pipefail
KUBELET_TAG="$1"
chmod +x /tmp/Q11v3_LabSetUp_compute-0.bash /tmp/Q11v3_Cleanup_Reset_compute-0.bash
sudo KUBELET_TAG="${KUBELET_TAG}" bash /tmp/Q11v3_LabSetUp_compute-0.bash
EOSSH

echo
echo "Checking node versions (may take ~30-60s for kubeletVersion to reflect)..."
kubectl get nodes -o wide || true

echo
echo "✅ Skew created. Now complete the upgrade task: bring compute-0 up to match control-plane v${CP_VERSION}."
