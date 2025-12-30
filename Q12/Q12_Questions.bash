#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
Question 12 — Alpine + SBOM (bom)

Task
1) The 'alpine' Deployment in namespace 'alpine' initially runs 3 containers, each using a different Alpine image.
2) Identify which container/image contains package:
     libcrypto3 = 3.1.4-r5
3) Use the pre-installed 'bom' tool to generate an SPDX document for the IDENTIFIED image at:
     ~/alpine.spdx
   Tip: run: bom   (shows usage)
4) Update the alpine Deployment and REMOVE the container that uses the identified image/version.
   - Do not modify the other containers of the Deployment.
5) Deployment manifest file location:
     ~/alpine-deployment.yaml

Notes
- You may use kubectl exec to inspect packages in each container.
- Ensure the final Deployment has exactly 2 containers.
EOF
