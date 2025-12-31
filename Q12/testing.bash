#!/usr/bin/env bash
# Q12 STRICT Grader v5 — SPDX-correct checks
# - Confirms: bom exists, namespace/deploy ok, target container removed
# - Confirms: ~/alpine.spdx contains libcrypto3 with the expected version using SPDX fields / purl
set -euo pipefail
trap '' PIPE

NS="alpine"
DEP="alpine"
SPDX="$HOME/alpine.spdx"
STATE_FILE="/root/.q12_target"

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

k() { kubectl "$@"; }

echo "== Q12 STRICT Grader v5 =="
echo "Date: $(date -Is)"
echo

# --- Target state file ---
if [[ -f "$STATE_FILE" ]]; then
  add_pass "Target state file present"
else
  add_fail "Target state file present" "Missing $STATE_FILE" "Re-run Q12 lab setup that writes /root/.q12_target"
fi

TARGET_VER=""; TARGET_IMAGE=""; TARGET_CONTAINER=""
if [[ -f "$STATE_FILE" ]]; then
  IFS='|' read -r TARGET_VER TARGET_IMAGE TARGET_CONTAINER < "$STATE_FILE" || true
fi

# --- bom exists ---
if command -v bom >/dev/null 2>&1; then
  add_pass "bom exists"
else
  add_fail "bom exists" "bom not found in PATH" "Re-run lab setup; ensure /usr/local/bin/bom wrapper exists"
fi

# --- namespace/deployment/pod checks ---
if k get ns "$NS" >/dev/null 2>&1; then
  add_pass "Namespace $NS exists"
else
  add_fail "Namespace $NS exists" "Namespace missing" "kubectl create ns $NS"
fi

if k -n "$NS" get deploy "$DEP" >/dev/null 2>&1; then
  add_pass "Deployment $DEP exists"
else
  add_fail "Deployment $DEP exists" "Deployment missing" "kubectl -n $NS apply -f ~/alpine-deployment.yaml"
fi

POD="$(k -n "$NS" get pod -l app=alpine -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "$POD" ]]; then
  add_pass "Pod detected ($POD)"
else
  add_fail "Pod detected" "No pod found with label app=alpine" "kubectl -n $NS get pods; fix scheduling/image pulls"
fi

# containers count
if [[ -n "$POD" ]]; then
  CNT="$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[*].name}' | wc -w | tr -d ' ')"
  if [[ "$CNT" == "2" ]]; then
    add_pass "Deployment has 2 containers (target removed)"
  else
    add_fail "Deployment has 2 containers (target removed)" "Found $CNT containers" "Edit ~/alpine-deployment.yaml to remove the target container only, then kubectl apply"
  fi
fi

# target container removed
if [[ -n "$TARGET_CONTAINER" && -n "$POD" ]]; then
  if k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[*].name}' | tr ' ' '\n' | grep -qx "$TARGET_CONTAINER"; then
    add_fail "Target container removed ($TARGET_CONTAINER)" "Target container still present in pod spec" "Remove container $TARGET_CONTAINER from ~/alpine-deployment.yaml and re-apply"
  else
    add_pass "Target container removed ($TARGET_CONTAINER)"
  fi
else
  add_warn "Target container removed" "Could not determine target container (missing state file or pod)" "Ensure /root/.q12_target exists and pod is running"
fi

# --- SPDX existence + header ---
if [[ -f "$SPDX" ]]; then
  add_pass "SPDX exists at ~/alpine.spdx"
else
  add_fail "SPDX exists at ~/alpine.spdx" "File missing" "Generate: bom spdx <TARGET_IMAGE> > ~/alpine.spdx"
fi

if [[ -f "$SPDX" ]] && grep -qE '^SPDXVersion:' "$SPDX"; then
  add_pass "SPDX header present"
else
  add_fail "SPDX header present" "Missing SPDXVersion header" "Regenerate: bom spdx <TARGET_IMAGE> > ~/alpine.spdx"
fi

# --- SPDX contains libcrypto3 + expected version (SPDX-correct) ---
# We accept any of these evidence forms:
#  A) PackageName: libcrypto3 + PackageVersion: <ver>  (if present)
#  B) purl for libcrypto3@<ver>                        (present in your output)
#  C) cpe contains <ver>                               (present in your output)
if [[ -f "$SPDX" && -n "$TARGET_VER" ]]; then
  if awk -v ver="$TARGET_VER" '
    BEGIN{inpkg=0; nameok=0; verok=0;}
    /^##### Package:/ {inpkg=1; nameok=0; verok=0;}
    inpkg && /^PackageName:[[:space:]]*libcrypto3[[:space:]]*$/ {nameok=1;}
    inpkg && /^PackageVersion:[[:space:]]*/ {
      if ($0 ~ ver) verok=1;
    }
    END{ exit ! (nameok && verok); }
  ' "$SPDX" >/dev/null 2>&1; then
    add_pass "SPDX contains libcrypto3 with PackageVersion=$TARGET_VER"

  # FIX: use fixed-string match for purl prefix (Syft emits '?arch=...' etc after it)
  elif grep -qF "pkg:apk/alpine/libcrypto3@${TARGET_VER}" "$SPDX" >/dev/null 2>&1; then
    add_pass "SPDX contains libcrypto3 purl with version $TARGET_VER"

  # FIX: use fixed-string match for CPE prefix (Syft emits ':*:*:*...' etc after it)
  elif grep -qF "cpe:2.3:a:libcrypto3:libcrypto3:${TARGET_VER}" "$SPDX" >/dev/null 2>&1; then
    add_pass "SPDX contains libcrypto3 cpe with version $TARGET_VER"

  else
    add_fail "SPDX contains libcrypto3 version $TARGET_VER" \
      "Could not find libcrypto3 at expected version in SPDX (checked PackageVersion/purl/cpe)" \
      "Regenerate SPDX for the correct image: bom spdx \"$TARGET_IMAGE\" > ~/alpine.spdx (then re-run grader)"
  fi
else
  add_fail "SPDX contains libcrypto3 version <target>" \
    "Missing SPDX or missing target version (state file)" \
    "Ensure /root/.q12_target exists and SPDX generated: bom spdx <TARGET_IMAGE> > ~/alpine.spdx"
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
