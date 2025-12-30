#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
========================
Question 12
========================

Task

- The alpine Deployment in the alpine namespace has three containers that run different versions of the alpine image.
- First, find out which version of the alpine image contains the libcrypto3 package at version 3.1.4-r5.
- Next, use the pre-installed bom tool to create an SPDX document for the identified image version at:
    ~/alpine.spdx
- You can find the bom tool documentation at: bom
- Finally, update the alpine Deployment and remove the container that uses the identified image version.
- The Deployment's manifest file can be found at:
    ~/alpine-deployment.yaml
- Do not modify any other containers of the Deployment.

Notes
- Do not delete the Deployment.
- Do not modify any namespaces other than what is required by the task.
EOF
