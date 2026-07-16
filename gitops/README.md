# GitOps

Declarative delivery for the cluster. Argo CD watches this directory and syncs
the declared state; the desired versions live in Git, not in operators' shells.

```text
gitops/
|-- argocd/                 Argo CD bootstrap (install.sh, pinned version)
`-- applications/
    |-- chatwoot/           Argo CD Application -> helm/chatwoot
    |-- observability/      (week 3)
    `-- secrets/            (week 3: Sealed Secrets)
```

## Flow

1. CI builds and scans the Chatwoot image and pushes it to GHCR.
2. The desired image tag is set in `helm/chatwoot/values.yaml` in Git.
3. Argo CD syncs the change into the cluster and corrects any drift.

See `argocd/README.md` to bootstrap Argo CD and register the application.
