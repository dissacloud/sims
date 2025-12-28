#!/usr/bin/env bash
kubectl -n prod delete ingress web --ignore-not-found
kubectl -n prod delete deploy web --ignore-not-found
kubectl -n prod delete svc web --ignore-not-found
kubectl -n prod delete secret web-cert --ignore-not-found
echo "Cleanup done"
