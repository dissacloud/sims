#!/usr/bin/env bash
# Q11 Lab Setup (controlplane) — create a deliberate version skew by downgrading compute-0 to previous minor.
# Enables repeatable practice of upgrading from 1.33->1.34 or 1.32->1.33.

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="compute-0"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need kubectl
need ssh
need scp

# Determine control-plane server version (target)
CP_VERSION="$(kubectl version --short 2>/dev/null | awk -F': ' '/Server Version/ {gsub(/^v/,"",$2); print $2}' | head -n1)"
if [[ -z "${CP_VERSION}" ]]; then
  echo "ERROR: Could not determine Server Version."
  kubectl version --short || true
  exit 1
fi
CP_MINOR="$(echo "${CP_VERSION}" | awk -F. '{print $1"."$2}')"

echo "🚀 Q11 Setup — creating version skew"
echo "Control-plane server version: v${CP_VERSION}"
echo "Worker: ${WORKER}"
echo "Target minor: ${CP_MINOR}"
echo

# Push compute script to worker and execute it with TARGET_MINOR=control-plane minor
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /mnt/data/Q11_LabSetUp_compute-0.bash "${WORKER}:/tmp/Q11_LabSetUp_compute-0.bash" >/dev/null

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER}" bash -s -- "${CP_MINOR}" <<'EOSSH'
set -euo pipefail
TARGET_MINOR="$1"
chmod +x /tmp/Q11_LabSetUp_compute-0.bash
sudo TARGET_MINOR="${TARGET_MINOR}" bash /tmp/Q11_LabSetUp_compute-0.bash
EOSSH

echo
echo "Checking node versions (may take ~30-60s for kubelet to report)..."
kubectl get nodes -o wide || true

echo
echo "✅ Q11 skew created. Now perform the upgrade task to bring compute-0 up to v${CP_VERSION}."
