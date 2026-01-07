#!/usr/bin/env bash
set -euo pipefail

echo "== Q7 Lab Setup: Kubernetes Auditing (BROKEN BASELINE + TRAPS) =="

APISERVER="/etc/kubernetes/manifests/kube-apiserver.yaml"
APISERVER_BAK="/etc/kubernetes/manifests/kube-apiserver.yaml.q7bak"

POLICY_DIR="/etc/kubernetes/logpolicy"
POLICY_FILE="${POLICY_DIR}/audit-policy.yaml"
LOG_DIR="/var/log/kubernetes"
LOG_FILE="${LOG_DIR}/audit-logs.txt"

# Backup kube-apiserver manifest once (so reset is safe)
if [[ ! -f "${APISERVER_BAK}" ]]; then
  sudo cp "${APISERVER}" "${APISERVER_BAK}"
  echo "[INFO] Backed up kube-apiserver manifest to ${APISERVER_BAK}"
fi

# Create dirs & base policy (only 'what not to log') - intentionally incomplete
sudo mkdir -p "${POLICY_DIR}"
sudo mkdir -p "${LOG_DIR}"

cat <<'EOF' | sudo tee "${POLICY_FILE}" >/dev/null
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Basic policy: what NOT to log
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

  # TRAP: A too-broad catch-all (wrong) that candidates must fix by extending correctly.
  # If left as-is above specific rules, it can shadow intent.
  - level: Metadata
EOF

# Prepare log file
sudo touch "${LOG_FILE}"
sudo chmod 600 "${LOG_FILE}"
sudo truncate -s 0 "${LOG_FILE}" || true

# WAIT HERE — before any kubectl usage
wait_for_apiserver() {
  echo "[INFO] Waiting for kube-apiserver to become ready..."
  for i in {1..60}; do
    if KUBECONFIG=/etc/kubernetes/admin.conf kubectl get --raw='/readyz' >/dev/null 2>&1; then
      echo "[INFO] kube-apiserver is ready"
      return 0
    fi
    sleep 2
  done
  echo "[ERROR] kube-apiserver did not become ready in time" >&2
  exit 1
}


# Ensure webapps namespace exists (grader will generate actions against it)
KUBECONFIG=/etc/kubernetes/admin.conf kubectl get ns webapps >/dev/null 2>&1 || \
  KUBECONFIG=/etc/kubernetes/admin.conf kubectl create ns webapps >/dev/null

# Create a baseline deployment in webapps (grader will patch/restart to generate deployment events)
KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n webapps get deploy audit-gen >/dev/null 2>&1 || \
  KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n webapps create deploy audit-gen --image=nginx:1.25-alpine >/dev/null

echo
echo "[INFO] Baseline created:"
echo " - Policy file (incomplete + trap): ${POLICY_FILE}"
echo " - Log file (empty):               ${LOG_FILE}"
echo " - Namespace: webapps"
echo " - Deployment: webapps/audit-gen"
echo
echo "[INFO] kube-apiserver is NOT configured for auditing yet (candidate must do flags + mounts)."
echo "Run: ./question.sh"
