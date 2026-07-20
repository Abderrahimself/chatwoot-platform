# Chatwoot Platform

Infrastructure and delivery platform for operating self-hosted [Chatwoot](https://www.chatwoot.com/) on Kubernetes.

The application is deployed unmodified from upstream. This repository owns everything around it: virtual machine provisioning, node configuration, the container build and scan pipeline, GitOps delivery, secret management, observability, and backup/restore.

## Scenario

The platform is built against a concrete operating scenario: a retail group replacing a per-seat SaaS support tool with self-hosted Chatwoot — roughly 25 support agents, 400 conversations per day with seasonal peaks near 2,000 — while keeping customer conversation history under its own control. The deployment must be reproducible, observable, and restorable by a single operator.

## Architecture

```text
Chatwoot source repository (pinned upstream release)
        |
GitHub Actions: image build + Trivy scan
        |
GitHub Container Registry
        |
GitOps manifests (this repository)
        |
Argo CD
        |
k3s on a Terraform-provisioned VM
        |
Ingress
        |
Chatwoot Web + Sidekiq
        |
PostgreSQL + Redis + object storage
```

| Layer | Tooling |
|---|---|
| Provisioning | Terraform + libvirt/KVM |
| Node configuration | Ansible (single-node k3s) |
| Runtime | k3s, Helm |
| Delivery | GitHub Actions, Trivy, GHCR, Argo CD |
| Secrets | Sealed Secrets |
| Observability | Prometheus, Grafana, Loki, Grafana Alloy, Tempo, OpenTelemetry Collector |
| Recovery | Scheduled PostgreSQL and attachment backups, restore procedures |

See [docs/architecture.md](docs/architecture.md) for details.

## Deployment Target

A single libvirt/KVM virtual machine running single-node k3s:

| Name | Role | RAM | vCPU | Disk |
|---|---|---:|---:|---:|
| `k3s-node` | k3s server + worker | 7 GB | 4 | 40 GB |

All components run as lightweight single replicas with short retention (Prometheus 24 h, Loki 24 h, Tempo 6 h). The resilience scope is pod-level: restart behavior, rolling deployments, GitOps drift correction, and restore from backup. Node-level high availability is out of scope by design.

## Status

- [x] VM provisioning — Terraform + libvirt, cloud-init, key-only SSH
- [x] Node configuration and k3s installation — Ansible
- [x] Chatwoot deployment — Helm chart (web, Sidekiq, PostgreSQL, Redis, migrations, ingress)
- [x] Image build and scan pipeline — GitHub Actions, Trivy, GHCR
- [x] GitOps delivery and drift correction — Argo CD
- [x] Secret management — Sealed Secrets
- [x] Observability — metrics, dashboards, centralized logs, tracing
- [x] Backup and tested restore — PostgreSQL + attachments

## Repository Layout

```text
.
|-- infra/           Terraform (libvirt VM) and Ansible
|-- helm/            Helm charts: the Chatwoot stack and the backup CronJob
|-- gitops/          Argo CD applications, sealed secrets, dashboards and alerts
|-- backup/          Local download target for fetched archives (never committed)
|-- local-run/       Compose override for running upstream Chatwoot locally
|-- scripts/         Operational tooling (hygiene gate, backup fetch)
`-- docs/            Architecture and operations runbooks
```

## Getting Started

Requirements: libvirt/KVM, Terraform >= 1.5, an SSH key at `~/.ssh/id_ed25519.pub`.

```bash
cd infra
terraform init
terraform apply
terraform output k3s_node_ssh   # prints the SSH command for the provisioned VM
```

The VM network (`10.17.3.0/24`, NAT) provides DHCP and local DNS for the `platform.local` domain.

## Related Repositories

- **Application source:** a fork of [chatwoot/chatwoot](https://github.com/chatwoot/chatwoot), kept identical to upstream. Container images are built from pinned upstream release tags — never from a moving branch.
