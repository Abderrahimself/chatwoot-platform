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
PostgreSQL + Redis + Object Storage
```

## Components

- **Terraform** provisions one libvirt/KVM virtual machine, its NAT network, and its disks.
- **Ansible** configures the VM and installs single-node k3s.
- **GitHub Actions** builds the Chatwoot image from a pinned upstream release tag, scans it with Trivy, pushes it to GHCR, and updates the desired image version in Git.
- **GitHub Container Registry** stores the built images.
- **Argo CD** watches the declared GitOps state and syncs it into k3s, reverting manual drift.
- **Helm** deploys Chatwoot web, Sidekiq, PostgreSQL, Redis, object storage, database migrations, ingress, and operational settings.
- **Sealed Secrets** keeps sensitive values encrypted before they enter Git.
- **Prometheus and Grafana** provide metrics, dashboards, and alerts.
- **Loki and Grafana Alloy** collect and query logs from Chatwoot web and Sidekiq.
- **OpenTelemetry Collector and Tempo** provide a basic trace path.
- **Backup jobs** protect PostgreSQL data and attachment storage; restore procedures are tested, not assumed.

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
- Object storage: one instance.
- Argo CD: no HA replicas.
- Prometheus: 24-hour retention.
- Loki: 24-hour retention.
- Tempo: 6-hour retention.

## Runtime Shape

Chatwoot runs as two workloads from the same image:

- **Web** serves the dashboard, API, widget, and WebSocket traffic.
- **Sidekiq** processes background jobs.

Both depend on:

- **PostgreSQL** for durable application data.
- **Redis** for queues, cache, and pub/sub. Redis is a hard runtime dependency, not an optional cache: if it is down, the application is down.
- **Object storage** for attachments.

Database migrations run as a dedicated one-off job before the application serves traffic — never automatically at container start, where concurrent replicas would race.

## Responsibility Boundary

Upstream Chatwoot owns application features, business logic, and UI behavior. This platform owns the operational layer: infrastructure, configuration, image pipeline, deployment manifests, secret handling, monitoring, logging, tracing, backup, and restore. The upstream source is inspected for operational facts (Dockerfiles, environment variables, migrations, health endpoints) but never functionally modified.
