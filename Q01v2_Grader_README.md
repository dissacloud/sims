# Q01 v2 Grader — Usage

This grader outputs a kube-bench-like PASS/FAIL summary by checking:
- kubelet config YAML keys in /var/lib/kubelet/config.yaml
- etcd static pod args in /etc/kubernetes/manifests/etcd.yaml (controlplane only)

## Run on controlplane (includes etcd check)
```bash
sudo bash Q01v2_Grader.bash controlplane
```

## Run on worker node (kubelet checks only)
```bash
sudo bash Q01v2_Grader.bash node
```

Exit codes:
- 0 = all required checks passed
- 2 = one or more required checks failed
