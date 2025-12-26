# Question 1 — CIS Benchmark Remediation (kubeadm)

## Context
A CIS Benchmark tool reported configuration violations on a **kubeadm-provisioned** Kubernetes cluster.

You must remediate the findings via configuration changes and restart the affected components so the new settings take effect.

## Task

A (simulated) `kube-bench` scan report has been generated at:
- `/root/kube-bench-report-q01.txt`

Use it as the source of truth for what must be fixed.

### A) Fix all CIS violations found against the **kubelet**
- The cluster uses the **Docker Engine** as its container runtime.
  - If needed, use `docker` commands to troubleshoot running containers.
- Ensure the kubelet argument `--anonymous-auth` is set to **false**
- Ensure the kubelet argument `--authorization-mode` is **not** set to `AlwaysAllow`
- Use **Webhook** authentication/authorization where possible

### B) Fix all CIS violations found against **etcd**
- Ensure the etcd argument `--client-cert-auth` is set to **true**

## Success Criteria / Validation
You should be able to demonstrate the remediations by:
- Showing corrected configuration files/arguments for kubelet and etcd
- Restarting the affected components (kubelet + etcd static pod reload)
- Confirming the updated args are in effect (describe pods / inspect manifests / runtime status)

## Notes
- kubelet kubeadm flags are typically located at: `/var/lib/kubelet/kubeadm-flags.env`
- etcd (kubeadm) typically runs as a static pod: `/etc/kubernetes/manifests/etcd.yaml`
