#!/usr/bin/env bash
# Q07 v2 — Cleanup/Reset
# Restores kube-apiserver manifest and audit policy from the latest backup.
set -euo pipefail

APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
POLICY_FILE="/etc/kubernetes/logpolicy/audit-policy.yaml"
AUDIT_LOG_FILE="/var/log/kubernetes/audit-logs.txt"

latest_backup="$(ls -1dt /root/cis-q07-backups-* 2>/dev/null | head -n1 || true)"
if [[ -z "${latest_backup}" ]]; then
  echo "❌ No backup directory found at /root/cis-q07-backups-*"
  echo "   Cannot safely reset automatically."
  exit 1
fi

echo "🧹 Resetting Q07 using backup: ${latest_backup}"

if [[ -f "${latest_backup}/kube-apiserver.yaml.bak" ]]; then
  cp -a "${latest_backup}/kube-apiserver.yaml.bak" "${APISERVER_MANIFEST}"
  echo "✅ Restored kube-apiserver manifest"
else
  echo "⚠️ Missing kube-apiserver backup in ${latest_backup}"
fi

if [[ -f "${latest_backup}/audit-policy.yaml.bak" ]]; then
  cp -a "${latest_backup}/audit-policy.yaml.bak" "${POLICY_FILE}"
  echo "✅ Restored audit policy"
else
  echo "ℹ️ No audit-policy backup found; leaving current policy in place."
fi

if [[ -f "${latest_backup}/audit-logs.txt.bak" ]]; then
  cp -a "${latest_backup}/audit-logs.txt.bak" "${AUDIT_LOG_FILE}" || true
  echo "✅ Restored audit log file"
else
  # keep file but truncate to reduce noise
  [[ -f "${AUDIT_LOG_FILE}" ]] && truncate -s 0 "${AUDIT_LOG_FILE}" || true
  echo "ℹ️ Truncated current audit log for cleanliness"
fi

echo
echo "ℹ️ kube-apiserver will restart automatically due to manifest restore."
echo "   Check readiness: export KUBECONFIG=/etc/kubernetes/admin.conf && kubectl get --raw=/readyz"


chmod +x Q07v2_Cleanup_Reset.bash
