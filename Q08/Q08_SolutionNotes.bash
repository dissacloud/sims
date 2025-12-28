#!/usr/bin/env bash
cat <<'TXT'
Q08 — Solution Notes (reference)

1) Deny all ingress in prod

kubectl -n prod apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-policy
  namespace: prod
spec:
  podSelector: {}
  policyTypes:
  - Ingress
YAML

2) Allow ingress to data ONLY from prod namespace (env=prod)

kubectl -n data apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-prod
  namespace: data
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          env: prod
YAML

3) Verify quickly

kubectl get netpol -n prod
kubectl get netpol -n data

# should succeed
kubectl -n prod exec prod-tester -- wget -qO- --timeout=2 http://data-web.data.svc.cluster.local >/dev/null && echo OK

# should fail
kubectl -n dev exec dev-tester -- wget -qO- --timeout=2 http://data-web.data.svc.cluster.local >/dev/null && echo "UNEXPECTED" || echo "DENIED (expected)"

# should fail
kubectl -n dev exec dev-tester -- wget -qO- --timeout=2 http://prod-web.prod.svc.cluster.local >/dev/null && echo "UNEXPECTED" || echo "DENIED (expected)"
TXT
