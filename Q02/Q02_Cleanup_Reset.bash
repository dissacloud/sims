#!/usr/bin/env bash
set -euo pipefail

echo "🧹 Cleaning up / resetting API Server hardening lab (Q02)"

APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"
INSECURE_KUBECONFIG="/root/.kube/config"
BACKUP_ROOT="/root"

echo
echo "🔍 Locating most recent Q02 backup directory..."
backup_dir="$(ls -d ${BACKUP_ROOT}/cis-q02-backups-* 2>/dev/null | sort | tail -n 1 || true)"

if [[ -z "${backup_dir}" ]]; then
  echo "WARN: No cis-q02-backups-* directory found. Nothing to restore."
else
  echo "📦 Using backup directory: ${backup_dir}"

  if [[ -f "${backup_dir}/kube-apiserver.yaml" ]]; then
    echo "↩️  Restoring kube-apiserver manifest..."
    cp -a "${backup_dir}/kube-apiserver.yaml" "${APISERVER_MANIFEST}"
  else
    echo "WARN: kube-apiserver.yaml not found in backup."
  fi

  if [[ -f "${backup_dir}/config" ]]; then
    echo "↩️  Restoring previous kubeconfig..."
    mkdir -p /root/.kube
    cp -a "${backup_dir}/config" "${INSECURE_KUBECONFIG}"
  fi
fi

echo
echo "🧹 Removing lab-created RBAC objects..."
if KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get clusterrolebinding system-anonymous >/dev/null 2>&1; then
  KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl delete clusterrolebinding system-anonymous
  echo "✅ Removed ClusterRoleBinding system-anonymous"
else
  echo "ℹ️  ClusterRoleBinding system-anonymous not present"
fi

echo
echo "🧹 Removing simulated kube-bench report..."
rm -f /root/kube-bench-report-q02.txt

echo
echo "🔁 Restarting kubelet to reconcile static pods..."
systemctl daemon-reload >/dev/null 2>&1 || true
systemctl restart kubelet

echo
echo "⏳ Waiting for API server to become ready..."
for i in $(seq 1 30); do
  if KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get --raw=/readyz >/dev/null 2>&1; then
    echo "✅ API server is ready."
    break
  fi
  sleep 2
done

echo
echo "🔐 Resetting kubectl to admin context..."
export KUBECONFIG="${ADMIN_KUBECONFIG}"

echo
echo "✅ Q02 cleanup complete."
echo
echo "Validation:"
echo "  kubectl get nodes"
