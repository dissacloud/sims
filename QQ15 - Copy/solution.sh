#!/usr/bin/env bash
# Instructions only (do not run as a fix script)

cat <<'EOF'
REFERENCE SOLUTION (INSTRUCTIONS ONLY) — Q15 (Istio L4 mTLS STRICT)

1) Confirm Istio control plane is healthy:
   - istio-system namespace exists
   - istiod is running and has endpoints

2) Identify the target namespace:
   - The sim uses namespace: mtls

3) Enable revision-based sidecar injection for the target namespace:
   - This lab uses Istio revision-based injection via istio-revision-tag-default.
   - The namespace must have: istio.io/rev=default
   - The key istio-injection must NOT exist (remove it if present).

   Commands:
     kubectl label ns mtls istio.io/rev=default --overwrite
     kubectl label ns mtls istio-injection- --overwrite 2>/dev/null || true

4) Recreate workloads so existing pods receive sidecars:
   - Delete pods in mtls (fastest), then wait for new pods.

   Commands:
     kubectl -n mtls delete pod --all
     kubectl -n mtls get pods

5) Verify every pod in mtls has the istio-proxy sidecar:
   - Inspect pod container list; each pod must include "istio-proxy".

6) Enforce namespace-wide STRICT mTLS:
   - Create/update PeerAuthentication named "default" in namespace mtls with mtls.mode: STRICT.

7) Validate outcomes:
   - ./grader.sh
EOF
