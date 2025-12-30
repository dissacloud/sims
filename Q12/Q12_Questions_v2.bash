#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="/root/.q12_target_version"
TARGET_VER="$(cat "$STATE_FILE" 2>/dev/null || true)"

if [[ -z "${TARGET_VER}" ]]; then
  echo "ERROR: Missing ${STATE_FILE}. Re-run the lab setup."
  exit 2
fi

cat <<EOF
== Question 12 ==

Task:
- In namespace 'alpine', the 'alpine' Deployment runs a Pod with 3 containers.
- Identify which container/image has: libcrypto3=${TARGET_VER}
- Use 'bom' to generate an SPDX (tag-value) SBOM for that IMAGE and save it to:
    ~/alpine.spdx
- Update the Deployment manifest at:
    ~/alpine-deployment.yaml
  and REMOVE the container that uses the identified image (the one with libcrypto3=${TARGET_VER}).
- Do not modify the remaining containers.

Notes:
- 'bom' is available (wrapper around syft). Run: bom --help
EOF
