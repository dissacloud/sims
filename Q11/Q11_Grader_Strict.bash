#!/usr/bin/env bash
# Q11 Strict Grader (exam-style) — v2
# Strictly verifies:
#  - worker kubeletVersion == control-plane kubeletVersion
#  - worker is Ready and schedulable
#  - drain before uncordon (NodeNotSchedulable before NodeSchedulable in Events)

set -u
trap '' PIPE

ADMIN_KUBECONFIG="${ADMIN_KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="${WORKER:-}"
CP_NODE="${CP_NODE:-}"

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

k(){ KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl "$@"; }

echo "== Q11 Strict Grader (kube-bench-like) =="
echo "Date: $(date -Is)"
echo "KUBECONFIG: ${ADMIN_KUBECONFIG}"
echo

if k get --raw=/readyz >/dev/null 2>&1; then
  add_pass "API server reachable (/readyz)"
else
  add_fail "API server reachable (/readyz)" "API not reachable" "Check control plane and KUBECONFIG=/etc/kubernetes/admin.conf"
fi

if [[ -z "${CP_NODE}" ]]; then
  CP_NODE="$(k get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi
if [[ -z "${WORKER}" ]]; then
  WORKER="$(k get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi

[[ -n "${CP_NODE}" ]] && add_pass "Control-plane detected (${CP_NODE})" || add_fail "Control-plane detected" "Not found" "Set CP_NODE explicitly"
[[ -n "${WORKER}" ]] && add_pass "Worker detected (${WORKER})" || add_fail "Worker detected" "Not found" "Set WORKER explicitly"

if [[ -z "${CP_NODE}" || -z "${WORKER}" ]]; then
  echo; for r in "${results[@]}"; do echo "$r"; echo; done
  echo "== Summary =="; echo "${pass} checks PASS"; echo "${warn} checks WARN"; echo "${fail} checks FAIL"
  exit 2
fi

ready="$(k get node "${WORKER}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null || true)"
[[ "${ready}" == "True" ]] && add_pass "Worker Ready=True" || add_fail "Worker Ready=True" "Ready='${ready:-<missing>}'" "Fix kubelet on worker"

unsched="$(k get node "${WORKER}" -o jsonpath='{.spec.unschedulable}' 2>/dev/null || true)"
if [[ -z "${unsched}" || "${unsched}" == "false" ]]; then
  add_pass "Worker schedulable (uncordoned)"
else
  add_fail "Worker schedulable (uncordoned)" "spec.unschedulable=true" "kubectl uncordon ${WORKER}"
fi

cp_ver="$(k get node "${CP_NODE}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"
wk_ver="$(k get node "${WORKER}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"

[[ -n "${cp_ver}" ]] && add_pass "CP kubeletVersion=${cp_ver}" || add_fail "CP kubeletVersion" "Missing" "Check kubelet on control-plane"
[[ -n "${wk_ver}" ]] && add_pass "Worker kubeletVersion=${wk_ver}" || add_fail "Worker kubeletVersion" "Missing" "Check kubelet on worker"

if [[ -n "${cp_ver}" && -n "${wk_ver}" ]]; then
  [[ "${wk_ver}" == "${cp_ver}" ]] && add_pass "Version match (strict)" || add_fail "Version match (strict)" "Worker=${wk_ver} CP=${cp_ver}" "Upgrade worker kubelet to ${cp_ver}"
fi

ev="$(k get events -A --field-selector involvedObject.kind=Node,involvedObject.name=${WORKER} --sort-by=.lastTimestamp 2>/dev/null || true)"
if [[ -z "${ev}" ]]; then
  add_fail "Events available for order check" "No node events returned" "Drain then uncordon the worker"
else
  cordon_idx="$(printf "%s\n" "${ev}" | grep -n 'NodeNotSchedulable' | head -n1 | cut -d: -f1)"
  uncordon_idx="$(printf "%s\n" "${ev}" | grep -n 'NodeSchedulable' | tail -n1 | cut -d: -f1)"

  [[ -n "${cordon_idx}" ]] && add_pass "Drain event present (NodeNotSchedulable)" || add_fail "Drain event present" "Missing NodeNotSchedulable" "kubectl drain ${WORKER} ..."
  [[ -n "${uncordon_idx}" ]] && add_pass "Uncordon event present (NodeSchedulable)" || add_fail "Uncordon event present" "Missing NodeSchedulable" "kubectl uncordon ${WORKER}"

  if [[ -n "${cordon_idx}" && -n "${uncordon_idx}" ]]; then
    [[ "${cordon_idx}" -lt "${uncordon_idx}" ]] && add_pass "Order OK: drain before uncordon" || add_fail "Order OK: drain before uncordon" "Order incorrect" "Redo: drain -> upgrade -> uncordon"
  fi
fi

echo
for r in "${results[@]}"; do echo "$r"; echo; done

echo "== Summary =="
echo "${pass} checks PASS"
echo "${warn} checks WARN"
echo "${fail} checks FAIL"

exit $([[ "${fail}" -eq 0 ]] && echo 0 || echo 2)
