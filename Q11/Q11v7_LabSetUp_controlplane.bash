#!/usr/bin/env bash
# Q11 v7 Lab Setup (controlplane) — kubelet skew on worker (robust for exam labs)
#
# Fixes vs v6:
# - Correct worker autodetection (won't pick controlplane when control-plane label has empty value)
# - Uses local script directory (~/sims/Q11) for scp sources, not /mnt/data
# - Clearer diagnostics and explicit WORKER override recommended
#
# Usage (recommended):
#   WORKER=node01 KUBELET_TAG=v1.33.3 bash Q11v7_LabSetUp_controlplane.bash
#
# If you omit WORKER, it will pick the first node that does NOT have the
# 'node-role.kubernetes.io/control-plane' label.

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
KUBELET_TAG="${KUBELET_TAG:-v1.33.3}"
WORKER="${WORKER:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SRC="${SCRIPT_DIR}/Q11v5_LabSetUp_worker.bash"
CLEAN_SRC="${SCRIPT_DIR}/Q11v5_Cleanup_Reset_worker.bash"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 127; }; }
need kubectl
need ssh
need scp

echo "== Q11 v7 Setup (kubelet skew) =="
echo "Date: $(date -Is)"
echo "KUBECONFIG: ${KUBECONFIG}"
echo "Requested kubelet tag: ${KUBELET_TAG}"
echo "Script dir: ${SCRIPT_DIR}"
echo

echo "[0] Verify local worker scripts exist..."
if [[ ! -f "${SETUP_SRC}" ]]; then
  echo "❌ Missing: ${SETUP_SRC}"
  echo "Remediation: ensure Q11v5_LabSetUp_worker.bash is in the same folder as this script."
  exit 2
fi
if [[ ! -f "${CLEAN_SRC}" ]]; then
  echo "❌ Missing: ${CLEAN_SRC}"
  echo "Remediation: ensure Q11v5_Cleanup_Reset_worker.bash is in the same folder as this script."
  exit 2
fi
echo "✅ Found worker scripts."
echo

echo "[1] Basic API check..."
kubectl get nodes >/dev/null 2>&1 && echo "✅ kubectl can reach the API" || {
  echo "❌ kubectl cannot reach the API using KUBECONFIG=${KUBECONFIG}"
  exit 3
}
echo

echo "[2] Detecting control-plane version (best-effort)..."
set +e
CP_VERSION="$(kubectl version --short 2>/dev/null | awk -F': ' '/Server Version/ {gsub(/^v/,"",$2); print $2}' | head -n1)"
rc=$?
set -e
if [[ $rc -ne 0 || -z "${CP_VERSION}" ]]; then
  echo "⚠️  Could not parse Server Version (rc=$rc). Continuing."
  CP_VERSION="<unknown>"
fi
echo "Control-plane server version: v${CP_VERSION}"
echo

if [[ -z "${WORKER}" ]]; then
  echo "[3] Auto-detecting worker node (no control-plane label)..."
  # Use label selector to exclude control-plane nodes (works even if label value is empty)
  WORKER="$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi

if [[ -z "${WORKER}" ]]; then
  echo "❌ Could not auto-detect a worker node."
  echo "Remediation: set explicitly, e.g.: WORKER=node01 KUBELET_TAG=v1.33.3 bash $0"
  exit 4
fi

echo "Worker selected: ${WORKER}"
echo

echo "[4] Testing SSH connectivity to ${WORKER} ..."
set +e
ssh -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER}" "echo SSH_OK: \$(hostname)"
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  echo "❌ SSH test failed to ${WORKER} (rc=${rc})."
  echo "Remediation: ssh ${WORKER} manually and confirm you can authenticate."
  exit 5
fi
echo

echo "[5] Copying scripts to worker..."
scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SETUP_SRC}" "${WORKER}:/tmp/Q11v5_LabSetUp_worker.bash"
scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${CLEAN_SRC}" "${WORKER}:/tmp/Q11v5_Cleanup_Reset_worker.bash"
echo "✅ Scripts copied."
echo

echo "[6] Executing worker setup (sudo)..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER}" bash -s -- "${KUBELET_TAG}" <<'EOSSH'
set -euo pipefail
KUBELET_TAG="$1"
chmod +x /tmp/Q11v5_LabSetUp_worker.bash /tmp/Q11v5_Cleanup_Reset_worker.bash
echo "Worker: $(hostname)"
echo "Before: $(kubelet --version 2>/dev/null || echo '<kubelet missing>')"
sudo KUBELET_TAG="${KUBELET_TAG}" bash /tmp/Q11v5_LabSetUp_worker.bash
echo "After:  $(kubelet --version 2>/dev/null || echo '<kubelet missing>')"
EOSSH

echo
echo "[7] Wait for kubeletVersion to refresh in API..."
sleep 15
kubectl get nodes -o wide || true

echo
echo "✅ Skew should now be present on ${WORKER}."
echo "If not, SSH to worker and run:"
echo "  sudo KUBELET_TAG=${KUBELET_TAG} bash /tmp/Q11v5_LabSetUp_worker.bash"
