#!/usr/bin/env bash
# Q11 (APT-based) Cleanup — controlplane orchestrator (v2)
#
# Supports RESTORE_MINOR + TARGET_VERSION passthrough.
#
# Usage:
#   bash Q11_Apt_Cleanup_Reset_controlplane_v2.bash
#   WORKER=node01 RESTORE_MINOR=1.34 bash Q11_Apt_Cleanup_Reset_controlplane_v2.bash
#   WORKER=node01 RESTORE_MINOR=1.34 TARGET_VERSION=1.34.3-1.1 bash Q11_Apt_Cleanup_Reset_controlplane_v2.bash

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="${WORKER:-}"
RESTORE_MINOR="${RESTORE_MINOR:-1.34}"
TARGET_VERSION="${TARGET_VERSION:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need kubectl
need ssh
need scp
need awk

CP_NODE="$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

if [[ -z "${WORKER}" ]]; then
  WORKER="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}'     | awk -v cp="${CP_NODE}" '$1!=cp && $2=="" {print $1; exit}' || true)"
fi

echo "== Q11 APT Cleanup (controlplane) v2 =="
echo "Date: $(date -Is)"
echo "Control-plane: ${CP_NODE:-<unknown>}"
echo "Worker: ${WORKER}"
echo "RESTORE_MINOR: ${RESTORE_MINOR}"
echo "TARGET_VERSION: ${TARGET_VERSION:-<auto>}"
echo

if [[ -z "${WORKER}" ]]; then
  echo "ERROR: Could not determine a worker node."
  echo "Remediation: set WORKER explicitly, e.g.: WORKER=node01 bash $0"
  exit 2
fi

if [[ "${WORKER}" == "${CP_NODE}" ]]; then
  echo "ERROR: Refusing to run worker cleanup on the control-plane node (${CP_NODE})."
  echo "Remediation: set WORKER to the worker node name (e.g. node01)."
  exit 3
fi

echo "[1] Copying worker cleanup script..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null   "${SCRIPT_DIR}/Q11_Apt_Cleanup_Reset_worker_v2.bash"   "${WORKER}:/tmp/Q11_Apt_Cleanup_Reset_worker.bash" >/dev/null
echo "✅ Copied."
echo

echo "[2] Executing cleanup on worker (sudo bash)..."
if [[ -n "${TARGET_VERSION}" ]]; then
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null     "${WORKER}" "chmod +x /tmp/Q11_Apt_Cleanup_Reset_worker.bash && sudo RESTORE_MINOR=${RESTORE_MINOR} TARGET_VERSION=${TARGET_VERSION} bash /tmp/Q11_Apt_Cleanup_Reset_worker.bash"
else
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null     "${WORKER}" "chmod +x /tmp/Q11_Apt_Cleanup_Reset_worker.bash && sudo RESTORE_MINOR=${RESTORE_MINOR} bash /tmp/Q11_Apt_Cleanup_Reset_worker.bash"
fi

echo
echo "[3] Cluster node versions:"
sleep 15
kubectl get nodes -o wide || true

echo
echo "✅ Cleanup complete."
