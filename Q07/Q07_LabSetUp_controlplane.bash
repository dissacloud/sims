#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Setting up API Server Auditing lab (Q07 v1) — CONTROLPLANE (kubeadm static pod)"

ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"
APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
POLICY_DIR="/etc/kubernetes/logpolicy"
POLICY_FILE="${POLICY_DIR}/audit-policy.yaml"
AUDIT_LOG_DIR="/var/log/kubernetes"
AUDIT_LOG_FILE="${AUDIT_LOG_DIR}/audit-logs.txt"
REPORT="/root/kube-bench-report-q07.txt"

ts="$(date +%Y%m%d%H%M%S)"
backup_dir="/root/cis-q07-backups-${ts}"
mkdir -p "${backup_dir}"

echo "📦 Backing up kube-apiserver manifest to: ${backup_dir}"
cp -a "${APISERVER_MANIFEST}" "${backup_dir}/kube-apiserver.yaml"

echo "📦 Ensuring policy and log directories exist"
mkdir -p "${POLICY_DIR}"
mkdir -p "${AUDIT_LOG_DIR}"

echo "🧩 Writing BASIC audit policy (intentionally incomplete) to: ${POLICY_FILE}"
cat > "${POLICY_FILE}" <<'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
# Don't log watch requests (noise)
- level: None
  verbs: ["watch"]
# Don't log health checks
- level: None
  nonResourceURLs:
  - "/healthz*"
  - "/readyz*"
  - "/livez*"
# Default: log nothing else (INTENTIONALLY WRONG for the lab; must be changed)
- level: None
EOF

echo "📦 Backing up policy file to: ${backup_dir}"
cp -a "${POLICY_FILE}" "${backup_dir}/audit-policy.yaml"

echo
echo "🧩 Ensuring audit is NOT effectively enabled yet (intentional misconfig)..."
tmp="${backup_dir}/kube-apiserver.stripped.yaml"
cp -a "${APISERVER_MANIFEST}" "${tmp}"

sed -i '/--audit-policy-file=/d' "${tmp}"
sed -i '/--audit-log-path=/d' "${tmp}"
sed -i '/--audit-log-maxage=/d' "${tmp}"
sed -i '/--audit-log-maxbackup=/d' "${tmp}"
sed -i '/--audit-log-maxsize=/d' "${tmp}"

grep -vE '(/etc/kubernetes/logpolicy|/var/log/kubernetes|name: audit-|name: logpolicy|name: auditlog|audit-policy\.yaml|audit-logs\.txt)' "${tmp}" > "${tmp}.2" || true
mv "${tmp}.2" "${tmp}"

cp -a "${tmp}" "${APISERVER_MANIFEST}"

echo "✅ kube-apiserver manifest updated (audit flags removed)."

echo
echo "🧹 Removing any existing audit log file for a clean start..."
rm -f "${AUDIT_LOG_FILE}"

echo
echo "📝 Writing simulated findings report: ${REPORT}"
cat > "${REPORT}" <<EOF
# Q07 Findings (SIMULATED) — API Server Auditing

[INFO] Cluster: kubeadm static pods (controlplane)
[INFO] Required policy path: ${POLICY_FILE}
[INFO] Required log path:    ${AUDIT_LOG_FILE}

[FAIL] API server is not configured to use the audit policy and write audit logs
       * Required flags:
         - --audit-policy-file=${POLICY_FILE}
         - --audit-log-path=${AUDIT_LOG_FILE}
         - --audit-log-maxbackup=2
         - --audit-log-maxage=10

[FAIL] Audit policy is incomplete
       * Required additions:
         - Namespaces interactions at level RequestResponse
         - Deployments interactions in namespace webapps at level RequestResponse (include request body)
         - ConfigMap and Secret interactions in all namespaces at the Metadata level
         - All other requests at the Metadata level

== Summary ==
2 tasks outstanding
EOF

echo
echo "⏳ Waiting for kube-apiserver to be Ready..."
for i in {1..60}; do
  if KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get --raw=/readyz >/dev/null 2>&1; then
    echo "✅ API server is Ready."
    break
  fi
  sleep 2
done

echo
echo "✅ Q07 lab setup complete."
echo "Files:"
echo "  - Policy:  ${POLICY_FILE}"
echo "  - Report:  ${REPORT}"
echo "  - Audit log (will be created by candidate): ${AUDIT_LOG_FILE}"
