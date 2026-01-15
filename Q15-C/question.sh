#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
CKS Simulation — Question 15 (Istio L4 mTLS — Classic Injection)

Context:
A microservices-based application using unencrypted Layer 4 (L4) transport must be secured with Istio.

Task:
1) Ensure all Pods in the target namespace "mtls" have the istio-proxy sidecar injected.
2) Configure mutual authentication in STRICT mode for all workloads in namespace "mtls".

Constraints / traps:
- Target namespace is lowercase: mtls
- Decoy namespaces exist: mtls-decoy and mtls1
- A decoy STRICT PeerAuthentication exists in istio-system (irrelevant to target)
- Target namespace currently has PeerAuthentication/default set to PERMISSIVE; change it to STRICT
EOF
