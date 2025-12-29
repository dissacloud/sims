#!/usr/bin/env bash
# Q11 (APT-based) Cleanup — controlplane orchestrator (v3)
# Uses worker cleanup v3 (no-tty gpg).

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="${WORKER:-node01}"
RESTORE_MINOR="${RESTORE_MINOR:-1.34}"
TARGET_VERSION="${TARGET_VERSION:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== Q11 APT Cleanup (controlplane) v3 =="
echo "Date: $(date -Is)"
echo "Worker: ${WORKER}"
echo "RESTORE_MINOR: ${RESTORE_MINOR}"
echo "TARGET_VERSION: ${TARGET_VERSION:-<auto>}"
echo

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null   "${SCRIPT_DIR}/Q11_Apt_Cleanup_Reset_worker_v3.bash"   "${WORKER}:/tmp/Q11_Apt_Cleanup_Reset_worker.bash" >/dev/null

if [[ -n "${TARGET_VERSION}" ]]; then
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null     "${WORKER}" "chmod +x /tmp/Q11_Apt_Cleanup_Reset_worker.bash && sudo RESTORE_MINOR=${RESTORE_MINOR} TARGET_VERSION=${TARGET_VERSION} bash /tmp/Q11_Apt_Cleanup_Reset_worker.bash"
else
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null     "${WORKER}" "chmod +x /tmp/Q11_Apt_Cleanup_Reset_worker.bash && sudo RESTORE_MINOR=${RESTORE_MINOR} bash /tmp/Q11_Apt_Cleanup_Reset_worker.bash"
fi

echo
echo "Waiting for kubeletVersion to refresh..."
sleep 25
kubectl get nodes -o wide || true
echo
echo "✅ Cleanup complete on ${WORKER}."
