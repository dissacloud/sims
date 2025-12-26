#!/usr/bin/env bash
# Q06 Auto-Verifier (kube-bench-like) — v1 (robust)

set -u

NS="lamp"
DEPLOY="lamp-deployment"
ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

echo "== Q06 Auto-Verifier (kube-bench-like) =="
echo "Date: $(date -Is)"
echo "Target: ${NS}/${DEPLOY}"
echo

if KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get ns "${NS}" >/dev/null 2>&1; then
  add_pass "Namespace ${NS} exists"
else
  add_fail "Namespace ${NS} exists" "Namespace not found" "Run Q06_LabSetUp.bash or create namespace ${NS}"
fi

if KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n "${NS}" get deploy "${DEPLOY}" >/dev/null 2>&1; then
  add_pass "Deployment ${DEPLOY} exists"
else
  add_fail "Deployment ${DEPLOY} exists" "Deployment not found" "Ensure ${NS}/${DEPLOY} exists"
fi

run_as_user="$(KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n "${NS}" get deploy "${DEPLOY}" -o jsonpath='{.spec.template.spec.containers[0].securityContext.runAsUser}' 2>/dev/null || true)"
ro_rootfs="$(KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n "${NS}" get deploy "${DEPLOY}" -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null || true)"
allow_pe="$(KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n "${NS}" get deploy "${DEPLOY}" -o jsonpath='{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation}' 2>/dev/null || true)"

if [[ "${run_as_user}" == "20000" ]]; then
  add_pass "runAsUser is 20000"
else
  add_fail "runAsUser is 20000" "Found '${run_as_user:-missing}'" "Set securityContext.runAsUser: 20000 in the container spec"
fi

if [[ "${ro_rootfs}" == "true" ]]; then
  add_pass "readOnlyRootFilesystem is true"
else
  add_fail "readOnlyRootFilesystem is true" "Found '${ro_rootfs:-missing}'" "Set securityContext.readOnlyRootFilesystem: true in the container spec"
fi

if [[ "${allow_pe}" == "false" ]]; then
  add_pass "allowPrivilegeEscalation is false"
else
  add_fail "allowPrivilegeEscalation is false" "Found '${allow_pe:-missing}'" "Set securityContext.allowPrivilegeEscalation: false in the container spec"
fi

pods="$(KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n "${NS}" get pods -l app=lamp -o name 2>/dev/null || true)"
if [[ -n "${pods}" ]]; then
  add_pass "Pods exist for app=lamp"
else
  add_warn "Pods exist for app=lamp" "No pods found yet" "Wait for rollout to complete and re-run grader"
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
