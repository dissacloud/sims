#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
CKS Simulation — Question 15 (Istio L4 mTLS)

Context:
A microservices-based application using unencrypted Layer 4 (L4) transport must be secured with Istio.

Task:
- Ensure that all Pods in the "mTLS namespace" have the istio-proxy sidecar injected.
- Configure mutual authentication in STRICT mode for all workloads in that mTLS namespace.

Constraints / traps:
- The real namespace name is lowercase: mtls
- A decoy namespace exists with injection already enabled: mtls-decoy (do NOT fix only this)
- Another “looks-correct” namespace name variant exists: mtls1
- A decoy STRICT PeerAuthentication exists in istio-system (do NOT apply STRICT there and assume it’s done)
- The target namespace currently has PeerAuthentication set to PERMISSIVE; you must change it to STRICT
EOF
