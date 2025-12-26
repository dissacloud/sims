# Question 6 — Solution Notes

## 0) Review findings (optional)
```bash
sudo cat /root/kube-bench-report-q06.txt
```

## 1) Edit the manifest
```bash
vi ~/finer-sunbeam/lamp-deployment.yaml
```

Under the container `securityContext`, set:

```yaml
securityContext:
  runAsUser: 20000
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
```

## 2) Apply and verify
```bash
kubectl apply -f ~/finer-sunbeam/lamp-deployment.yaml
kubectl -n lamp rollout status deploy/lamp-deployment
kubectl -n lamp get deploy lamp-deployment -o yaml | grep -E "runAsUser|readOnlyRootFilesystem|allowPrivilegeEscalation"
```
