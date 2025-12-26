#!/usr/bin/env bash
# Q07 Strict Auto-Verifier (kube-bench-like) — v1
# Strictly enforces FIRST-MATCH semantics and rule ordering for audit-policy.yaml.

set -u

POLICY_FILE="/etc/kubernetes/logpolicy/audit-policy.yaml"
ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"
APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
AUDIT_LOG_FILE="/var/log/kubernetes/audit-logs.txt"

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

echo "== Q07 Strict Auto-Verifier (kube-bench-like) =="
echo "Date: $(date -Is)"
echo "Policy: ${POLICY_FILE}"
echo

# Sanity: apiserver reachable
if KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get --raw=/readyz >/dev/null 2>&1; then
  add_pass "API server reachable (/readyz)"
else
  add_fail "API server reachable (/readyz)" "API server not reachable" "Fix kube-apiserver and re-run"
fi

# Required flags (still checked)
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

if [[ ! -f "${POLICY_FILE}" ]]; then
  add_fail "Audit policy file exists" "Missing ${POLICY_FILE}" "Create/restore the file at ${POLICY_FILE}"
else
  add_pass "Audit policy file exists"
fi

# ---------- Strict policy parsing ----------
parse_out="$(awk '
  BEGIN{ in=0; idx=0; }
  function flush(){
    if(in==0) return;
    gsub(/\r/,"",buf);
    print idx "|" level "|" has_verbs "|" has_nonres "|" has_resources "|" has_namespaces "|" buf;
  }
  /^\s*-\s*level:\s*/{
    flush();
    in=1; idx++;
    buf=$0 "\n";
    level=$0; sub(/^\s*-\s*level:\s*/,"",level); gsub(/\s+/,"",level);
    has_verbs=0; has_nonres=0; has_resources=0; has_namespaces=0;
    next;
  }
  {
    if(in==1){
      buf=buf $0 "\n";
      if($0 ~ /^\s*verbs:\s*/){has_verbs=1}
      if($0 ~ /^\s*nonResourceURLs:\s*/){has_nonres=1}
      if($0 ~ /^\s*resources:\s*/){has_resources=1}
      if($0 ~ /^\s*namespaces:\s*/){has_namespaces=1}
    }
  }
  END{flush();}
' "${POLICY_FILE}" 2>/dev/null || true)"

if [[ -z "${parse_out}" ]]; then
  add_fail "Policy contains at least one rule (- level: ...)"     "Could not parse any rules; file may be empty or not in expected format"     "Ensure the policy has rules starting with '- level: ...'"
else
  add_pass "Policy contains rule blocks"
fi

idx_deploy_webapps=""
idx_namespaces=""
idx_cmsecret=""
idx_catchall_meta=""
idx_catchall_none=""

while IFS='|' read -r idx level has_verbs has_nonres has_resources has_namespaces buf; do
  b="${buf}"

  if [[ "${level}" == "RequestResponse" ]]      && echo "${b}" | grep -qE 'deployments'      && echo "${b}" | grep -qE 'namespaces:\s*\[\s*webapps\s*\]'; then
    idx_deploy_webapps="${idx}"
  fi

  if [[ "${level}" == "RequestResponse" ]]      && echo "${b}" | grep -qE 'namespaces'; then
    if [[ -z "${idx_namespaces}" ]]; then
      idx_namespaces="${idx}"
    fi
  fi

  if [[ "${level}" == "Metadata" ]]      && echo "${b}" | grep -qE '(configmaps|secrets)'; then
    idx_cmsecret="${idx}"
  fi

  if [[ "${level}" == "Metadata" && "${has_verbs}" -eq 0 && "${has_nonres}" -eq 0 && "${has_resources}" -eq 0 && "${has_namespaces}" -eq 0 ]]; then
    idx_catchall_meta="${idx}"
  fi

  if [[ "${level}" == "None" && "${has_verbs}" -eq 0 && "${has_nonres}" -eq 0 && "${has_resources}" -eq 0 && "${has_namespaces}" -eq 0 ]]; then
    idx_catchall_none="${idx}"
  fi
done <<< "${parse_out}"

if [[ -n "${idx_deploy_webapps}" ]]; then
  add_pass "Policy has RequestResponse rule for deployments in namespace webapps"
else
  add_fail "Policy has RequestResponse rule for deployments in namespace webapps"     "Missing deployments(webapps) RequestResponse rule"     "Add a rule: level RequestResponse for apps/deployments with namespaces: [webapps]"
fi

if [[ -n "${idx_namespaces}" ]]; then
  add_pass "Policy has RequestResponse rule for namespaces"
else
  add_fail "Policy has RequestResponse rule for namespaces"     "Missing namespaces RequestResponse rule"     "Add a rule: level RequestResponse for resource namespaces"
fi

if [[ -n "${idx_cmsecret}" ]]; then
  add_pass "Policy has Metadata rule for ConfigMaps/Secrets"
else
  add_fail "Policy has Metadata rule for ConfigMaps/Secrets"     "Missing Metadata rule for configmaps/secrets"     "Add a rule: level Metadata for resources: [secrets, configmaps]"
fi

if [[ -n "${idx_catchall_meta}" ]]; then
  add_pass "Policy has catch-all Metadata rule"
else
  add_fail "Policy has catch-all Metadata rule"     "Missing final catch-all Metadata rule"     "Add FINAL rule: '- level: Metadata' with no selectors"
fi

last_idx="$(echo "${parse_out}" | awk -F'|' 'END{print $1}' 2>/dev/null || true)"
last_idx="${last_idx:-}"

if [[ -n "${idx_catchall_none}" ]]; then
  add_fail "Policy must not contain catch-all None rule"     "Found catch-all None rule at rule index ${idx_catchall_none}"     "Remove/replace the unscoped '- level: None' catch-all; use '- level: Metadata' as final rule"
else
  add_pass "No catch-all None rule present"
fi

if [[ -n "${idx_catchall_meta}" && -n "${last_idx}" ]]; then
  if [[ "${idx_catchall_meta}" == "${last_idx}" ]]; then
    add_pass "Catch-all Metadata rule is LAST (strict)"
  else
    add_fail "Catch-all Metadata rule is LAST (strict)"       "Catch-all Metadata is at index ${idx_catchall_meta}, but last rule is index ${last_idx}"       "Move the unscoped '- level: Metadata' rule to the VERY END"
  fi
fi

# Ensure specific rules appear BEFORE catch-all
if [[ -n "${idx_catchall_meta}" && -n "${idx_deploy_webapps}" ]]; then
  if (( idx_deploy_webapps < idx_catchall_meta )); then
    add_pass "deployments(webapps) rule appears before catch-all (strict)"
  else
    add_fail "deployments(webapps) rule appears before catch-all (strict)"       "deployments(webapps) rule index ${idx_deploy_webapps} is not before catch-all ${idx_catchall_meta}"       "Place deployments(webapps) RequestResponse rule ABOVE catch-all Metadata"
  fi
fi

if [[ -n "${idx_catchall_meta}" && -n "${idx_namespaces}" ]]; then
  if (( idx_namespaces < idx_catchall_meta )); then
    add_pass "namespaces rule appears before catch-all (strict)"
  else
    add_fail "namespaces rule appears before catch-all (strict)"       "namespaces rule index ${idx_namespaces} is not before catch-all ${idx_catchall_meta}"       "Place namespaces RequestResponse rule ABOVE catch-all Metadata"
  fi
fi

if [[ -n "${idx_catchall_meta}" && -n "${idx_cmsecret}" ]]; then
  if (( idx_cmsecret < idx_catchall_meta )); then
    add_pass "configmaps/secrets rule appears before catch-all (strict)"
  else
    add_fail "configmaps/secrets rule appears before catch-all (strict)"       "configmaps/secrets rule index ${idx_cmsecret} is not before catch-all ${idx_catchall_meta}"       "Place configmaps/secrets Metadata rule ABOVE catch-all Metadata"
  fi
fi

# Shadowing check: no early unscoped Metadata
shadow_fail=0
shadow_reason=""
while IFS='|' read -r idx level has_verbs has_nonres has_resources has_namespaces buf; do
  if [[ "${level}" == "Metadata" && "${has_verbs}" -eq 0 && "${has_nonres}" -eq 0 && "${has_resources}" -eq 0 && "${has_namespaces}" -eq 0 ]]; then
    for req in "${idx_deploy_webapps:-}" "${idx_namespaces:-}" "${idx_cmsecret:-}"; do
      if [[ -n "${req}" ]] && (( idx < req )); then
        shadow_fail=1
        shadow_reason="Unscoped Metadata catch-all at index ${idx} appears before required rule index ${req}"
      fi
    done
  fi
done <<< "${parse_out}"

if [[ "${shadow_fail}" -eq 0 ]]; then
  add_pass "No early unscoped Metadata rule shadows required rules (strict)"
else
  add_fail "No early unscoped Metadata rule shadows required rules (strict)"     "${shadow_reason}"     "Ensure only ONE unscoped '- level: Metadata' exists and it is the LAST rule"
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
