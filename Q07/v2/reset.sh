#!/usr/bin/env bash
set -euo pipefail

echo "== Resetting Q7 to broken baseline =="

APISERVER="/etc/kubernetes/manifests/kube-apiserver.yaml"
APISERVER_BAK="/etc/kubernetes/manifests/kube-apiserver.yaml.q7bak"

POLICY_DIR="/etc/kubernetes/logpolicy"
POLICY_FILE="${POLICY_DIR}/audit-policy.yaml"
LOG_DIR="/var/log/kubernetes"
LOG_FILE="${LOG_DIR}/audit-logs.txt"

# Restore kube-apiserver manifest from backup (safe and deterministic)
if [[ -f "${APISERVER_BAK}" ]]; then
  sudo cp "${APISERVER_BAK}" "${APISERVER}"
  echo "[INFO] Restored kube-apiserver manifest from ${APISERVER_BAK}"
else
  echo "[WARN] No apiserver backup found; cannot safely restore manifest. Re-run labsetup.sh."
fi

# Restore the baseline policy with traps
sudo mkdir -p "${POLICY_DIR}"
cat <<'EOF' | sudo tee "${POLICY_FILE}" >/dev/null
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: None
    nonResourceURLs:
      - /healthz*
      - /readyz*
      - /livez*
      - /metrics
  - level: None
    resources:
      - group: ""
        resources: ["events"]
  - level: Metadata
EOF

# Reset logs
sudo mkdir -p "${LOG_DIR}"
sudo touch "${LOG_FILE}"
sudo chmod 600 "${LOG_FILE}"
sudo truncate -s 0 "${LOG_FILE}" || true

# Ensure webapps baseline exists
KUBECONFIG=/etc/kubernetes/admin.conf kubectl get ns webapps >/dev/null 2>&1 || \
  KUBECONFIG=/etc/kubernetes/admin.conf kubectl create ns webapps >/dev/null
KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n webapps get deploy audit-gen >/dev/null 2>&1 || \
  KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n webapps create deploy audit-gen --image=nginx:1.25-alpine >/dev/null

echo "[INFO] Reset complete. kube-apiserver will restart automatically if manifest changed."
echo "Run: ./question.sh"
