#!/usr/bin/env bash
set -euo pipefail

echo "== Q12 Lab Setup v10 — Alpine SBOM (bom) using PUBLIC images (robust libcrypto3 parsing) =="

NS="alpine"
MANIFEST="$HOME/alpine-deployment.yaml"
BACKUP_DIR="/root/cis-q12-backups-$(date +%Y%m%d%H%M%S)"
STATE_FILE="/root/.q12_target"  # stores: TARGET_VER|TARGET_IMAGE|TARGET_CONTAINER
mkdir -p "$BACKUP_DIR"

# -----------------------------
# [0] Ensure syft + bom wrapper exist
# -----------------------------
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
  bom spdx <IMAGE>   # SPDX Tag-Value to stdout
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

# -----------------------------
# [1] Create namespace + deployment (PUBLIC alpine tags)
# -----------------------------
echo "[1] Creating namespace + deployment..."
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
        image: alpine:3.17
        imagePullPolicy: IfNotPresent
        command: ["sleep","3600"]
      - name: alpine-318
        image: alpine:3.18
        imagePullPolicy: IfNotPresent
        command: ["sleep","3600"]
      - name: alpine-319
        image: alpine:3.19
        imagePullPolicy: IfNotPresent
        command: ["sleep","3600"]
YAML

cp -f "$MANIFEST" "$BACKUP_DIR/alpine-deployment.yaml.original"
kubectl apply -f "$MANIFEST"
kubectl -n "$NS" rollout status deploy/alpine --timeout=240s

POD="$(kubectl -n "$NS" get pod -l app=alpine -o jsonpath='{.items[0].metadata.name}')"
echo "✅ Pod: $POD"
echo

# -----------------------------
# [2] Discover libcrypto3 versions + choose deterministic target
# Rule: pick the HIGHEST version string among containers (sort -V).
# State file MUST be: <version>|<image>|<container>
# -----------------------------
echo "[2] Discovering libcrypto3 versions in each container..."

extract_ver() {
  # input: a line containing libcrypto3-<ver>
  # output: <ver> (e.g. 3.1.8-r1)
  echo "$1" | sed -nE 's/.*libcrypto3-([0-9]+\.[0-9]+\.[0-9]+-r[0-9]+).*/\1/p' | head -n1
}

declare -A RAW
declare -A VER

for c in alpine-317 alpine-318 alpine-319; do
  # FIX: Always fetch the FIRST header line beginning with "libcrypto3-"
  out="$(kubectl -n "$NS" exec "$POD" -c "$c" -- sh -lc \
    'apk update >/dev/null 2>&1; apk info -a libcrypto3 2>/dev/null | grep -m1 "^libcrypto3-" || true' \
    | tr -d '\r' || true)"

  if [[ -z "${out}" ]]; then
    echo "ERROR: could not determine libcrypto3 header line in container $c"
    echo "Remediation: exec and inspect manually:"
    echo "  kubectl -n $NS exec $POD -c $c -- sh -lc 'apk info -a libcrypto3 | head -n 30'"
    exit 2
  fi

  v="$(extract_ver "$out")"
  if [[ -z "${v}" ]]; then
    echo "ERROR: could not parse libcrypto3 version from: '$out' (container $c)"
    exit 2
  fi

  RAW["$c"]="$out"
  VER["$c"]="$v"
  echo "  $c => ${out}   (parsed: ${v})"
done

best_c="alpine-317"
best_ver="${VER[$best_c]}"
for c in alpine-318 alpine-319; do
  cv="${VER[$c]}"
  top="$(printf "%s\n%s\n" "$best_ver" "$cv" | sort -V | tail -n1)"
  if [[ "$top" == "$cv" ]]; then
    best_ver="$cv"
    best_c="$c"
  fi
done

TARGET_IMAGE="$(kubectl -n "$NS" get pod "$POD" -o jsonpath="{.spec.containers[?(@.name=='$best_c')].image}")"

echo
echo "✅ Target selected (highest libcrypto3):"
echo "  Container: $best_c"
echo "  Image:     $TARGET_IMAGE"
echo "  Version:   $best_ver"
echo

printf "%s|%s|%s\n" "$best_ver" "$TARGET_IMAGE" "$best_c" > "$STATE_FILE"
chmod 600 "$STATE_FILE"

echo "Wrote target state: $STATE_FILE"
echo "  $(cat "$STATE_FILE")"
echo
echo "Manifest location: $MANIFEST"
echo "Backup copy:       $BACKUP_DIR/alpine-deployment.yaml.original"
echo "✅ Q12 environment ready"
