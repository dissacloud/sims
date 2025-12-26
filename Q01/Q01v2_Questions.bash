# Question 1 — CIS Benchmark Remediation (Exam-Realistic)

## Context
A CIS Benchmark tool (`kube-bench`) reported configuration violations on a **kubeadm-provisioned** Kubernetes cluster.

A (simulated) kube-bench report is available at:
- `/root/kube-bench-report-q01.txt`

You must remediate the findings via configuration changes and restart the affected components so the new settings take effect.

## Task

### A) Fix all CIS violations found against the **kubelet**
- The cluster uses the **Docker Engine** as its container runtime (use `docker` to troubleshoot if needed)
- Ensure anonymous authentication is disabled
  - Expected effective setting: `authentication.anonymous.enabled: false`
- Ensure authorization mode is not `AlwaysAllow`
  - Expected effective setting: `authorization.mode: Webhook` (preferred) or a secure mode set (e.g., `Node,RBAC`)
- Use webhook authentication/authorization where possible
  - Expected effective setting: `authentication.webhook.enabled: true`

> In kubeadm clusters, these are typically controlled by the kubelet config file:
> - `/var/lib/kubelet/config.yaml`
>
> (Some environments also use `/var/lib/kubelet/kubeadm-flags.env` for additional args.)

### B) Fix all CIS violations found against **etcd** (controlplane)
- Ensure the etcd argument `--client-cert-auth` is set to **true**
  - Typical location: `/etc/kubernetes/manifests/etcd.yaml`

## Success Criteria / Validation
- Show the corrected effective configuration for kubelet and etcd
- Restart the affected components (kubelet + etcd static pod reload)
- Confirm the updated settings are in effect (node Ready, kube-system pods healthy, args/config reflect changes)
