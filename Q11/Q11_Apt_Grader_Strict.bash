#!/usr/bin/env bash
# Q11 APT Strict Grader (exam-style)
# Verifies (strict):
#  - worker kubeletVersion == control-plane kubeletVersion (authoritative)
#  - worker Ready and schedulable (uncordoned)
#  - drain -> uncordon order from Node events (NodeNotSchedulable before NodeSchedulable)
#  - worker apt package versions for kubelet/kubectl match control-plane kubeletVersion (prefix match)
#
# Usage:
#   bash Q11_Apt_Grader_Strict.bash
#   WORKER=node01 CP_NODE=controlplane bash Q11_Apt_Grader_Strict.bash

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

need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }
need kubectl
need awk
need grep
need ssh

echo "== Q11 APT Strict Grader (kube-bench-like) =="
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

# --- Version checks (authoritative) ---
cp_kubelet_ver="$(k get node "${CP_NODE}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"
wk_kubelet_ver="$(k get node "${WORKER}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"

echo "Info: CP kubeletVersion='${cp_kubelet_ver:-<unknown>}' ; Worker kubeletVersion='${wk_kubelet_ver:-<unknown>}'"
echo

if [[ -z "${cp_kubelet_ver}" ]]; then
  add_fail "Control-plane kubeletVersion readable" "Could not read kubeletVersion on ${CP_NODE}" "Ensure kubelet is running on ${CP_NODE}"
fi
if [[ -z "${wk_kubelet_ver}" ]]; then
  add_fail "Worker kubeletVersion readable" "Could not read kubeletVersion on ${WORKER}" "Ensure kubelet is running on ${WORKER}"
fi

if [[ -n "${cp_kubelet_ver}" && -n "${wk_kubelet_ver}" ]]; then
  if [[ "${wk_kubelet_ver}" == "${cp_kubelet_ver}" ]]; then
    add_pass "Worker kubeletVersion matches control-plane (strict)"
  else
    add_fail "Worker kubeletVersion matches control-plane (strict)"       "Worker=${wk_kubelet_ver} Control-plane=${cp_kubelet_ver}"       "Upgrade worker kubelet to ${cp_kubelet_ver}"
  fi
fi

# --- APT package versions on worker (kubelet/kubectl) ---
# Convert "v1.34.3" -> "1.34.3" for apt prefix matching.
target_prefix="$(echo "${cp_kubelet_ver:-}" | sed 's/^v//')"

if [[ -n "${target_prefix}" ]]; then
  # Run dpkg-query on worker. Expect output: "kubelet 1.34.3-1.1" etc.
  dpkg_out="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER}" "dpkg-query -W -f='\\${Package} \\${Version}\\n' kubelet kubectl 2>/dev/null || true" 2>/dev/null || true)"
  if [[ -z "${dpkg_out}" ]]; then
    add_fail "Worker has kubelet/kubectl packages installed"       "dpkg-query returned no data"       "Ensure kubelet/kubectl installed via apt on worker"
  else
    kubelet_pkg_ver="$(echo "${dpkg_out}" | awk '$1=="kubelet"{print $2}' | head -n1)"
    kubectl_pkg_ver="$(echo "${dpkg_out}" | awk '$1=="kubectl"{print $2}' | head -n1)"

    echo "Info: Worker dpkg versions: kubelet='${kubelet_pkg_ver:-<missing>}' kubectl='${kubectl_pkg_ver:-<missing>}'"
    echo

    if [[ -n "${kubelet_pkg_ver}" && "${kubelet_pkg_ver}" == ${target_prefix}* ]]; then
      add_pass "Worker kubelet package version matches CP kubeletVersion prefix (${target_prefix}*)"
    else
      add_fail "Worker kubelet package version matches CP kubeletVersion prefix (${target_prefix}*)"         "kubelet pkg='${kubelet_pkg_ver:-<missing>}' expected prefix '${target_prefix}'"         "On worker: sudo apt-get install -y kubelet=<TARGET_VERSION> ; sudo systemctl restart kubelet"
    fi

    if [[ -n "${kubectl_pkg_ver}" && "${kubectl_pkg_ver}" == ${target_prefix}* ]]; then
      add_pass "Worker kubectl package version matches CP kubeletVersion prefix (${target_prefix}*)"
    else
      add_fail "Worker kubectl package version matches CP kubeletVersion prefix (${target_prefix}*)"         "kubectl pkg='${kubectl_pkg_ver:-<missing>}' expected prefix '${target_prefix}'"         "On worker: sudo apt-get install -y kubectl=<TARGET_VERSION>"
    fi

    # Holds are not inherently wrong, but can mask future upgrades; warn only.
    holds="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WORKER}" "apt-mark showhold 2>/dev/null | egrep '^(kubelet|kubectl|kubeadm)$' || true" 2>/dev/null || true)"
    if [[ -n "${holds}" ]]; then
      add_warn "Worker apt holds detected (informational)"         "Held packages: $(echo "${holds}" | tr '\n' ' ' | sed 's/  */ /g')"         "Optional: sudo apt-mark unhold kubelet kubectl kubeadm (only if required by your workflow)"
    else
      add_pass "No worker apt holds for kubelet/kubectl/kubeadm (informational)"
    fi
  fi
else
  add_warn "APT package verification skipped"     "Could not derive target prefix from control-plane kubeletVersion"     "Fix control-plane kubeletVersion detection first"
fi

# --- Drain/uncordon order via Node events ---
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
