#!/usr/bin/env bash
# Q11 Strict Grader (exam-style) — CONTROLPLANE ONLY
# Validates:
# - Worker kubeletVersion matches control plane kubeletVersion
# - Worker is Ready and uncordoned
# - Deployments/StatefulSets unchanged from setup baseline
# - Warns (does not fail) if control plane version changed

set -euo pipefail
set -u
trap '' PIPE

ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"
k(){ KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl "$@"; }

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

echo "== Q11 Strict Grader (kube-bench-like) =="
echo "Date: $(date -Is)"
echo

HOST="$(hostname || true)"
if [[ "${HOST}" != "controlplane" ]]; then
  add_fail "Run location is controlplane"     "This grader must be run on the control plane (you are on '${HOST}')"     "Exit the worker node and run: bash Q11_Grader_Strict.bash on controlplane"
  echo
  for r in "${results[@]}"; do echo "$r"; echo; done
  echo "== Summary =="; echo "0 checks PASS"; echo "0 checks WARN"; echo "1 checks FAIL"
  exit 2
fi

BASE="/root/.q11"
if [[ -d "${BASE}" ]]; then
  add_pass "Baseline exists"
else
  add_fail "Baseline exists"     "Baseline directory ${BASE} not found"     "Re-run setup: bash Q11_LabSetUp_controlplane.bash"
fi

CP_NODE="$(cat "${BASE}/controlplane.node" 2>/dev/null || echo "controlplane")"
WK_NODE="$(cat "${BASE}/worker.node" 2>/dev/null || echo "compute-0")"
CP_VER_BASE="$(cat "${BASE}/controlplane.kubeletVersion" 2>/dev/null || true)"

if k get --raw=/readyz >/dev/null 2>&1; then
  add_pass "API server reachable (/readyz)"
else
  add_fail "API server reachable (/readyz)"     "API server not reachable"     "Fix cluster control plane before grading"
fi

if k get node "${CP_NODE}" >/dev/null 2>&1; then
  add_pass "Control plane node '${CP_NODE}' exists"
else
  add_fail "Control plane node '${CP_NODE}' exists"     "Could not find node '${CP_NODE}'"     "Run: kubectl get nodes; ensure correct control plane node name"
fi

if k get node "${WK_NODE}" >/dev/null 2>&1; then
  add_pass "Worker node '${WK_NODE}' exists"
else
  add_fail "Worker node '${WK_NODE}' exists"     "Could not find node '${WK_NODE}'"     "Run: kubectl get nodes; ensure worker node name matches (expected compute-0)"
fi

CP_VER="$(k get node "${CP_NODE}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"
WK_VER="$(k get node "${WK_NODE}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"

if [[ -n "${CP_VER_BASE}" && "${CP_VER}" == "${CP_VER_BASE}" ]]; then
  add_pass "Control plane kubeletVersion unchanged (${CP_VER})"
else
  add_warn "Control plane kubeletVersion unchanged"     "Expected '${CP_VER_BASE}', found '${CP_VER}'"     "This task should not upgrade/downgrade the control plane"
fi

if [[ -n "${CP_VER}" && -n "${WK_VER}" && "${CP_VER}" == "${WK_VER}" ]]; then
  add_pass "Worker kubeletVersion matches control plane (${WK_VER})"
else
  add_fail "Worker kubeletVersion matches control plane"     "Worker is '${WK_VER}', control plane is '${CP_VER}'"     "Upgrade kubeadm/kubelet/kubectl on ${WK_NODE} to match ${CP_VER}, restart kubelet, then uncordon"
fi

READY="$(k get node "${WK_NODE}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null || true)"
if [[ "${READY}" == "True" ]]; then
  add_pass "Worker node is Ready"
else
  add_fail "Worker node is Ready"     "Ready condition is '${READY}'"     "Check kubelet on ${WK_NODE}: systemctl status kubelet; journalctl -u kubelet"
fi

UNSCHED="$(k get node "${WK_NODE}" -o jsonpath='{.spec.unschedulable}' 2>/dev/null || true)"
if [[ -z "${UNSCHED}" || "${UNSCHED}" == "false" ]]; then
  add_pass "Worker node is uncordoned (schedulable)"
else
  add_fail "Worker node is uncordoned (schedulable)"     "Node is cordoned/unschedulable"     "Run: kubectl uncordon ${WK_NODE}"
fi

DEP_BASE="${BASE}/deployments.baseline.yaml"
STS_BASE="${BASE}/statefulsets.baseline.yaml"

tmpd="$(mktemp -d)"
cleanup(){ rm -rf "${tmpd}"; }
trap cleanup EXIT

k get deploy -A -o yaml > "${tmpd}/deployments.now.yaml" || true
k get sts -A -o yaml > "${tmpd}/statefulsets.now.yaml" || true

normalize() {
  sed -E     -e '/creationTimestamp:/d'     -e '/resourceVersion:/d'     -e '/uid:/d'     -e '/managedFields:/,/^  [^ ]/d'     -e '/^status:/,$d'
}

if [[ -f "${DEP_BASE}" ]]; then
  if diff -u <(normalize < "${DEP_BASE}") <(normalize < "${tmpd}/deployments.now.yaml") >/dev/null 2>&1; then
    add_pass "Deployments unchanged (baseline match)"
  else
    add_fail "Deployments unchanged (baseline match)"       "Deployments YAML differs from baseline"       "Do not modify workloads. If you edited deployments, revert changes. Draining is fine."
  fi
else
  add_warn "Deployments baseline present"     "Baseline file missing (${DEP_BASE})"     "Re-run setup: bash Q11_LabSetUp_controlplane.bash"
fi

if [[ -f "${STS_BASE}" ]]; then
  if diff -u <(normalize < "${STS_BASE}") <(normalize < "${tmpd}/statefulsets.now.yaml") >/dev/null 2>&1; then
    add_pass "StatefulSets unchanged (baseline match)"
  else
    add_fail "StatefulSets unchanged (baseline match)"       "StatefulSets YAML differs from baseline"       "Do not modify workloads. If you edited statefulsets, revert changes."
  fi
else
  add_warn "StatefulSets baseline present"     "Baseline file missing (${STS_BASE})"     "Re-run setup: bash Q11_LabSetUp_controlplane.bash"
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
