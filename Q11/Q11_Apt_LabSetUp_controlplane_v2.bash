#!/usr/bin/env bash
# Q11 (APT-based) Lab Setup — controlplane orchestrator (v2)
#
# Fixes vs v1:
# - Correct worker auto-detection (never selects controlplane).
# - Refuses to run the worker setup on the controlplane node.
# - Passes TARGET_MINOR/TARGET_VERSION through to the worker script.
#
# Usage:
#   bash Q11_Apt_LabSetUp_controlplane_v2.bash
#   WORKER=node01 TARGET_MINOR=1.33 bash Q11_Apt_LabSetUp_controlplane_v2.bash
#   WORKER=node01 TARGET_VERSION=1.33.3-1.1 bash Q11_Apt_LabSetUp_controlplane_v2.bash

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="${WORKER:-}"
TARGET_MINOR="${TARGET_MINOR:-1.33}"
TARGET_VERSION="${TARGET_VERSION:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need kubectl
need ssh
need scp
need awk

CP_NODE="$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

# Auto-detect worker (first node that is not the control-plane node and has no control-plane label key)
if [[ -z "${WORKER}" ]]; then
  WORKER="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}'     | awk -v cp="${CP_NODE}" '$1!=cp && $2=="" {print $1; exit}' || true)"
fi

echo "== Q11 APT Lab Setup (controlplane) v2 =="
echo "Date: $(date -Is)"
echo "Control-plane: ${CP_NODE:-<unknown>}"
echo "Worker: ${WORKER}"
echo "Target worker minor (skew): ${TARGET_MINOR}"
echo "Target worker version (optional): ${TARGET_VERSION:-<auto>}"
echo

if [[ -z "${WORKER}" ]]; then
  echo "ERROR: Could not determine a worker node."
  echo "Remediation: set WORKER explicitly, e.g.: WORKER=node01 bash $0"
  exit 2
fi

if [[ "${WORKER}" == "${CP_NODE}" ]]; then
  echo "ERROR: Refusing to run worker skew on the control-plane node (${CP_NODE})."
  echo "Remediation: set WORKER to the worker node name (e.g. node01)."
  exit 3
fi

echo "[0] Current cluster node versions:"
kubectl get nodes -o wide || true
echo

echo "[1] Copying worker setup + cleanup scripts to worker..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null   "${SCRIPT_DIR}/Q11_Apt_LabSetUp_worker_v2.bash"   "${WORKER}:/tmp/Q11_Apt_LabSetUp_worker.bash" >/dev/null
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null   "${SCRIPT_DIR}/Q11_Apt_Cleanup_Reset_worker_v2.bash"   "${WORKER}:/tmp/Q11_Apt_Cleanup_Reset_worker.bash" >/dev/null
echo "✅ Copied."
echo

echo "[2] Executing worker setup (sudo bash)..."
if [[ -n "${TARGET_VERSION}" ]]; then
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null     "${WORKER}" "chmod +x /tmp/Q11_Apt_LabSetUp_worker.bash /tmp/Q11_Apt_Cleanup_Reset_worker.bash && sudo TARGET_MINOR=${TARGET_MINOR} TARGET_VERSION=${TARGET_VERSION} bash /tmp/Q11_Apt_LabSetUp_worker.bash"
else
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null     "${WORKER}" "chmod +x /tmp/Q11_Apt_LabSetUp_worker.bash /tmp/Q11_Apt_Cleanup_Reset_worker.bash && sudo TARGET_MINOR=${TARGET_MINOR} bash /tmp/Q11_Apt_LabSetUp_worker.bash"
fi
echo

echo "[3] Waiting briefly for kubeletVersion to refresh in API..."
sleep 25
kubectl get nodes -o wide || true

echo
echo "✅ Q11 (APT-based) skew environment ready."
echo "Now solve using the standard exam flow: drain -> apt/kubeadm upgrade node -> restart kubelet -> uncordon."
