#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
CKS Simulation — Q15 (Istio L4 mTLS)

Context:
A microservices-based application uses unencrypted Layer 4 (L4) TCP transport and must be secured with Istio.

Task:
1) Ensure all Pods in the target namespace "mtls" have the istio-proxy sidecar injected.
2) Configure mutual authentication in STRICT mode for all workloads in namespace "mtls".

Notes / Traps:
- Namespace name is lowercase: mtls
- Decoy namespace exists: mtls-decoy (injection enabled — do NOT fix only this)
- Another decoy namespace exists: mtls1 (also injection enabled)
- A STRICT PeerAuthentication exists in istio-system (decoy — do NOT assume it solves mtls)
- The target namespace currently has PeerAuthentication/default set to PERMISSIVE; you must change it to STRICT

Validation expectation:
- Every Pod in mtls must have container "istio-proxy"
- PeerAuthentication/default in mtls must be STRICT
EOF
