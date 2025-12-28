#!/usr/bin/env bash
# Q11 v5 Controlplane Setup — create version skew on a worker node.
# This version does NOT require passwordless SSH; it will prompt if needed.
#
# Usage:
#   bash Q11v5_LabSetUp_controlplane.bash
#   WORKER=node01 KUBELET_TAG=v1.33.3 bash Q11v5_LabSetUp_controlplane.bash

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
KUBELET_TAG="${KUBELET_TAG:-v1.33.3}"
WORKER="${WORKER:-}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need kubectl
need ssh
need scp

# Auto-detect worker if not set
if [[ -z "${WORKER}" ]]; then
  WORKER="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}'     | awk '$2=="" {print $1}' | head -n1 || true)"
fi

if [[ -z "${WORKER}" ]]; then
  echo "ERROR: Could not determine worker node."
  echo "Set it explicitly, e.g.: WORKER=node01 bash $0"
  exit 2
fi

CP_VERSION="$(kubectl version --short 2>/dev/null | awk -F': ' '/Server Version/ {gsub(/^v/,"",$2); print $2}' | head -n1)"

echo "== Q11 v5 Setup (kubelet skew) =="
echo "Date: $(date -Is)"
echo "Control-plane server version: v${CP_VERSION:-<unknown>}"
echo "Worker: ${WORKER}"
echo "Target kubelet tag (worker): ${KUBELET_TAG}"
echo

# Stage scripts to worker
echo "Copying setup/cleanup scripts to ${WORKER}:/tmp ..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /mnt/data/Q11v5_LabSetUp_worker.bash "${WORKER}:/tmp/Q11v5_LabSetUp_worker.bash"
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /mnt/data/Q11v5_Cleanup_Reset_worker.bash "${WORKER}:/tmp/Q11v5_Cleanup_Reset_worker.bash"

echo "Executing setup on worker (may prompt for SSH password if required)..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER}" bash -s -- "${KUBELET_TAG}" <<'EOSSH'
set -euo pipefail
KUBELET_TAG="$1"
chmod +x /tmp/Q11v5_LabSetUp_worker.bash /tmp/Q11v5_Cleanup_Reset_worker.bash
sudo KUBELET_TAG="${KUBELET_TAG}" bash /tmp/Q11v5_LabSetUp_worker.bash
EOSSH

echo
echo "Waiting briefly for node status to refresh..."
sleep 5
kubectl get nodes -o wide || true

echo
echo "✅ Skew created. Now upgrade ${WORKER} to match the control plane."
