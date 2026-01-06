#!/usr/bin/env bash
# Q07 Auto-Verifier (kube-bench-like) — v4 (effective-state + robust)
# - Verifies audit flags from running kube-apiserver pod (one-arg-per-line)
# - Verifies required mounts from running pod
# - Verifies policy file content (tolerant) + catch-all
# - Generates events and checks audit log content (behaviour)
# - Suppresses SIGPIPE noise

set -u
trap '' PIPE

ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"
APISERVER_NS="kube-system"
POLICY_FILE="/etc/kubernetes/logpolicy/audit-policy.yaml"
AUDIT_LOG_FILE="/var/log/kubernetes/audit-logs.txt"

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

k() { KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl "$@"; }

norm_file() {
  # Normalize CRLF + NBSP to standard ASCII spaces.
  cat "$1" 2>/dev/null | tr -d '\r' | tr '\302\240' ' ' || true
}

echo "== Q07 Auto-Verifier (kube-bench-like) =="
echo "Date: $(date -Is)"
echo "Policy: ${POLICY_FILE}"
echo "Log:    ${AUDIT_LOG_FILE}"
echo

# --- API readiness ---
if k get --raw=/readyz >/dev/null 2>&1; then
  add_pass "API server is reachable (/readyz)"
else
  add_fail "API server is reachable (/readyz)" "API server not reachable" "Check kube-apiserver static pod; use: sudo crictl ps -a | grep kube-apiserver && sudo crictl logs <id>"
fi

# --- Identify kube-apiserver pod ---
APIPOD="$(k -n "${APISERVER_NS}" get pods -l component=kube-apiserver -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "${APIPOD}" ]]; then
  add_pass "kube-apiserver pod detected (${APIPOD})"
else
  add_fail "kube-apiserver pod detected" "Could not find pod with label component=kube-apiserver" "Ensure kube-apiserver static pod is running"
fi

# --- Effective command args (ONE per line) ---
api_cmd_lines="$(k -n "${APISERVER_NS}" get pod "${APIPOD}" -o jsonpath='{range .spec.containers[0].command[*]}{.}{"\n"}{end}' 2>/dev/null || true)"

need_flags=(
  "--audit-policy-file=/etc/kubernetes/logpolicy/audit-policy.yaml"
  "--audit-log-path=/var/log/kubernetes/audit-logs.txt"
  "--audit-log-maxbackup=2"
  "--audit-log-maxage=10"
)

for f in "${need_flags[@]}"; do
  if echo "${api_cmd_lines}" | grep -qxF "${f}" 2>/dev/null; then
    add_pass "Effective apiserver args include: ${f}"
  else
    add_fail "Effective apiserver args include: ${f}" \
      "Flag not present in running kube-apiserver args" \
      "Edit /etc/kubernetes/manifests/kube-apiserver.yaml and add: ${f} under containers[0].command, then wait for restart"
  fi
done

# --- Effective mounts (running pod) ---
mounts="$(k -n "${APISERVER_NS}" get pod "${APIPOD}" -o jsonpath='{range .spec.containers[0].volumeMounts[*]}{.mountPath}{"\n"}{end}' 2>/dev/null || true)"

if echo "${mounts}" | grep -qx "/etc/kubernetes/logpolicy" 2>/dev/null; then
  add_pass "Effective pod mounts /etc/kubernetes/logpolicy"
else
  add_fail "Effective pod mounts /etc/kubernetes/logpolicy" \
    "Mount not found in running kube-apiserver pod" \
    "Add volumeMount for /etc/kubernetes/logpolicy (readOnly) + hostPath volume"
fi

if echo "${mounts}" | grep -qx "/var/log/kubernetes" 2>/dev/null; then
  add_pass "Effective pod mounts /var/log/kubernetes"
else
  add_fail "Effective pod mounts /var/log/kubernetes" \
    "Mount not found in running kube-apiserver pod" \
    "Add volumeMount for /var/log/kubernetes (read-write) + hostPath volume"
fi

# --- Policy file existence + tolerant content checks ---
policy_txt="$(norm_file "${POLICY_FILE}")"
if [[ -n "${policy_txt}" ]]; then
  add_pass "Audit policy file exists and is readable"
else
  add_fail "Audit policy file exists and is readable" \
    "Missing/unreadable ${POLICY_FILE}" \
    "Create/restore policy file at ${POLICY_FILE}"
fi

# Namespaces at RequestResponse (tolerant)
if echo "${policy_txt}" | grep -qiE 'level:\s*RequestResponse' \
  && echo "${policy_txt}" | grep -qiE 'resources:|resources:' \
  && echo "${policy_txt}" | grep -qiE 'namespaces' 2>/dev/null; then
  add_pass "Policy includes namespaces at RequestResponse (tolerant)"
else
  add_fail "Policy includes namespaces at RequestResponse" \
    "Could not detect RequestResponse namespaces rule" \
    "Add a RequestResponse rule that targets core resource: namespaces"
fi

# Deployments in webapps at RequestResponse (tolerant)
if echo "${policy_txt}" | grep -qiE 'level:\s*RequestResponse' \
  && echo "${policy_txt}" | grep -qiE 'deployments' \
  && echo "${policy_txt}" | grep -qiE 'webapps' 2>/dev/null; then
  add_pass "Policy includes deployments(webapps) at RequestResponse (tolerant)"
else
  add_fail "Policy includes deployments(webapps) at RequestResponse" \
    "Could not detect deployments(webapps) RequestResponse rule" \
    "Add RequestResponse rule for apps/deployments with namespaces: [webapps]"
fi

# Configmaps + secrets at Metadata (tolerant)
if echo "${policy_txt}" | grep -qiE 'level:\s*Metadata' \
  && echo "${policy_txt}" | grep -qiE 'configmaps' \
  && echo "${policy_txt}" | grep -qiE 'secrets' 2>/dev/null; then
  add_pass "Policy includes ConfigMaps/Secrets at Metadata (tolerant)"
else
  add_fail "Policy includes ConfigMaps/Secrets at Metadata" \
    "Could not detect Metadata rule for configmaps+secrets" \
    "Add Metadata rule targeting core resources: [configmaps, secrets]"
fi

# Catch-all Metadata rule exists (must exist; strict ordering checked elsewhere)
if echo "${policy_txt}" | grep -qiE '^\s*-\s*level:\s*Metadata\s*$' 2>/dev/null; then
  add_pass "Policy includes catch-all Metadata rule"
else
  add_fail "Policy includes catch-all Metadata rule" \
    "Could not find unscoped '- level: Metadata' rule" \
    "Add a final rule: '- level: Metadata'"
fi

# --- Functional audit-log checks (behaviour) ---
# Generate events so logs have something to match
k get ns webapps >/dev/null 2>&1 || k create ns webapps >/dev/null 2>&1 || true
k get ns q07-audit-test >/dev/null 2>&1 || k create ns q07-audit-test >/dev/null 2>&1 || true

k -n q07-audit-test create configmap q07-cm --from-literal=a=b --dry-run=client -o yaml | k apply -f - >/dev/null 2>&1 || true
k -n q07-audit-test create secret generic q07-secret --from-literal=x=y --dry-run=client -o yaml | k apply -f - >/dev/null 2>&1 || true

cat <<'YAML' | k -n webapps apply -f - >/dev/null 2>&1 || true
apiVersion: apps/v1
kind: Deployment
metadata:
  name: q07-deploy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: q07
  template:
    metadata:
      labels:
        app: q07
    spec:
      containers:
      - name: web
        image: nginx:1.25-alpine
YAML

sleep 2

if [[ -f "${AUDIT_LOG_FILE}" ]]; then
  add_pass "Audit log file exists at ${AUDIT_LOG_FILE}"
else
  add_fail "Audit log file exists at ${AUDIT_LOG_FILE}" \
    "Audit log file not found" \
    "Confirm --audit-log-path and /var/log/kubernetes mount; ensure apiserver restarted cleanly"
fi

log_txt="$(tail -n 1500 "${AUDIT_LOG_FILE}" 2>/dev/null || true)"

# Deployments in webapps should be RequestResponse with requestObject
if echo "${log_txt}" | grep -q '"resource":"deployments"' \
  && echo "${log_txt}" | grep -q '"namespace":"webapps"' \
  && echo "${log_txt}" | grep -q '"level":"RequestResponse"' \
  && echo "${log_txt}" | grep -q '"requestObject"'; then
  add_pass "Audit log contains RequestResponse+requestObject for deployments in webapps"
else
  add_warn "Audit log contains RequestResponse+requestObject for deployments in webapps" \
    "Could not confirm required fields in recent lines" \
    "Re-run after: kubectl -n webapps rollout restart deploy/q07-deploy"
fi

# Namespaces should be RequestResponse
if echo "${log_txt}" | grep -q '"resource":"namespaces"' && echo "${log_txt}" | grep -q '"level":"RequestResponse"'; then
  add_pass "Audit log contains RequestResponse for namespaces"
else
  add_warn "Audit log contains RequestResponse for namespaces" \
    "Could not confirm namespaces RequestResponse in recent lines" \
    "Create another namespace and re-run"
fi

# ConfigMaps and Secrets should be Metadata
if echo "${log_txt}" | grep -q '"resource":"configmaps"' && echo "${log_txt}" | grep -q '"level":"Metadata"'; then
  add_pass "Audit log contains Metadata for ConfigMaps"
else
  add_warn "Audit log contains Metadata for ConfigMaps" \
    "Could not confirm configmaps Metadata in recent lines" \
    "Generate another configmap and re-run"
fi

if echo "${log_txt}" | grep -q '"resource":"secrets"' && echo "${log_txt}" | grep -q '"level":"Metadata"'; then
  add_pass "Audit log contains Metadata for Secrets"
else
  add_warn "Audit log contains Metadata for Secrets" \
    "Could not confirm secrets Metadata in recent lines" \
    "Generate another secret and re-run"
fi

echo
# Print results safely (avoid SIGPIPE noise)
for r in "${results[@]}"; do
  printf "%s\n\n" "$r" || true
done

echo "== Summary =="
echo "${pass} checks PASS"
echo "${warn} checks WARN"
echo "${fail} checks FAIL"

if [[ "${fail}" -eq 0 ]]; then
  exit 0
else
  exit 2
fi

