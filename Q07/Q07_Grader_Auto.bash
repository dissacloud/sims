#!/usr/bin/env bash
# Q07 Auto-Verifier (kube-bench-like) — v1 (robust)

set -u

ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"
APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
POLICY_FILE="/etc/kubernetes/logpolicy/audit-policy.yaml"
AUDIT_LOG_FILE="/var/log/kubernetes/audit-logs.txt"

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

echo "== Q07 Auto-Verifier (kube-bench-like) =="
echo "Date: $(date -Is)"
echo

if KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get --raw=/readyz >/dev/null 2>&1; then
  add_pass "API server is reachable (/readyz)"
else
  add_fail "API server is reachable (/readyz)" "API server not reachable" "Fix kube-apiserver static pod; check docker logs"
fi

if [[ -f "${APISERVER_MANIFEST}" ]]; then
  add_pass "kube-apiserver manifest present"
else
  add_fail "kube-apiserver manifest present" "Missing ${APISERVER_MANIFEST}" "Ensure kubeadm static pod manifest exists"
fi

need_flags=(
  "--audit-policy-file=${POLICY_FILE}"
  "--audit-log-path=${AUDIT_LOG_FILE}"
  "--audit-log-maxbackup=2"
  "--audit-log-maxage=10"
)

for f in "${need_flags[@]}"; do
  if grep -qF "${f}" "${APISERVER_MANIFEST}" 2>/dev/null; then
    add_pass "Manifest contains flag: ${f}"
  else
    add_fail "Manifest contains flag: ${f}" "Flag not found" "Add ${f} under kube-apiserver command args"
  fi
done

if grep -qE 'mountPath:\s*/etc/kubernetes/logpolicy' "${APISERVER_MANIFEST}" 2>/dev/null; then
  add_pass "Manifest mounts /etc/kubernetes/logpolicy"
else
  add_fail "Manifest mounts /etc/kubernetes/logpolicy" "No volumeMount detected" "Add volumeMount+hostPath for /etc/kubernetes/logpolicy (readOnly)"
fi

if grep -qE 'mountPath:\s*/var/log/kubernetes' "${APISERVER_MANIFEST}" 2>/dev/null; then
  add_pass "Manifest mounts /var/log/kubernetes"
else
  add_fail "Manifest mounts /var/log/kubernetes" "No volumeMount detected" "Add volumeMount+hostPath for /var/log/kubernetes"
fi

if [[ -f "${POLICY_FILE}" ]]; then
  add_pass "Audit policy file exists"
else
  add_fail "Audit policy file exists" "Missing ${POLICY_FILE}" "Create/restore policy file at ${POLICY_FILE}"
fi

policy_txt="$(cat "${POLICY_FILE}" 2>/dev/null || true)"

if echo "${policy_txt}" | grep -qiE 'level:\s*RequestResponse' && echo "${policy_txt}" | grep -qiE 'namespaces'; then
  add_pass "Policy includes namespaces at RequestResponse (best-effort)"
else
  add_fail "Policy includes namespaces at RequestResponse" "No RequestResponse rule for namespaces detected" "Add a RequestResponse rule for resource namespaces"
fi

if echo "${policy_txt}" | grep -qiE 'deployments' && echo "${policy_txt}" | grep -qiE 'namespaces:\s*\[\s*webapps\s*\]'; then
  add_pass "Policy includes deployments scoped to webapps (best-effort)"
else
  add_fail "Policy includes deployments scoped to webapps" "No deployments(webapps) rule detected" "Add RequestResponse rule for apps/deployments in namespaces: [webapps]"
fi

if echo "${policy_txt}" | grep -qiE 'level:\s*Metadata' && echo "${policy_txt}" | grep -qiE '(secrets|configmaps)'; then
  add_pass "Policy includes ConfigMaps/Secrets at Metadata (best-effort)"
else
  add_fail "Policy includes ConfigMaps/Secrets at Metadata" "No Metadata rule for secrets+configmaps detected" "Add Metadata rule for resources secrets and configmaps"
fi

if echo "${policy_txt}" | grep -qiE '^\s*-\s*level:\s*Metadata\s*$'; then
  add_pass "Policy includes catch-all Metadata rule (best-effort)"
else
  add_fail "Policy includes catch-all Metadata rule" "No final '- level: Metadata' detected" "Add final rule '- level: Metadata'"
fi

# Functional audit log checks (generate events)
KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get ns webapps >/dev/null 2>&1 || KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl create ns webapps >/dev/null 2>&1 || true
KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get ns q07-audit-test >/dev/null 2>&1 || KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl create ns q07-audit-test >/dev/null 2>&1 || true

KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n q07-audit-test create configmap q07-cm --from-literal=a=b --dry-run=client -o yaml | KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl apply -f - >/dev/null 2>&1 || true
KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n q07-audit-test create secret generic q07-secret --from-literal=x=y --dry-run=client -o yaml | KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl apply -f - >/dev/null 2>&1 || true

cat <<'EOF' | KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n webapps apply -f - >/dev/null 2>&1 || true
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
        ports:
        - containerPort: 80
EOF

KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get ns >/dev/null 2>&1 || true
sleep 2

if [[ -f "${AUDIT_LOG_FILE}" ]]; then
  add_pass "Audit log file exists at ${AUDIT_LOG_FILE}"
else
  add_fail "Audit log file exists at ${AUDIT_LOG_FILE}" "Audit log file not found" "Ensure apiserver writes to ${AUDIT_LOG_FILE} and mounts /var/log/kubernetes"
fi

log_txt="$(tail -n 500 "${AUDIT_LOG_FILE}" 2>/dev/null || true)"

if echo "${log_txt}" | grep -q '"resource":"deployments"' 2>/dev/null && echo "${log_txt}" | grep -q '"namespace":"webapps"' 2>/dev/null; then
  if echo "${log_txt}" | grep -q '"level":"RequestResponse"' 2>/dev/null && echo "${log_txt}" | grep -q '"requestObject"' 2>/dev/null; then
    add_pass "Audit log contains RequestResponse+requestObject for deployments in webapps (best-effort)"
  else
    add_fail "Audit log contains RequestResponse+requestObject for deployments in webapps" "Missing RequestResponse/requestObject in recent entries" "Ensure deployments(webapps) rule is RequestResponse and ordered before catch-all"
  fi
else
  add_warn "Audit log contains deployment events for webapps (best-effort)" "No deployments/webapps entries found in last 500 lines" "Re-run after applying another deployment change"
fi

if echo "${log_txt}" | grep -q '"resource":"namespaces"' 2>/dev/null; then
  if echo "${log_txt}" | grep -q '"level":"RequestResponse"' 2>/dev/null; then
    add_pass "Audit log contains RequestResponse for namespaces (best-effort)"
  else
    add_fail "Audit log contains RequestResponse for namespaces" "Namespaces entries not at RequestResponse in recent logs" "Ensure namespaces rule is RequestResponse and above catch-all"
  fi
else
  add_warn "Audit log contains namespaces events (best-effort)" "No namespaces entries found in recent logs" "Create a namespace and re-run"
fi

if echo "${log_txt}" | grep -q '"resource":"configmaps"' 2>/dev/null && echo "${log_txt}" | grep -q '"level":"Metadata"' 2>/dev/null; then
  add_pass "Audit log contains Metadata for ConfigMaps (best-effort)"
else
  add_warn "Audit log contains Metadata for ConfigMaps (best-effort)" "Could not confirm configmaps at Metadata in recent logs" "Ensure policy has Metadata rule for configmaps"
fi

if echo "${log_txt}" | grep -q '"resource":"secrets"' 2>/dev/null && echo "${log_txt}" | grep -q '"level":"Metadata"' 2>/dev/null; then
  add_pass "Audit log contains Metadata for Secrets (best-effort)"
else
  add_warn "Audit log contains Metadata for Secrets (best-effort)" "Could not confirm secrets at Metadata in recent logs" "Ensure policy has Metadata rule for secrets"
fi

echo
for r in "${results[@]}"; do
  echo "$r"
  echo
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
