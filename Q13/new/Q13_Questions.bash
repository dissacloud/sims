#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
== Question 13 ==

Context:
For compliance, all user namespaces enforce the restricted Pod Security Standards.

Task:
- The "confidential" namespace contains a Deployment that is not compliant with the restricted Pod Security Standard.
  Thus, its Pods cannot be scheduled / become Running.
- Modify the Deployment to be compliant, and verify that the Pods are running.
- The Deployment & manifest file can be found at:
    ~/nginx-unprivileged.yaml

Constraints:
- Do not relax/disable Pod Security Admission.
- Make the workload compliant (restricted).

Additional requirement (important):
- Set readOnlyRootFilesystem: true for nginx.
- Define writable volumes + mounts for:
    /tmp
    /var/cache/nginx
  (nginx frequently fails at startup if these are not writable when rootfs is read-only)

EOF
