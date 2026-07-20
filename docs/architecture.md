# Architecture

## Delivery Flow

```text
Chatwoot source repository (pinned upstream release)
        |
GitHub Actions
Build + Trivy scan
        |
GitHub Container Registry
        |
GitOps manifests
        |
Argo CD
        |
k3s
        |
Ingress
        |
Chatwoot Web + Sidekiq
        |
PostgreSQL + Redis + attachment volume
```

## Components

- **Terraform** provisions one libvirt/KVM virtual machine, its NAT network, and its disks.
- **Ansible** configures the VM and installs single-node k3s.
- **GitHub Actions** builds the Chatwoot image from a pinned upstream release tag, scans it with Trivy, pushes it to GHCR, and updates the desired image version in Git.
- **GitHub Container Registry** stores the built images.
- **Argo CD** watches the declared GitOps state and syncs it into k3s, reverting manual drift.
- **Helm** deploys Chatwoot web, Sidekiq, PostgreSQL, Redis, the attachment volume, database migrations, ingress, and operational settings.
- **Sealed Secrets** keeps sensitive values encrypted before they enter Git.
- **Prometheus and Grafana** provide metrics, dashboards, and alerts.
- **Loki and Grafana Alloy** collect and query logs from Chatwoot web and Sidekiq.
- **OpenTelemetry Collector and Tempo** provide a basic trace path.
- **A backup CronJob** dumps PostgreSQL and archives the attachment volume on a
  schedule; `scripts/fetch-backup.sh` copies archives off the node, because the
  archive volume otherwise shares a disk with the data it protects. The restore
  procedure has been executed against real data, not just written down — see
  `docs/resilience.md`.

## Infrastructure Shape

The deployment target is intentionally a single VM:

| Name | Role | RAM | vCPU | Disk |
|---|---|---:|---:|---:|
| `k3s-node` | Single-node k3s server and worker | 7 GB | 4 | 40 GB |

The IP address is discovered from Terraform output after provisioning. Access is SSH with public-key authentication only; password login and root login are disabled via cloud-init.

There is no multi-node Kubernetes design and no node-level high-availability claim. Pod-level restart and rolling deployment are in scope; node-failure tolerance is not.

All components run in lightweight, single-replica mode:

- Chatwoot web: one replica.
- Chatwoot Sidekiq: one replica.
- PostgreSQL: one instance.
- Redis: one instance.
- Attachments: one ReadWriteOnce volume, co-mounted by web and Sidekiq.
- Argo CD: no HA replicas.
- Prometheus: 24-hour retention.
- Loki: 48-hour retention.
- Tempo: 48-hour retention.

Single replicas are a deliberate trade for the memory budget, and they have a
measured cost: losing the web pod is a real outage rather than a degraded
service. `docs/resilience.md` quantifies it.

## Runtime Shape

Chatwoot runs as two workloads from the same image:

- **Web** serves the dashboard, API, widget, and WebSocket traffic.
- **Sidekiq** processes background jobs.

Both depend on:

- **PostgreSQL** for durable application data.
- **Redis** for queues, cache, and pub/sub. Redis is a hard runtime dependency, not an optional cache: if it is down, the application is down.
- **A persistent volume** for attachments, written through Rails ActiveStorage's
  local disk service. Object storage would be the next step if this ever needed
  more than one node; on a single node it is a component that buys nothing.

Database migrations run as a dedicated one-off job before the application serves traffic — never automatically at container start, where concurrent replicas would race.

## Responsibility Boundary

Upstream Chatwoot owns application features, business logic, and UI behavior. This platform owns the operational layer: infrastructure, configuration, image pipeline, deployment manifests, secret handling, monitoring, logging, tracing, backup, and restore. The upstream source is inspected for operational facts (Dockerfiles, environment variables, migrations, health endpoints) but never functionally modified.
