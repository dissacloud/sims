#!/usr/bin/env bash
# Q12 Solution (instructions) — prints the command sequence to perform the task.

set -euo pipefail

cat <<'EOF'
========================
Q12 — Suggested Solution
========================

0) Set context
-------------
export NS=alpine
export DEP=alpine

1) Locate the Pod and list its containers
----------------------------------------
kubectl -n $NS get deploy $DEP
POD="$(kubectl -n $NS get pod -l app=alpine -o jsonpath='{.items[0].metadata.name}')"
echo "Pod: $POD"
kubectl -n $NS get pod "$POD" -o jsonpath='{.spec.containers[*].name}{"\n"}'

2) Check libcrypto3 version in each container
---------------------------------------------
# Run this for each container name you saw above:
for c in $(kubectl -n $NS get pod "$POD" -o jsonpath='{.spec.containers[*].name}'); do
  echo "== $c =="
  kubectl -n $NS exec "$POD" -c "$c" -- sh -lc 'apk update >/dev/null 2>&1; apk info -v libcrypto3 2>/dev/null || echo "libcrypto3 not installed"'
done

# Identify which container prints:
#   libcrypto3-3.1.4-r5

3) Generate SPDX for the IDENTIFIED image using bom
---------------------------------------------------
# Confirm bom works:
bom help || true

# Determine the IMAGE used by the identified container (replace CONTAINER_NAME):
CONTAINER_NAME="<REPLACE_WITH_IDENTIFIED_CONTAINER>"
IMG="$(kubectl -n $NS get deploy $DEP -o jsonpath='{.spec.template.spec.containers[?(@.name=="'"$CONTAINER_NAME"'")].image}')"
echo "Identified image: $IMG"

# Generate SPDX Tag-Value to ~/alpine.spdx:
bom spdx "$IMG" > "$HOME/alpine.spdx"

# Validate file:
test -s "$HOME/alpine.spdx" && head -n 5 "$HOME/alpine.spdx"

4) Remove the identified container from the Deployment
------------------------------------------------------
vi "$HOME/alpine-deployment.yaml"

# Delete ONLY the container block for the identified container.
# Do NOT change the other containers (names/images/commands).

kubectl apply -f "$HOME/alpine-deployment.yaml"
kubectl -n $NS rollout status deploy/$DEP --timeout=180s

# Confirm only 2 containers remain:
POD2="$(kubectl -n $NS get pod -l app=alpine -o jsonpath='{.items[0].metadata.name}')"
kubectl -n $NS get pod "$POD2" -o jsonpath='{.spec.containers[*].name}{"\n"}'

5) Quick re-check (remaining containers must NOT be the 3.1.4-r5 one)
---------------------------------------------------------------------
for c in $(kubectl -n $NS get pod "$POD2" -o jsonpath='{.spec.containers[*].name}'); do
  echo "== $c =="
  kubectl -n $NS exec "$POD2" -c "$c" -- sh -lc 'apk info -v libcrypto3 2>/dev/null || true'
done
EOF
