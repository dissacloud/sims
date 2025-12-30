#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="/root/.q12_target"
IFS='|' read -r TARGET_VER TARGET_IMAGE TARGET_CONTAINER < "$STATE_FILE"

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
