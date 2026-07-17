# Argo CD bootstrap

Argo CD is the one component installed imperatively — it cannot deploy itself
before it exists. Everything after this bootstrap is declarative: Argo CD syncs
the applications under `gitops/applications/` from Git.

## Install

```bash
export KUBECONFIG=../../infra/ansible/.artifacts/kubeconfig
./install.sh                 # pinned ARGOCD_VERSION, overridable via env
```

## Register the Chatwoot application

```bash
kubectl apply -f ../applications/chatwoot/application.yaml
```

Argo CD then deploys the `helm/chatwoot` chart from the platform repo and keeps
the cluster matching Git: `prune` removes resources deleted from Git and
`selfHeal` reverts manual changes made directly in the cluster.

## UI access

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
# https://localhost:8080  — user: admin, password from install.sh output
```

## Notes

- Version is pinned (`install.sh`), never tracking latest.
- The application `chatwoot-secrets` Secret is delivered as a SealedSecret
  synced from `gitops/secrets/` (see the `secrets` Application); only the
  in-cluster sealed-secrets controller can decrypt it. Plaintext secret
  values never enter Git.
- On the single 7 GB node, the applicationset, notifications, and dex
  components can be scaled to zero to reclaim memory if needed.
