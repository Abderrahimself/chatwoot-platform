# GitOps

Declarative delivery for the cluster. Argo CD watches this directory and syncs
the declared state; the desired versions live in Git, not in operators' shells.

```text
gitops/
|-- argocd/                 Argo CD bootstrap (install.sh, pinned version)
|-- secrets/                SealedSecret manifests (encrypted; safe in Git)
|-- observability/          Traefik tracing HelmChartConfig (k3s-managed, applied out-of-band)
|-- observability-config/   Grafana dashboard + PrometheusRule alerts (synced by Argo)
`-- applications/
    |-- chatwoot/           Argo CD Application -> helm/chatwoot
    |-- backup/             Argo CD Application -> helm/backup
    |-- observability/      Applications: metrics, logs, traces, dashboard + alerts
    `-- secrets/            Applications: sealed-secrets controller + gitops/secrets sync
```

## Flow

1. CI builds and scans the Chatwoot image and pushes it to GHCR.
2. The desired image tag is set in `helm/chatwoot/values.yaml` in Git.
3. Argo CD syncs the change into the cluster and corrects any drift.

See `argocd/README.md` to bootstrap Argo CD and register the application.
