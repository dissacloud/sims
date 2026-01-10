#!/usr/bin/env bash
set -euo pipefail

NS="ai"
HOST_DEVMEM="/opt/lab/devmem"

log(){ echo "[reset] $*"; }

log "Deleting namespace '${NS}' (removes all lab resources)"
if kubectl get ns "${NS}" >/dev/null 2>&1; then
  kubectl delete ns "${NS}" --wait=true
else
  log "Namespace '${NS}' not present — nothing to delete"
fi

log "Removing simulated host /dev/mem file"
if sudo test -f "${HOST_DEVMEM}"; then
  sudo rm -f "${HOST_DEVMEM}"
  log "Removed ${HOST_DEVMEM}"
else
  log "Host file ${HOST_DEVMEM} not present"
fi

log "Removing empty lab directory (if unused)"
if sudo test -d "/opt/lab"; then
  sudo rmdir /opt/lab 2>/dev/null || true
fi

log "Reset complete. Environment is back to pre-lab state."

echo
echo "Verification (should show nothing lab-related):"
kubectl get ns | grep -E "^ai" || echo "✓ namespace ai absent"
sudo test -f "${HOST_DEVMEM}" || echo "✓ /opt/lab/devmem absent"
