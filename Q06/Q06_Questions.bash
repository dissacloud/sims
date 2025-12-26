# Question 6 — Validate Pod Immutability (securityContext)

## Context
You must validate an existing Pod to ensure the immutability of its containers.

## Task
Modify the existing Deployment **lamp-deployment**, running in namespace **lamp**, so that its containers:

- run with user ID **20000**
- use a **read-only root filesystem**
- **forbid privilege escalation**

The deployment manifest file can be found at:
- `~/finer-sunbeam/lamp-deployment.yaml`

## Constraints
- Modify the existing Deployment (apply changes so the running pods reflect the new configuration).
