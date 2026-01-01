#!/usr/bin/env bash
# Q14 Lab Setup (controlplane orchestrator)
# Creates an insecure Docker configuration on a worker node to simulate the exam task:
# - user 'developer' is in docker group
# - /var/run/docker.sock group is 'docker' (not root)
# - dockerd listens on a TCP port (2375)
#
# Usage:
#   bash Q14_LabSetUp_controlplane.bash
#   WORKER=node01 bash Q14_LabSetUp_controlplane.bash
#
set -euo pipefail
trap '' PIPE

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

WORKER_NODE="${WORKER:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 2; }; }
need kubectl
need ssh
need scp

echo "== Q14 Lab Setup (controlplane) =="
echo "Date: $(date -Is)"
echo "Script dir: ${SCRIPT_DIR}"
echo

# Auto-detect a non-control-plane node if WORKER not set
if [[ -z "${WORKER_NODE}" ]]; then
  WORKER_NODE="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}'     | awk '$2=="" {print $1}' | head -n1 || true)"
fi

if [[ -z "${WORKER_NODE}" ]]; then
  echo "ERROR: Could not auto-detect a worker node."
  echo "Remediation: set WORKER explicitly, e.g. WORKER=node01 bash $0"
  exit 2
fi

echo "Worker node selected: ${WORKER_NODE}"
echo

# Ensure local worker scripts exist
for f in Q14_LabSetUp_worker.bash Q14_Cleanup_Reset_worker.bash; do
  if [[ ! -f "${SCRIPT_DIR}/${f}" ]]; then
    echo "ERROR: missing ${SCRIPT_DIR}/${f}"
    exit 2
  fi
done

# Check SSH connectivity (non-interactive if possible)
if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER_NODE}" "true" >/dev/null 2>&1; then
  echo "✅ SSH connectivity to ${WORKER_NODE} confirmed (BatchMode)."
else
  echo "⚠️  Cannot SSH to ${WORKER_NODE} in BatchMode (passwordless SSH likely not configured)."
  echo
  echo "Fallback manual steps:"
  echo "  scp ${SCRIPT_DIR}/Q14_LabSetUp_worker.bash ${WORKER_NODE}:/tmp/Q14_LabSetUp_worker.bash"
  echo "  scp ${SCRIPT_DIR}/Q14_Cleanup_Reset_worker.bash ${WORKER_NODE}:/tmp/Q14_Cleanup_Reset_worker.bash"
  echo "  ssh ${WORKER_NODE}"
  echo "  sudo bash /tmp/Q14_LabSetUp_worker.bash"
  exit 3
fi

echo "[1] Copying worker setup + cleanup scripts to worker..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SCRIPT_DIR}/Q14_LabSetUp_worker.bash" "${WORKER_NODE}:/tmp/Q14_LabSetUp_worker.bash" >/dev/null
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SCRIPT_DIR}/Q14_Cleanup_Reset_worker.bash" "${WORKER_NODE}:/tmp/Q14_Cleanup_Reset_worker.bash" >/dev/null
echo "✅ Copied."
echo

echo "[2] Executing worker setup (sudo bash)..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER_NODE}" "chmod +x /tmp/Q14_LabSetUp_worker.bash && sudo bash /tmp/Q14_LabSetUp_worker.bash"
echo

echo "[3] Cluster sanity check..."
kubectl get nodes -o wide
echo
echo "✅ Q14 lab environment ready. Target node is '${WORKER_NODE}'."
