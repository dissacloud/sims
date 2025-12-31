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

Hints (what restricted typically requires):
- runAsNonRoot: true (and set runAsUser/runAsGroup to a non-zero UID/GID)
- allowPrivilegeEscalation: false
- drop ALL Linux capabilities
- seccompProfile: RuntimeDefault
- avoid privileged / hostPath / hostNetwork, etc.

EOF
