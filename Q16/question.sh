#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
CKS Simulation — Question 16 (TLS Secret)

Context:
You must complete securing access to a web server using SSL files stored in a TLS Secret.

Task:
- Create a TLS Secret named "clever-cactus" in the "clever-cactus" namespace.
- Use certificate file:
  /home/candidate/clever-cactus/web k8s.local.crt
- Use key file:
  /home/candidate/clever-cactus/web k8s.local.key
- There is an existing Deployment named "clever-cactus" already configured to use this TLS Secret.
- Do NOT modify the existing Deployment.

Traps:
- There is a decoy secret named clever-cactus in the default namespace (irrelevant).
- There is a decoy cert/key pair under /home/candidate/clever-cactus/decoy (wrong path).
- The certificate file name contains a space: "web k8s.local.crt" (quote paths properly).

When done:
- Run: ./grader.sh
EOF
