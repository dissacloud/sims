#!/usr/bin/env bash
# Q07 v2 Strict Grader — fails if rule ordering is wrong (first-match semantics)
set -u

POLICY_FILE="/etc/kubernetes/logpolicy/audit-policy.yaml"

pass=0; fail=0; warn=0
results=()
add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }

norm_file(){ cat "$1" 2>/dev/null | tr -d '\r' | tr '\302\240' ' ' || true; }

echo "== Q07 Strict Auto-Verifier (kube-bench-like) =="
echo "Date: $(date -Is)"
echo "Policy: ${POLICY_FILE}"
echo

policy_txt="$(norm_file "${POLICY_FILE}")"
if [[ -z "${policy_txt}" ]]; then
  add_fail "Audit policy file exists" "Missing/unreadable ${POLICY_FILE}" "Create/restore ${POLICY_FILE}"
else
  add_pass "Audit policy file exists"
fi

# Parse rule blocks
parse_rules="$(awk '
  BEGIN{in=0; idx=0;}
  function flush(){ if(in==0) return; gsub(/\r/,"",buf); gsub(/\302\240/," ",buf); print idx "|" buf; }
  /^\s*-\s*level:\s*/{ flush(); in=1; idx++; buf=$0 "\n"; next; }
  { if(in==1){ buf=buf $0 "\n"; } }
  END{flush();}
' "${POLICY_FILE}" 2>/dev/null || true)"

idx_deploy=""
idx_ns=""
idx_cmsec=""
idx_catch=""

last_idx="$(echo "${parse_rules}" | awk -F'|' 'END{print $1}')"

while IFS='|' read -r idx buf; do
  b="${buf}"

  if echo "${b}" | grep -qiE '^\s*-\s*level:\s*RequestResponse' \
     && echo "${b}" | grep -qiE 'deployments' \
     && echo "${b}" | grep -qiE 'namespaces:\s*\[\s*"?webapps"?\s*\]|namespaces:.*webapps'; then
    idx_deploy="${idx}"
  fi

  if echo "${b}" | grep -qiE '^\s*-\s*level:\s*RequestResponse' \
     && echo "${b}" | grep -qiE 'namespaces'; then
    [[ -z "${idx_ns}" ]] && idx_ns="${idx}"
  fi

  if echo "${b}" | grep -qiE '^\s*-\s*level:\s*Metadata' \
     && echo "${b}" | grep -qiE '(configmaps|secrets)'; then
    idx_cmsec="${idx}"
  fi

  if echo "${b}" | grep -qiE '^\s*-\s*level:\s*Metadata\s*$' \
     && ! echo "${b}" | grep -qiE '^\s*(verbs:|nonResourceURLs:|resources:|namespaces:|users:)' ; then
    idx_catch="${idx}"
  fi
done <<< "${parse_rules}"

[[ -n "${idx_deploy}" ]] && add_pass "Deployments(webapps) RequestResponse rule present" \
  || add_fail "Deployments(webapps) RequestResponse rule present" "Missing" "Add RequestResponse rule for apps/deployments in namespaces: [webapps]"

[[ -n "${idx_ns}" ]] && add_pass "Namespaces RequestResponse rule present" \
  || add_fail "Namespaces RequestResponse rule present" "Missing" "Add RequestResponse rule for namespaces"

[[ -n "${idx_cmsec}" ]] && add_pass "ConfigMaps/Secrets Metadata rule present" \
  || add_fail "ConfigMaps/Secrets Metadata rule present" "Missing" "Add Metadata rule for configmaps and secrets"

[[ -n "${idx_catch}" ]] && add_pass "Catch-all Metadata rule present" \
  || add_fail "Catch-all Metadata rule present" "Missing" "Add final '- level: Metadata' catch-all"

# Ordering
if [[ -n "${idx_catch}" && -n "${last_idx}" ]]; then
  if [[ "${idx_catch}" == "${last_idx}" ]]; then
    add_pass "Catch-all Metadata rule is LAST (strict)"
  else
    add_fail "Catch-all Metadata rule is LAST (strict)" \
      "Catch-all at index ${idx_catch}, last rule index ${last_idx}" \
      "Move unscoped '- level: Metadata' to the very end"
  fi
fi

# Specific rules must appear before catch-all
for name in "deployments(webapps)=${idx_deploy}" "namespaces=${idx_ns}" "configmaps/secrets=${idx_cmsec}"; do
  key="${name%%=*}"; val="${name##*=}"
  if [[ -n "${val}" && -n "${idx_catch}" ]]; then
    if (( val < idx_catch )); then
      add_pass "${key} rule appears before catch-all (strict)"
    else
      add_fail "${key} rule appears before catch-all (strict)" \
        "Rule index ${val} is not before catch-all ${idx_catch}" \
        "Move ${key} rule above the catch-all Metadata rule"
    fi
  fi
done

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


chmod +x Q07v2_Grader_Strict.bash
