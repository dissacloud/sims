#!/usr/bin/env bash
# Instructions only – do not execute as a fix script

cat <<'EOF'
REFERENCE SOLUTION — Q1 (CIS Benchmark)

1) SSH into node01.

2) Fix kubelet CIS issues:
   - Edit /var/lib/kubelet/config.yaml
   - Set:
     authentication.anonymous.enabled = false
     authentication.webhook.enabled   = true
     authorization.mode               = Webhook

3) Restart kubelet:
   systemctl daemon-reload
   systemctl restart kubelet

4) Fix etcd CIS issue:
   - Edit /etc/kubernetes/manifests/etcd.yaml
   - Ensure the command list includes:
     --client-cert-auth=true

5) Save the file.
   - kubelet will automatically restart the etcd static Pod.

6) Validate:
   - kubelet is running
   - etcd Pod restarts and is Running
   - kubectl get nodes shows Ready

Do not:
- Edit systemd kubelet flags
- Restart etcd with systemctl
- Leave authorization-mode as AlwaysAllow
EOF
