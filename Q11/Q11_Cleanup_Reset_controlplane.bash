#!/usr/bin/env bash
# Q11 Cleanup — CONTROLPLANE orchestrator
# Purpose:
#   Trigger the WORKER cleanup from the control plane (via SSH), restoring the worker kubelet
#   from the backup directory created during Q11 setup.
#
# Usage:
#   bash Q11_Cleanup_Reset_controlplane.bash
#   WORKER=node01 bash Q11_Cleanup_Reset_controlplane.bash
#
# Notes:
# - This script RUNS on the control plane, but EXECUTES the restore on the worker via SSH.
# - Requires SSH access from control plane to worker (interactive password OK; sudo password may be required on worker).

set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="${WORKER:-}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing required command: $1"; exit 127; }; }
need kubectl
need ssh
need scp

echo "== Q11 Cleanup (controlplane orchestrator) =="
echo "Date: $(date -Is)"
echo "KUBECONFIG: ${KUBECONFIG}"
echo

# Auto-detect a worker if not provided
if [[ -z "${WORKER}" ]]; then
  WORKER="$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi

if [[ -z "${WORKER}" ]]; then
  echo "ERROR: Could not auto-detect a worker node."
  echo "Remediation: set WORKER explicitly, e.g.: WORKER=node01 bash $0"
  exit 2
fi

echo "Worker selected: ${WORKER}"
echo

# Robust worker cleanup script (copied to worker each run so it always exists and matches expectations)
cat > /tmp/Q11_Cleanup_Reset_worker.bash <<'WORKER_BASH'
#!/usr/bin/env bash
# Q11 Worker Cleanup — robust restore of kubelet binary from backup
set -euo pipefail

echo "== Q11 Worker Cleanup (robust) =="
echo "Node: $(hostname)"
echo "Date: $(date -Is)"
echo

# Locate a backup directory created by the setup scripts.
# Supports:
#   /root/cis-q11-backups
#   /root/cis-q11*-backups-<timestamp>
#   /root/cis-q11v*-backups-<timestamp>
candidates=(
  /root/cis-q11-backups
  /root/cis-q11*-backups-*
  /root/cis-q11v*-backups-*
)

BACKUP_DIR=""
for pat in "${candidates[@]}"; do
  for match in $pat; do
    [[ -d "$match" ]] || continue
    BACKUP_DIR="$match"
  done
done

if [[ -z "${BACKUP_DIR}" ]]; then
  echo "ERROR: Could not find any Q11 backup directory under /root."
  echo "Remediation: ls -lah /root | grep cis-q11 ; identify the backup dir and restore kubelet manually."
  exit 2
fi

# Pick newest by mtime (covers multiple matches)
BACKUP_DIR="$(ls -1dt /root/cis-q11-backups /root/cis-q11*-backups-* /root/cis-q11v*-backups-* 2>/dev/null | head -n1)"
echo "Using backup dir: ${BACKUP_DIR}"

# Find a plausible original kubelet backup file
orig=""
for f in   "${BACKUP_DIR}/kubelet.original"   "${BACKUP_DIR}/kubelet.before"   "${BACKUP_DIR}"/kubelet.before.*   "${BACKUP_DIR}"/kubelet.*original* ; do
  [[ -f "$f" ]] || continue
  orig="$f"
  break
done

if [[ -z "${orig}" ]]; then
  echo "ERROR: No kubelet backup file found in ${BACKUP_DIR}"
  echo "Remediation: ls -lah ${BACKUP_DIR} and identify additionally created kubelet backup filename."
  exit 3
fi

echo "Restoring kubelet from: ${orig}"
echo

DEST="/usr/bin/kubelet"

echo "Stopping kubelet..."
sudo systemctl stop kubelet || true
sleep 1

echo "Installing restored kubelet..."
sudo cp -a "${orig}" "${DEST}.new"
sudo chmod 0755 "${DEST}.new"
sudo mv -f "${DEST}.new" "${DEST}"
sudo chmod 0755 "${DEST}"

echo "Starting kubelet..."
sudo systemctl daemon-reload
sudo systemctl start kubelet

echo
echo "kubelet version now:"
kubelet --version || true

echo
echo "✅ Worker cleanup complete."
WORKER_BASH

chmod +x /tmp/Q11_Cleanup_Reset_worker.bash

echo "[1] Copying robust worker cleanup to ${WORKER}..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /tmp/Q11_Cleanup_Reset_worker.bash "${WORKER}:/tmp/Q11_Cleanup_Reset_worker.bash" >/dev/null
echo "✅ Copied to ${WORKER}:/tmp/Q11_Cleanup_Reset_worker.bash"
echo

echo "[2] Executing worker cleanup on ${WORKER} (sudo)..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER}" "chmod +x /tmp/Q11_Cleanup_Reset_worker.bash && sudo bash /tmp/Q11_Cleanup_Reset_worker.bash"
echo

echo "[3] Waiting for node to re-register..."
sleep 10
kubectl get nodes -o wide || true

echo
echo "✅ Q11 cleanup orchestration complete."
