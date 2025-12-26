#!/usr/bin/env bash
set -euo pipefail

echo "🧹 Cleaning up / resetting misbehaving pod containment lab (Q05)"

NS="ollama"
REPORT="/root/kube-bench-report-q05.txt"
BACKUP_ROOT="/root"

echo
echo "🔍 Locating most recent Q05 backup directory..."
backup_dir="$(ls -d ${BACKUP_ROOT}/cis-q05-backups-* 2>/dev/null | sort | tail -n 1 || true)"
echo "Backup: ${backup_dir:-none}"

echo
echo "🧹 Deleting namespace ${NS} (removes deployments/pods)..."
kubectl delete ns "${NS}" --ignore-not-found

echo
echo "🧹 Removing simulated report..."
rm -f "${REPORT}"

echo "✅ Q05 cleanup complete."
