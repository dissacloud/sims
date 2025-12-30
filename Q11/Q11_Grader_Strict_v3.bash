#!/usr/bin/env bash
# Q11 Strict Grader (exam-style) — v3
# Strictly verifies:
#  - worker kubeletVersion == control-plane kubeletVersion
#  - worker is Ready and schedulable
#  - drain before uncordon (NodeNotSchedulable before NodeSchedulable in Events)
#
# Key fix vs v2:
#  - Do NOT award PASS merely for "worker kubeletVersion detected".
#    Detection is required, but correctness is only PASS when versions match.
#
# Usage:
#   bash Q11_Grader_Strict_v3.bash
#   WORKER=node01 CP_NODE=controlplane bash Q11_Grader_Strict_v3.bash

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

# --- API check ---
if k get --raw=/readyz >/dev/null 2>&1; then
  add_pass "API server reachable (/readyz)"
else
  add_fail "API server reachable (/readyz)" "API not reachable" "Check control plane and set KUBECONFIG=/etc/kubernetes/admin.conf"
fi

# --- Identify nodes ---
if [[ -z "${CP_NODE}" ]]; then
  CP_NODE="$(k get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi
if [[ -z "${WORKER}" ]]; then
  WORKER="$(k get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi

if [[ -n "${CP_NODE}" ]]; then
  add_pass "Control-plane detected (${CP_NODE})"
else
  add_fail "Control-plane detected" "No node with label node-role.kubernetes.io/control-plane found" "Set CP_NODE explicitly, e.g. CP_NODE=controlplane"
fi

if [[ -n "${WORKER}" ]]; then
  add_pass "Worker detected (${WORKER})"
else
  add_fail "Worker detected" "No non-control-plane node found" "Set WORKER explicitly, e.g. WORKER=node01"
fi

if [[ -z "${CP_NODE}" || -z "${WORKER}" ]]; then
  echo
  for r in "${results[@]}"; do echo "$r"; echo; done
  echo "== Summary =="; echo "${pass} checks PASS"; echo "${warn} checks WARN"; echo "${fail} checks FAIL"
  exit 2
fi

# --- Final state: Ready + schedulable ---
ready="$(k get node "${WORKER}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null || true)"
if [[ "${ready}" == "True" ]]; then
  add_pass "Worker Ready=True"
else
  add_fail "Worker Ready=True" "Ready='${ready:-<missing>}'" "Fix kubelet on worker; check: ssh ${WORKER} 'sudo systemctl status kubelet -l'"
fi

unsched="$(k get node "${WORKER}" -o jsonpath='{.spec.unschedulable}' 2>/dev/null || true)"
if [[ -z "${unsched}" || "${unsched}" == "false" ]]; then
  add_pass "Worker schedulable (uncordoned)"
else
  add_fail "Worker schedulable (uncordoned)" "spec.unschedulable=true" "Run: kubectl uncordon ${WORKER}"
fi

# --- Version checks (strict correctness) ---
cp_ver="$(k get node "${CP_NODE}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"
wk_ver="$(k get node "${WORKER}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"

if [[ -z "${cp_ver}" ]]; then
  add_fail "Control-plane kubeletVersion readable" "Could not read kubeletVersion on ${CP_NODE}" "Ensure kubelet is running on ${CP_NODE}"
fi

if [[ -z "${wk_ver}" ]]; then
  add_fail "Worker kubeletVersion readable" "Could not read kubeletVersion on ${WORKER}" "Ensure kubelet is running on ${WORKER}"
fi

# Optional: print detected versions (informational, no scoring)
echo "Info: CP kubeletVersion='${cp_ver:-<unknown>}' ; Worker kubeletVersion='${wk_ver:-<unknown>}'"
echo

if [[ -n "${cp_ver}" && -n "${wk_ver}" ]]; then
  if [[ "${wk_ver}" == "${cp_ver}" ]]; then
    add_pass "Worker kubeletVersion matches control-plane (strict)"
  else
    add_fail "Worker kubeletVersion matches control-plane (strict)"       "Worker=${wk_ver} Control-plane=${cp_ver}"       "Upgrade worker kubelet to ${cp_ver} (restart kubelet; wait for nodeInfo to refresh)"
  fi
fi

# --- Drain/uncordon order via Node events (strict-ish) ---
ev="$(k get events -A --field-selector involvedObject.kind=Node,involvedObject.name=${WORKER} --sort-by=.lastTimestamp 2>/dev/null || true)"
if [[ -z "${ev}" ]]; then
  add_fail "Events available for order check" "No node events returned" "Redo sequence: kubectl drain ${WORKER} ... ; then kubectl uncordon ${WORKER}"
else
  cordon_idx="$(printf "%s\n" "${ev}" | grep -n 'NodeNotSchedulable' | head -n1 | cut -d: -f1)"
  uncordon_idx="$(printf "%s\n" "${ev}" | grep -n 'NodeSchedulable' | tail -n1 | cut -d: -f1)"

  if [[ -n "${cordon_idx}" ]]; then
    add_pass "Drain event present (NodeNotSchedulable)"
  else
    add_fail "Drain event present (NodeNotSchedulable)" "Missing NodeNotSchedulable" "Run: kubectl drain ${WORKER} --ignore-daemonsets --delete-emptydir-data --force"
  fi

  if [[ -n "${uncordon_idx}" ]]; then
    add_pass "Uncordon event present (NodeSchedulable)"
  else
    add_fail "Uncordon event present (NodeSchedulable)" "Missing NodeSchedulable" "Run: kubectl uncordon ${WORKER}"
  fi

  if [[ -n "${cordon_idx}" && -n "${uncordon_idx}" ]]; then
    if [[ "${cordon_idx}" -lt "${uncordon_idx}" ]]; then
      add_pass "Order OK: drain before uncordon"
    else
      add_fail "Order OK: drain before uncordon" "Order incorrect in events" "Redo: drain -> upgrade -> uncordon"
    fi
  fi

  # Optional: eviction hint (may be absent, so warn only)
  evicted="$(k get events -A --field-selector reason=Evicted --sort-by=.lastTimestamp 2>/dev/null | grep -F "${WORKER}" | tail -n 1 || true)"
  if [[ -n "${evicted}" ]]; then
    add_pass "Drain eviction activity observed (Evicted events present)"
  else
    add_warn "Drain eviction activity observed (Evicted events present)"       "No Evicted events referencing ${WORKER} found (can be normal)"       "Optional: run drain again after scheduling a test pod on ${WORKER}"
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
