#!/usr/bin/env bash
set -euo pipefail

# Q03 Auto-Verifier (kube-bench-like)
# Validates:
# - kube-apiserver uses admission-control-config-file
# - ImagePolicyWebhook enabled
# - AdmissionConfiguration denies on failure (failurePolicy=Fail, defaultAllow=false)
# - kubeconfig points to https://smooth-yak.local/review
# - Applying ~/vulnerable.yaml is denied (best-effort)

APISERVER_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
ADMISSION_CFG="/etc/kubernetes/bouncer/admission-configuration.yaml"
WEBHOOK_KUBECONFIG="/etc/kubernetes/bouncer/imagepolicywebhook.kubeconfig"
ADMIN_KUBECONFIG="/etc/kubernetes/admin.conf"
VULN_MANIFEST="${HOME}/vulnerable.yaml"
SCANNER_URL="https://smooth-yak.local/review"
BOUNCER_DIR="/etc/kubernetes/bouncer"


pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

echo "== Q03 Auto-Verifier (kube-bench-like) =="
echo "Date: $(date -Is)"
echo

# 1) apiserver manifest present
if [[ -f "${APISERVER_MANIFEST}" ]]; then
  add_pass "APISERVER manifest present"
else
  add_fail "APISERVER manifest present" \
    "${APISERVER_MANIFEST} not found" \
    "Run this grader on the kubeadm control-plane node"
fi

# Optional: confirm apiserver is up (prevents confusing downstream failures)
if KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl get --raw='/readyz' >/dev/null 2>&1; then
  add_pass "APISERVER readyz endpoint reachable"
else
  add_fail "APISERVER readyz endpoint reachable" \
    "API server not ready; kubectl may fail" \
    "Fix kube-apiserver static pod (flags + mounts) and wait for it to become ready"
fi


# 2) admission-control-config-file points to provided config
if grep -qE -- "--admission-control-config-file(=| )${ADMISSION_CFG}" "${APISERVER_MANIFEST}" 2>/dev/null; then
  add_pass "APISERVER admission-control-config-file configured"
else
  val="$(grep -E -- '--admission-control-config-file' "${APISERVER_MANIFEST}" 2>/dev/null | head -n1 || true)"
  add_fail "APISERVER admission-control-config-file configured" \
    "Found '${val:-missing}'" \
    "Set --admission-control-config-file=${ADMISSION_CFG} in kube-apiserver manifest"
fi

# 3) enable-admission-plugins includes ImagePolicyWebhook
if grep -qE -- '--enable-admission-plugins(=| ).*ImagePolicyWebhook' "${APISERVER_MANIFEST}" 2>/dev/null; then
  add_pass "APISERVER ImagePolicyWebhook enabled"
else
  val="$(grep -E -- '--enable-admission-plugins' "${APISERVER_MANIFEST}" 2>/dev/null | head -n1 || true)"
  add_fail "APISERVER ImagePolicyWebhook enabled" \
    "ImagePolicyWebhook not present in '${val:-missing}'" \
    "Add ImagePolicyWebhook to --enable-admission-plugins"
fi

# 3.5) kube-apiserver must mount /etc/kubernetes/bouncer into the container (hostPath + volumeMount)
# Without this, apiserver cannot read admission-control-config-file and will crashloop, breaking kubectl.

if grep -qE -- "path:\s*${BOUNCER_DIR}(\s|$)" "${APISERVER_MANIFEST}" 2>/dev/null; then
  add_pass "APISERVER hostPath volume for bouncer present (${BOUNCER_DIR})"
else
  add_fail "APISERVER hostPath volume for bouncer present (${BOUNCER_DIR})" \
    "No hostPath volume found for ${BOUNCER_DIR}" \
    "Add a volume under spec.volumes: hostPath.path: ${BOUNCER_DIR} (DirectoryOrCreate recommended)"
fi

if grep -qE -- "mountPath:\s*${BOUNCER_DIR}(\s|$)" "${APISERVER_MANIFEST}" 2>/dev/null; then
  add_pass "APISERVER volumeMount for bouncer present (${BOUNCER_DIR})"
else
  add_fail "APISERVER volumeMount for bouncer present (${BOUNCER_DIR})" \
    "No volumeMount found for ${BOUNCER_DIR}" \
    "Add a volumeMount under kube-apiserver container: mountPath: ${BOUNCER_DIR} (readOnly: true recommended)"
fi


# 4) AdmissionConfiguration fields
if [[ -f "${ADMISSION_CFG}" ]]; then
  add_pass "AdmissionConfiguration file present"
else
  add_fail "AdmissionConfiguration file present" \
    "${ADMISSION_CFG} not found" \
    "Ensure the config exists at ${ADMISSION_CFG}"
fi

if grep -qE -- '^\s*defaultAllow:\s*false\s*$' "${ADMISSION_CFG}" 2>/dev/null; then
  add_pass "ImagePolicyWebhook defaultAllow=false"
else
  val="$(grep -E -- 'defaultAllow:' "${ADMISSION_CFG}" 2>/dev/null | head -n1 || true)"
  add_fail "ImagePolicyWebhook defaultAllow=false" \
    "Found '${val:-missing}'" \
    "Set defaultAllow: false"
fi

if grep -qE -- '^\s*failurePolicy:\s*Fail\s*$' "${ADMISSION_CFG}" 2>/dev/null; then
  add_pass "ImagePolicyWebhook failurePolicy=Fail (deny on backend failure)"
else
  val="$(grep -E -- 'failurePolicy:' "${ADMISSION_CFG}" 2>/dev/null | head -n1 || true)"
  add_fail "ImagePolicyWebhook failurePolicy=Fail (deny on backend failure)" \
    "Found '${val:-missing}'" \
    "Set failurePolicy: Fail"
fi

# 5) kubeconfig server points to scanner URL
if [[ -f "${WEBHOOK_KUBECONFIG}" ]]; then
  add_pass "Webhook kubeconfig present"
else
  add_fail "Webhook kubeconfig present" \
    "${WEBHOOK_KUBECONFIG} not found" \
    "Ensure kubeconfig exists at ${WEBHOOK_KUBECONFIG}"
fi

if grep -qE -- "server:\s*${SCANNER_URL}" "${WEBHOOK_KUBECONFIG}" 2>/dev/null; then
  add_pass "Webhook endpoint configured (${SCANNER_URL})"
else
  val="$(grep -E -- 'server:' "${WEBHOOK_KUBECONFIG}" 2>/dev/null | head -n1 || true)"
  add_fail "Webhook endpoint configured (${SCANNER_URL})" \
    "Found '${val:-missing}'" \
    "Set clusters[].cluster.server: ${SCANNER_URL}"
fi

# 6) Best-effort functional test: vulnerable.yaml should be denied
echo "⏳ Best-effort functional test: applying ${VULN_MANIFEST} should be denied..."
if [[ -f "${VULN_MANIFEST}" ]]; then
  KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl delete pod vulnerable --ignore-not-found >/dev/null 2>&1 || true
  out="$(KUBECONFIG="${ADMIN_KUBECONFIG}" kubectl apply -f "${VULN_MANIFEST}" 2>&1 || true)"
  if echo "${out}" | grep -qiE 'denied|forbidden|ImagePolicyWebhook|admission'; then
    add_pass "Functional test: vulnerable workload denied (expected)"
  else
    add_warn "Functional test: vulnerable workload denied (expected)" \
      "Did not observe a denial message. Output: $(echo "${out}" | head -n1)" \
      "If your scanner policy differs, validate denial using the scanner logs and confirm ImagePolicyWebhook is active"
  fi
else
  add_warn "Functional test: vulnerable workload denied (expected)" \
    "${VULN_MANIFEST} not found" \
    "Ensure ~/vulnerable.yaml exists (provided by setup) and re-run grader"
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
