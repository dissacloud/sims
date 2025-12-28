#!/usr/bin/env bash
# Q11 v8 Lab Setup (controlplane) — uses v6 worker script (handles 'Text file busy')
#
# Usage:
#   WORKER=node01 KUBELET_TAG=v1.33.3 bash Q11v8_LabSetUp_controlplane.bash

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
KUBELET_TAG="${KUBELET_TAG:-v1.33.3}"
WORKER="${WORKER:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SRC="${SCRIPT_DIR}/Q11v6_LabSetUp_worker.bash"
CLEAN_SRC="${SCRIPT_DIR}/Q11v6_Cleanup_Reset_worker.bash"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 127; }; }
need kubectl
need ssh
need scp

echo "== Q11 v8 Setup (kubelet skew) =="
echo "Date: $(date -Is)"
echo "Requested kubelet tag: ${KUBELET_TAG}"
echo "Script dir: ${SCRIPT_DIR}"
echo

echo "[0] Verify local worker scripts exist..."
[[ -f "${SETUP_SRC}" ]] || { echo "❌ Missing: ${SETUP_SRC}"; exit 2; }
[[ -f "${CLEAN_SRC}" ]] || { echo "❌ Missing: ${CLEAN_SRC}"; exit 2; }
echo "✅ Found worker scripts."
echo

echo "[1] Basic API check..."
kubectl get nodes >/dev/null 2>&1 && echo "✅ kubectl can reach the API" || { echo "❌ kubectl cannot reach the API"; exit 3; }
echo

if [[ -z "${WORKER}" ]]; then
  echo "[2] Auto-detecting worker node (no control-plane label)..."
  WORKER="$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi
[[ -n "${WORKER}" ]] || { echo "❌ Could not determine worker; set WORKER=node01"; exit 4; }
echo "Worker selected: ${WORKER}"
echo

echo "[3] Testing SSH connectivity to ${WORKER} ..."
ssh -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER}" "echo SSH_OK: \$(hostname)"
echo

echo "[4] Copying scripts to worker..."
scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SETUP_SRC}" "${WORKER}:/tmp/Q11v6_LabSetUp_worker.bash"
scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${CLEAN_SRC}" "${WORKER}:/tmp/Q11v6_Cleanup_Reset_worker.bash"
echo "✅ Scripts copied."
echo

echo "[5] Executing worker setup (sudo)..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER}" bash -s -- "${KUBELET_TAG}" <<'EOSSH'
set -euo pipefail
KUBELET_TAG="$1"
chmod +x /tmp/Q11v6_LabSetUp_worker.bash /tmp/Q11v6_Cleanup_Reset_worker.bash
echo "Worker: $(hostname)"
echo "Before: $(kubelet --version 2>/dev/null || echo '<kubelet missing>')"
sudo KUBELET_TAG="${KUBELET_TAG}" bash /tmp/Q11v6_LabSetUp_worker.bash
echo "After:  $(kubelet --version 2>/dev/null || echo '<kubelet missing>')"
EOSSH

echo
echo "[6] Wait for kubeletVersion to refresh in API..."
sleep 20
kubectl get nodes -o wide || true

echo
echo "✅ Skew should now be present on ${WORKER}."
