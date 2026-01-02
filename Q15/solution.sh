#!/usr/bin/env bash
# Instructions only (do not run as a fix script)

cat <<'EOF'
REFERENCE SOLUTION (INSTRUCTIONS ONLY) — Q15 (Istio L4 mTLS STRICT)

1) Confirm Istio is installed and control plane is healthy:
   - istio-system namespace exists
   - istiod is running

2) Identify the target namespace:
   - The sim uses namespace: mtls

3) Ensure sidecar injection is enabled for the target namespace:
   - Label the namespace for auto-injection (istio-injection=enabled), OR use revision label if your Istio uses revisions.
   - Do not label only the decoy namespace.

4) Restart/recreate workloads in the namespace so that existing pods receive sidecars:
   - Rollout restart deployments (or delete pods) in mtls.
   - Wait for new pods to become Running.

5) Verify every pod in mtls has the istio-proxy sidecar:
   - Inspect pod container list: each pod should include "istio-proxy".

6) Enforce namespace-wide STRICT mTLS:
   - Create/update PeerAuthentication named "default" in namespace mtls with mtls.mode: STRICT.

7) Validate outcomes:
   - Sidecar exists on all pods in mtls.
   - PeerAuthentication/default in mtls is STRICT.
   - Kubernetes nodes remain Ready.

Then run: ./grader.sh
EOF
