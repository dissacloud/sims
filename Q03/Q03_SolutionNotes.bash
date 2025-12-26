# Question 3 — Solution Notes (ImagePolicyWebhook)

## 0) Review the findings
```bash
sudo cat /root/kube-bench-report-q03.txt
```

## 1) Configure kube-apiserver to use AdmissionConfiguration and enable ImagePolicyWebhook
Edit:
```bash
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

Ensure:
- `--admission-control-config-file=/etc/kubernetes/bouncer/admission-configuration.yaml`
- `--enable-admission-plugins` includes `ImagePolicyWebhook`

Example (preserve existing plugins; add ImagePolicyWebhook):
```yaml
- --admission-control-config-file=/etc/kubernetes/bouncer/admission-configuration.yaml
- --enable-admission-plugins=NodeRestriction,NamespaceLifecycle,ServiceAccount,DefaultStorageClass,ResourceQuota,ImagePolicyWebhook
```

Save; kubelet will restart the API server static pod automatically.

Validate restart:
```bash
kubectl -n kube-system get pods | grep kube-apiserver
kubectl -n kube-system describe pod <kube-apiserver-pod> | grep -E "admission-control-config-file|enable-admission-plugins"
```

## 2) Configure ImagePolicyWebhook to deny on backend failure
Edit:
```bash
sudo vi /etc/kubernetes/bouncer/admission-configuration.yaml
```

Ensure:
- `defaultAllow: false`
- `failurePolicy: Fail`

## 3) Point kubeconfig to the scanner endpoint
Edit:
```bash
sudo vi /etc/kubernetes/bouncer/imagepolicywebhook.kubeconfig
```

Set:
```yaml
clusters:
- name: image-scanner
  cluster:
    server: https://smooth-yak.local/review
```

## 4) Test — vulnerable workload should be denied
```bash
kubectl delete pod vulnerable --ignore-not-found
kubectl apply -f ~/vulnerable.yaml
```

Expected: admission should reject the pod creation (denied).

If kubectl reports success, re-check:
- API server args (admission-control-config-file, enable-admission-plugins includes ImagePolicyWebhook)
- AdmissionConfiguration (defaultAllow=false, failurePolicy=Fail)
- kubeconfig server points to https://smooth-yak.local/review

## 5) Optional: observe scanner logs (if accessible)
```bash
sudo tail -n 50 /var/log/nginx/access_log
```
