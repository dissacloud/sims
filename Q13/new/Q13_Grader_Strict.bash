#!/usr/bin/env bash
# Q13 STRICT Grader — restricted PSA compliance + runtime correctness
set -euo pipefail
trap '' PIPE

NS="confidential"
DEP="nginx-unprivileged"
APP_LABEL="nginx-unprivileged"
MANIFEST="$HOME/nginx-unprivileged.yaml"

pass=0; fail=0; warn=0
results=()

add_pass(){ results+=("[PASS] $1"); pass=$((pass+1)); }
add_fail(){ results+=("[FAIL] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); fail=$((fail+1)); }
add_warn(){ results+=("[WARN] $1"$'\n'"       * Reason: $2"$'\n'"       * Remediation: $3"); warn=$((warn+1)); }

k(){ kubectl "$@"; }

echo "== Q13 STRICT Grader =="
echo "Date: $(date -Is)"
echo

if k get ns "$NS" >/dev/null 2>&1; then
  add_pass "Namespace $NS exists"
else
  add_fail "Namespace $NS exists" "Namespace missing" "kubectl create ns $NS"
fi

if k get ns "$NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null | grep -qx 'restricted'; then
  add_pass "Namespace enforces PodSecurity restricted"
else
  add_fail "Namespace enforces PodSecurity restricted" "pod-security.kubernetes.io/enforce is not 'restricted'" "kubectl label ns $NS pod-security.kubernetes.io/enforce=restricted --overwrite"
fi

if k -n "$NS" get deploy "$DEP" >/dev/null 2>&1; then
  add_pass "Deployment $DEP exists"
else
  add_fail "Deployment $DEP exists" "Deployment missing" "kubectl -n $NS apply -f $MANIFEST"
fi

POD="$(k -n "$NS" get pod -l app="$APP_LABEL" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "$POD" ]]; then
  add_pass "Pod exists ($POD)"
else
  if k -n "$NS" get rs -l app="$APP_LABEL" >/dev/null 2>&1; then
    add_fail "Pod exists" "No pod created; likely still blocked by restricted PSA (see ReplicaSet events)" "Fix securityContext fields in ~/nginx-unprivileged.yaml and re-apply"
  else
    add_fail "Pod exists" "No ReplicaSet/Pod found for label app=$APP_LABEL" "kubectl -n $NS get deploy,rs,pods; ensure labels match"
  fi
fi

if [[ -n "$POD" ]]; then
  PHASE="$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  READY="$(k -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)"
  if [[ "$PHASE" == "Running" && "$READY" == "true" ]]; then
    add_pass "Pod is Running and Ready"
  else
    add_fail "Pod is Running and Ready" "Pod phase=$PHASE ready=$READY" "kubectl -n $NS describe pod $POD; fix PSA fields and runtime writable mounts for RO rootfs"
  fi
fi

if [[ -n "$POD" ]]; then
  IMG="$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[?(@.name=="nginx")].image}' 2>/dev/null || true)"
  if [[ "$IMG" == "nginxinc/nginx-unprivileged:1.25-alpine" ]]; then
    add_pass "Uses correct image nginxinc/nginx-unprivileged:1.25-alpine"
  else
    add_fail "Uses correct image nginxinc/nginx-unprivileged:1.25-alpine" "Found image='$IMG'" "Set container image to nginxinc/nginx-unprivileged:1.25-alpine"
  fi

  PORT="$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[?(@.name=="nginx")].ports[0].containerPort}' 2>/dev/null || true)"
  if [[ "$PORT" == "8080" ]]; then
    add_pass "Container port is 8080"
  else
    add_fail "Container port is 8080" "Found containerPort='$PORT'" "Set containerPort: 8080"
  fi
fi

if [[ -n "$POD" ]]; then
  RUN_AS_NON_ROOT="$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.securityContext.runAsNonRoot}' 2>/dev/null || true)"
  SECCOMP="$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.securityContext.seccompProfile.type}' 2>/dev/null || true)"
  if [[ "$RUN_AS_NON_ROOT" == "true" ]]; then
    add_pass "Pod securityContext.runAsNonRoot=true"
  else
    add_fail "Pod securityContext.runAsNonRoot=true" "Found runAsNonRoot='$RUN_AS_NON_ROOT'" "Set spec.template.spec.securityContext.runAsNonRoot: true"
  fi
  if [[ "$SECCOMP" == "RuntimeDefault" || "$SECCOMP" == "Localhost" ]]; then
    add_pass "Pod seccompProfile.type is RuntimeDefault/Localhost"
  else
    add_fail "Pod seccompProfile.type is RuntimeDefault/Localhost" "Found seccompProfile.type='$SECCOMP'" "Set spec.template.spec.securityContext.seccompProfile.type: RuntimeDefault"
  fi

  APE="$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[?(@.name=="nginx")].securityContext.allowPrivilegeEscalation}' 2>/dev/null || true)"
  RO="$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[?(@.name=="nginx")].securityContext.readOnlyRootFilesystem}' 2>/dev/null || true)"
  UID="$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[?(@.name=="nginx")].securityContext.runAsUser}' 2>/dev/null || true)"
  GID="$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[?(@.name=="nginx")].securityContext.runAsGroup}' 2>/dev/null || true)"
  DROPS="$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[?(@.name=="nginx")].securityContext.capabilities.drop[*]}' 2>/dev/null || true)"
  ADDS="$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[?(@.name=="nginx")].securityContext.capabilities.add[*]}' 2>/dev/null || true)"

  if [[ "$APE" == "false" ]]; then
    add_pass "allowPrivilegeEscalation=false"
  else
    add_fail "allowPrivilegeEscalation=false" "Found allowPrivilegeEscalation='$APE'" "Set container securityContext.allowPrivilegeEscalation: false"
  fi

  if [[ "$RO" == "true" ]]; then
    add_pass "readOnlyRootFilesystem=true"
  else
    add_fail "readOnlyRootFilesystem=true" "Found readOnlyRootFilesystem='$RO'" "Set container securityContext.readOnlyRootFilesystem: true"
  fi

  if [[ -n "$UID" && "$UID" != "0" && -n "$GID" && "$GID" != "0" ]]; then
    add_pass "runAsUser/runAsGroup are non-root (UID=$UID GID=$GID)"
  else
    add_fail "runAsUser/runAsGroup are non-root" "Found UID='$UID' GID='$GID'" "Set container securityContext.runAsUser and runAsGroup to non-zero values (e.g. 101)"
  fi

  if echo " $DROPS " | grep -q " ALL "; then
    add_pass "capabilities.drop includes ALL"
  else
    add_fail "capabilities.drop includes ALL" "Found drop='$DROPS'" "Set container securityContext.capabilities.drop: ["ALL"]"
  fi

  if [[ -n "$ADDS" ]]; then
    add_fail "No added capabilities" "Found capabilities.add='$ADDS'" "Remove capabilities.add and keep drop: ["ALL"]"
  else
    add_pass "No added capabilities"
  fi

  TMP_MOUNT="$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[?(@.name=="nginx")].volumeMounts[?(@.mountPath=="/tmp")].name}' 2>/dev/null || true)"
  CACHE_MOUNT="$(k -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[?(@.name=="nginx")].volumeMounts[?(@.mountPath=="/var/cache/nginx")].name}' 2>/dev/null || true)"

  if [[ -n "$TMP_MOUNT" ]]; then
    add_pass "Writable /tmp mount present (volumeMount name=$TMP_MOUNT)"
  else
    add_fail "Writable /tmp mount present" "No volumeMount for /tmp detected" "Add emptyDir volume + mountPath: /tmp"
  fi

  if [[ -n "$CACHE_MOUNT" ]]; then
    add_pass "Writable /var/cache/nginx mount present (volumeMount name=$CACHE_MOUNT)"
  else
    add_fail "Writable /var/cache/nginx mount present" "No volumeMount for /var/cache/nginx detected" "Add emptyDir volume + mountPath: /var/cache/nginx"
  fi

  if [[ -n "$TMP_MOUNT" ]]; then
    TMP_VOL="$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.volumes[?(@.name==\"$TMP_MOUNT\")].emptyDir}" 2>/dev/null || true)"
    if [[ -n "$TMP_VOL" ]]; then add_pass "Volume for /tmp is emptyDir"; else add_fail "Volume for /tmp is emptyDir" "Volume '$TMP_MOUNT' is not emptyDir" "Define spec.volumes: - name: $TMP_MOUNT emptyDir: {}"; fi
  fi

  if [[ -n "$CACHE_MOUNT" ]]; then
    CACHE_VOL="$(k -n "$NS" get pod "$POD" -o jsonpath="{.spec.volumes[?(@.name==\"$CACHE_MOUNT\")].emptyDir}" 2>/dev/null || true)"
    if [[ -n "$CACHE_VOL" ]]; then add_pass "Volume for /var/cache/nginx is emptyDir"; else add_fail "Volume for /var/cache/nginx is emptyDir" "Volume '$CACHE_MOUNT' is not emptyDir" "Define spec.volumes: - name: $CACHE_MOUNT emptyDir: {}"; fi
  fi
fi

echo
for r in "${results[@]}"; do
  echo "$r"
  echo
done

echo "== Summary =="
echo "${pass} PASS"
echo "${warn} WARN"
echo "${fail} FAIL"

[[ "$fail" -eq 0 ]]
