#!/usr/bin/env bash
# Q11 (APT-based) Lab Setup — controlplane orchestrator (v3)
# Uses worker scripts v3 (no-tty gpg).

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="${WORKER:-node01}"
TARGET_MINOR="${TARGET_MINOR:-1.33}"
TARGET_VERSION="${TARGET_VERSION:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== Q11 APT Lab Setup (controlplane) v3 =="
echo "Date: $(date -Is)"
echo "Worker: ${WORKER}"
echo "Target worker minor (skew): ${TARGET_MINOR}"
echo "Target worker version (optional): ${TARGET_VERSION:-<auto>}"
echo

kubectl get nodes -o wide || true
echo

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null   "${SCRIPT_DIR}/Q11_Apt_LabSetUp_worker_v3.bash"   "${WORKER}:/tmp/Q11_Apt_LabSetUp_worker.bash" >/dev/null

if [[ -n "${TARGET_VERSION}" ]]; then
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null     "${WORKER}" "chmod +x /tmp/Q11_Apt_LabSetUp_worker.bash && sudo TARGET_MINOR=${TARGET_MINOR} TARGET_VERSION=${TARGET_VERSION} bash /tmp/Q11_Apt_LabSetUp_worker.bash"
else
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null     "${WORKER}" "chmod +x /tmp/Q11_Apt_LabSetUp_worker.bash && sudo TARGET_MINOR=${TARGET_MINOR} bash /tmp/Q11_Apt_LabSetUp_worker.bash"
fi

echo
echo "Waiting for kubeletVersion to refresh..."
sleep 25
kubectl get nodes -o wide || true
echo
echo "✅ Skew created on ${WORKER}."
