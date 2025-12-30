#!/usr/bin/env bash
set -euo pipefail
trap '' PIPE

NS="alpine"
DEP="alpine"
MANIFEST="$HOME/alpine-deployment.yaml"
SPDX="$HOME/alpine.spdx"
STATE_FILE="/root/.q12_target_version"

TARGET_VER="$(cat "$STATE_FILE" 2>/dev/null || true)"
[[ -n "${TARGET_VER}" ]] || { echo "ERROR: Missing ${STATE_FILE}. Re-run lab setup."; exit 2; }

pass=0; fail=0
out=()

p(){ out+=("[PASS] $1"); pass=$((pass+1)); }
f(){ out+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }

echo "== Q12 STRICT Grader v4 =="
echo "Date: $(date -Is)"
echo "Target: libcrypto3=${TARGET_VER}"
echo

command -v bom >/dev/null 2>&1 && p "bom exists" || f "bom exists" "bom not found" "Re-run lab setup"

kubectl get ns "$NS" >/dev/null 2>&1 && p "Namespace alpine exists" || f "Namespace alpine exists" "Missing namespace" "Re-run lab setup"
kubectl -n "$NS" get deploy "$DEP" >/dev/null 2>&1 && p "Deployment alpine exists" || f "Deployment alpine exists" "Missing deployment" "Re-run lab setup"

POD="$(kubectl -n "$NS" get pod -l app=alpine -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[[ -n "$POD" ]] && p "Pod detected ($POD)" || f "Pod detected" "No alpine pod found" "Fix deployment rollout"

# Count containers (strict: should be 2 after removal)
CONTAINERS="$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{range .spec.containers[*]}{.name}{"\n"}{end}' 2>/dev/null || true)"
COUNT="$(printf "%s" "$CONTAINERS" | sed '/^$/d' | wc -l | tr -d ' ')"

if [[ "$COUNT" -eq 2 ]]; then
  p "Deployment now has 2 containers (one removed)"
else
  f "Deployment now has 2 containers" "Found $COUNT containers" "Remove ONLY the container that has libcrypto3=${TARGET_VER} and apply the manifest"
fi

[[ -f "$MANIFEST" ]] && p "Manifest exists at ~/alpine-deployment.yaml" || f "Manifest exists" "Missing manifest file" "Ensure manifest is at ~/alpine-deployment.yaml"

# SPDX checks
if [[ -f "$SPDX" ]]; then
  p "SPDX exists at ~/alpine.spdx"
  grep -q '^SPDXVersion:' "$SPDX" && p "SPDX header present" || f "SPDX header present" "No SPDXVersion header" "Regenerate: bom spdx <IMAGE> > ~/alpine.spdx"

  if grep -q 'PackageName: libcrypto3' "$SPDX" && grep -q "PackageVersion: ${TARGET_VER}" "$SPDX"; then
    p "SPDX contains libcrypto3 ${TARGET_VER}"
  else
    f "SPDX contains libcrypto3 ${TARGET_VER}" "Target package/version not found in SPDX" "Generate SPDX for the image/container that had libcrypto3=${TARGET_VER}"
  fi
else
  f "SPDX exists at ~/alpine.spdx" "Missing SPDX file" "Generate: bom spdx <IMAGE> > ~/alpine.spdx"
fi

echo
for r in "${out[@]}"; do echo "$r"; echo; done
echo "== Summary =="; echo "${pass} PASS"; echo "${fail} FAIL"
[[ "$fail" -eq 0 ]] && exit 0 || exit 2
