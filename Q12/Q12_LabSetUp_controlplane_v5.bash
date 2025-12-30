#!/usr/bin/env bash
set -euo pipefail

echo "== Q12 Lab Setup v5 — Deterministic Alpine + SBOM (syft + bom wrapper) =="

NS="alpine"
MANIFEST="$HOME/alpine-deployment.yaml"
BACKUP="/root/cis-q12-backups-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP"

# -----------------------------
# [0] Install syft + provide `bom` wrapper
# -----------------------------
echo "[0] Ensuring 'syft' is installed (SBOM engine)..."
if ! command -v syft >/dev/null 2>&1; then
  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
fi
echo "✅ syft available: $(command -v syft)"

echo "[0.1] Ensuring 'bom' command exists (wrapper around syft)..."
if ! command -v bom >/dev/null 2>&1; then
  cat >/usr/local/bin/bom <<'BOM'
#!/usr/bin/env bash
set -euo pipefail
usage() {
  cat <<'EOF'
Usage:
  bom version
  bom packages <IMAGE>
  bom spdx <IMAGE>   # SPDX Tag-Value to stdout
EOF
}
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then usage; exit 0; fi
cmd="${1:-}"; img="${2:-}"
case "$cmd" in
  version) exec syft version ;;
  packages) [[ -n "$img" ]] || { usage; exit 2; }; exec syft packages "$img" ;;
  spdx) [[ -n "$img" ]] || { usage; exit 2; }; exec syft "$img" -o spdx-tag-value ;;
  *) usage; exit 2 ;;
esac
BOM
  chmod +x /usr/local/bin/bom
fi
command -v bom >/dev/null 2>&1 || { echo "ERROR: bom still not available after wrapper install attempt."; exit 2; }
echo "✅ bom available: $(command -v bom)"
echo

# -----------------------------
# [1] Build tool detection
# -----------------------------
if command -v docker >/dev/null 2>&1; then
  BUILD_TOOL="docker"
elif command -v nerdctl >/dev/null 2>&1; then
  BUILD_TOOL="nerdctl"
else
  echo "ERROR: Neither 'docker' nor 'nerdctl' is available to build local images."
  exit 2
fi
echo "Build tool: ${BUILD_TOOL}"
echo "Backup dir: ${BACKUP}"
echo

# -----------------------------
# [2] Resolve deterministic APK URLs (avoid mirror drift)
# -----------------------------
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 2; }; }
need curl

ARCH_UNAME="$(uname -m)"
case "${ARCH_UNAME}" in
  x86_64|amd64) APK_ARCH="x86_64" ;;
  aarch64|arm64) APK_ARCH="aarch64" ;;
  *) echo "ERROR: Unsupported arch: ${ARCH_UNAME}"; exit 2 ;;
esac

ALPINE_MIRROR_BASE="${ALPINE_MIRROR_BASE:-https://dl-cdn.alpinelinux.org/alpine}"

url_exists() { curl -fsI --max-time 10 "$1" >/dev/null 2>&1; }

resolve_apk() {
  local pkgfile="$1"
  local -a branches=("v3.19" "v3.18" "v3.20" "v3.17")
  local -a repos=("main" "community")
  for b in "${branches[@]}"; do
    for r in "${repos[@]}"; do
      local u="${ALPINE_MIRROR_BASE}/${b}/${r}/${APK_ARCH}/${pkgfile}"
      if url_exists "$u"; then
        echo "$u"
        return 0
      fi
    done
  done
  return 1
}

TARGET_LIBCRYPTO="libcrypto3-3.1.4-r5.apk"
TARGET_LIBSSL="libssl3-3.1.4-r5.apk"

ALT1_LIBCRYPTO="libcrypto3-3.1.8-r1.apk"
ALT1_LIBSSL="libssl3-3.1.8-r1.apk"

ALT2_LIBCRYPTO="libcrypto3-3.3.5-r0.apk"
ALT2_LIBSSL="libssl3-3.3.5-r0.apk"

echo "[2] Resolving APK URLs..."
LIBCRYPTO_A_URL="${LIBCRYPTO_A_URL:-$(resolve_apk "$TARGET_LIBCRYPTO" || true)}"
LIBSSL_A_URL="${LIBSSL_A_URL:-$(resolve_apk "$TARGET_LIBSSL" || true)}"
LIBCRYPTO_B_URL="${LIBCRYPTO_B_URL:-$(resolve_apk "$ALT1_LIBCRYPTO" || true)}"
LIBSSL_B_URL="${LIBSSL_B_URL:-$(resolve_apk "$ALT1_LIBSSL" || true)}"
LIBCRYPTO_C_URL="${LIBCRYPTO_C_URL:-$(resolve_apk "$ALT2_LIBCRYPTO" || true)}"
LIBSSL_C_URL="${LIBSSL_C_URL:-$(resolve_apk "$ALT2_LIBSSL" || true)}"

if [[ -z "${LIBCRYPTO_A_URL}" || -z "${LIBSSL_A_URL}" ]]; then
  echo "ERROR: Could not resolve target APK URLs for ${TARGET_LIBCRYPTO}/${TARGET_LIBSSL}."
  echo "Override explicitly, e.g.:"
  echo "  LIBCRYPTO_A_URL=<url> LIBSSL_A_URL=<url> bash $0"
  echo "Or override mirror base:"
  echo "  ALPINE_MIRROR_BASE=https://<mirror>/alpine bash $0"
  exit 2
fi

echo "Target URLs:"
echo "  A libcrypto: ${LIBCRYPTO_A_URL}"
echo "  A libssl:    ${LIBSSL_A_URL}"
echo

# -----------------------------
# [3] Build local images
# -----------------------------
WORKDIR="/root/q12-image-build"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/a" "$WORKDIR/b" "$WORKDIR/c"

write_df_pinned() {
  local dir="$1" base="$2" libcrypto_url="$3" libssl_url="$4"
  cat > "${dir}/Dockerfile" <<EOF
FROM ${base}
RUN set -eux; \
    apk add --no-cache ca-certificates wget; \
    wget -q -O /tmp/libcrypto.apk "${libcrypto_url}"; \
    wget -q -O /tmp/libssl.apk "${libssl_url}"; \
    apk add --allow-untrusted /tmp/libcrypto.apk /tmp/libssl.apk; \
    rm -f /tmp/libcrypto.apk /tmp/libssl.apk; \
    apk info -v libcrypto3 | tee /libcrypto3.version
CMD ["sleep","3600"]
EOF
}

write_df_base() {
  local dir="$1" base="$2"
  cat > "${dir}/Dockerfile" <<EOF
FROM ${base}
CMD ["sleep","3600"]
EOF
}

write_df_pinned "$WORKDIR/a" "alpine:3.19" "$LIBCRYPTO_A_URL" "$LIBSSL_A_URL"

if [[ -n "${LIBCRYPTO_B_URL}" && -n "${LIBSSL_B_URL}" ]]; then
  write_df_pinned "$WORKDIR/b" "alpine:3.19" "$LIBCRYPTO_B_URL" "$LIBSSL_B_URL"
else
  echo "WARN: Could not resolve B package URLs; building B from base image only."
  write_df_base "$WORKDIR/b" "alpine:3.19"
fi

if [[ -n "${LIBCRYPTO_C_URL}" && -n "${LIBSSL_C_URL}" ]]; then
  write_df_pinned "$WORKDIR/c" "alpine:3.20" "$LIBCRYPTO_C_URL" "$LIBSSL_C_URL"
else
  echo "WARN: Could not resolve C package URLs; building C from base image only."
  write_df_base "$WORKDIR/c" "alpine:3.20"
fi

echo "[3] Building images..."
$BUILD_TOOL build -t q12-alpine:a "$WORKDIR/a"
$BUILD_TOOL build -t q12-alpine:b "$WORKDIR/b"
$BUILD_TOOL build -t q12-alpine:c "$WORKDIR/c"

echo "✅ Images built: q12-alpine:a (target), q12-alpine:b, q12-alpine:c"
echo

echo "[3.1] SBOM sanity check (q12-alpine:a contains libcrypto3 3.1.4-r5)..."
if bom packages q12-alpine:a 2>/dev/null | grep -qE 'libcrypto3\s+3\.1\.4-r5'; then
  echo "✅ SBOM sanity-check passed."
else
  echo "WARN: SBOM did not show libcrypto3 3.1.4-r5 in q12-alpine:a output."
fi
echo

# -----------------------------
# [4] Create namespace + deployment
# -----------------------------
echo "[4] Creating namespace '${NS}' and deploying pod with 3 containers..."
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
      - name: alpine-318
        image: q12-alpine:a
        imagePullPolicy: IfNotPresent
        command: ["sleep","3600"]
      - name: alpine-319
        image: q12-alpine:b
        imagePullPolicy: IfNotPresent
        command: ["sleep","3600"]
      - name: alpine-320
        image: q12-alpine:c
        imagePullPolicy: IfNotPresent
        command: ["sleep","3600"]
YAML

cp -f "$MANIFEST" "$BACKUP/alpine-deployment.yaml.original"
kubectl apply -f "$MANIFEST"

echo
echo "[5] Waiting for rollout..."
kubectl -n "$NS" rollout status deploy/alpine --timeout=180s

echo
kubectl -n "$NS" get deploy alpine
kubectl -n "$NS" get pods -o wide

echo
echo "Manifest location: $MANIFEST"
echo "Backup copy:       $BACKUP/alpine-deployment.yaml.original"
echo
echo "✅ Q12 environment ready."
