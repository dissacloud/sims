#!/usr/bin/env bash
# Q11 v3 Cleanup/Reset (controlplane) — restore kubelet on compute-0 using worker cleanup script.

set -euo pipefail

WORKER="compute-0"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need ssh

echo "🧹 Q11 v3 Cleanup — restoring kubelet on ${WORKER}"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER}" bash -s <<'EOSSH'
set -euo pipefail
chmod +x /tmp/Q11v3_Cleanup_Reset_compute-0.bash || true
sudo bash /tmp/Q11v3_Cleanup_Reset_compute-0.bash
EOSSH
echo "✅ Cleanup triggered."
