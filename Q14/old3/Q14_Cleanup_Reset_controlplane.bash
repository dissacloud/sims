#!/usr/bin/env bash
# Q14 Cleanup (controlplane orchestrator) — triggers worker cleanup remotely.
set -euo pipefail
trap '' PIPE

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER_NODE="${WORKER:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 2; }; }
need kubectl
need ssh
need scp

echo "== Q14 Cleanup (controlplane) =="
echo "Date: $(date -Is)"
echo

if [[ -z "${WORKER_NODE}" ]]; then
  WORKER_NODE="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}'     | awk '$2=="" {print $1}' | head -n1 || true)"
fi
if [[ -z "${WORKER_NODE}" ]]; then
  echo "ERROR: Could not auto-detect worker. Set WORKER explicitly."
  exit 2
fi
echo "Worker: ${WORKER_NODE}"
echo

if [[ ! -f "${SCRIPT_DIR}/Q14_Cleanup_Reset_worker.bash" ]]; then
  echo "ERROR: missing ${SCRIPT_DIR}/Q14_Cleanup_Reset_worker.bash"
  exit 2
fi

echo "[1] Copying worker cleanup script..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SCRIPT_DIR}/Q14_Cleanup_Reset_worker.bash" "${WORKER_NODE}:/tmp/Q14_Cleanup_Reset_worker.bash" >/dev/null
echo "✅ Copied."
echo

echo "[2] Executing cleanup on worker (sudo bash)..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER_NODE}" "chmod +x /tmp/Q14_Cleanup_Reset_worker.bash && sudo bash /tmp/Q14_Cleanup_Reset_worker.bash"
echo

echo "[3] Cluster sanity check..."
kubectl get nodes -o wide
echo
echo "✅ Q14 cleanup done."
