#!/usr/bin/env bash
set -euo pipefail

echo "== Q12 Lab Setup v4 — Deterministic Alpine + SBOM (installs bom wrapper) =="

NS="alpine"
MANIFEST="$HOME/alpine-deployment.yaml"
BACKUP="/root/cis-q12-backups-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP"

# -----------------------------
# Install syft, then provide a 'bom' wrapper compatible with the sim wording.
# -----------------------------

echo "[0] Ensuring 'syft' is installed (SBOM engine)..."
if ! command -v syft >/dev/null 2>&1; then
  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
fi

echo "[0.1] Ensuring 'bom' command exists (wrapper around syft)..."
if ! command -v bom >/dev/null 2>&1; then
  cat > /usr/local/bin/bom <<'EOF'
#!/usr/bin/env bash
# Minimal compatibility wrapper used by these sims.
# Supported:
#   bom version
#   bom packages <IMAGE>
#   bom spdx <IMAGE>      (prints SPDX Tag-Value to stdout)
# Notes:
# - Uses syft under the hood.
# - Keeps interface stable for exam-style tasks.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bom version
  bom packages <IMAGE>
  bom spdx <IMAGE>   # outputs SPDX Tag-Value
USAGE
}

cmd="${1:-}"
shift || true

case "$cmd" in
  version)
    syft version
    ;;
  packages)
    img="${1:-}"
    [[ -n "$img" ]] || { usage; exit 2; }
    syft packages "$img"
    ;;
  spdx)
    img="${1:-}"
    [[ -n "$img" ]] || { usage; exit 2; }
    # SPDX Tag-Value contains 'SPDXVersion: ...' which our graders look for.
    syft "$img" -o spdx-tag-value
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown subcommand: $cmd" >&2
    usage
    exit 2
    ;;
esac
EOF
  chmod +x /usr/local/bin/bom
fi

if ! command -v bom >/dev/null 2>&1; then
  echo "ERROR: bom still not available after install attempt." >&2
  echo "Diagnostics:" >&2
  command -v syft >/dev/null 2>&1 && echo "  syft: $(command -v syft)" >&2 || true
  echo "  PATH=$PATH" >&2
  exit 2
fi

echo "✅ bom available: $(command -v bom)"
bom version || true

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
  echo "ERROR: Neither 'docker' nor 'nerdctl' is available to build local images." >&2
  echo "Remediation: install nerdctl/buildkit or enable docker, then re-run." >&2
  exit 2
fi

echo "Build tool: $BUILD_TOOL"
echo "Backup dir: $BACKUP"

# -----------------------------
# Deterministic local images
# -----------------------------
WORKDIR="/root/q12-image-build"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/a" "$WORKDIR/b" "$WORKDIR/c"

write_df() {
  local dir="$1" base="$2" libcrypto_apk="$3" libssl_apk="$4"
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

ARCH="x86_64"

# TARGET image: libcrypto3=3.1.4-r5
BASE_A="alpine:3.19"
LIBCRYPTO_A="https://dl-cdn.alpinelinux.org/alpine/v3.19/main/${ARCH}/libcrypto3-3.1.4-r5.apk"
LIBSSL_A="https://dl-cdn.alpinelinux.org/alpine/v3.19/main/${ARCH}/libssl3-3.1.4-r5.apk"

# Non-target images
BASE_B="alpine:3.19"
LIBCRYPTO_B="https://dl-cdn.alpinelinux.org/alpine/v3.19/main/${ARCH}/libcrypto3-3.1.8-r1.apk"
LIBSSL_B="https://dl-cdn.alpinelinux.org/alpine/v3.19/main/${ARCH}/libssl3-3.1.8-r1.apk"

BASE_C="alpine:3.20"
LIBCRYPTO_C="https://dl-cdn.alpinelinux.org/alpine/v3.20/main/${ARCH}/libcrypto3-3.3.5-r0.apk"
LIBSSL_C="https://dl-cdn.alpinelinux.org/alpine/v3.20/main/${ARCH}/libssl3-3.3.5-r0.apk"

write_df "$WORKDIR/a" "$BASE_A" "$LIBCRYPTO_A" "$LIBSSL_A"
write_df "$WORKDIR/b" "$BASE_B" "$LIBCRYPTO_B" "$LIBSSL_B"
write_df "$WORKDIR/c" "$BASE_C" "$LIBCRYPTO_C" "$LIBSSL_C"

echo "[1] Building local images..."
$BUILD_TOOL build -t q12-alpine:a "$WORKDIR/a"
$BUILD_TOOL build -t q12-alpine:b "$WORKDIR/b"
$BUILD_TOOL build -t q12-alpine:c "$WORKDIR/c"

echo "✅ Images built: q12-alpine:a (TARGET), q12-alpine:b, q12-alpine:c"

# Quick sanity check for the target version via bom
if bom packages q12-alpine:a 2>/dev/null | grep -q "libcrypto3.*3.1.4-r5"; then
  echo "✅ Sanity check passed: q12-alpine:a contains libcrypto3=3.1.4-r5"
else
  echo "⚠️  Sanity check could not confirm libcrypto3=3.1.4-r5 via bom." >&2
  echo "    This can happen if image inspection is restricted on your runtime." >&2
  echo "    The task can still proceed, but graders may fail if bom cannot inspect images." >&2
fi

echo
# -----------------------------
# Create namespace + Deployment manifest
# -----------------------------

echo "[2] Creating namespace + deployment manifest..."
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"

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

kubectl apply -f "$MANIFEST"

echo
kubectl -n "$NS" rollout status deploy/alpine --timeout=180s || true
kubectl -n "$NS" get pods -o wide

echo
echo "Manifest location: $MANIFEST"
echo "Backup copy:       $BACKUP/alpine-deployment.yaml.original"
echo
echo "✅ Q12 v4 environment ready (deterministic + bom available)."
