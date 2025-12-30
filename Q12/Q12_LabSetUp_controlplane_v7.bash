#!/usr/bin/env bash
set -euo pipefail

echo "== Q12 Lab Setup v7 — Alpine SBOM (bom) + deterministic target libcrypto3 =="

NS="alpine"
MANIFEST="$HOME/alpine-deployment.yaml"
BACKUP_DIR="/root/cis-q12-backups-$(date +%Y%m%d%H%M%S)"
STATE_FILE="/root/.q12_target_version"          # used by Questions + Grader
mkdir -p "$BACKUP_DIR"

# ---------
# [0] Ensure syft + bom wrapper exist
# ---------
echo "[0] Ensuring syft + bom exist..."
if ! command -v syft >/dev/null 2>&1; then
  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
fi

if ! command -v bom >/dev/null 2>&1; then
  cat >/usr/local/bin/bom <<'BOM'
#!/usr/bin/env bash
set -euo pipefail
usage(){ cat <<'EOF'
Usage:
  bom version
  bom packages <IMAGE>
  bom spdx <IMAGE>
EOF
}
case "${1:-}" in
  ""|-h|--help|help) usage; exit 0 ;;
  version) exec syft version ;;
  packages) [[ -n "${2:-}" ]] || { usage; exit 2; }; exec syft packages "$2" ;;
  spdx) [[ -n "${2:-}" ]] || { usage; exit 2; }; exec syft "$2" -o spdx-tag-value ;;
  *) usage; exit 2 ;;
esac
BOM
  chmod +x /usr/local/bin/bom
fi

bom version >/dev/null 2>&1 || { echo "ERROR: bom/syft not functional"; exit 2; }
echo "✅ bom OK"
echo

# ---------
# [1] Build tool detection
# ---------
if command -v docker >/dev/null 2>&1; then
  BUILD_TOOL="docker"
elif command -v nerdctl >/dev/null 2>&1; then
  BUILD_TOOL="nerdctl"
else
  echo "ERROR: Need docker or nerdctl to build deterministic images."
  exit 2
fi
echo "Build tool: ${BUILD_TOOL}"
echo "Backup dir: ${BACKUP_DIR}"
echo

# ---------
# [2] Resolve a target libcrypto3/libssl3 version that EXISTS on mirrors
#     We choose from a short list, in order (most exam-like first).
# ---------
need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 2; }; }
need curl

ARCH_UNAME="$(uname -m)"
case "${ARCH_UNAME}" in
  x86_64|amd64) APK_ARCH="x86_64" ;;
  aarch64|arm64) APK_ARCH="aarch64" ;;
  *) echo "ERROR: Unsupported arch: ${ARCH_UNAME}"; exit 2 ;;
esac

# Try a few official mirrors if the CDN you hit is missing a rev.
MIRRORS=(
  "${ALPINE_MIRROR_BASE:-https://dl-cdn.alpinelinux.org/alpine}"
  "https://dl-2.alpinelinux.org/alpine"
  "https://dl-3.alpinelinux.org/alpine"
  "https://dl-4.alpinelinux.org/alpine"
)

# Branch/repo search order
BRANCHES=("v3.20" "v3.19" "v3.18" "v3.17")
REPOS=("main" "community")

# Candidate target versions (you can extend this list later)
CANDIDATE_VERSIONS=(
  "3.1.8-r0"
  "3.1.8-r1"
  "3.3.5-r0"
  "3.0.15-r0"
)

url_exists(){ curl -fsI --max-time 8 "$1" >/dev/null 2>&1; }

resolve_pair_for_version() {
  local ver="$1"
  local crypto="libcrypto3-${ver}.apk"
  local ssl="libssl3-${ver}.apk"

  for base in "${MIRRORS[@]}"; do
    for b in "${BRANCHES[@]}"; do
      for r in "${REPOS[@]}"; do
        local c_url="${base}/${b}/${r}/${APK_ARCH}/${crypto}"
        local s_url="${base}/${b}/${r}/${APK_ARCH}/${ssl}"
        if url_exists "$c_url" && url_exists "$s_url"; then
          echo "${ver}|${c_url}|${s_url}"
          return 0
        fi
      done
    done
  done
  return 1
}

echo "[2] Selecting a resolvable target version for libcrypto3..."
FOUND=""
for v in "${CANDIDATE_VERSIONS[@]}"; do
  if FOUND="$(resolve_pair_for_version "$v" 2>/dev/null)"; then
    break
  fi
done

if [[ -z "${FOUND}" ]]; then
  echo "ERROR: Could not resolve any candidate libcrypto3/libssl3 APK pair."
  echo "Remediation: extend CANDIDATE_VERSIONS or set ALPINE_MIRROR_BASE to a working mirror."
  exit 2
fi

TARGET_VER="$(echo "$FOUND" | awk -F'|' '{print $1}')"
LIBCRYPTO_URL="$(echo "$FOUND" | awk -F'|' '{print $2}')"
LIBSSL_URL="$(echo "$FOUND" | awk -F'|' '{print $3}')"

echo "✅ Target selected: libcrypto3=${TARGET_VER}"
echo "  libcrypto: ${LIBCRYPTO_URL}"
echo "  libssl:    ${LIBSSL_URL}"
echo "${TARGET_VER}" > "${STATE_FILE}"
chmod 600 "${STATE_FILE}"
echo

# ---------
# [3] Build deterministic images:
#     - target image has the chosen TARGET_VER baked in
#     - alt images are “normal” Alpine tags (no pin)
# ---------
WORKDIR="/root/q12-build"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/target" "$WORKDIR/alt1" "$WORKDIR/alt2"

cat >"$WORKDIR/target/Dockerfile" <<EOF
FROM alpine:3.19
RUN set -eux; \
    apk add --no-cache ca-certificates curl; \
    curl -fsSL -o /tmp/libcrypto.apk "${LIBCRYPTO_URL}"; \
    curl -fsSL -o /tmp/libssl.apk "${LIBSSL_URL}"; \
    apk add --allow-untrusted /tmp/libcrypto.apk /tmp/libssl.apk; \
    rm -f /tmp/libcrypto.apk /tmp/libssl.apk; \
    apk info -v libcrypto3 | tee /libcrypto3.version
CMD ["sleep","3600"]
EOF

cat >"$WORKDIR/alt1/Dockerfile" <<'EOF'
FROM alpine:3.18
CMD ["sleep","3600"]
EOF

cat >"$WORKDIR/alt2/Dockerfile" <<'EOF'
FROM alpine:3.20
CMD ["sleep","3600"]
EOF

echo "[3] Building images..."
$BUILD_TOOL build -t q12-alpine:target "$WORKDIR/target"
$BUILD_TOOL build -t q12-alpine:alt1 "$WORKDIR/alt1"
$BUILD_TOOL build -t q12-alpine:alt2 "$WORKDIR/alt2"

echo "[3.1] SBOM sanity check on target image..."
if bom packages q12-alpine:target | grep -Eqi "libcrypto3[[:space:]]+${TARGET_VER}"; then
  echo "✅ SBOM shows libcrypto3 ${TARGET_VER} in q12-alpine:target"
else
  echo "ERROR: SBOM did not show libcrypto3 ${TARGET_VER} in q12-alpine:target"
  exit 2
fi
echo

# ---------
# [4] Create namespace + deployment
# ---------
echo "[4] Creating namespace + deployment..."
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
      - name: alpine-317
        image: q12-alpine:alt1
        imagePullPolicy: IfNotPresent
        command: ["sleep","3600"]
      - name: alpine-318
        image: q12-alpine:target
        imagePullPolicy: IfNotPresent
        command: ["sleep","3600"]
      - name: alpine-319
        image: q12-alpine:alt2
        imagePullPolicy: IfNotPresent
        command: ["sleep","3600"]
YAML

cp -f "$MANIFEST" "$BACKUP_DIR/alpine-deployment.yaml.original"
kubectl apply -f "$MANIFEST"
kubectl -n "$NS" rollout status deploy/alpine --timeout=180s

echo
echo "Manifest location: $MANIFEST"
echo "Target version stored at: ${STATE_FILE}"
echo "✅ Q12 environment ready"
