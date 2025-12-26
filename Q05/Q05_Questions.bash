# Question 5 — Misbehaving Pod Containment

## Context
A Pod is misbehaving and poses a security threat to the system.

One of the Pods belonging to the application **ollama** is misbehaving; it is directly accessing the system's memory by reading from the sensitive file:
- `/dev/mem`

A simulated findings report exists at:
- `/root/kube-bench-report-q05.txt`

The cluster uses the Docker Engine as its container runtime. If needed, use `docker` to troubleshoot running containers.

## Task
1. Identify the misbehaving Pod accessing `/dev/mem`.
2. Identify the Deployment managing the misbehaving Pod and **scale it to zero replicas**.
3. Do not modify the Deployment except for scaling it down.
4. Do not modify any other Deployments.
5. Do not delete any Deployments.
