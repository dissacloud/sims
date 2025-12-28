#!/usr/bin/env bash
# Q10 Solution Notes — ServiceAccount Token Hardening
# Use as reference after attempting the question.

set -euo pipefail

NS="monitoring"
SA="stats-monitor-sa"
DEPLOY="stats-monitor"

echo "== Q10 Solution Notes =="
echo "Namespace: ${NS}"
echo

echo "1) Disable ServiceAccount token automount:"
echo "kubectl -n ${NS} patch sa ${SA} -p '{"automountServiceAccountToken":false}'"
echo

echo "2) Edit Deployment to inject projected SA token:"
cat <<'YAML'

# Add under spec.template.spec:
volumes:
- name: token
  projected:
    sources:
    - serviceAccountToken:
        path: token
        expirationSeconds: 3600

# Add under the container spec (spec.template.spec.containers[0]):
volumeMounts:
- name: token
  mountPath: /var/run/secrets/kubernetes.io/serviceaccount
  readOnly: true

# This results in the token being available at:
# /var/run/secrets/kubernetes.io/serviceaccount/token

YAML
echo

echo "3) Apply your updated manifest:"
echo "kubectl -n ${NS} apply -f <your-file>.yaml"
echo

echo "4) Validate:"
echo "kubectl -n ${NS} get sa ${SA} -o yaml | grep -i automountServiceAccountToken"
echo "kubectl -n ${NS} get deploy ${DEPLOY} -o yaml | egrep -n 'projected:|serviceAccountToken:|name: token|mountPath: /var/run/secrets/kubernetes.io/serviceaccount|readOnly: true'"
echo

echo "5) Run the grader:"
echo "bash Q10_Grader_Auto.bash"
