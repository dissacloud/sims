#!/usr/bin/env bash
set -euo pipefail

LAB_HOME="${HOME}/subtle-bee"
DOCKERFILE="${LAB_HOME}/build/Dockerfile"
DEPLOYMENT="${LAB_HOME}/deployment.yaml"
BACKUP_ROOT="/root"

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

latest_backup="$(ls -d ${BACKUP_ROOT}/cis-q04-backups-* 2>/dev/null | sort | tail -n 1 || true)"

echo "== Q04 Auto-Verifier (kube-bench-like) =="
echo "Date: $(date -Is)"
echo "Dockerfile: ${DOCKERFILE}"
echo "Deployment: ${DEPLOYMENT}"
echo "Backup: ${latest_backup:-none}"
echo

# Dockerfile present
[[ -f "${DOCKERFILE}" ]] && add_pass "Dockerfile present" || \
add_fail "Dockerfile present" "Missing Dockerfile" "Ensure Dockerfile exists"

# Effective USER
eff_user="$(grep -E '^\s*USER\s+' "${DOCKERFILE}" | tail -n 1 | awk '{print $2}')"
if [[ "${eff_user}" == "65535" || "${eff_user}" == "nobody" ]]; then
  add_pass "Dockerfile runtime user is unprivileged (USER ${eff_user})"
else
  add_fail "Dockerfile runtime user is unprivileged" \
    "Effective USER is '${eff_user}'" \
    "Change only the final USER to 65535 or nobody"
fi

# Deployment present
[[ -f "${DEPLOYMENT}" ]] && add_pass "Deployment manifest present" || \
add_fail "Deployment manifest present" "Missing deployment.yaml" "Ensure manifest exists"

# privileged false
if grep -qE '^\s*privileged:\s*false\s*$' "${DEPLOYMENT}"; then
  add_pass "Deployment privileged mode disabled"
else
  add_fail "Deployment privileged mode disabled" \
    "privileged is not false" \
    "Set privileged: false"
fi

# Best-effort minimal change checks (safe diff)
if [[ -n "${latest_backup}" ]]; then
  dcount="$(diff -u "${latest_backup}/Dockerfile" "${DOCKERFILE}" 2>/dev/null || true | grep -E '^[+-]' | grep -vE '^\+\+\+|^---' | wc -l)"
  [[ "${dcount}" -le 2 ]] && add_pass "Dockerfile modified minimally" || \
    add_warn "Dockerfile modified minimally" "Detected ${dcount} changed lines" "Only one instruction should change"

  mcount="$(diff -u "${latest_backup}/deployment.yaml" "${DEPLOYMENT}" 2>/dev/null || true | grep -E '^[+-]' | grep -vE '^\+\+\+|^---' | wc -l)"
  [[ "${mcount}" -le 2 ]] && add_pass "Deployment modified minimally" || \
    add_warn "Deployment modified minimally" "Detected ${mcount} changed lines" "Only one field should change"
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

[[ "${fail}" -eq 0 ]]
