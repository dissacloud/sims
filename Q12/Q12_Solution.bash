#!/usr/bin/env bash
# Q12 Solution — Instructions ONLY (no automation)

cat <<'EOF'
Q12 — Expected Solution Steps (CKS-style)

1) Identify which Alpine image contains:
     libcrypto3 = 3.1.4-r5

   Inspect each image directly using bom, for example:

     bom packages alpine:3.18 | grep libcrypto3
     bom packages alpine:3.19 | grep libcrypto3
     bom packages alpine:3.20 | grep libcrypto3

   Note the image version where libcrypto3 is exactly 3.1.4-r5.

2) Generate an SPDX SBOM for THAT image only:

     bom spdx <alpine-image> > ~/alpine.spdx

   Example:
     bom spdx alpine:3.19 > ~/alpine.spdx

3) Edit the deployment manifest:

     vi ~/alpine-deployment.yaml

   Remove ONLY the container that uses the identified Alpine image.
   Do NOT modify the other containers.

4) Apply the change:

     kubectl apply -f ~/alpine-deployment.yaml

5) Verify:
   - ~/alpine.spdx exists
   - Deployment now has exactly TWO containers
   - Remaining containers are unchanged

EOF
