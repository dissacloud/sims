# Question 4 — Dockerfile + Deployment Security Best Practices

## Task

### A) Dockerfile
Analyze and edit the Dockerfile located at:
- `~/subtle-bee/build/Dockerfile`

Fix **one instruction** present in the file that is a prominent security best-practice issue.

Constraints:
- Do **not** add or remove instructions
- Only modify the **one existing instruction** with a security best-practice concern
- Do **not** build the Dockerfile (storage constraints; building may result in a zero score)
- If you need an unprivileged user, use `nobody` with UID `65535`

### B) Kubernetes manifest
Analyze and edit the manifest file located at:
- `~/subtle-bee/deployment.yaml`

Fix **one field** present in the file that is a prominent security best-practice issue.

Constraints:
- Do **not** add or remove fields
- Only modify the **one existing field** with a security best-practice concern
- If you need an unprivileged user, use `nobody` with UID `65535`

## Hint
A simulated findings report exists at:
- `/root/kube-bench-report-q04.txt`
