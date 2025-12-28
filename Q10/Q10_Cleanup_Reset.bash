#!/usr/bin/env bash
set -euo pipefail

kubectl delete ns monitoring --ignore-not-found
echo "🧹 Q10 environment cleaned"
