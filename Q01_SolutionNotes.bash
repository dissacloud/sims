# Question 1 — Solution Notes (CIS Benchmark Remediation)

## 0) Review the kube-bench findings

The lab setup generates a simulated kube-bench output here:
```bash
sudo cat /root/kube-bench-report-q01.txt
```

Use the failing checks as your remediation targets.

---

## 0) Quick situational awareness
```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods
```

If the lab states “Docker runtime”, you may use:
```bash
docker ps
docker logs <container>
```

(If Docker is not present in your environment, rely on `kubectl` + kubelet logs instead.)

---

## 1) Remediate kubelet CIS violations

### 1.1 Identify where kubelet arguments are set
For kubeadm clusters, kubelet flags are typically in:
- `/var/lib/kubelet/kubeadm-flags.env`

Check current flags:
```bash
sudo cat /var/lib/kubelet/kubeadm-flags.env
```

You are targeting:
- `--anonymous-auth=false`
- `--authorization-mode` must **not** be `AlwaysAllow`
- Use webhook authn/authz where possible:
  - `--authentication-token-webhook=true`
  - Prefer `--authorization-mode=Webhook` (or a secure mode set like `Node,RBAC` depending on requirement)

### 1.2 Apply fixes (edit kubeadm-flags.env)
Edit the file:
```bash
sudo vi /var/lib/kubelet/kubeadm-flags.env
```

Ensure the `KUBELET_KUBEADM_ARGS="..."` value includes **at least**:
- `--anonymous-auth=false`
- a secure authorization mode (NOT AlwaysAllow), e.g.:
  - `--authorization-mode=Webhook`  (matches “use webhook where possible”)
- enable token webhook:
  - `--authentication-token-webhook=true`

Example (illustrative; keep existing flags intact):
```bash
KUBELET_KUBEADM_ARGS="... --anonymous-auth=false --authorization-mode=Webhook --authentication-token-webhook=true"
```

### 1.3 Restart kubelet
```bash
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

### 1.4 Validate kubelet settings took effect
Kubelet is a node process; validate by confirming the node is Ready and system pods are healthy:
```bash
kubectl get nodes
kubectl -n kube-system get pods
```

Optionally validate the running kubelet process args:
```bash
ps aux | grep -E '[k]ubelet'
```

---

## 2) Remediate etcd CIS violation

### 2.1 Inspect etcd static pod manifest
For kubeadm, etcd is usually a static pod:
```bash
sudo vi /etc/kubernetes/manifests/etcd.yaml
```

Find the command args and ensure:
- `--client-cert-auth=true`

Example snippet (illustrative):
```yaml
- --client-cert-auth=true
```

### 2.2 Restart / reload etcd
With kubeadm static pods, editing the manifest triggers kubelet to recreate the pod automatically.

Still, ensure kubelet is running:
```bash
sudo systemctl restart kubelet
```

### 2.3 Validate etcd pod restarted and is healthy
```bash
kubectl -n kube-system get pods | grep etcd
kubectl -n kube-system describe pod <etcd-pod-name>
```

---

## 3) End-state checklist (what the examiner wants to see)
- kubelet:
  - `--anonymous-auth=false`
  - `--authorization-mode` is not `AlwaysAllow` (secure mode set; webhook preferred where required)
  - webhook authn/authz enabled where possible (`--authentication-token-webhook=true`, `--authorization-mode=Webhook`)
- etcd:
  - `--client-cert-auth=true`
- affected components restarted and cluster returns to a healthy state
  - nodes Ready
  - kube-system pods Running
