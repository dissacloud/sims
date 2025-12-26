# Question 2 — Secure the Kubernetes API Server (kubeadm)

## Context
For testing purposes, the kubeadm-provisioned cluster’s API Server was configured to allow unauthenticated and unauthorized access.

A (simulated) kube-bench report is available at:
- `/root/kube-bench-report-q02.txt`

## Task

### 1) Secure the cluster’s API server by configuring:
- Forbid anonymous authentication
- Use authorization mode: `Node,RBAC`
- Use admission controller: `NodeRestriction`

### 2) Notes / Constraints
- The cluster uses the Docker Engine as its container runtime. If needed, use `docker` to troubleshoot running containers.
- `kubectl` is currently configured to use unauthenticated and unauthorized access.
  - You do **not** have to change it first, but be aware that `kubectl` will stop working once you have secured the cluster.
- You can use the cluster’s original kubectl configuration file located at:
  - `/etc/kubernetes/admin.conf`
  to access the secured cluster.

### 3) Cleanup
- Remove the ClusterRoleBinding `system-anonymous`.

## Success Criteria
- kube-apiserver is secured as required (anonymous disabled, Node+RBAC authorization, NodeRestriction enabled)
- `system-anonymous` ClusterRoleBinding no longer exists
- API server is healthy after changes (static pod restarted)
