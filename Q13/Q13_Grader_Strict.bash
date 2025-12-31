#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

NS="confidential"
DEP="nginx-unprivileged"
APP="nginx-unprivileged"
FILE="$HOME/nginx-unprivileged.yaml"

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

k(){ kubectl "$@"; }

echo "== Q13 STRICT Grader (PSS restricted compliance) =="
echo "Date: $(date -Is)"
echo

# API reachability
if k get --raw=/readyz >/dev/null 2>&1; then
  add_pass "API server reachable (/readyz)"
else
  add_fail "API server reachable (/readyz)" "API not reachable" "Fix control plane / kube-apiserver first"
fi

# Namespace exists
if k get ns "$NS" >/dev/null 2>&1; then
  add_pass "Namespace $NS exists"
else
  add_fail "Namespace $NS exists" "Namespace missing" "Re-run lab setup or create namespace"
fi

# PSS restricted labels
enf="$(k get ns "$NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || true)"
if [[ "$enf" == "restricted" ]]; then
  add_pass "Namespace enforces restricted PSS"
else
  add_fail "Namespace enforces restricted PSS" "enforce label is '$enf' (expected 'restricted')" \
    "kubectl label ns $NS pod-security.kubernetes.io/enforce=restricted --overwrite"
fi

# Manifest existence
if [[ -f "$FILE" ]]; then
  add_pass "Manifest exists at ~/nginx-unprivileged.yaml"
else
  add_fail "Manifest exists at ~/nginx-unprivileged.yaml" "File missing" "The task expects you to edit ~/nginx-unprivileged.yaml"
fi

# Deployment exists
if k -n "$NS" get deploy "$DEP" >/dev/null 2>&1; then
  add_pass "Deployment $DEP exists"
else
  add_fail "Deployment $DEP exists" "Deployment missing" "kubectl -n $NS apply -f ~/nginx-unprivileged.yaml"
fi

# Pods Running + Ready
pods="$(k -n "$NS" get pods -l app="$APP" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$pods" -ge 1 ]]; then
  add_pass "At least one pod exists for app=$APP"
else
  add_fail "At least one pod exists for app=$APP" "No pods found" "kubectl -n $NS get rs,pods; fix admission failures and rollout"
fi

ready="$(k -n "$NS" get pods -l app="$APP" -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | grep -c '^true$' || true)"
if [[ "$ready" -ge 1 ]]; then
  add_pass "At least one pod is Ready"
else
  add_fail "At least one pod is Ready" "Pods not Ready/Running" \
    "Fix restricted compliance in the Deployment template and re-apply; then wait for rollout"
fi

# --- Restricted compliance checks on the Deployment template (authoritative) ---
jsonpath(){ k -n "$NS" get deploy "$DEP" -o "jsonpath=$1" 2>/dev/null || true; }

runAsNonRoot="$(jsonpath '{.spec.template.spec.securityContext.runAsNonRoot}')"
seccompType="$(jsonpath '{.spec.template.spec.securityContext.seccompProfile.type}')"

c_ape="$(jsonpath '{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation}')"
c_priv="$(jsonpath '{.spec.template.spec.containers[0].securityContext.privileged}')"
c_rofs="$(jsonpath '{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}')"
c_drop="$(jsonpath '{.spec.template.spec.containers[0].securityContext.capabilities.drop[*]}')"
c_runAsUser="$(jsonpath '{.spec.template.spec.containers[0].securityContext.runAsUser}')"
c_runAsGroup="$(jsonpath '{.spec.template.spec.containers[0].securityContext.runAsGroup}')"
c_seccomp="$(jsonpath '{.spec.template.spec.containers[0].securityContext.seccompProfile.type}')"

# runAsNonRoot: true either at pod level or container level (restricted expects true effectively)
if [[ "$runAsNonRoot" == "true" || "$(jsonpath '{.spec.template.spec.containers[0].securityContext.runAsNonRoot}')" == "true" ]]; then
  add_pass "runAsNonRoot is enabled"
else
  add_fail "runAsNonRoot is enabled" "runAsNonRoot not set true (pod or container level)" \
    "Set spec.template.spec.securityContext.runAsNonRoot: true (or container securityContext)"
fi

# allowPrivilegeEscalation: false
if [[ "$c_ape" == "false" ]]; then
  add_pass "allowPrivilegeEscalation=false"
else
  add_fail "allowPrivilegeEscalation=false" "Value is '$c_ape' (expected false)" \
    "Set container securityContext.allowPrivilegeEscalation: false"
fi

# privileged must not be true
if [[ "$c_priv" != "true" ]]; then
  add_pass "privileged is not enabled"
else
  add_fail "privileged is not enabled" "privileged=true is forbidden under restricted" \
    "Remove privileged:true (or set privileged:false)"
fi

# capabilities drop ALL
if echo "$c_drop" | tr ' ' '\n' | grep -qx "ALL"; then
  add_pass "Capabilities drop includes ALL"
else
  add_fail "Capabilities drop includes ALL" "capabilities.drop does not include ALL" \
    "Set container securityContext.capabilities.drop: [\"ALL\"]"
fi

# seccomp must be RuntimeDefault (pod-level or container-level)
if [[ "$seccompType" == "RuntimeDefault" || "$c_seccomp" == "RuntimeDefault" ]]; then
  add_pass "seccompProfile RuntimeDefault set"
else
  add_fail "seccompProfile RuntimeDefault set" "Missing seccompProfile.type=RuntimeDefault" \
    "Set spec.template.spec.securityContext.seccompProfile.type: RuntimeDefault"
fi

# strongly recommended (and commonly required by restricted) to set non-zero UID/GID
if [[ -n "$c_runAsUser" && "$c_runAsUser" != "0" ]]; then
  add_pass "runAsUser is non-zero ($c_runAsUser)"
else
  add_fail "runAsUser is non-zero" "runAsUser missing or 0" \
    "Set container securityContext.runAsUser to a non-zero UID (e.g. 10001)"
fi

if [[ -n "$c_runAsGroup" && "$c_runAsGroup" != "0" ]]; then
  add_pass "runAsGroup is non-zero ($c_runAsGroup)"
else
  add_fail "runAsGroup is non-zero" "runAsGroup missing or 0" \
    "Set container securityContext.runAsGroup to a non-zero GID (e.g. 10001)"
fi

# optional but good hardening; grader enforces it to be exam-like
if [[ "$c_rofs" == "true" ]]; then
  add_pass "readOnlyRootFilesystem=true"
else
  add_fail "readOnlyRootFilesystem=true" "Value is '$c_rofs' (expected true)" \
    "Set container securityContext.readOnlyRootFilesystem: true"
fi

echo
for r in "${results[@]}"; do
  echo "$r"
  echo
done

echo "== Summary =="
echo "${pass} PASS"
echo "${warn} WARN"
echo "${fail} FAIL"

[[ "$fail" -eq 0 ]]
