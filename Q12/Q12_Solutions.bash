#!/usr/bin/env bash
# Q12_Solution.bash — Instructions-only solution guide (no destructive changes)
# Purpose: Provide step-by-step commands to complete Q12.
# Notes:
# - This script prints instructions; it does NOT apply manifest changes automatically.
# - Assumes lab setup wrote /root/.q12_target with: TARGET_VER|TARGET_IMAGE|TARGET_CONTAINER

set -euo pipefail

NS="alpine"
DEP="alpine"
MANIFEST="$HOME/alpine-deployment.yaml"
SPDX="$HOME/alpine.spdx"
STATE_FILE="/root/.q12_target"

echo "== Q12 Solution (Instructions) =="
echo "Namespace: $NS"
echo "Deployment: $DEP"
echo "Manifest:   $MANIFEST"
echo "Output:     $SPDX"
echo

if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: Missing $STATE_FILE"
  echo "Remediation: Re-run the lab setup script that creates Q12 target state."
  exit 2
fi

IFS='|' read -r TARGET_VER TARGET_IMAGE TARGET_CONTAINER < "$STATE_FILE"

echo "Target (from lab setup):"
echo "  libcrypto3 version: $TARGET_VER"
echo "  image:              $TARGET_IMAGE"
echo "  container name:     $TARGET_CONTAINER"
echo

cat <<'EOF'
------------------------------------------------------------
Step 0 — Sanity checks
------------------------------------------------------------
# Confirm bom works:
bom version

# Confirm the alpine pod exists and see the 3 containers:
kubectl -n alpine get pods -l app=alpine -o wide
POD=$(kubectl -n alpine get pod -l app=alpine -o jsonpath='{.items[0].metadata.name}')
kubectl -n alpine get pod "$POD" -o jsonpath='{.spec.containers[*].name}{"\n"}'

------------------------------------------------------------
Step 1 — Prove which container has the target libcrypto3 version
------------------------------------------------------------
# For each container, print libcrypto3 version (should match your target on ONE container):
POD=$(kubectl -n alpine get pod -l app=alpine -o jsonpath='{.items[0].metadata.name}')

for c in alpine-317 alpine-318 alpine-319; do
  echo "== $c =="
  kubectl -n alpine exec "$POD" -c "$c" -- sh -lc \
    'apk update >/dev/null 2>&1; apk info -v libcrypto3 | head -n1'
done

# Expected:
# - One container prints: libcrypto3-<TARGET_VER> (e.g. libcrypto3-3.1.8-r1)
# - That container is the one you must REMOVE from the deployment manifest.

------------------------------------------------------------
Step 2 — Generate SPDX SBOM for the TARGET IMAGE using bom
------------------------------------------------------------
# Use the image name, not the container name:
# (Replace <IMAGE> with the target image.)
# Create the SPDX Tag-Value SBOM and save it to ~/alpine.spdx

bom spdx <IMAGE> > ~/alpine.spdx

# Validate the file looks like SPDX:
head -n 30 ~/alpine.spdx
grep -nE 'SPDXVersion:|PackageName: libcrypto3|PackageVersion:' -n ~/alpine.spdx | head -n 50

------------------------------------------------------------
Step 3 — Remove the TARGET container from the Deployment manifest
------------------------------------------------------------
# Open the manifest:
vi ~/alpine-deployment.yaml

# In:
#   spec.template.spec.containers:
# remove ONLY the container block that corresponds to the target image/container.
# Keep the other containers unchanged.
#
# After editing, apply:
kubectl apply -f ~/alpine-deployment.yaml

# Wait for rollout:
kubectl -n alpine rollout status deploy/alpine --timeout=240s

# Confirm there are now exactly 2 containers in the pod:
POD=$(kubectl -n alpine get pod -l app=alpine -o jsonpath='{.items[0].metadata.name}')
kubectl -n alpine get pod "$POD" -o jsonpath='{.spec.containers[*].name}{"\n"}'

------------------------------------------------------------
Step 4 — Run the strict grader
------------------------------------------------------------
bash Q12_Grader_Strict_v3.bash

EOF

# Print target substitutions at the bottom for convenience
echo "------------------------------------------------------------"
echo "Convenience: your concrete target values"
echo "------------------------------------------------------------"
echo "TARGET_VER=$TARGET_VER"
echo "TARGET_IMAGE=$TARGET_IMAGE"
echo "TARGET_CONTAINER=$TARGET_CONTAINER"
echo
echo "So your SBOM command should be:"
echo "  bom spdx \"$TARGET_IMAGE\" > \"$SPDX\""
echo
echo "And in $MANIFEST you should remove the container named:"
echo "  $TARGET_CONTAINER"
