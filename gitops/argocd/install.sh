#!/usr/bin/env bash
# Bootstrap Argo CD on the cluster at a pinned version. This is the one
# imperative bootstrap step; everything Argo CD then manages is declarative.
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v3.4.5}"
MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# Server-side apply: the applicationset CRD is too large for the
# last-applied-configuration annotation that a client-side apply would write.
kubectl apply --server-side --force-conflicts -n argocd -f "$MANIFEST"

echo "Waiting for Argo CD to become ready..."
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s

echo
echo "Argo CD ${ARGOCD_VERSION} installed."
echo "Initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
echo "UI: kubectl -n argocd port-forward svc/argocd-server 8080:443  (user: admin)"
