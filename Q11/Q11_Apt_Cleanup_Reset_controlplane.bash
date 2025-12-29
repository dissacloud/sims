#!/usr/bin/env bash
# Q11 (APT-based) Cleanup — controlplane orchestrator
# Runs the worker cleanup script remotely (so you don't accidentally run it on controlplane).
#
# Usage:
#   bash Q11_Apt_Cleanup_Reset_controlplane.bash
#   WORKER=node01 bash Q11_Apt_Cleanup_Reset_controlplane.bash
#   WORKER=node01 TARGET_VERSION=1.34.3-1.1 bash Q11_Apt_Cleanup_Reset_controlplane.bash

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="${WORKER:-}"
TARGET_VERSION="${TARGET_VERSION:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need kubectl
need ssh
need scp

if [[ -z "${WORKER}" ]]; then
  WORKER="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}' | awk '$2=="" {print $1}' | head -n1 || true)"
fi

echo "== Q11 APT Cleanup (controlplane) =="
echo "Date: $(date -Is)"
echo "Worker: ${WORKER}"
echo "TARGET_VERSION: ${TARGET_VERSION:-<auto>}"
echo

if [[ -z "${WORKER}" ]]; then
  echo "ERROR: Could not determine a worker node."
  echo "Remediation: set WORKER explicitly, e.g.: WORKER=node01 bash $0"
  exit 2
fi

echo "[1] Copying worker cleanup script..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "${SCRIPT_DIR}/Q11_Apt_Cleanup_Reset_worker.bash" \
  "${WORKER}:/tmp/Q11_Apt_Cleanup_Reset_worker.bash" >/dev/null
echo "✅ Copied."
echo

echo "[2] Executing cleanup on worker (sudo bash)..."
if [[ -n "${TARGET_VERSION}" ]]; then
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "${WORKER}" "chmod +x /tmp/Q11_Apt_Cleanup_Reset_worker.bash && sudo TARGET_VERSION=${TARGET_VERSION} bash /tmp/Q11_Apt_Cleanup_Reset_worker.bash"
else
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "${WORKER}" "chmod +x /tmp/Q11_Apt_Cleanup_Reset_worker.bash && sudo bash /tmp/Q11_Apt_Cleanup_Reset_worker.bash"
fi

echo
echo "[3] Cluster node versions:"
sleep 15
kubectl get nodes -o wide || true

echo
echo "✅ Cleanup complete."
