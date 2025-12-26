#!/usr/bin/env bash
# Q05 Auto-Verifier (kube-bench-like) — v1 (robust)
# Verifies:
# - identifies a pod in ns=ollama that mounts host /dev/mem (misbehaving)
# - verifies the owning Deployment is scaled to 0 replicas
# - verifies the benign deployment remains at 1 replica (best-effort integrity)

set -u

NS="ollama"
ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

echo "== Q05 Auto-Verifier (kube-bench-like) =="
echo "Date: $(date -Is)"
echo "Namespace: ${NS}"
echo

# Basic namespace check
if KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get ns "${NS}" >/dev/null 2>&1; then
  add_pass "Namespace ${NS} exists"
else
  add_fail "Namespace ${NS} exists" \
    "Namespace not found" \
    "Run Q05_LabSetUp.bash or ensure the namespace exists"
fi

# Find misbehaving pod by /dev/mem hostPath or mountPath
mis_pod="$(
  KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n "${NS}" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.volumes[*]}{.hostPath.path}{" "}{end}{"\t"}{range .spec.containers[*].volumeMounts[*]}{.mountPath}{" "}{end}{"\n"}{end}' 2>/dev/null \
  | grep -E '/dev/mem' 2>/dev/null \
  | head -n 1 \
  | awk '{print $1}' 2>/dev/null || true
)"

if [[ -n "${mis_pod}" ]]; then
  add_pass "Identified misbehaving pod accessing /dev/mem: ${mis_pod}"
else
  add_fail "Identified misbehaving pod accessing /dev/mem" \
    "No pod in ${NS} appears to mount /dev/mem" \
    "Inspect pod specs for /dev/mem mount (hostPath) and ensure the lab is set up"
fi

# Resolve owning deployment (pod -> rs -> deploy)
own_rs="$(KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n "${NS}" get pod "${mis_pod}" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || true)"
own_kind="$(KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n "${NS}" get pod "${mis_pod}" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || true)"

if [[ "${own_kind}" == "ReplicaSet" && -n "${own_rs}" ]]; then
  add_pass "Misbehaving pod is owned by ReplicaSet ${own_rs}"
else
  add_fail "Misbehaving pod is owned by a ReplicaSet" \
    "Owner kind='${own_kind:-missing}' name='${own_rs:-missing}'" \
    "Ensure the misbehaving pod is part of a Deployment-managed ReplicaSet"
fi

own_deploy="$(KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n "${NS}" get rs "${own_rs}" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || true)"
own_deploy_kind="$(KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n "${NS}" get rs "${own_rs}" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || true)"

if [[ "${own_deploy_kind}" == "Deployment" && -n "${own_deploy}" ]]; then
  add_pass "Misbehaving ReplicaSet is owned by Deployment ${own_deploy}"
else
  add_fail "Misbehaving ReplicaSet is owned by a Deployment" \
    "Owner kind='${own_deploy_kind:-missing}' name='${own_deploy:-missing}'" \
    "Identify the Deployment managing the misbehaving pod and scale it to 0"
fi

# Check scaled to 0
replicas="$(KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n "${NS}" get deploy "${own_deploy}" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
if [[ "${replicas}" == "0" ]]; then
  add_pass "Offending Deployment scaled to 0 replicas (${own_deploy})"
else
  add_fail "Offending Deployment scaled to 0 replicas (${own_deploy})" \
    "spec.replicas is '${replicas:-missing}'" \
    "Run: kubectl -n ${NS} scale deploy/${own_deploy} --replicas=0"
fi

# Best-effort integrity check: benign deployment should remain 1 (as setup)
api_repl="$(KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl -n "${NS}" get deploy ollama-api -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
if [[ "${api_repl}" == "1" ]]; then
  add_pass "Other Deployment unchanged (ollama-api replicas=1)"
else
  add_warn "Other Deployment unchanged (ollama-api replicas=1)" \
    "ollama-api spec.replicas is '${api_repl:-missing}'" \
    "Do not modify other deployments; revert if changed"
fi

# Output
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
