#!/usr/bin/env bash
# Q07 v2 — Audit Policy Lab Setup (CONTROLPLANE)
# Intentionally removes audit flags/mounts from kube-apiserver and installs a minimal "basic" policy.
set -euo pipefail

echo "🚀 Setting up auditing lab (Q07 v2) — CONTROLPLANE (kubeadm)"

ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"
APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
POLICY_DIR="/etc/kubernetes/logpolicy"
POLICY_FILE="${POLICY_DIR}/audit-policy.yaml"
LOG_DIR="/var/log/kubernetes"
AUDIT_LOG_FILE="${LOG_DIR}/audit-logs.txt"

TS="$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="/root/cis-q07-backups-${TS}"
mkdir -p "${BACKUP_DIR}"

echo "📦 Backing up to: ${BACKUP_DIR}"
cp -a "${APISERVER_MANIFEST}" "${BACKUP_DIR}/kube-apiserver.yaml.bak"

mkdir -p "${POLICY_DIR}" "${LOG_DIR}"
if [[ -f "${POLICY_FILE}" ]]; then
  cp -a "${POLICY_FILE}" "${BACKUP_DIR}/audit-policy.yaml.bak"
fi
if [[ -f "${AUDIT_LOG_FILE}" ]]; then
  cp -a "${AUDIT_LOG_FILE}" "${BACKUP_DIR}/audit-logs.txt.bak" || true
fi

echo "🧩 Creating a BASIC audit policy (intentionally incomplete)…"
cat > "${POLICY_FILE}" <<'POL'
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
# BASIC: only specifies what NOT to log (noise)
- level: None
  verbs: ["watch"]

- level: None 'POL'
# add basic health checks exclusion
cat >> "${POLICY_FILE}" <<'POL'
  nonResourceURLs:
  - "/healthz*"
  - "/readyz*"
  - "/livez*"

# NOTE: The required RequestResponse/Metadata rules are NOT present yet (candidate must add).
POL

# Ensure log file path exists (even before apiserver writes to it)
touch "${AUDIT_LOG_FILE}"
chmod 0644 "${AUDIT_LOG_FILE}"

echo "🧩 Removing audit flags and audit mounts from kube-apiserver manifest (break state)…"
# Remove any existing audit flags
sed -i \
  -e '/--audit-policy-file=/d' \
  -e '/--audit-log-path=/d' \
  -e '/--audit-log-maxbackup=/d' \
  -e '/--audit-log-maxage=/d' \
  "${APISERVER_MANIFEST}"

# Remove audit-related volumeMounts and volumes (by name or mountPath)
# volumeMounts: remove any mountPath to /etc/kubernetes/logpolicy or /var/log/kubernetes AND any name used by those
sed -i \
  -e '/mountPath:\s*\/etc\/kubernetes\/logpolicy\b/{N;d;}' \
  -e '/mountPath:\s*\/var\/log\/kubernetes\b/{N;d;}' \
  "${APISERVER_MANIFEST}"

# Remove volumes named audit-policy/audit-log or hostPath referencing those dirs
# This is best-effort; if blocks vary, cleanup script will restore.
sed -i \
  -e '/- name:\s*audit-policy\b/,+3d' \
  -e '/- name:\s*audit-log\b/,+3d' \
  -e '/path:\s*\/etc\/kubernetes\/logpolicy\b/{N;N;d;}' \
  -e '/path:\s*\/var\/log\/kubernetes\b/{N;N;d;}' \
  "${APISERVER_MANIFEST}" || true

echo "✅ Setup complete."
echo "   - Basic policy at: ${POLICY_FILE}"
echo "   - Target log at:   ${AUDIT_LOG_FILE}"
echo
echo "ℹ️ kube-apiserver will be restarted automatically by kubelet due to manifest change."
echo "   Validate when ready: KUBECONFIG=${ADMIN_KUBECONFIG} kubectl get --raw=/readyz"


chmod +x Q07v2_LabSetUp_controlplane.bash
