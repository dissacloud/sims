#!/usr/bin/env bash
set -euo pipefail

echo "🧹 Cleaning up / resetting CIS kubelet + etcd lab (Q01 v2)"

KUBELET_CONFIG="/var/lib/kubelet/config.yaml"
KUBEADM_FLAGS_FILE="/var/lib/kubelet/kubeadm-flags.env"
ETCD_MANIFEST="/etc/kubernetes/manifests/etcd.yaml"
ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"
BACKUP_ROOT="/root"

echo
echo "🔍 Locating most recent Q01 backup directory..."
backup_dir="$(ls -d ${BACKUP_ROOT}/cis-q01v2-backups-* 2>/dev/null | sort | tail -n 1 || true)"

if [[ -z "${backup_dir}" ]]; then
  echo "WARN: No cis-q01v2-backups-* directory found. Nothing to restore."
else
  echo "📦 Using backup directory: ${backup_dir}"

  if [[ -f "${backup_dir}/config.yaml" ]]; then
    echo "↩️  Restoring kubelet config.yaml"
    cp -a "${backup_dir}/config.yaml" "${KUBELET_CONFIG}"
  fi

  if [[ -f "${backup_dir}/kubeadm-flags.env" ]]; then
    echo "↩️  Restoring kubeadm-flags.env"
    cp -a "${backup_dir}/kubeadm-flags.env" "${KUBEADM_FLAGS_FILE}"
  fi

  if [[ -f "${backup_dir}/etcd.yaml" ]]; then
    echo "↩️  Restoring etcd static pod manifest"
    cp -a "${backup_dir}/etcd.yaml" "${ETCD_MANIFEST}"
  fi
fi

echo
echo "🧹 Removing simulated kube-bench report..."
rm -f /root/kube-bench-report-q01.txt

echo
echo "🔁 Restarting kubelet to reconcile configuration and static pods..."
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
echo "🔐 Ensuring kubectl is using admin kubeconfig"
export KUBECONFIG="${ADMIN_KUBECONFIG}"

echo
echo "✅ Q01 v2 cleanup complete."
echo "Validation:"
echo "  kubectl get nodes"
