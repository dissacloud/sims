#!/usr/bin/env bash
# Q12 STRICT Grader — verifies:
# - bom exists
# - ~/alpine.spdx exists and looks like SPDX Tag-Value
# - alpine deployment exists and ends with exactly 2 containers
# - remaining containers keep expected images (no modifications)
# - libcrypto3 3.1.4-r5 is NOT present in any remaining container

set -u
trap '' PIPE

NS="alpine"
DEP="alpine"
SPDX_OUT="$HOME/alpine.spdx"

# Expected baseline (adjust if your lab setup differs)
declare -A EXPECTED_IMAGES=(
  ["alpine-317"]="alpine:3.17"
  ["alpine-318"]="alpine:3.18"
  ["alpine-319"]="alpine:3.19"
)

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

k(){ kubectl "$@"; }

echo "== Q12 STRICT Grader =="
echo "Date: $(date -Is)"
echo "Namespace: $NS"
echo "Deployment: $DEP"
echo "SPDX: $SPDX_OUT"
echo

# [0] bom exists
if command -v bom >/dev/null 2>&1; then
  add_pass "bom command available ($(command -v bom))"
else
  add_fail "bom command available" "bom not found in PATH" "Ensure bom exists (per lab setup) or provide /usr/local/bin/bom"
fi

# [1] namespace + deployment
if k get ns "$NS" >/dev/null 2>&1; then
  add_pass "Namespace '$NS' exists"
else
  add_fail "Namespace '$NS' exists" "Namespace missing" "Recreate namespace '$NS' and the alpine deployment"
fi

if k -n "$NS" get deploy "$DEP" >/dev/null 2>&1; then
  add_pass "Deployment '$DEP' exists in '$NS'"
else
  add_fail "Deployment '$DEP' exists in '$NS'" "Deployment missing" "Recreate the alpine deployment"
fi

# [2] pod + container count
POD="$(k -n "$NS" get pod -l app=alpine -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "${POD}" ]]; then
  add_pass "Pod detected ($POD)"
else
  add_fail "Pod detected" "No pod with label app=alpine" "Ensure Deployment selector/labels are correct and pod is Running"
fi

CONTAINERS="$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null || true)"
cnt="$(wc -w <<<"${CONTAINERS:-}" | tr -d ' ')"
if [[ "$cnt" == "2" ]]; then
  add_pass "Final pod has exactly 2 containers"
else
  add_fail "Final pod has exactly 2 containers" "Found $cnt containers: ${CONTAINERS:-<none>}" "Remove exactly one container from the Deployment"
fi

# [3] remaining containers name+image strict
if [[ -n "${CONTAINERS:-}" ]]; then
  for c in $CONTAINERS; do
    img="$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[?(@.name==\"$c\")].image}" 2>/dev/null || true)"
    exp="${EXPECTED_IMAGES[$c]:-}"
    if [[ -z "$exp" ]]; then
      add_fail "Container name is allowed: $c" "Unexpected container name" "Do not add/rename containers; only remove one"
      continue
    fi
    if [[ "$img" == "$exp" ]]; then
      add_pass "Container '$c' image unchanged ($img)"
    else
      add_fail "Container '$c' image unchanged" "Expected $exp but found $img" "Revert '$c' image to $exp (do not modify other containers)"
    fi
  done
fi

# [4] SPDX output exists and looks valid
if [[ -s "$SPDX_OUT" ]]; then
  if grep -q '^SPDXVersion:' "$SPDX_OUT" && grep -q '^DataLicense:' "$SPDX_OUT"; then
    add_pass "SPDX file exists and appears valid (Tag-Value)"
  else
    add_fail "SPDX file exists and appears valid" "Missing SPDXVersion/DataLicense headers" "Generate using: bom spdx <IMAGE> > ~/alpine.spdx"
  fi
else
  add_fail "SPDX file exists at ~/alpine.spdx" "File missing or empty" "Run: bom spdx <IDENTIFIED_IMAGE> > ~/alpine.spdx"
fi

# [5] Ensure remaining containers do NOT contain libcrypto3 3.1.4-r5
found_target=0
if [[ -n "${CONTAINERS:-}" ]]; then
  for c in $CONTAINERS; do
    out="$(k -n "$NS" exec "$POD" -c "$c" -- sh -lc 'apk info -v libcrypto3 2>/dev/null || true' 2>/dev/null || true)"
    if echo "$out" | grep -q 'libcrypto3-3\.1\.4-r5'; then
      found_target=1
      add_fail "Removed container that had libcrypto3 3.1.4-r5"         "Still found libcrypto3-3.1.4-r5 in remaining container '$c'"         "Remove the container/image that contains libcrypto3 3.1.4-r5 and keep the others unchanged"
    fi
  done
fi
if [[ "$found_target" -eq 0 ]]; then
  add_pass "No remaining container contains libcrypto3 3.1.4-r5"
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

if [[ "$fail" -eq 0 ]]; then
  exit 0
else
  exit 2
fi
