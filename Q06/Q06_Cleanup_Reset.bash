#!/usr/bin/env bash
set -euo pipefail

echo "🧹 Cleaning up / resetting container immutability lab (Q06)"

NS="lamp"
WORKDIR="${HOME}/finer-sunbeam"
MANIFEST="${WORKDIR}/lamp-deployment.yaml"
REPORT="/root/kube-bench-report-q06.txt"
BACKUP_ROOT="/root"

echo
echo "🔍 Locating most recent Q06 backup directory..."
backup_dir="$(ls -d ${BACKUP_ROOT}/cis-q06-backups-* 2>/dev/null | sort | tail -n 1 || true)"
echo "Backup: ${backup_dir:-none}"

if [[ -n "${backup_dir}" && -f "${backup_dir}/lamp-deployment.yaml" ]]; then
  mkdir -p "${WORKDIR}"
  cp -a "${backup_dir}/lamp-deployment.yaml" "${MANIFEST}"
fi

echo
echo "🧹 Deleting namespace ${NS} (removes deployment/pods)..."
kubectl delete ns "${NS}" --ignore-not-found

echo
echo "🧹 Removing simulated report..."
rm -f "${REPORT}"

echo "✅ Q06 cleanup complete."
