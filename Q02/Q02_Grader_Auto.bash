#!/usr/bin/env bash
set -euo pipefail

# Q02 Auto-Verifier (Unified)
# Checks kube-apiserver manifest flags + RBAC cleanup and prints kube-bench-like PASS/FAIL summary.

APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

echo "== Q02 Auto-Verifier (kube-bench-like) =="
echo "Date: $(date -Is)"
echo

if [[ ! -f "${APISERVER_MANIFEST}" ]]; then
  add_fail "1.2.x kube-apiserver manifest present" \
    "${APISERVER_MANIFEST} not found (not a kubeadm control-plane?)" \
    "Run on the control-plane node where kube-apiserver runs as a static pod"
else
  add_pass "1.2.x kube-apiserver manifest present"
fi

# 1) anonymous-auth=false
if grep -qE -- '--anonymous-auth(=| )false' "${APISERVER_MANIFEST}" 2>/dev/null; then
  add_pass "1.2.1 --anonymous-auth set to false"
else
  val="$(grep -E -- '--anonymous-auth(=| )' "${APISERVER_MANIFEST}" 2>/dev/null | head -n1 || true)"
  add_fail "1.2.1 --anonymous-auth set to false" \
    "Found '${val:-missing}'" \
    "Edit ${APISERVER_MANIFEST} and set --anonymous-auth=false"
fi

# 2) authorization-mode=Node,RBAC (exact required)
if grep -qE -- '--authorization-mode(=| )Node,RBAC' "${APISERVER_MANIFEST}" 2>/dev/null; then
  add_pass "1.2.2 --authorization-mode set to Node,RBAC"
else
  val="$(grep -E -- '--authorization-mode(=| )' "${APISERVER_MANIFEST}" 2>/dev/null | head -n1 || true)"
  add_fail "1.2.2 --authorization-mode set to Node,RBAC" \
    "Found '${val:-missing}'" \
    "Edit ${APISERVER_MANIFEST} and set --authorization-mode=Node,RBAC"
fi

# 3) enable-admission-plugins includes NodeRestriction
if grep -qE -- '--enable-admission-plugins(=| ).*NodeRestriction' "${APISERVER_MANIFEST}" 2>/dev/null; then
  add_pass "1.2.8 NodeRestriction admission plugin enabled"
else
  val="$(grep -E -- '--enable-admission-plugins(=| )' "${APISERVER_MANIFEST}" 2>/dev/null | head -n1 || true)"
  add_fail "1.2.8 NodeRestriction admission plugin enabled" \
    "NodeRestriction not present in '${val:-missing}'" \
    "Add NodeRestriction to --enable-admission-plugins in ${APISERVER_MANIFEST}"
fi

# 4) RBAC cleanup: system-anonymous ClusterRoleBinding removed
if KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get clusterrolebinding system-anonymous >/dev/null 2>&1; then
  add_fail "RBAC system-anonymous ClusterRoleBinding removed" \
    "clusterrolebinding/system-anonymous still exists" \
    "kubectl delete clusterrolebinding system-anonymous (using admin.conf)"
else
  add_pass "RBAC system-anonymous ClusterRoleBinding removed"
fi

# Output
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
