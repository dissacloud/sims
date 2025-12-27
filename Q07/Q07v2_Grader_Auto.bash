#!/usr/bin/env bash
# Q07 v2 Auto-Verifier (kube-bench-like) — robust
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

norm_file() {
  # Normalize CRLF + NBSP to standard ASCII spaces.
  # NBSP bytes: \302\240
  cat "$1" 2>/dev/null | tr -d '\r' | tr '\302\240' ' ' || true
}

echo "== Q07 Auto-Verifier (kube-bench-like) =="
echo "Date: $(date -Is)"
echo "Manifest: ${APISERVER_MANIFEST}"
echo "Policy:   ${POLICY_FILE}"
echo "Log:      ${AUDIT_LOG_FILE}"
echo

if KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get --raw=/readyz >/dev/null 2>&1; then
  add_pass "API server is reachable (/readyz)"
else
  add_fail "API server is reachable (/readyz)" "API server not reachable" "Fix kube-apiserver static pod; check logs"
fi

manifest_txt="$(norm_file "${APISERVER_MANIFEST}")"
if [[ -n "${manifest_txt}" ]]; then
  add_pass "kube-apiserver manifest present"
else
  add_fail "kube-apiserver manifest present" "Cannot read ${APISERVER_MANIFEST}" "Ensure file exists and is readable"
fi

need_flags=(
  "--audit-policy-file=/etc/kubernetes/logpolicy/audit-policy.yaml"
  "--audit-log-path=/var/log/kubernetes/audit-logs.txt"
  "--audit-log-maxbackup=2"
  "--audit-log-maxage=10"
)

for f in "${need_flags[@]}"; do
  if printf "%s" "${manifest_txt}" | grep -qF "${f}" 2>/dev/null; then
    add_pass "Manifest contains flag: ${f}"
  else
    add_fail "Manifest contains flag: ${f}" "Flag not found" "Add ${f} under kube-apiserver command args"
  fi
done

if printf "%s" "${manifest_txt}" | grep -qE 'mountPath:\s*/etc/kubernetes/logpolicy\b' 2>/dev/null; then
  add_pass "Manifest mounts /etc/kubernetes/logpolicy"
else
  add_fail "Manifest mounts /etc/kubernetes/logpolicy" "No volumeMount detected" "Add volumeMount+hostPath for /etc/kubernetes/logpolicy (readOnly)"
fi

if printf "%s" "${manifest_txt}" | grep -qE 'mountPath:\s*/var/log/kubernetes\b' 2>/dev/null; then
  add_pass "Manifest mounts /var/log/kubernetes"
else
  add_fail "Manifest mounts /var/log/kubernetes" "No volumeMount detected" "Add volumeMount+hostPath for /var/log/kubernetes"
fi

policy_txt="$(norm_file "${POLICY_FILE}")"
if [[ -n "${policy_txt}" ]]; then
  add_pass "Audit policy file exists"
else
  add_fail "Audit policy file exists" "Missing/unreadable ${POLICY_FILE}" "Create/restore policy file at ${POLICY_FILE}"
fi

# Parse rules by "- level:" blocks (best-effort)
parse_rules="$(awk '
  BEGIN{in=0; idx=0;}
  function flush(){
    if(in==0) return;
    gsub(/\r/,"",buf); gsub(/\302\240/," ",buf);
    print idx "|" buf;
  }
  /^\s*-\s*level:\s*/{ flush(); in=1; idx++; buf=$0 "\n"; next; }
  { if(in==1){ buf=buf $0 "\n"; } }
  END{flush();}
' "${POLICY_FILE}" 2>/dev/null || true)"

has_ns_rr=0
has_deploy_webapps_rr=0
has_cmsecret_meta=0
has_catchall_meta=0

while IFS='|' read -r idx buf; do
  b="${buf}"

  if echo "${b}" | grep -qiE '^\s*-\s*level:\s*RequestResponse' && echo "${b}" | grep -qiE 'namespaces'; then
    has_ns_rr=1
  fi

  if echo "${b}" | grep -qiE '^\s*-\s*level:\s*RequestResponse' \
     && echo "${b}" | grep -qiE 'deployments' \
     && echo "${b}" | grep -qiE 'namespaces:\s*\[\s*"?webapps"?\s*\]|namespaces:.*webapps'; then
    has_deploy_webapps_rr=1
  fi

  if echo "${b}" | grep -qiE '^\s*-\s*level:\s*Metadata' && echo "${b}" | grep -qiE '(configmaps|secrets)'; then
    has_cmsecret_meta=1
  fi

  if echo "${b}" | grep -qiE '^\s*-\s*level:\s*Metadata\s*$' \
     && ! echo "${b}" | grep -qiE '^\s*(verbs:|nonResourceURLs:|resources:|namespaces:|users:)' ; then
    has_catchall_meta=1
  fi
done <<< "${parse_rules}"

[[ "${has_ns_rr}" -eq 1 ]] && add_pass "Policy includes namespaces at RequestResponse" \
  || add_fail "Policy includes namespaces at RequestResponse" "No namespaces RequestResponse rule detected" "Add RequestResponse rule for namespaces"

[[ "${has_deploy_webapps_rr}" -eq 1 ]] && add_pass "Policy includes deployments(webapps) at RequestResponse" \
  || add_fail "Policy includes deployments(webapps) at RequestResponse" "No deployments(webapps) rule detected" "Add RequestResponse rule for apps/deployments in namespaces: [webapps]"

[[ "${has_cmsecret_meta}" -eq 1 ]] && add_pass "Policy includes ConfigMaps/Secrets at Metadata" \
  || add_fail "Policy includes ConfigMaps/Secrets at Metadata" "No Metadata rule for configmaps/secrets detected" "Add Metadata rule for configmaps and secrets"

[[ "${has_catchall_meta}" -eq 1 ]] && add_pass "Policy includes catch-all Metadata rule" \
  || add_fail "Policy includes catch-all Metadata rule" "No final '- level: Metadata' detected" "Add final catch-all '- level: Metadata'"

# Generate events
KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get ns webapps >/dev/null 2>&1 || KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl create ns webapps >/dev/null 2>&1 || true
KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get ns q07-audit-test >/dev/null 2>&1 || KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl create ns q07-audit-test >/dev/null 2>&1 || true

KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n q07-audit-test create configmap q07-cm --from-literal=a=b --dry-run=client -o yaml | \
  KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl apply -f - >/dev/null 2>&1 || true

KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n q07-audit-test create secret generic q07-secret --from-literal=x=y --dry-run=client -o yaml | \
  KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl apply -f - >/dev/null 2>&1 || true

cat <<'YAML' | KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n webapps apply -f - >/dev/null 2>&1 || true
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
  add_fail "Audit log file exists at ${AUDIT_LOG_FILE}" "Audit log file not found" "Ensure apiserver writes to ${AUDIT_LOG_FILE} and mounts /var/log/kubernetes"
fi

log_txt="$(tail -n 800 "${AUDIT_LOG_FILE}" 2>/dev/null || true)"

if echo "${log_txt}" | grep -q '"resource":"deployments"' && echo "${log_txt}" | grep -q '"namespace":"webapps"'; then
  if echo "${log_txt}" | grep -q '"level":"RequestResponse"' && echo "${log_txt}" | grep -q '"requestObject"'; then
    add_pass "Audit log contains RequestResponse+requestObject for deployments in webapps"
  else
    add_warn "Audit log contains RequestResponse+requestObject for deployments in webapps" "Could not confirm RequestResponse+requestObject in recent lines" "Ensure deployments(webapps) rule is RequestResponse and ordered before catch-all"
  fi
else
  add_warn "Audit log contains deployment events for webapps" "No deployments/webapps entries found recently" "Re-run: kubectl -n webapps rollout restart deploy/q07-deploy"
fi

if echo "${log_txt}" | grep -q '"resource":"namespaces"' && echo "${log_txt}" | grep -q '"level":"RequestResponse"'; then
  add_pass "Audit log contains RequestResponse for namespaces"
else
  add_warn "Audit log contains RequestResponse for namespaces" "Could not confirm namespaces RequestResponse in recent lines" "Create a namespace and re-run"
fi

if echo "${log_txt}" | grep -q '"resource":"configmaps"' && echo "${log_txt}" | grep -q '"level":"Metadata"'; then
  add_pass "Audit log contains Metadata for ConfigMaps"
else
  add_warn "Audit log contains Metadata for ConfigMaps" "Could not confirm configmaps Metadata in recent lines" "Generate a configmap and re-run"
fi

if echo "${log_txt}" | grep -q '"resource":"secrets"' && echo "${log_txt}" | grep -q '"level":"Metadata"'; then
  add_pass "Audit log contains Metadata for Secrets"
else
  add_warn "Audit log contains Metadata for Secrets" "Could not confirm secrets Metadata in recent lines" "Generate a secret and re-run"
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
exit $([[ "${fail}" -eq 0 ]] && echo 0 || echo 2)


chmod +x Q07v2_Grader_Auto.bash
