# Question 7 — Solution Notes

## 0) Read findings
```bash
sudo cat /root/kube-bench-report-q07.txt
```

## 1) Update the audit policy
```bash
sudo vi /etc/kubernetes/logpolicy/audit-policy.yaml
```

Example (order matters; first match wins):

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: None
  verbs: ["watch"]

- level: None
  nonResourceURLs:
  - "/healthz*"
  - "/readyz*"
  - "/livez*"

- level: RequestResponse
  resources:
  - group: "apps"
    resources: ["deployments"]
  namespaces: ["webapps"]

- level: RequestResponse
  resources:
  - group: ""
    resources: ["namespaces"]

- level: Metadata
  resources:
  - group: ""
    resources: ["secrets", "configmaps"]

- level: Metadata
```

## 2) Configure kube-apiserver to enable auditing
Edit:
```bash
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

Add flags:
- `--audit-policy-file=/etc/kubernetes/logpolicy/audit-policy.yaml`
- `--audit-log-path=/var/log/kubernetes/audit-logs.txt`
- `--audit-log-maxbackup=2`
- `--audit-log-maxage=10`

Add mounts (volumeMounts + hostPath volumes):
- hostPath `/etc/kubernetes/logpolicy` mounted to `/etc/kubernetes/logpolicy` (readOnly)
- hostPath `/var/log/kubernetes` mounted to `/var/log/kubernetes`

Save; kubelet restarts apiserver.

## 3) Verify
```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl get --raw=/readyz
sudo tail -n 5 /var/log/kubernetes/audit-logs.txt
```
