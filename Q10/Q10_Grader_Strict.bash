#!/usr/bin/env bash
# Q10 Strict Grader — ordering + exact-field matching (exam-style)

set -u
trap '' PIPE

NS="monitoring"
SA="stats-monitor-sa"
DEP="stats-monitor"
MANIFEST="$HOME/stats-monitor/deployment.yaml"
TOKEN_DIR="/var/run/secrets/kubernetes.io/serviceaccount"
TOKEN_FILE="/var/run/secrets/kubernetes.io/serviceaccount/token"

pass=0; fail=0; warn=0
out=()

p(){ out+=("[PASS] $1"); pass=$((pass+1)); }
f(){ out+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
w(){ out+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

echo "== Q10 Strict Verifier (kube-bench-like) =="
echo "Date: $(date -Is)"
echo "Namespace: ${NS}"
echo "Manifest:  ${MANIFEST}"
echo

[[ -f "${MANIFEST}" ]] && p "Deployment manifest file exists at ${MANIFEST}" ||   f "Deployment manifest file exists at ${MANIFEST}" "File not found" "Re-run lab setup; ensure file exists"

kubectl get ns "${NS}" >/dev/null 2>&1 && p "Namespace ${NS} exists" || f "Namespace ${NS} exists" "Namespace missing" "Re-run lab setup"

kubectl -n "${NS}" get sa "${SA}" >/dev/null 2>&1 && p "ServiceAccount ${SA} exists" || f "ServiceAccount ${SA} exists" "Missing" "Re-run lab setup"

sa_auto="$(kubectl -n "${NS}" get sa "${SA}" -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null || true)"
[[ "${sa_auto}" == "false" ]] && p "ServiceAccount automountServiceAccountToken is false" ||   f "ServiceAccount automountServiceAccountToken is false" "Got '${sa_auto:-<unset>}' (must be explicitly false)" "kubectl -n ${NS} patch sa ${SA} -p '{"automountServiceAccountToken":false}'"

kubectl -n "${NS}" get deploy "${DEP}" >/dev/null 2>&1 && p "Deployment ${DEP} exists" ||   f "Deployment ${DEP} exists" "Missing" "Apply: kubectl apply -f ${MANIFEST}"

proj_type="$(kubectl -n "${NS}" get deploy "${DEP}" -o jsonpath='{.spec.template.spec.volumes[?(@.name=="token")].projected}' 2>/dev/null || true)"
[[ -n "${proj_type}" && "${proj_type}" != "null" ]] && p "Projected volume named 'token' exists" ||   f "Projected volume named 'token' exists" "Not found" "Add volumes: - name: token projected: sources: - serviceAccountToken: {path: token}"

proj_path="$(kubectl -n "${NS}" get deploy "${DEP}" -o jsonpath='{.spec.template.spec.volumes[?(@.name=="token")].projected.sources[0].serviceAccountToken.path}' 2>/dev/null || true)"
[[ "${proj_path}" == "token" ]] && p "Projected sources[0].serviceAccountToken.path == 'token'" ||   f "Projected sources[0].serviceAccountToken.path == 'token'" "Got '${proj_path:-<empty>}'" "Ensure first projected source is serviceAccountToken with path: token"

mp="$(kubectl -n "${NS}" get deploy "${DEP}" -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="token")].mountPath}' 2>/dev/null || true)"
ro="$(kubectl -n "${NS}" get deploy "${DEP}" -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="token")].readOnly}' 2>/dev/null || true)"

[[ "${mp}" == "${TOKEN_DIR}" ]] && p "MountPath is exactly ${TOKEN_DIR}" ||   f "MountPath is exactly ${TOKEN_DIR}" "Got '${mp:-<empty>}'" "Mount at ${TOKEN_DIR} (directory)"

[[ "${ro}" == "true" ]] && p "Token mount is readOnly: true" ||   f "Token mount is readOnly: true" "Got '${ro:-<empty>}'" "Set readOnly: true for the token volumeMount"

pod="$(kubectl -n "${NS}" get pods -l app=stats-monitor -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "${pod}" ]]; then
  f "Pod exists for app=stats-monitor" "No pod found" "Fix rollout: kubectl -n ${NS} get pods"
else
  p "Pod detected: ${pod}"
  if kubectl -n "${NS}" exec "${pod}" -- sh -c "test -f '${TOKEN_FILE}'" >/dev/null 2>&1; then
    p "Token file exists in pod (${TOKEN_FILE})"
  else
    f "Token file exists in pod (${TOKEN_FILE})" "Missing" "Fix projected token volume + mountPath + path"
  fi
fi

if kubectl -n "${NS}" rollout status deploy/"${DEP}" --timeout=15s >/dev/null 2>&1; then
  p "Deployment rollout is ready"
else
  w "Deployment rollout is ready" "Not ready within 15s" "Check logs: kubectl -n ${NS} logs deploy/${DEP}"
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
