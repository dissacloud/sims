#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="/root/.q12_target"

die() { echo "ERROR: $*" >&2; exit 2; }

# --- Validate state file exists and is readable ---
[[ -f "$STATE_FILE" ]] || die "Missing $STATE_FILE. Re-run the Q12 lab setup to generate it."
[[ -s "$STATE_FILE" ]] || die "$STATE_FILE exists but is empty."

# --- Read and sanitize fields ---
# Expected format: <version>|<image>|<container>
# Example: 3.1.8-r1|alpine:3.19|alpine-319
raw="$(tr -d '\r' < "$STATE_FILE" | head -n1)"
IFS='|' read -r TARGET_VER TARGET_IMAGE TARGET_CONTAINER <<<"$raw"

# Trim whitespace (defensive)
TARGET_VER="$(echo "${TARGET_VER:-}" | xargs)"
TARGET_IMAGE="$(echo "${TARGET_IMAGE:-}" | xargs)"
TARGET_CONTAINER="$(echo "${TARGET_CONTAINER:-}" | xargs)"

[[ -n "$TARGET_VER" ]] || die "TARGET_VER missing in $STATE_FILE (expected: ver|image|container)."
[[ -n "$TARGET_IMAGE" ]] || die "TARGET_IMAGE missing in $STATE_FILE (expected: ver|image|container)."
[[ -n "$TARGET_CONTAINER" ]] || die "TARGET_CONTAINER missing in $STATE_FILE (expected: ver|image|container)."

# Optional format sanity checks (won’t be perfect, but prevents obvious corruption)
echo "$TARGET_VER" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+$' \
  || die "TARGET_VER '$TARGET_VER' does not look like <x.y.z-rN>. Check $STATE_FILE."

echo "$TARGET_CONTAINER" | grep -Eq '^alpine-[0-9]+' \
  || die "TARGET_CONTAINER '$TARGET_CONTAINER' does not look like alpine-###. Check $STATE_FILE."

cat <<EOF
== Question 12 ==

Namespace: alpine
Deployment: alpine
Manifest:   ~/alpine-deployment.yaml

Task:
1) Identify the container/image in the 'alpine' pod that has:
     libcrypto3=${TARGET_VER}
   (Hint: it is in container '${TARGET_CONTAINER}' using image '${TARGET_IMAGE}').

2) Generate an SPDX (tag-value) SBOM for THAT IMAGE using 'bom' and save it to:
     ~/alpine.spdx

3) Edit ~/alpine-deployment.yaml and REMOVE the container that uses that image
   (the one with libcrypto3=${TARGET_VER}). Leave the other containers unchanged.

Expected tooling:
- bom version
- bom packages <IMAGE>
- bom spdx <IMAGE> > ~/alpine.spdx
EOF
