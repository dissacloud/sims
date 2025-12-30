#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

NS="alpine"
DEP="alpine"
MANIFEST="$HOME/alpine-deployment.yaml"
SPDX="$HOME/alpine.spdx"
STATE_FILE="/root/.q12_target"

pass=0; fail=0
out=()

p(){ out+=("[PASS] $1"); pass=$((pass+1)); }
f(){ out+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }

echo "== Q12 STRICT Grader v3 =="
echo "Date: $(date -Is)"
echo

if [[ -f "$STATE_FILE" ]]; then
  IFS='|' read -r TARGET_VER TARGET_IMAGE TARGET_CONTAINER < "$STATE_FILE"
  p "Target state file present"
else
  f "Target state file present" "Missing $STATE_FILE" "Re-run lab setup"
  TARGET_VER=""; TARGET_IMAGE=""; TARGET_CONTAINER=""
fi

command -v bom >/dev/null 2>&1 && p "bom exists" || f "bom exists" "bom not found" "Re-run lab setup"

kubectl get ns "$NS" >/dev/null 2>&1 && p "Namespace alpine exists" || f "Namespace alpine exists" "Missing namespace" "Re-run lab setup"
kubectl -n "$NS" get deploy "$DEP" >/dev/null 2>&1 && p "Deployment alpine exists" || f "Deployment alpine exists" "Missing deployment" "Re-run lab setup"

POD="$(kubectl -n "$NS" get pod -l app=alpine -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[[ -n "$POD" ]] && p "Pod detected ($POD)" || f "Pod detected" "No pod found" "kubectl -n alpine rollout status deploy/alpine"

# strict: deployment must now have exactly 2 containers
CONTAINER_COUNT="$(kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[*].name}' \
  | wc -w | tr -d ' ')"
if [[ "$CONTAINER_COUNT" -eq 2 ]]; then
  p "Deployment has 2 containers (target removed)"
else
  f "Deployment has 2 containers" "Found ${CONTAINER_COUNT} containers" "Remove only the target container and apply the manifest"
fi

# strict: target container name should NOT exist anymore in deployment spec
if [[ -n "${TARGET_CONTAINER}" ]]; then
  if kubectl -n "$NS" get deploy "$DEP" -o jsonpath='{.spec.template.spec.containers[*].name}' | grep -qw "$TARGET_CONTAINER"; then
    f "Target container removed" "Target container still present: ${TARGET_CONTAINER}" "Edit manifest and remove that container, then kubectl apply -f ~/alpine-deployment.yaml"
  else
    p "Target container removed (${TARGET_CONTAINER})"
  fi
fi

# SPDX must exist and contain libcrypto3 + target version
if [[ -f "$SPDX" ]]; then
  p "SPDX exists at ~/alpine.spdx"
  grep -q '^SPDXVersion:' "$SPDX" && p "SPDX header present" || f "SPDX header present" "No SPDXVersion header" "Regenerate: bom spdx ${TARGET_IMAGE} > ~/alpine.spdx"

  if grep -q 'PackageName: libcrypto3' "$SPDX" && grep -q "PackageVersion: ${TARGET_VER}" "$SPDX"; then
    p "SPDX contains libcrypto3 ${TARGET_VER}"
  else
    f "SPDX contains libcrypto3 ${TARGET_VER}" "Target package/version not found in SPDX" "Generate SPDX for ${TARGET_IMAGE}: bom spdx ${TARGET_IMAGE} > ~/alpine.spdx"
  fi
else
  f "SPDX exists at ~/alpine.spdx" "Missing SPDX file" "Generate: bom spdx ${TARGET_IMAGE} > ~/alpine.spdx"
fi

echo
for r in "${out[@]}"; do echo "$r"; echo; done
echo "== Summary =="; echo "${pass} PASS"; echo "${fail} FAIL"
[[ "$fail" -eq 0 ]] && exit 0 || exit 2
