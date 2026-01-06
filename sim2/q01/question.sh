#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
CKS Simulation — Question 1 (CIS Benchmark)

Context:
You must resolve issues that a CIS Benchmark tool found for the kubeadm-provisioned cluster.

Task:
- Fix all issues via configuration and restart affected components.
- Fix the following kubelet violations:
  - Ensure anonymous-auth is set to false
  - Ensure authorization-mode is not set to AlwaysAllow
  - Use Webhook authentication/authorization where possible
- Fix the following etcd violation:
  - Ensure --client-cert-auth is set to true

Important:
- You must SSH into node01 to apply fixes.
- This is a kubeadm cluster.
- Do not redeploy the cluster.

When finished:
- Run ./grader.sh
EOF
