# Question 7 — API Server Auditing (kubeadm static pod)

## Context
You must implement auditing for the kubeadm provisioned cluster.

A basic audit policy exists at:
- `/etc/kubernetes/logpolicy/audit-policy.yaml`

## Tasks

### 1) Reconfigure the cluster API server so that:
- the policy at `/etc/kubernetes/logpolicy/audit-policy.yaml` is used
- logs are stored at `/var/log/kubernetes/audit-logs.txt`
- a maximum of **2** audit log files are retained
- logs are retained for **10 days**

The cluster uses Docker Engine as the container runtime. You may use `docker` for troubleshooting if needed.

### 2) Extend the basic policy to log:
- namespace interactions at **RequestResponse** level
- the **request body** of **deployments** interactions in namespace **webapps**
- ConfigMap and Secret interactions in all namespaces at the **Metadata** level
- all other requests at the **Metadata** level

Make sure the API server uses the extended policy.
