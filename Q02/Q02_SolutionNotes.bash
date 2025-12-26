# Question 2 — Solution Notes (Secure API Server)

## 0) Read the findings
```bash
sudo cat /root/kube-bench-report-q02.txt
```

## 1) Use admin kubeconfig (important once you harden the API server)
If kubectl stops working during/after hardening, switch to:
```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
```

(You can keep a second terminal with this set to avoid lockout.)

## 2) Fix kube-apiserver static pod manifest
Edit:
```bash
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

Ensure the following flags are set:

### 2.1 Forbid anonymous authentication
```yaml
- --anonymous-auth=false
```

### 2.2 Use authorization mode Node,RBAC
```yaml
- --authorization-mode=Node,RBAC
```

### 2.3 Enable NodeRestriction admission plugin
Ensure `--enable-admission-plugins` includes `NodeRestriction`, e.g.:
```yaml
- --enable-admission-plugins=NodeRestriction,NamespaceLifecycle,ServiceAccount,DefaultStorageClass,ResourceQuota
```

> Keep existing plugins and add NodeRestriction; do not remove required defaults for your cluster.

Save the file. Because this is a static pod, kubelet will restart the API server automatically.

Validate restart:
```bash
kubectl -n kube-system get pods | grep kube-apiserver
kubectl -n kube-system describe pod <kube-apiserver-pod> | grep -E "anonymous-auth|authorization-mode|enable-admission-plugins"
```

## 3) Remove the ClusterRoleBinding system-anonymous
```bash
kubectl delete clusterrolebinding system-anonymous
```

Confirm it is gone:
```bash
kubectl get clusterrolebinding | grep system-anonymous || echo "system-anonymous removed"
```

## 4) Final validation
- Your *old* (anonymous) kubectl config should now fail (expected).
- Admin kubeconfig should work:
```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl auth can-i get pods -A
kubectl get nodes
```
