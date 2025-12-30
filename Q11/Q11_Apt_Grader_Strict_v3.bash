#!/usr/bin/env bash
# Q11 (APT-based) STRICT Grader — v3 (adds "pre-upgrade skew must exist" proof)
#
# What this validates (exam-style):
#   A) Final state correctness (authoritative):
#      - API reachable
#      - Worker Ready + schedulable
#      - Worker kubelet minor matches control-plane minor
#      - Worker apt kubelet/kubectl minor matches control-plane minor (via SSH)
#
#   B) Process evidence (best-effort, because Events rotate):
#      - cordon/drain then uncordon (NodeNotSchedulable -> NodeSchedulable ordering)
#        Default: WARN if missing, FAIL only if STRICT_EVENTS=1.
#
#   C) NEW: Pre-upgrade skew must have existed (deterministic):
#      - Requires evidence from the LAB SETUP script on the worker:
#        /root/cis-q11-apt-backups-*/dpkg_versions.before.txt
#      - Verifies that the *recorded pre-state* kubelet minor on the worker
#        was LOWER than the control-plane minor at grading time.
#
# Usage:
#   bash Q11_Apt_Grader_Strict_v3.bash
#   WORKER=node01 bash Q11_Apt_Grader_Strict_v3.bash
#   STRICT_EVENTS=1 bash Q11_Apt_Grader_Strict_v3.bash

set -u
trap '' PIPE

KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="${WORKER:-}"
STRICT_EVENTS="${STRICT_EVENTS:-0}"

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
echo "STRICT_EVENTS: ${STRICT_EVENTS}"
echo

# [1] API check
if k get --raw=/readyz >/dev/null 2>&1; then
  add_pass "API server reachable (/readyz)"
else
  add_fail "API server reachable (/readyz)" "API not reachable" "Fix control-plane components first."
fi

# Detect control-plane node (best-effort label)
CP_NODE="$(k get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "${CP_NODE}" ]]; then
  # kubeadm sometimes uses node-role.kubernetes.io/master
  CP_NODE="$(k get nodes -l node-role.kubernetes.io/master -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi

if [[ -n "${CP_NODE}" ]]; then
  add_pass "Control-plane node detected (${CP_NODE})"
else
  add_fail "Control-plane node detected" "Could not detect control-plane node" "Ensure control-plane node is labeled (control-plane/master)."
  CP_NODE="controlplane"
fi

# Auto-detect worker if not provided
if [[ -z "${WORKER}" ]]; then
  # Choose first node that is not the control-plane node and has no control-plane label
  WORKER="$(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.labels.node-role\.kubernetes\.io/control-plane}{" "}{.metadata.labels.node-role\.kubernetes\.io/master}{"\n"}{end}' 2>/dev/null \
    | awk -v cp="${CP_NODE}" '$1!=cp && $2=="" && $3=="" {print $1; exit}')"
fi

if [[ -n "${WORKER}" && "${WORKER}" != "${CP_NODE}" ]]; then
  add_pass "Worker node selected (${WORKER})"
else
  add_fail "Worker node selected" "Worker not found or equals control-plane (${WORKER:-<empty>})" "Set WORKER explicitly, e.g. WORKER=node01."
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

# --- NEW: Pre-upgrade skew must exist (deterministic proof from setup backup) ---
# We require the worker setup to have recorded dpkg_versions.before.txt under /root/cis-q11-apt-backups-*
# and that recorded kubelet minor must be LOWER than the control-plane minor.
if ssh ${SSH_OPTS} "${WORKER}" "true" >/dev/null 2>&1; then
  pre_dir="$(ssh ${SSH_OPTS} "${WORKER}" "ls -1dt /root/cis-q11-apt-backups-* 2>/dev/null | head -n1" 2>/dev/null || true)"
  if [[ -n "${pre_dir}" ]]; then
    pre_file="${pre_dir}/dpkg_versions.before.txt"
    pre_kubelet_pkg="$(ssh ${SSH_OPTS} "${WORKER}" "awk '\$1==\"kubelet\"{print \$2; exit}' ${pre_file} 2>/dev/null" 2>/dev/null || true)"
    pre_minor="$(minor_from_pkg_ver "${pre_kubelet_pkg}")"

    if [[ -z "${pre_kubelet_pkg}" || -z "${pre_minor}" ]]; then
      add_fail "Pre-upgrade skew evidence exists (setup backup)" \
        "Could not read kubelet version from ${pre_file}" \
        "Re-run the Q11 APT lab setup so it records dpkg_versions.before.txt on the worker."
    else
      if [[ -n "${CP_MINOR}" && "${pre_minor}" != "${CP_MINOR}" ]]; then
        # Compare numerically: X.Y
        pre_major="${pre_minor%%.*}"; pre_min="${pre_minor##*.}"
        cp_major="${CP_MINOR%%.*}";  cp_min="${CP_MINOR##*.}"
        if [[ "${pre_major}" -lt "${cp_major}" || ( "${pre_major}" -eq "${cp_major}" && "${pre_min}" -lt "${cp_min}" ) ]]; then
          add_pass "Pre-upgrade skew existed (worker was ${pre_kubelet_pkg}, below CP minor ${CP_MINOR}.x)"
        else
          add_fail "Pre-upgrade skew existed" \
            "Recorded pre-state kubelet minor (${pre_minor}.x) is not lower than control-plane minor (${CP_MINOR}.x)" \
            "Re-run the lab setup to skew the worker to a LOWER minor than the control-plane (e.g., 1.33 when CP is 1.34)."
        fi
      else
        add_fail "Pre-upgrade skew existed" \
          "Recorded pre-state kubelet minor appears to match control-plane minor (pre=${pre_kubelet_pkg}, CP=${CP_KUBELET_VER})" \
          "Re-run the lab setup to create a mismatch first; the upgrade task must start skewed."
      fi
    fi
  else
    add_fail "Pre-upgrade skew evidence exists (setup backup)" \
      "No /root/cis-q11-apt-backups-* directory found on worker" \
      "Run the Q11 APT lab setup again (it should create /root/cis-q11-apt-backups-*/dpkg_versions.before.txt)."
  fi
else
  add_fail "Pre-upgrade skew evidence exists (setup backup)" \
    "Cannot SSH to worker to read setup backups" \
    "Ensure controlplane can SSH to the worker (passwordless or configured) and re-run."
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
  add_fail "Worker kubelet minor matches control-plane" \
    "Mismatch: control-plane=${CP_KUBELET_VER:-<unknown>} worker=${WK_KUBELET_VER:-<unknown>}" \
    "Upgrade worker to match control-plane minor."
fi

# --- Process evidence via Events (best-effort) ---
# If STRICT_EVENTS=1, missing evidence becomes FAIL; otherwise WARN.
events_json="$(k get events -A --field-selector involvedObject.kind=Node,involvedObject.name=${WORKER} -o json 2>/dev/null || true)"

# Extract earliest timestamps for the two reasons from JSON without jq (portable):
# We use a simple awk state machine to print "ts reason" then select earliest.
extract_ts_reason() {
  # prints lines: "<ts> <reason>"
  echo "${events_json}" | awk '
    BEGIN{ts=""; reason=""; in=0}
    /"lastTimestamp":/ {gsub(/[",]/,""); ts=$2}
    /"eventTime":/     {gsub(/[",]/,""); if($2!="null") ts=$2}
    /"reason":/        {gsub(/[",]/,""); reason=$2}
    /"involvedObject":/ {in=1}
    in==1 && /}/ {in=0}
    ts!="" && reason!="" {print ts, reason; ts=""; reason=""}
  ' 2>/dev/null
}

ts_lines="$(extract_ts_reason || true)"
NS_TS="$(echo "${ts_lines}" | awk '$2=="NodeNotSchedulable" {print $1}' | sort | head -n1)"
S_TS="$(echo "${ts_lines}"  | awk '$2=="NodeSchedulable"   {print $1}' | sort | head -n1)"

if [[ -n "${NS_TS}" && -n "${S_TS}" ]]; then
  if [[ "${NS_TS}" < "${S_TS}" ]]; then
    add_pass "Process evidence: cordon/drain then uncordon (Events ordering OK)"
  else
    add_fail "Process evidence: cordon/drain then uncordon" \
      "Ordering unexpected (NotSchedulable=${NS_TS}, Schedulable=${S_TS})" \
      "Do: kubectl drain (first) -> upgrade -> kubectl uncordon (last)."
  fi
else
  msg="No NodeNotSchedulable/NodeSchedulable events found (events may have rotated)."
  rem="If you need strict proof, re-run drain+uncordon and grade immediately; or set STRICT_EVENTS=1 to fail-closed."
  if [[ "${STRICT_EVENTS}" == "1" ]]; then
    add_fail "Process evidence: drain/uncordon recorded" "${msg}" "Run: kubectl drain ... ; upgrade ; kubectl uncordon ... (then re-run grader immediately)."
  else
    add_warn "Process evidence: drain/uncordon recorded (best-effort)" "${msg}" "${rem}"
  fi
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
    add_fail "Worker apt kubelet minor matches control-plane" \
      "kubelet pkg minor=${wk_pkg_minor:-<unknown>} control-plane minor=${CP_MINOR:-<unknown>}" \
      "Switch worker repo to v${CP_MINOR} channel and upgrade kubelet/kubectl."
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
