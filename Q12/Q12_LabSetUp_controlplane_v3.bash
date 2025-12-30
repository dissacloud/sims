#!/usr/bin/env bash
set -euo pipefail

echo "== Q12 Lab Setup v3 — Deterministic Alpine + SBOM (installs bom) =="

NS="alpine"
MANIFEST="$HOME/alpine-deployment.yaml"
BACKUP="/root/cis-q12-backups-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP"

# -----------------------------
# Ensure 'bom' tool is present (via Anchore Syft)
# -----------------------------
echo "[0] Ensuring 'bom' is installed (syft)..."
if ! command -v bom >/dev/null 2>&1; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl not found; cannot install bom."
    echo "Remediation: install curl or pre-stage bom/syft, then re-run."
    exit 2
  fi
  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
    | sh -s -- -b /usr/local/bin >/dev/null
fi

if command -v bom >/dev/null 2>&1; then
  echo "✅ bom installed: $(command -v bom)"
  bom version >/dev/null 2>&1 || true
else
  echo "ERROR: bom still not available after install attempt."
  exit 2
fi
echo

# -----------------------------
# Build tool detection
# -----------------------------
BUILD_TOOL=""
if command -v docker >/dev/null 2>&1; then
  BUILD_TOOL="docker"
elif command -v nerdctl >/dev/null 2>&1; then
  BUILD_TOOL="nerdctl"
else
  echo "ERROR: Neither 'docker' nor 'nerdctl' is available to build local images."
  echo "Remediation options:"
  echo "  - Install nerdctl/buildkit OR enable docker, then re-run."
  exit 2
fi

echo "[1] Build tool: $BUILD_TOOL"
echo "    Backup dir: $BACKUP"
echo

# -----------------------------
# Deterministic local images
# -----------------------------
# Goal: create 3 local images:
# - q12-alpine:a -> contains libcrypto3=3.1.4-r5 (TARGET)
# - q12-alpine:b -> contains libcrypto3=3.1.8-r1 (non-target)
# - q12-alpine:c -> contains libcrypto3=3.3.5-r0 (non-target)
#
# We install exact APKs from direct URLs (not from 'apk update' indexes) to avoid repo drift.
# This assumes x86_64. If your lab is arm64, change ARCH to aarch64 and update URLs.
# -----------------------------

WORKDIR="/root/q12-image-build"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/a" "$WORKDIR/b" "$WORKDIR/c"

ARCH="${ARCH:-x86_64}"

write_df() {
  local dir="$1"
  local base="$2"
  local libcrypto_apk="$3"
  local libssl_apk="$4"

  cat > "${dir}/Dockerfile" <<EOF
FROM ${base}
RUN set -eux; \
    apk add --no-cache ca-certificates wget; \
    wget -q -O /tmp/libcrypto.apk "${libcrypto_apk}"; \
    wget -q -O /tmp/libssl.apk "${libssl_apk}"; \
    apk add --allow-untrusted /tmp/libcrypto.apk /tmp/libssl.apk; \
    rm -f /tmp/libcrypto.apk /tmp/libssl.apk; \
    apk info -v libcrypto3 | tee /libcrypto3.version
CMD ["sleep","3600"]
EOF
}

BASE_A="alpine:3.19"
LIBCRYPTO_A="https://dl-cdn.alpinelinux.org/alpine/v3.19/main/${ARCH}/libcrypto3-3.1.4-r5.apk"
LIBSSL_A="https://dl-cdn.alpinelinux.org/alpine/v3.19/main/${ARCH}/libssl3-3.1.4-r5.apk"

BASE_B="alpine:3.19"
LIBCRYPTO_B="https://dl-cdn.alpinelinux.org/alpine/v3.19/main/${ARCH}/libcrypto3-3.1.8-r1.apk"
LIBSSL_B="https://dl-cdn.alpinelinux.org/alpine/v3.19/main/${ARCH}/libssl3-3.1.8-r1.apk"

BASE_C="alpine:3.20"
LIBCRYPTO_C="https://dl-cdn.alpinelinux.org/alpine/v3.20/main/${ARCH}/libcrypto3-3.3.5-r0.apk"
LIBSSL_C="https://dl-cdn.alpinelinux.org/alpine/v3.20/main/${ARCH}/libssl3-3.3.5-r0.apk"

write_df "$WORKDIR/a" "$BASE_A" "$LIBCRYPTO_A" "$LIBSSL_A"
write_df "$WORKDIR/b" "$BASE_B" "$LIBCRYPTO_B" "$LIBSSL_B"
write_df "$WORKDIR/c" "$BASE_C" "$LIBCRYPTO_C" "$LIBSSL_C"

echo "[2] Building deterministic local images..."
$BUILD_TOOL build -t q12-alpine:a "$WORKDIR/a"
$BUILD_TOOL build -t q12-alpine:b "$WORKDIR/b"
$BUILD_TOOL build -t q12-alpine:c "$WORKDIR/c"
echo "✅ Images built: q12-alpine:a (TARGET), q12-alpine:b, q12-alpine:c"
echo

echo "[3] Creating namespace + deployment manifest..."
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS" >/dev/null

cat <<'YAML' > "$MANIFEST"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alpine
  namespace: alpine
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alpine
  template:
    metadata:
      labels:
        app: alpine
    spec:
      containers:
      - name: alpine-a
        image: q12-alpine:a
        imagePullPolicy: IfNotPresent
        command: ["sleep","3600"]
      - name: alpine-b
        image: q12-alpine:b
        imagePullPolicy: IfNotPresent
        command: ["sleep","3600"]
      - name: alpine-c
        image: q12-alpine:c
        imagePullPolicy: IfNotPresent
        command: ["sleep","3600"]
YAML

cp -f "$MANIFEST" "$BACKUP/alpine-deployment.yaml.original"

kubectl apply -f "$MANIFEST" >/dev/null

echo
echo "[4] Verifying rollout..."
kubectl -n "$NS" rollout status deploy/alpine --timeout=180s >/dev/null 2>&1 || true
kubectl -n "$NS" get pods -o wide

echo
echo "[5] Sanity check (image-based): which image contains libcrypto3=3.1.4-r5 ?"
if bom packages q12-alpine:a 2>/dev/null | grep -q "libcrypto3.*3.1.4-r5"; then
  echo "✅ q12-alpine:a contains libcrypto3=3.1.4-r5 (TARGET)"
else
  echo "⚠️  Could not confirm via 'bom packages q12-alpine:a'."
  echo "    Remediation: run manually: bom packages q12-alpine:a | grep libcrypto3"
fi

echo
echo "Manifest location:"
echo "  $MANIFEST"
echo "Backup copy:"
echo "  $BACKUP/alpine-deployment.yaml.original"
echo
echo "✅ Q12 v3 environment ready."
