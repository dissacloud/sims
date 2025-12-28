#!/usr/bin/env bash
# Q11 v3 Strict Grader — validates worker upgrade to match control plane after skew.
# Run on controlplane.

set -u
trap '' PIPE

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
WORKER="compute-0"

pass=0; fail=0; warn=0
out=()

p(){ out+=("[PASS] $1"); pass=$((pass+1)); }
f(){ out+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
w(){ out+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

echo "== Q11 v3 Strict Verifier (kube-bench-like) =="
echo "Date: $(date -Is)"
echo "Worker: ${WORKER}"
echo

if kubectl get --raw=/readyz >/dev/null 2>&1; then
  p "API server is reachable (/readyz)"
else
  f "API server is reachable (/readyz)" "API not reachable" "Fix control plane before grading"
fi

CP="$(kubectl version --short 2>/dev/null | awk -F': ' '/Server Version/ {gsub(/^v/,"",$2); print $2}' | head -n1)"
if [[ -n "${CP}" ]]; then
  p "Control-plane server version detected: v${CP}"
else
  f "Control-plane server version detected" "Could not determine server version" "kubectl version --short"
fi

if kubectl get node "${WORKER}" >/dev/null 2>&1; then
  p "Worker node ${WORKER} exists"
else
  f "Worker node ${WORKER} exists" "Node not found" "kubectl get nodes"
fi

# Effective kubelet versions (from node status)
cp_kubelet="$(kubectl get node -o jsonpath='{.items[?(@.metadata.name=="controlplane")].status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"
wk_kubelet="$(kubectl get node "${WORKER}" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)"

if [[ -n "${wk_kubelet}" ]]; then
  p "Worker kubeletVersion reported: ${wk_kubelet}"
else
  f "Worker kubeletVersion reported" "Empty kubeletVersion" "Wait and retry; ensure kubelet is running"
fi

# Strict match to control plane kubeletVersion if available; otherwise match to server minor
if [[ -n "${cp_kubelet}" ]]; then
  if [[ "${wk_kubelet}" == "${cp_kubelet}" ]]; then
    p "Worker kubeletVersion matches controlplane kubeletVersion (${cp_kubelet})"
  else
    f "Worker kubeletVersion matches controlplane kubeletVersion (${cp_kubelet})" \
      "Worker=${wk_kubelet}" \
      "Upgrade compute-0 kubelet to ${cp_kubelet} and restart kubelet; then uncordon"
  fi
else
  cp_minor="$(echo "${CP}" | awk -F. '{print $1"."$2}')"
  wk_minor="$(echo "${wk_kubelet#v}" | awk -F. '{print $1"."$2}')"
  if [[ "${wk_minor}" == "${cp_minor}" ]]; then
    p "Worker kubelet minor matches control-plane server minor (${cp_minor})"
  else
    f "Worker kubelet minor matches control-plane server minor (${cp_minor})" \
      "Worker minor=${wk_minor}" \
      "Upgrade worker to minor ${cp_minor}"
  fi
fi

# Node readiness and schedulable
ready="$(kubectl get node "${WORKER}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null || true)"
if [[ "${ready}" == "True" ]]; then
  p "Worker node is Ready"
else
  f "Worker node is Ready" "Ready=${ready:-<empty>}" "Fix kubelet/CNI; ensure node returns Ready"
fi

unsched="$(kubectl get node "${WORKER}" -o jsonpath='{.spec.unschedulable}' 2>/dev/null || true)"
if [[ "${unsched}" == "true" ]]; then
  f "Worker node is uncordoned (schedulable)" "Node is cordoned" "Run: kubectl uncordon ${WORKER}"
else
  p "Worker node is uncordoned (schedulable)"
fi

echo
for r in "${out[@]}"; do
  printf "%s\n\n" "$r" || true
done

echo "== Summary =="
echo "${pass} checks PASS"
echo "${warn} checks WARN"
echo "${fail} checks FAIL"

[[ "${fail}" -eq 0 ]] && exit 0 || exit 2
