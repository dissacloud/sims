#!/usr/bin/env bash
cat <<'TXT'
Question 8 — NetworkPolicies across namespaces

Context
You must implement NetworkPolicies controlling the traffic flow of existing deployments across namespaces.

Task
1) Create a NetworkPolicy named deny-policy in the prod namespace to block all ingress traffic.
   - The prod namespace is labeled: env=prod

2) Create a NetworkPolicy named allow-from-prod in the data namespace to allow ingress traffic ONLY from Pods in the prod namespace.
   - Use the label of the prod namespace to allow traffic (namespaceSelector).
   - The data namespace is labeled: env=data

Rules
- Do NOT modify or delete any namespaces or Pods.
- Only create the required NetworkPolicies.

Hints
- Ingress is denied for selected pods when ANY NetworkPolicy selecting those pods exists and does not allow the traffic.
- For a 'deny all ingress' policy: podSelector: {} and policyTypes: [Ingress] with no ingress rules.
- For 'allow only from prod': podSelector: {} and ingress.from.namespaceSelector.matchLabels.env=prod

Validation (what the grader checks)
- deny-policy exists in prod and blocks ingress
- allow-from-prod exists in data and allows ingress only from namespace env=prod
- Functional tests:
  - prod-tester -> data-web should SUCCEED
  - dev-tester  -> data-web should FAIL
  - dev-tester  -> prod-web should FAIL (due to deny-policy)
TXT
