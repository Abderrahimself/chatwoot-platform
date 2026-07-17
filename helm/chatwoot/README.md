# chatwoot Helm chart

Deploys Chatwoot (web + Sidekiq) with PostgreSQL, Redis, and local-path
storage onto single-node k3s. Minimal and self-contained — no external
subcharts.

## Prerequisites

- k3s reachable via the Ansible-fetched kubeconfig.
- The application Secret present in the namespace (see below).

## Secret

The chart references an existing Secret (default name `chatwoot-secrets`) and
never renders secret values itself; plaintext secret values never enter Git.

The Secret is managed declaratively as a SealedSecret in `gitops/secrets/`,
which only the in-cluster sealed-secrets controller can decrypt. To bootstrap
a brand-new environment, create the plaintext Secret once:

```bash
kubectl create namespace chatwoot

kubectl -n chatwoot create secret generic chatwoot-secrets \
  --from-literal=SECRET_KEY_BASE="$(openssl rand -hex 64)" \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -hex 24)" \
  --from-literal=REDIS_PASSWORD="$(openssl rand -hex 24)" \
  --from-literal=ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY="$(openssl rand -hex 16)" \
  --from-literal=ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY="$(openssl rand -hex 16)" \
  --from-literal=ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT="$(openssl rand -hex 16)"
```

then seal it into Git and let the controller adopt it (see
`gitops/secrets/README.md`).

## Install

```bash
export KUBECONFIG=../../infra/ansible/.artifacts/kubeconfig
helm upgrade --install chatwoot . -n chatwoot
```

The install ordering is handled without manual steps:

- PostgreSQL and Redis come up as ordinary Deployments with local-path PVCs.
- A `db:chatwoot_prepare` Job runs as a Helm `post-install,post-upgrade` hook;
  it waits for PostgreSQL, then creates and migrates the schema.
- web and Sidekiq share a `wait-for-deps` init container that blocks until the
  schema exists and Redis answers, so they never boot against an empty database.

## Access

Ingress is served by the k3s-bundled Traefik at the VM IP. `FRONTEND_URL` and
the ingress host default to `chatwoot.10.17.3.165.nip.io`, which resolves to
the VM with no local DNS setup. Decide this hostname before creating any inbox —
Chatwoot snapshots `FRONTEND_URL` into inboxes at creation time.

## Notes

- Image pinned to an upstream release tag (`values.yaml`), never `:latest`.
- Attachments use a local-path PVC (ActiveStorage on disk); object storage is a
  later, optional enhancement.
