#!/usr/bin/env bash
set -euo pipefail

echo "🧹 Cleaning up / resetting API Server Auditing lab (Q07)"

APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
POLICY_FILE="/etc/kubernetes/logpolicy/audit-policy.yaml"
AUDIT_LOG_FILE="/var/log/kubernetes/audit-logs.txt"
REPORT="/root/kube-bench-report-q07.txt"
ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"

backup_dir="$(ls -d /root/cis-q07-backups-* 2>/dev/null | sort | tail -n 1 || true)"
echo "Backup: ${backup_dir:-none}"

if [[ -n "${backup_dir}" && -f "${backup_dir}/kube-apiserver.yaml" ]]; then
  echo "📦 Restoring kube-apiserver manifest from backup..."
  cp -a "${backup_dir}/kube-apiserver.yaml" "${APISERVER_MANIFEST}"
fi

if [[ -n "${backup_dir}" && -f "${backup_dir}/audit-policy.yaml" ]]; then
  echo "📦 Restoring audit policy from backup..."
  mkdir -p /etc/kubernetes/logpolicy
  cp -a "${backup_dir}/audit-policy.yaml" "${POLICY_FILE}"
fi

echo "🧹 Removing audit log file and report..."
rm -f "${AUDIT_LOG_FILE}" "${REPORT}"

echo "🧹 Removing test namespaces (best-effort)..."
KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl delete ns webapps --ignore-not-found >/dev/null 2>&1 || true
KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl delete ns q07-audit-test --ignore-not-found >/dev/null 2>&1 || true

echo "⏳ Waiting for API server to be Ready after restore..."
for i in {1..60}; do
  if KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get --raw=/readyz >/dev/null 2>&1; then
    echo "✅ API server is Ready."
    break
  fi
  sleep 2
done

echo "✅ Q07 cleanup complete."
