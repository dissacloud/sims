#!/usr/bin/env bash

cat <<'EOF'
Question 7 — Kubernetes Auditing

Context:
You must implement auditing for the kubeadm-provisioned cluster.

Tasks:
1. Reconfigure the kube-apiserver to:
   - Use the audit policy at:
     /etc/kubernetes/logpolicy/audit-policy.yaml
   - Write audit logs to:
     /var/log/kubernetes/audit-logs.txt
   - Retain a maximum of 2 log files for 10 days

2. The basic audit policy only specifies what NOT to log.
   Extend the policy to log:
   - Namespace interactions at RequestResponse level
   - Request body of Deployment interactions in namespace "webapps"
   - ConfigMap and Secret interactions in all namespaces at Metadata level
   - All other requests at Metadata level

3. Make sure the API server uses the extended policy.

When finished:
- Run ./grader.sh
EOF
