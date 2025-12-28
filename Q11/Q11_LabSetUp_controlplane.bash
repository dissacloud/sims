#!/usr/bin/env bash
# Q11 Lab Setup — controlplane orchestrator

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="${WORKER:-node01}"
KUBELET_TAG="${KUBELET_TAG:-v1.33.3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== Q11 Lab Setup (controlplane) =="
echo "Worker: ${WORKER}"
echo "Target kubelet: ${KUBELET_TAG}"
echo

kubectl get nodes

echo
echo "[1] Copying scripts to worker"
scp "${SCRIPT_DIR}/Q11_LabSetUp_worker.bash" "${WORKER}:/tmp/Q11_LabSetUp_worker.bash"
scp "${SCRIPT_DIR}/Q11_Cleanup_Reset_worker.bash" "${WORKER}:/tmp/Q11_Cleanup_Reset_worker.bash"

echo
echo "[2] Executing worker setup"
ssh "${WORKER}" "chmod +x /tmp/Q11_LabSetUp_worker.bash && sudo KUBELET_TAG=${KUBELET_TAG} bash /tmp/Q11_LabSetUp_worker.bash"

echo
echo "[3] Waiting for node status"
sleep 20
kubectl get nodes -o wide

echo
echo "✅ Q11 environment ready"
