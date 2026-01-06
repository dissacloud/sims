
#!/usr/bin/env bash

Question 7 — Auditing

Context
You must implement auditing for the kubeadm provisioned cluster.

Task
1) Reconfigure the API server so that:
   - audit policy file: /etc/kubernetes/logpolicy/audit-policy.yaml
   - audit logs stored at: /var/log/kubernetes/audit-logs.txt
   - maximum of 2 log files are retained
   - logs are retained for 10 days

2) Extend the basic policy to log:
   - namespace interactions at RequestResponse level
   - request body for deployment interactions in namespace webapps at RequestResponse level
   - ConfigMap and Secret interactions in all namespaces at Metadata level
   - all other requests at Metadata level

3) Make sure the API server uses the extended policy.

Notes
- The cluster may mention Docker for troubleshooting. Use whatever runtime tooling exists in your environment.


chmod +x Q07v2_Questions.bash
