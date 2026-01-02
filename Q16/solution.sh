#!/usr/bin/env bash
# Instructions only (do not execute as a fix script)

cat <<'EOF'
REFERENCE SOLUTION (INSTRUCTIONS ONLY) — Q16 TLS Secret

1) Confirm the namespace exists and the Deployment already references a secret named "clever-cactus".
   - Do not edit the Deployment.

2) Create a TLS secret in namespace "clever-cactus" with name "clever-cactus" using:
   - cert: /home/candidate/clever-cactus/web k8s.local.crt
   - key:  /home/candidate/clever-cactus/web k8s.local.key

   Use kubectl create secret tls ... -n clever-cactus --cert="..." --key="..."

3) Verify the secret exists in the correct namespace and is type kubernetes.io/tls.

4) Wait for the Deployment pods to become Ready (the missing secret will unblock the mount).

5) Validate by checking pod status and optionally curling the service via port-forward.
EOF
