#!/usr/bin/env bash

cat <<'EOF'
Q7 Solution Instructions (DO NOT EXECUTE)

1) Edit kube-apiserver static pod manifest:
   /etc/kubernetes/manifests/kube-apiserver.yaml

2) Add audit flags:
   --audit-policy-file=/etc/kubernetes/logpolicy/audit-policy.yaml
   --audit-log-path=/var/log/kubernetes/audit-logs.txt
   --audit-log-maxage=10
   --audit-log-maxbackup=2

3) Add mounts so kube-apiserver container can read policy and write logs:
   - hostPath /etc/kubernetes/logpolicy mounted read-only to /etc/kubernetes/logpolicy
   - hostPath /var/log/kubernetes mounted read-write to /var/log/kubernetes

4) Extend the audit policy file (order matters: specific rules before catch-all):
   - namespaces at RequestResponse
   - deployments in namespace webapps at Request (request body)
   - configmaps and secrets in all namespaces at Metadata
   - all other requests at Metadata (catch-all last)

5) Save the manifest and wait for kube-apiserver restart.

6) Verify:
   - /readyz works
   - /var/log/kubernetes/audit-logs.txt fills with events
   - Secret events do NOT include requestObject (must remain Metadata)
EOF
