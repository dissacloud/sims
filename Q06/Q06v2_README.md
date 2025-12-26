# Q06 v2 — Clean-running workload

This v2 setup uses `hashicorp/http-echo` instead of nginx so that once you apply:
- runAsUser: 20000
- readOnlyRootFilesystem: true
- allowPrivilegeEscalation: false

the Pod remains Running (no write attempts to /etc or /var/cache).

Use the existing Q06 grader (`Q06_Grader_Auto.bash`) unchanged.
