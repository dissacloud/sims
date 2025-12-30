#!/usr/bin/env bash
# Q12 STRICT Grader — v2 (deterministic local images: q12-alpine:a/b/c)
# Validates:
# - Candidate identified the ONLY image that contains libcrypto3=3.1.4-r5 (via bom, image-based)
# - SPDX SBOM generated at ~/alpine.spdx for that image (content must include libcrypto3 3.1.4-r5)
# - Deployment updated to remove ONLY the container using that image; other containers unchanged

set -euo pipefail
trap '' PIPE

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

NS="alpine"
DEPLOY="alpine"
MANIFEST="${HOME}/alpine-deployment.yaml"
SBOM="${HOME}/alpine.spdx"

# Expected container name->image mapping from the lab setup v2
declare -A EXPECTED
EXPECTED["alpine-a"]="q12-alpine:a"
EXPECTED["alpine-b"]="q12-alpine:b"
EXPECTED["alpine-c"]="q12-alpine:c"

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

need(){ command -v "$1" >/dev/null 2>&1 || { add_fail "Tool '$1' is available" "Missing $1 in PATH" "Ensure $1 is installed/available, then re-run"; }; }

echo "== Q12 STRICT Grader (v2) =="
echo "Date: $(date -Is)"
echo "Namespace: ${NS}"
echo "Deployment: ${DEPLOY}"
echo "Manifest: ${MANIFEST}"
echo "SBOM: ${SBOM}"
echo

need kubectl
need bom

# --- Basic objects ---
if kubectl get ns "${NS}" >/dev/null 2>&1; then
  add_pass "Namespace '${NS}' exists"
else
  add_fail "Namespace '${NS}' exists" "Namespace not found" "Run the lab setup or create namespace '${NS}'"
fi

if kubectl -n "${NS}" get deploy "${DEPLOY}" >/dev/null 2>&1; then
  add_pass "Deployment '${DEPLOY}' exists in namespace '${NS}'"
else
  add_fail "Deployment '${DEPLOY}' exists in namespace '${NS}'" "Deployment not found" "Run the lab setup or recreate Deployment '${DEPLOY}'"
fi

# --- Identify TARGET image (image-based, via bom) ---
TARGET_IMAGES=()
for tag in "q12-alpine:a" "q12-alpine:b" "q12-alpine:c"; do
  if bom packages "${tag}" 2>/dev/null | grep -Eiq '(^|[[:space:]])libcrypto3([^[:alnum:]]|$).*3\.1\.4-r5'; then
    TARGET_IMAGES+=("${tag}")
  fi
done

TARGET_IMAGE=""
if [[ "${#TARGET_IMAGES[@]}" -eq 1 ]]; then
  TARGET_IMAGE="${TARGET_IMAGES[0]}"
  add_pass "Identified exactly one image containing libcrypto3=3.1.4-r5 (${TARGET_IMAGE})"
elif [[ "${#TARGET_IMAGES[@]}" -eq 0 ]]; then
  add_fail "Identify image containing libcrypto3=3.1.4-r5 (via bom)" \
    "No matching image found among q12-alpine:a/b/c" \
    "Run: bom packages q12-alpine:a | grep libcrypto3 (repeat for b/c) and locate 3.1.4-r5"
else
  add_fail "Identify image containing libcrypto3=3.1.4-r5 (via bom)" \
    "Multiple images matched: ${TARGET_IMAGES[*]}" \
    "The lab expects only ONE match; re-run lab setup v2 or verify bom output"
  TARGET_IMAGE="${TARGET_IMAGES[0]}"
fi

# --- SBOM checks ---
if [[ -f "${SBOM}" ]]; then
  add_pass "SPDX file exists at ${SBOM}"
else
  add_fail "SPDX file exists at ${SBOM}" "File missing" "Generate: bom spdx <target-image> > ~/alpine.spdx"
fi

sbom_txt="$(cat "${SBOM}" 2>/dev/null || true)"

if echo "${sbom_txt}" | grep -qE '^SPDXVersion:'; then
  add_pass "SPDX header detected (SPDXVersion)"
else
  add_fail "SPDX header detected (SPDXVersion)" "SPDXVersion header missing" "Re-generate SPDX: bom spdx <target-image> > ~/alpine.spdx"
fi

if echo "${sbom_txt}" | grep -qiE 'libcrypto3' && echo "${sbom_txt}" | grep -qiE '3\.1\.4-r5'; then
  add_pass "SPDX content includes libcrypto3 and version 3.1.4-r5"
else
  add_fail "SPDX content includes libcrypto3=3.1.4-r5" \
    "SBOM does not show libcrypto3 3.1.4-r5" \
    "Ensure you generated SBOM for the correct image (the one that contains libcrypto3 3.1.4-r5)"
fi

if [[ -n "${TARGET_IMAGE}" ]]; then
  if echo "${sbom_txt}" | grep -qF "${TARGET_IMAGE}"; then
    add_pass "SPDX appears to reference target image tag (${TARGET_IMAGE})"
  else
    add_warn "SPDX references target image tag (${TARGET_IMAGE})" \
      "Could not find the literal tag string in SPDX (tool output may omit tag names)" \
      "If other checks pass, this may be acceptable; ensure SBOM was produced for the target image"
  fi
fi

# --- Deployment strict checks (effective state) ---
deploy_names=($(kubectl -n "${NS}" get deploy "${DEPLOY}" -o jsonpath='{.spec.template.spec.containers[*].name}' 2>/dev/null || true))
deploy_images=($(kubectl -n "${NS}" get deploy "${DEPLOY}" -o jsonpath='{.spec.template.spec.containers[*].image}' 2>/dev/null || true))

if [[ "${#deploy_names[@]}" -eq 2 ]]; then
  add_pass "Deployment has exactly 2 containers (one removed)"
else
  add_fail "Deployment has exactly 2 containers" \
    "Found ${#deploy_names[@]} containers (expected 2)" \
    "Edit ${MANIFEST} and remove only the container using the identified image; then kubectl apply -f ${MANIFEST}"
fi

declare -A EFFECTIVE
for i in "${!deploy_names[@]}"; do
  EFFECTIVE["${deploy_names[$i]}"]="${deploy_images[$i]}"
done

REMOVED_NAME=""
if [[ -n "${TARGET_IMAGE}" ]]; then
  for n in "${!EXPECTED[@]}"; do
    if [[ "${EXPECTED[$n]}" == "${TARGET_IMAGE}" ]]; then
      REMOVED_NAME="$n"
    fi
  done
fi

if [[ -n "${REMOVED_NAME}" ]]; then
  if [[ -z "${EFFECTIVE[$REMOVED_NAME]+x}" ]]; then
    add_pass "Container '${REMOVED_NAME}' (target image) removed from Deployment"
  else
    add_fail "Container '${REMOVED_NAME}' removed from Deployment" \
      "Container still present with image '${EFFECTIVE[$REMOVED_NAME]}'" \
      "Remove only that container from ${MANIFEST}, then apply the manifest"
  fi
else
  add_warn "Target container name resolved" \
    "Could not resolve target container name (target image unknown)" \
    "Fix image identification first (bom packages ...)"
fi

for n in "alpine-a" "alpine-b" "alpine-c"; do
  exp_img="${EXPECTED[$n]}"
  if [[ "${n}" == "${REMOVED_NAME}" ]]; then
    continue
  fi

  if [[ -n "${EFFECTIVE[$n]+x}" ]]; then
    if [[ "${EFFECTIVE[$n]}" == "${exp_img}" ]]; then
      add_pass "Container '${n}' preserved unchanged (${exp_img})"
    else
      add_fail "Container '${n}' preserved unchanged" \
        "Image changed from '${exp_img}' to '${EFFECTIVE[$n]}'" \
        "Revert '${n}' image back to '${exp_img}' and do not modify non-target containers"
    fi
  else
    add_fail "Container '${n}' preserved" \
      "Container missing (should not be removed)" \
      "Restore container '${n}' with image '${exp_img}' and remove only the target container"
  fi
done

if [[ -n "${TARGET_IMAGE}" ]]; then
  if printf '%s\n' "${deploy_images[@]}" | grep -qxF "${TARGET_IMAGE}"; then
    add_fail "Target image not present in Deployment" \
      "Found '${TARGET_IMAGE}' still referenced" \
      "Remove the container that uses '${TARGET_IMAGE}' and re-apply"
  else
    add_pass "Target image '${TARGET_IMAGE}' is no longer referenced by Deployment"
  fi
fi

# --- Manifest file checks ---
if [[ -f "${MANIFEST}" ]]; then
  add_pass "Manifest file exists at ${MANIFEST}"
else
  add_fail "Manifest file exists at ${MANIFEST}" \
    "File missing" \
    "Use the provided manifest at ${MANIFEST} to make the required change"
fi

if [[ -f "${MANIFEST}" && -n "${TARGET_IMAGE}" ]]; then
  if grep -qF "${TARGET_IMAGE}" "${MANIFEST}"; then
    add_fail "Manifest no longer references target image (${TARGET_IMAGE})" \
      "Target image string still present in ${MANIFEST}" \
      "Remove the container block that references ${TARGET_IMAGE} and re-apply"
  else
    add_pass "Manifest does not reference target image (${TARGET_IMAGE})"
  fi
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

if [[ "${fail}" -eq 0 ]]; then
  exit 0
else
  exit 2
fi
