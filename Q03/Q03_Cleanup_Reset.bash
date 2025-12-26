#!/usr/bin/env bash
set -euo pipefail

echo "🧹 Cleaning up / resetting ImagePolicyWebhook lab (Q03)"

APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
BOUNCER_DIR="/etc/kubernetes/bouncer"
ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"
BACKUP_ROOT="/root"

echo
echo "🔍 Locating most recent Q03 backup directory..."
backup_dir="$(ls -d ${BACKUP_ROOT}/cis-q03-backups-* 2>/dev/null | sort | tail -n 1 || true)"

if [[ -z "${backup_dir}" ]]; then
  echo "WARN: No cis-q03-backups-* directory found. Nothing to restore."
else
  echo "📦 Using backup directory: ${backup_dir}"

  if [[ -f "${backup_dir}/kube-apiserver.yaml" ]]; then
    echo "↩️  Restoring kube-apiserver manifest..."
    cp -a "${backup_dir}/kube-apiserver.yaml" "${APISERVER_MANIFEST}"
  fi

  # Restore bouncer files if they existed previously; otherwise remove dir
  restored_any=false
  for f in admission-configuration.yaml imagepolicywebhook.kubeconfig; do
    if [[ -f "${backup_dir}/${f}" ]]; then
      mkdir -p "${BOUNCER_DIR}"
      cp -a "${backup_dir}/${f}" "${BOUNCER_DIR}/${f}"
      restored_any=true
    fi
  done

  if [[ "${restored_any}" == "false" ]]; then
    rm -rf "${BOUNCER_DIR}"
  fi
fi

echo
echo "🧹 Removing simulated report and test manifest..."
rm -f /root/kube-bench-report-q03.txt
rm -f "${HOME}/vulnerable.yaml"

echo
echo "🔁 Restarting kubelet to reconcile static pods..."
systemctl daemon-reload >/dev/null 2>&1 || true
systemctl restart kubelet

echo
echo "⏳ Waiting for API server readiness..."
for i in $(seq 1 30); do
  if KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get --raw=/readyz >/dev/null 2>&1; then
    echo "✅ API server is ready."
    break
  fi
  sleep 2
done

echo
echo "✅ Q03 cleanup complete."
echo "Validation:"
echo "  KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes"
