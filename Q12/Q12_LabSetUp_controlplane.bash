#!/usr/bin/env bash
set -euo pipefail

echo "== Q12 Lab Setup — Alpine SBOM (ensures bom exists) =="

NS="alpine"
MANIFEST="$HOME/alpine-deployment.yaml"

# -----------------------------
# [0] Ensure syft exists
# -----------------------------
echo "[0] Ensuring 'syft' is installed..."
if ! command -v syft >/dev/null 2>&1; then
  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
fi
echo "✅ syft: $(syft version | head -n 1 || true)"

# -----------------------------
# [1] Provide 'bom' wrapper command
# -----------------------------
echo "[1] Ensuring 'bom' command exists..."
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

case "${1:-}" in
  ""|-h|--help|help) usage; exit 0 ;;
  version) exec syft version ;;
  packages)
    [[ -n "${2:-}" ]] || { usage; exit 2; }
    exec syft packages "$2"
    ;;
  spdx)
    [[ -n "${2:-}" ]] || { usage; exit 2; }
    exec syft "$2" -o spdx-tag-value
    ;;
  *)
    usage; exit 2
    ;;
esac
BOM
  chmod +x /usr/local/bin/bom
fi

command -v bom >/dev/null 2>&1 || { echo "ERROR: bom not available after setup"; exit 2; }
echo "✅ bom: $(command -v bom)"
bom version >/dev/null 2>&1 || { echo "ERROR: bom wrapper cannot run syft"; exit 2; }

# -----------------------------
# [2] Create namespace + deployment
# -----------------------------
echo "[2] Creating namespace + deployment..."
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
        command: ["sleep","3600"]
      - name: alpine-318
        image: alpine:3.18
        command: ["sleep","3600"]
      - name: alpine-319
        image: alpine:3.19
        command: ["sleep","3600"]
YAML

kubectl apply -f "$MANIFEST"
kubectl -n "$NS" rollout status deploy/alpine --timeout=180s

echo
echo "Manifest location: $MANIFEST"
echo "✅ Q12 environment ready"
