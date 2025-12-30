#!/usr/bin/env bash
# Q12 STRICT Grader — SBOM + Container Discipline

set -euo pipefail

NS="alpine"
DEPLOY="alpine"
SBOM="$HOME/alpine.spdx"

pass=0
fail=0

p() { echo "[PASS] $1"; pass=$((pass+1)); }
f() { echo "[FAIL] $1"; fail=$((fail+1)); }

echo "== Q12 STRICT Grader =="
echo "Date: $(date -Is)"
echo

# --- SBOM existence ---
if [[ -f "$SBOM" ]]; then
  p "SPDX file exists at ~/alpine.spdx"
else
  f "Missing ~/alpine.spdx"
fi

# --- SPDX sanity ---
if grep -q "SPDXVersion" "$SBOM" 2>/dev/null; then
  p "SPDX format detected"
else
  f "File is not valid SPDX"
fi

# --- Determine which image SHOULD have been removed ---
TARGET_IMAGE=""
for img in alpine:3.18 alpine:3.19 alpine:3.20; do
  if bom packages "$img" 2>/dev/null | grep -q "libcrypto3.*3.1.4-r5"; then
    TARGET_IMAGE="$img"
  fi
done

if [[ -n "$TARGET_IMAGE" ]]; then
  p "Identified vulnerable image: $TARGET_IMAGE"
else
  f "Could not identify Alpine image containing libcrypto3=3.1.4-r5"
fi

# --- Check deployment containers ---
IMAGES=$(kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.spec.template.spec.containers[*].image}')

COUNT=$(echo "$IMAGES" | wc -w | tr -d ' ')

if [[ "$COUNT" -eq 2 ]]; then
  p "Deployment has exactly 2 containers"
else
  f "Deployment should have 2 containers, found $COUNT"
fi

if echo "$IMAGES" | grep -q "$TARGET_IMAGE"; then
  f "Vulnerable image still present in Deployment"
else
  p "Vulnerable image correctly removed"
fi

# --- Ensure other images untouched ---
for img in alpine:3.18 alpine:3.19 alpine:3.20; do
  if [[ "$img" != "$TARGET_IMAGE" ]]; then
    if echo "$IMAGES" | grep -q "$img"; then
      p "Unrelated container $img preserved"
    fi
  fi
done

echo
echo "== Summary =="
echo "$pass PASS"
echo "$fail FAIL"

[[ "$fail" -eq 0 ]] && exit 0 || exit 2
