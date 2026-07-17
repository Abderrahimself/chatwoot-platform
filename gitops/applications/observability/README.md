# Observability

Argo CD Applications for the observability stack, all sized for a single
7 GB node (single replicas, short retention, explicit requests/limits).

| Application | Chart (pinned) | Role |
|---|---|---|
| `kube-prometheus-stack` | 87.17.0 | Prometheus, Alertmanager, Grafana, exporters — metrics + the Grafana UI |
| `loki` | 7.1.0 | Log store (single-binary, filesystem) |
| `alloy` | 1.10.1 | Log collector: tails pod logs → Loki |
| `tempo` | 1.24.4 | Trace store (monolithic, filesystem) |
| `otel-collector` | 0.165.0 | Receives OTLP traces from the ingress → Tempo |
| `observability-config` | (this repo) | Grafana dashboard + PrometheusRule alerts |

## Signals

- **Metrics** — Prometheus scrapes the cluster; Grafana reads it. Retention 24h.
- **Logs** — Alloy ships every pod's logs to Loki; searchable in Grafana by
  namespace/pod/container. Retention 48h.
- **Traces** — the k3s-bundled Traefik ingress exports OTLP to the OpenTelemetry
  Collector, which forwards to Tempo. One trace per request. Traefik is enabled
  for tracing by `gitops/observability/traefik-tracing.yaml`, a k3s
  `HelmChartConfig` applied out-of-band (Traefik is managed by k3s, not Argo CD).

## Dashboard and alerts

`observability-config` syncs `gitops/observability-config/`:

- **Chatwoot Platform Overview** dashboard (web/sidekiq availability, node
  memory headroom, per-pod CPU/memory, PV fill) — provisioned via the Grafana
  sidecar.
- Three alerts scoped to this platform's real risks: `ChatwootWebDown`
  (single-replica outage), `ChatwootContainerHighMemory` (OOM risk on the tight
  node), `PersistentVolumeFillingUp` (local-path disk fill).

## Access

Grafana is at `http://grafana.10.17.3.165.nip.io`; the admin credentials come
from the `grafana-admin` SealedSecret (`gitops/secrets/`).

## Registering

The Application manifests here are applied to the cluster once (`kubectl apply`),
after which each syncs its own source. The Grafana admin SealedSecret must
exist before `kube-prometheus-stack` syncs.
