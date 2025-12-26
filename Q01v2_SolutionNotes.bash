# Question 1 — Solution Notes (Exam-Realistic CIS Remediation)

## 0) Review kube-bench findings
```bash
sudo cat /root/kube-bench-report-q01.txt
```

---

## 1) Remediate kubelet findings (preferred: config.yaml)

### 1.1 Inspect kubelet config
```bash
sudo sed -n '1,200p' /var/lib/kubelet/config.yaml
```

You must ensure:
- `authentication.anonymous.enabled: false`
- `authentication.webhook.enabled: true`
- `authorization.mode` is NOT `AlwaysAllow` (prefer `Webhook`)

### 1.2 Edit kubelet config
```bash
sudo vi /var/lib/kubelet/config.yaml
```

Set/confirm these sections (illustrative):
```yaml
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true

authorization:
  mode: Webhook
```

### 1.3 Restart kubelet
```bash
sudo systemctl restart kubelet
```

### 1.4 Validate kubelet changes took effect
```bash
kubectl get nodes
kubectl -n kube-system get pods
```

Optional (process args are less useful when config.yaml is the source of truth, but still good signal):
```bash
ps aux | grep -E '[k]ubelet'
```

---

## 2) Remediate etcd finding (controlplane)

### 2.1 Edit etcd static pod manifest
```bash
sudo vi /etc/kubernetes/manifests/etcd.yaml
```

Ensure:
```yaml
- --client-cert-auth=true
```

### 2.2 Allow static pod restart / validate
Saving the manifest triggers kubelet to restart the etcd pod automatically.

Validate:
```bash
kubectl -n kube-system get pods | grep etcd
kubectl -n kube-system describe pod <etcd-pod-name> | grep -E 'client-cert-auth'
```

---

## 3) End-state checklist
- kubelet config effective:
  - anonymous disabled
  - webhook authn enabled
  - authorization mode not AlwaysAllow (Webhook preferred)
- etcd:
  - client cert auth enabled
- cluster healthy:
  - nodes Ready
  - kube-system pods Running

Optionally re-run kube-bench (if installed) to confirm previous FAIL items now PASS.
