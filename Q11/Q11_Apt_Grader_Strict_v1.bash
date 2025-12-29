#!/usr/bin/env bash
# Q11 (APT-based) STRICT Grader — exam-style (drain/upgrade/uncordon + final state)
#
# Verifies:
#  1) API reachable
#  2) Worker node exists (not control-plane)
#  3) Final state: worker Ready + uncordoned + kubelet minor matches control-plane
#  4) Evidence of process: NodeNotSchedulable event happened before NodeSchedulable (Events ordering)
#  5) Worker apt kubelet/kubectl package minor matches control-plane (via SSH)
#
# Usage:
#   bash Q11_Apt_Grader_Strict.bash
#   WORKER=node01 bash Q11_Apt_Grader_Strict.bash

set -u
trap '' PIPE

KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="${WORKER:-}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

k(){ KUBECONFIG="${KUBECONFIG}" kubectl "$@"; }

minor_from_kube_ver(){ # v1.34.3 -> 1.34
  echo "$1" | sed -E 's/^v?([0-9]+)\.([0-9]+)\..*/\1.\2/;t;d'
}

minor_from_pkg_ver(){ # 1.34.3-1.1 -> 1.34
  echo "$1" | sed -E 's/^([0-9]+\.[0-9]+)\..*/\1/;t;d'
}

echo "== Q11 APT STRICT Grader (kube-bench-like) =="
echo "Date: $(date -Is)"
echo "KUBECONFIG: ${KUBECONFIG}"
echo

# [1] API check
if k get --raw=/readyz >/dev/null 2>&1; then
  add_pass "API server reachable (/readyz)"
else
  add_fail "API server reachable (/readyz)" "API not reachable" "Fix control-plane components first."
fi

# Control-plane node
CP_NODE="$(k get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "${CP_NODE}" ]]; then
  add_pass "Control-plane node detected (${CP_NODE})"
else
  add_fail "Control-plane node detected" "Could not detect control-plane node" "Ensure control-plane node is labeled correctly."
fi

# Auto-detect worker if missing
if [[ -z "${WORKER}" ]]; then
  WORKER="$(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.node-role\.kubernetes\.io/control-plane}{"\n"}{end}' 2>/dev/null     | awk -v cp="${CP_NODE}" '$1!=cp && $2=="" {print $1; exit}')"
fi

if [[ -n "${WORKER}" && "${WORKER}" != "${CP_NODE}" ]]; then
  add_pass "Worker node selected (${WORKER})"
else
  add_fail "Worker node selected" "Worker not found or equals control-plane (${WORKER})" "Set WORKER explicitly, e.g. WORKER=node01."
fi

# Versions from API
CP_KUBELET_VER="$(k get node "${CP_NODE}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"
WK_KUBELET_VER="$(k get node "${WORKER}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"
CP_MINOR="$(minor_from_kube_ver "${CP_KUBELET_VER}")"
WK_MINOR="$(minor_from_kube_ver "${WK_KUBELET_VER}")"

if [[ -n "${CP_KUBELET_VER}" ]]; then
  add_pass "Control-plane kubeletVersion=${CP_KUBELET_VER}"
else
  add_fail "Control-plane kubeletVersion readable" "Empty kubeletVersion" "Check node/API."
fi

if [[ -n "${WK_KUBELET_VER}" ]]; then
  add_pass "Worker kubeletVersion=${WK_KUBELET_VER}"
else
  add_fail "Worker kubeletVersion readable" "Empty kubeletVersion" "Check worker node/API."
fi

# Final readiness + schedulable
WK_READY="$(k get node "${WORKER}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null || true)"
WK_UNSCHED="$(k get node "${WORKER}" -o jsonpath='{.spec.unschedulable}' 2>/dev/null || true)"

if [[ "${WK_READY}" == "True" ]]; then
  add_pass "Worker is Ready"
else
  add_fail "Worker is Ready" "Ready=${WK_READY:-<unknown>}" "Fix kubelet on worker."
fi

if [[ -z "${WK_UNSCHED}" || "${WK_UNSCHED}" == "false" ]]; then
  add_pass "Worker is schedulable (uncordoned)"
else
  add_fail "Worker is schedulable (uncordoned)" "spec.unschedulable=${WK_UNSCHED}" "Run: kubectl uncordon ${WORKER}"
fi

# Version match (strict on minor)
if [[ -n "${CP_MINOR}" && -n "${WK_MINOR}" && "${CP_MINOR}" == "${WK_MINOR}" ]]; then
  add_pass "Worker kubelet minor matches control-plane (v${CP_MINOR}.x)"
else
  add_fail "Worker kubelet minor matches control-plane"     "Mismatch: control-plane=${CP_KUBELET_VER} worker=${WK_KUBELET_VER}"     "Upgrade worker to match control-plane minor."
fi

# Evidence of process (Events ordering)
# We expect: NodeNotSchedulable occurs (cordon/drain) before NodeSchedulable (uncordon).
# Use lastTimestamp sorting to get earliest occurrences of each reason.
EVT_LINES="$(k get events -A --field-selector involvedObject.kind=Node,involvedObject.name=${WORKER} --sort-by=.lastTimestamp 2>/dev/null   | awk 'NR>1 {print $0}' || true)"

NS_TS="$(echo "${EVT_LINES}" | awk '$6=="NodeNotSchedulable" {print $1"T"$2"Z"; exit}')"
S_TS="$(echo "${EVT_LINES}" | awk '$6=="NodeSchedulable" {print $1"T"$2"Z"; exit}')"

if [[ -n "${NS_TS}" && -n "${S_TS}" ]]; then
  if [[ "${NS_TS}" < "${S_TS}" ]]; then
    add_pass "Process evidence: cordon/drain then uncordon (Events ordering OK)"
  else
    add_fail "Process evidence: cordon/drain then uncordon"       "Ordering unexpected (NotSchedulable=${NS_TS}, Schedulable=${S_TS})"       "Do: kubectl drain (first) -> upgrade -> kubectl uncordon (last)."
  fi
elif [[ -n "${NS_TS}" && -z "${S_TS}" ]]; then
  add_fail "Process evidence: uncordon recorded"     "Found NodeNotSchedulable but no NodeSchedulable event"     "Run: kubectl uncordon ${WORKER}"
else
  add_fail "Process evidence: drain/uncordon recorded"     "No NodeNotSchedulable/NodeSchedulable events found for this node"     "Run (in order): kubectl drain ... ; upgrade ; kubectl uncordon ..."
fi

# Worker package alignment via SSH (strict on minor)
if ssh ${SSH_OPTS} "${WORKER}" "command -v dpkg-query >/dev/null 2>&1" >/dev/null 2>&1; then
  pkgs="$(ssh ${SSH_OPTS} "${WORKER}" "dpkg-query -W -f='\${Package} \${Version}\n' kubelet kubectl 2>/dev/null" 2>/dev/null || true)"
  wk_kubelet_pkg="$(echo "${pkgs}" | awk '$1=="kubelet"{print $2; exit}')"
  wk_kubectl_pkg="$(echo "${pkgs}" | awk '$1=="kubectl"{print $2; exit}')"

  if [[ -n "${wk_kubelet_pkg}" ]]; then
    add_pass "Worker apt kubelet package version=${wk_kubelet_pkg}"
  else
    add_fail "Worker apt kubelet package present" "dpkg-query empty" "Install kubelet via apt on worker."
  fi

  if [[ -n "${wk_kubectl_pkg}" ]]; then
    add_pass "Worker apt kubectl package version=${wk_kubectl_pkg}"
  else
    add_fail "Worker apt kubectl package present" "dpkg-query empty" "Install kubectl via apt on worker."
  fi

  wk_pkg_minor="$(minor_from_pkg_ver "${wk_kubelet_pkg}")"
  if [[ -n "${CP_MINOR}" && -n "${wk_pkg_minor}" && "${wk_pkg_minor}" == "${CP_MINOR}" ]]; then
    add_pass "Worker apt kubelet minor matches control-plane (pkg ${wk_pkg_minor}.x)"
  else
    add_fail "Worker apt kubelet minor matches control-plane"       "kubelet pkg minor=${wk_pkg_minor:-<unknown>} control-plane minor=${CP_MINOR:-<unknown>}"       "Switch worker repo to v${CP_MINOR} channel and upgrade kubelet/kubectl."
  fi
else
  add_fail "SSH package check on worker" "SSH/dpkg-query unavailable" "Ensure controlplane can ssh to the worker (required by this grader)."
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
