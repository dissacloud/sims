#!/usr/bin/env bash
set -euo pipefail

# Q04 Auto-Verifier (kube-bench-like)

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
if [[ -f "${DOCKERFILE}" ]]; then
  add_pass "Dockerfile present"
else
  add_fail "Dockerfile present" "Missing ${DOCKERFILE}" "Ensure the Dockerfile exists at ${DOCKERFILE}"
fi

# Effective USER (last USER instruction)
eff_user="$(grep -E '^\s*USER\s+' "${DOCKERFILE}" 2>/dev/null | tail -n 1 | awk '{print $2}' || true)"
if [[ "${eff_user}" == "65535" || "${eff_user}" == "nobody" ]]; then
  add_pass "Dockerfile runtime user is unprivileged (USER ${eff_user})"
else
  add_fail "Dockerfile runtime user is unprivileged" "Effective USER is '${eff_user:-missing}' (expected 65535 or nobody)" "Modify ONLY the final USER instruction to USER 65535 (or USER nobody)"
fi

# Deployment present
if [[ -f "${DEPLOYMENT}" ]]; then
  add_pass "Deployment manifest present"
else
  add_fail "Deployment manifest present" "Missing ${DEPLOYMENT}" "Ensure the manifest exists at ${DEPLOYMENT}"
fi

# privileged: false
if grep -qE '^\s*privileged:\s*false\s*$' "${DEPLOYMENT}" 2>/dev/null; then
  add_pass "Deployment privileged mode disabled (privileged: false)"
else
  val="$(grep -E '^\s*privileged:\s*' "${DEPLOYMENT}" 2>/dev/null | head -n 1 || true)"
  add_fail "Deployment privileged mode disabled (privileged: false)" "Found '${val:-missing}'" "Modify ONLY privileged field to privileged: false"
fi

# Best-effort minimal-change checks
if [[ -n "${latest_backup}" && -f "${latest_backup}/Dockerfile" ]]; then
  dcount="$(diff -u "${latest_backup}/Dockerfile" "${DOCKERFILE}" 2>/dev/null | grep -E '^[+-]' | grep -vE '^\+\+\+|^---' | wc -l | tr -d ' ')"
  if [[ "${dcount}" -le 2 ]]; then
    add_pass "Dockerfile modified minimally (best-effort check)"
  else
    add_warn "Dockerfile modified minimally (best-effort check)" "Detected ${dcount} changed lines vs setup backup" "Task requires modifying only ONE instruction; revert extra changes if present"
  fi
fi

if [[ -n "${latest_backup}" && -f "${latest_backup}/deployment.yaml" ]]; then
  mcount="$(diff -u "${latest_backup}/deployment.yaml" "${DEPLOYMENT}" 2>/dev/null | grep -E '^[+-]' | grep -vE '^\+\+\+|^---' | wc -l | tr -d ' ')"
  if [[ "${mcount}" -le 2 ]]; then
    add_pass "Deployment modified minimally (best-effort check)"
  else
    add_warn "Deployment modified minimally (best-effort check)" "Detected ${mcount} changed lines vs setup backup" "Task requires modifying only ONE field; revert extra changes if present"
  fi
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
