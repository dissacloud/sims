#!/usr/bin/env bash
set -euo pipefail

NS="ai"
HOST_DEVMEM="/opt/lab/devmem"

log(){ echo "[reset] $*"; }

delete_devmem_on_node() {
  local node="$1"
  local cmd="
set -euo pipefail
sudo rm -f '${HOST_DEVMEM}' || true
sudo rmdir /opt/lab 2>/dev/null || true
"

  if [[ "$node" == "controlplane" || "$node" == "$(hostname)" ]]; then
    bash -lc "$cmd"
  else
    ssh -o StrictHostKeyChecking=no "$node" "bash -lc $(printf %q "$cmd")"
  fi
}

log "Deleting namespace '${NS}'"
kubectl get ns "${NS}" >/dev/null 2>&1 && kubectl delete ns "${NS}" --wait=true || true

log "Removing simulated /opt/lab/devmem from all nodes"
delete_devmem_on_node "controlplane"
mapfile -t nodes < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
for n in "${nodes[@]:-}"; do
  [[ -n "$n" ]] && delete_devmem_on_node "$n"
done

log "Reset complete (pre-lab state)."
