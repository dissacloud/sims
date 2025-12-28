#!/usr/bin/env bash
# Q11 Strict Grader — verifies:
#  - worker kubeletVersion matches control-plane kubeletVersion
#  - worker is Ready and schedulable
#  - cordon/uncordon order (NodeNotSchedulable -> NodeSchedulable events)
#
# Usage:
#   bash Q11_Grader_Strict_v1.bash
#   WORKER=node01 bash Q11_Grader_Strict_v1.bash

set -u
trap '' PIPE

ADMIN_KUBECONFIG="${ADMIN_KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="${WORKER:-}"

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

# --- API check ---
if k get --raw=/readyz >/dev/null 2>&1; then
  add_pass "API server reachable (/readyz)"
else
  add_fail "API server reachable (/readyz)" "API not reachable" "Fix control plane; ensure /etc/kubernetes/admin.conf is valid"
fi

# --- Determine nodes ---
CP_NODE="$(k get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "${CP_NODE}" ]]; then
  CP_NODE="$(k get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}'     | awk 'NF>=2 {print $1; exit}' 2>/dev/null || true)"
fi

if [[ -z "${WORKER}" ]]; then
  WORKER="$(k get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi

if [[ -n "${CP_NODE}" ]]; then
  add_pass "Control-plane node detected (${CP_NODE})"
else
  add_fail "Control-plane node detected" "Could not identify a control-plane node" "Ensure node has label node-role.kubernetes.io/control-plane"
fi

if [[ -n "${WORKER}" ]]; then
  add_pass "Worker node selected (${WORKER})"
else
  add_fail "Worker node selected" "Could not identify a worker node" "Set WORKER explicitly, e.g. WORKER=node01 bash Q11_Grader_Strict_v1.bash"
fi

if [[ -z "${CP_NODE}" || -z "${WORKER}" ]]; then
  echo
  for r in "${results[@]}"; do echo "$r"; echo; done
  echo "== Summary =="; echo "${pass} checks PASS"; echo "${warn} checks WARN"; echo "${fail} checks FAIL"
  exit 2
fi

# --- Current state checks ---
WORKER_READY="$(k get node "${WORKER}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null || true)"
if [[ "${WORKER_READY}" == "True" ]]; then
  add_pass "Worker Ready=True"
else
  add_fail "Worker Ready=True" "Worker is not Ready" "Troubleshoot kubelet on ${WORKER}: systemctl status kubelet; journalctl -u kubelet"
fi

WORKER_UNSCHED="$(k get node "${WORKER}" -o jsonpath='{.spec.unschedulable}' 2>/dev/null || true)"
if [[ -z "${WORKER_UNSCHED}" || "${WORKER_UNSCHED}" == "false" ]]; then
  add_pass "Worker is schedulable (uncordoned)"
else
  add_fail "Worker is schedulable (uncordoned)" "spec.unschedulable=true" "Run: kubectl uncordon ${WORKER}"
fi

CP_VER="$(k get node "${CP_NODE}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"
WK_VER="$(k get node "${WORKER}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"

if [[ -n "${CP_VER}" ]]; then
  add_pass "Control-plane kubeletVersion detected (${CP_VER})"
else
  add_fail "Control-plane kubeletVersion detected" "Could not read kubeletVersion" "Ensure kubelet is running on control-plane and API is healthy"
fi

if [[ -n "${WK_VER}" ]]; then
  add_pass "Worker kubeletVersion detected (${WK_VER})"
else
  add_fail "Worker kubeletVersion detected" "Could not read kubeletVersion" "Ensure kubelet is running on worker and node is registered"
fi

if [[ -n "${CP_VER}" && -n "${WK_VER}" ]]; then
  if [[ "${WK_VER}" == "${CP_VER}" ]]; then
    add_pass "Worker kubeletVersion matches control-plane (${WK_VER})"
  else
    add_fail "Worker kubeletVersion matches control-plane" "Worker=${WK_VER} Control-plane=${CP_VER}"       "Upgrade worker kubelet to ${CP_VER} and restart kubelet (then wait for node version to refresh)"
  fi
fi

# --- Drain/Cordon/Uncordon order (events) ---
events="$(k get events -A --field-selector involvedObject.kind=Node,involvedObject.name=${WORKER} --sort-by=.lastTimestamp 2>/dev/null || true)"

if [[ -z "${events}" ]]; then
  add_fail "Cordon/uncordon order (events present)" "No Node events found for ${WORKER}"     "Redo: kubectl drain ${WORKER} --ignore-daemonsets --delete-emptydir-data --force; then kubectl uncordon ${WORKER}"
else
  cordon_line="$(printf "%s\n" "${events}" | grep -n 'NodeNotSchedulable' | head -n1 | cut -d: -f1)"
  uncordon_line="$(printf "%s\n" "${events}" | grep -n 'NodeSchedulable' | tail -n1 | cut -d: -f1)"

  if [[ -n "${cordon_line}" ]]; then
    add_pass "Cordon event detected (NodeNotSchedulable)"
  else
    add_fail "Cordon event detected (NodeNotSchedulable)" "No NodeNotSchedulable event found"       "Run: kubectl drain ${WORKER} --ignore-daemonsets --delete-emptydir-data --force"
  fi

  if [[ -n "${uncordon_line}" ]]; then
    add_pass "Uncordon event detected (NodeSchedulable)"
  else
    add_fail "Uncordon event detected (NodeSchedulable)" "No NodeSchedulable event found"       "Run: kubectl uncordon ${WORKER}"
  fi

  if [[ -n "${cordon_line}" && -n "${uncordon_line}" ]]; then
    if [[ "${cordon_line}" -lt "${uncordon_line}" ]]; then
      add_pass "Order OK: cordon/drain occurred before uncordon (events ordered)"
    else
      add_fail "Order OK: cordon/drain occurred before uncordon" "Uncordon appears before cordon in sorted events"         "Redo in order: drain/cordon first, upgrade, then uncordon"
    fi
  fi

  evicted="$(k get events -A --field-selector reason=Evicted --sort-by=.lastTimestamp 2>/dev/null | grep -F "${WORKER}" | tail -n 1 || true)"
  if [[ -n "${evicted}" ]]; then
    add_pass "Drain produced eviction activity (Evicted events present)"
  else
    add_warn "Drain produced eviction activity (Evicted events present)"       "No Evicted events referencing ${WORKER} found (may be normal if few/no pods)"       "Optional: schedule a test pod on ${WORKER} then drain again"
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
