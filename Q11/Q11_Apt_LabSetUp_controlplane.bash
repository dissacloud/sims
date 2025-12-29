#!/usr/bin/env bash
# Q11 (APT-based) Lab Setup — controlplane orchestrator
#
# Runs the worker setup script on the selected worker node via SSH.
#
# Usage:
#   bash Q11_Apt_LabSetUp_controlplane.bash
#   WORKER=node01 TARGET_MINOR=1.33 bash Q11_Apt_LabSetUp_controlplane.bash

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

WORKER="${WORKER:-}"
TARGET_MINOR="${TARGET_MINOR:-1.33}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need kubectl
need ssh
need scp

# Auto-detect worker if not provided
if [[ -z "${WORKER}" ]]; then
  WORKER="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}' | awk '$2=="" {print $1}' | head -n1 || true)"
fi

echo "== Q11 APT Lab Setup (controlplane) =="
echo "Date: $(date -Is)"
echo "Worker: ${WORKER}"
echo "Target worker minor (skew): ${TARGET_MINOR}"
echo

if [[ -z "${WORKER}" ]]; then
  echo "ERROR: Could not determine a worker node."
  echo "Remediation: set WORKER explicitly, e.g.: WORKER=node01 bash $0"
  exit 2
fi

echo "[0] Current cluster node versions:"
kubectl get nodes -o wide || true
echo

echo "[1] Copying worker setup + cleanup scripts to worker..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "${SCRIPT_DIR}/Q11_Apt_LabSetUp_worker.bash" \
  "${WORKER}:/tmp/Q11_Apt_LabSetUp_worker.bash" >/dev/null
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "${SCRIPT_DIR}/Q11_Apt_Cleanup_Reset_worker.bash" \
  "${WORKER}:/tmp/Q11_Apt_Cleanup_Reset_worker.bash" >/dev/null
echo "✅ Copied."
echo

echo "[2] Executing worker setup (sudo bash)..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "${WORKER}" "chmod +x /tmp/Q11_Apt_LabSetUp_worker.bash /tmp/Q11_Apt_Cleanup_Reset_worker.bash && sudo TARGET_MINOR=${TARGET_MINOR} bash /tmp/Q11_Apt_LabSetUp_worker.bash"
echo

echo "[3] Waiting briefly for kubeletVersion to refresh in API..."
sleep 25
kubectl get nodes -o wide || true

echo
echo "✅ Q11 (APT-based) skew environment ready."
echo "Now solve using the standard exam flow: drain -> apt/kubeadm upgrade node -> restart kubelet -> uncordon."
