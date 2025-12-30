#!/usr/bin/env bash
set -euo pipefail

NS="alpine"
MANIFEST="$HOME/alpine-deployment.yaml"
SBOM="$HOME/alpine.spdx"

pass=0; fail=0

p() { echo "[PASS] $1"; ((pass++)); }
f() { echo "[FAIL] $1"; ((fail++)); }

echo "== Q12 STRICT Grader =="

# Namespace
kubectl get ns "$NS" >/dev/null 2>&1 || f "Namespace alpine missing"

# SBOM file
[[ -f "$SBOM" ]] && p "SPDX file exists at ~/alpine.spdx" || f "Missing ~/alpine.spdx"

# SBOM content
if grep -q "libcrypto3" "$SBOM" && grep -q "3.1.4-r5" "$SBOM"; then
  p "SBOM contains libcrypto3 3.1.4-r5"
else
  f "SBOM does not contain libcrypto3 3.1.4-r5"
fi

# Deployment containers
containers=$(kubectl -n alpine get deploy alpine -o jsonpath='{.spec.template.spec.containers[*].name}')

if echo "$containers" | grep -q alpine-317; then
  f "alpine-317 container was NOT removed"
else
  p "alpine-317 container removed"
fi

# Ensure others untouched
for c in alpine-318 alpine-319; do
  if echo "$containers" | grep -q "$c"; then
    p "$c still present"
  else
    f "$c was incorrectly modified or removed"
  fi
done

echo
echo "Summary: $pass PASS / $fail FAIL"
[[ $fail -eq 0 ]]
