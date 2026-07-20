# Runbook — platform demonstration

An ordered walkthrough of what this platform does: provisioning, delivery,
recovery from pod loss, drift correction, observability, and restore from
backup.

Every timing quoted here was measured on this deployment and is recorded in
`docs/resilience.md`. Where a number appears below, it is what the run actually
cost — not a target. If a segment behaves differently on the day, the honest
move is to say so rather than to talk past it.

Budget about **35 minutes** for the standard path. The extended path, which
destroys and rebuilds the VM, needs **90 minutes** and is described at the end.

## Before you start

```bash
cd <repo root>
export KUBECONFIG=$PWD/infra/ansible/.artifacts/kubeconfig

NODE_IP=$(terraform -chdir=infra output -raw k3s_node_ip)
APP=chatwoot.${NODE_IP}.nip.io
GRAFANA=grafana.${NODE_IP}.nip.io
```

Confirm the starting state is clean, so that anything that breaks later broke
because of the demo rather than before it:

```bash
kubectl get nodes
kubectl -n argocd get applications \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
curl -s -o /dev/null -w '%{http_code}\n' http://$APP/health
```

Expect one `Ready` node, ten applications all `Synced`/`Healthy`, and `200`.

Two preparations worth making beforehand:

- **Take a fresh backup and fetch it** (`scripts/fetch-backup.sh`). Segment 6 is
  a real restore. Do not run it against an archive you have not verified.
- **Have a second terminal open.** Segments 3 and 4 need a poll running in one
  window while you act in the other.

## The poll

Segments 3 and 4 are only meaningful if the impact is measured. This is the
same probe used to produce the figures in `docs/resilience.md`:

```bash
while :; do
  printf '%s %s\n' "$(date +%T)" \
    "$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 http://$APP/health)"
  sleep 0.3
done
```

Leave it running in the second terminal. `200` is healthy; `502` and `503` are
the outage.

---

## 1. The VM is reproducible

**Shows:** infrastructure is declared, not hand-built.

```bash
terraform -chdir=infra plan
```

Expect `No changes. Your infrastructure matches the configuration.` The point
is not that the plan is empty — it is that the running VM and the code agree,
so the VM can be recreated rather than rebuilt from memory.

Worth showing alongside: `infra/domain.tf` is where the VM's memory and CPU are
set. Growing the node is a one-line change, which is what makes the memory
trade in segment 3 a decision rather than a limitation.

Node configuration is Ansible (`infra/ansible/`), and the playbook is
idempotent — a second run reports `changed=0`. Re-running it live is safe if
there is time, but it is slow; saying it is idempotent and showing the roles is
usually enough.

## 2. The application is delivered from Git

**Shows:** nothing is deployed by hand; Git is the source of truth.

```bash
kubectl -n argocd get applications
kubectl -n chatwoot get deploy chatwoot-web \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

The image is pinned by tag and was built and scanned by CI before it was
published. It is never `latest`, and never built from a moving branch — so the
tag identifies one specific build that a specific pipeline run produced.

The delivery loop closes in Git: the build workflow commits the tag it just
pushed into `helm/chatwoot/values.yaml`, and Argo CD deploys from that. The
pipeline does not talk to the cluster at all.

Then open the application at `http://$APP` and show the restored conversation.
A platform demo that never shows the application working is a demo of YAML.

## 3. Losing a pod is an outage, and here is its cost

**Shows:** honest failure behaviour, measured rather than asserted.

With the poll running:

```bash
kubectl -n chatwoot delete pod -l app.kubernetes.io/component=web
```

Expect roughly **34 seconds** of failures — one `502` as the ingress drops the
backend, then a run of `503`s until the replacement passes its readiness probe.
Then `200` again, with no operator action.

Say plainly what this is: recovery is automatic, but it is not free, because
there is one replica and no second pod to absorb traffic. The recovery time is
Rails boot time. A second replica would remove the outage; the node's memory
budget will not currently fit one alongside Sidekiq, PostgreSQL and the
observability stack.

Then contrast it — same deployment, different mechanism:

```bash
kubectl -n chatwoot rollout restart deploy/chatwoot-web
```

Expect about **1.3 seconds** of failures, three probes at cutover. The
difference is entirely that a rolling update creates the replacement and waits
for it to be Ready before removing the old pod. Same single replica, two very
different outcomes, decided by how the change is made.

## 4. Declared state wins

**Shows:** the cluster cannot be changed by hand and stay changed.

```bash
kubectl -n chatwoot scale deploy/chatwoot-web --replicas=3
kubectl -n chatwoot get pods -l app.kubernetes.io/component=web -w
```

Three pods appear, then Argo CD notices the cluster disagrees with Git and
reverts to the declared single replica — measured at **40 seconds**. Note that
it corrects the *cluster*, never Git.

The practical consequence: `kubectl scale` is not how this system is changed.
Changing the replica count means changing the chart values and committing.

The operational edge is worth stating, because segment 6 depends on it — a
deliberate temporary change, such as scaling down to restore a database, will
be undone mid-procedure unless auto-sync is paused first. That is why the
restore runbook pauses it in its first step.

## 5. The platform can be observed

**Shows:** metrics, logs, and traces, each answering a different question.

Grafana at `http://$GRAFANA` (admin credentials come from the sealed
`grafana-admin` secret).

- **Metrics** — dashboard "Chatwoot Platform Overview" (`chatwoot-overview`).
  Show CPU and memory against the configured limits. Node headroom is the
  reason the single-replica trade in segment 3 exists, so this connects back.
- **Logs** — Explore, Loki datasource, `{namespace="chatwoot"}`. Filter to the
  web pod and show the requests generated in segment 2. Logs are collected from
  every pod without the application knowing anything about it.
- **Traces** — Explore, Tempo datasource, TraceQL `{}`. Spans come from the
  ingress, not from instrumenting Chatwoot: adding tracing gems would mean
  modifying the upstream application, which this platform deliberately does not
  do. It is a smaller claim than full application tracing, and it is the honest
  one.
- **Alerts** — three rules are loaded and evaluating: web down, container memory
  above 90% of its limit, and a volume filling up.

```bash
kubectl -n observability get prometheusrule chatwoot-platform \
  -o jsonpath='{range .spec.groups[*].rules[*]}{.alert}{"  "}{.labels.severity}{"\n"}{end}'
```

Name the rule explicitly — the metrics chart installs around thirty of its own,
and a bare `get prometheusrule` buries the three that were written here.

## 6. Data loss is recoverable

**Shows:** the backup is a real recovery path, not a scheduled job that writes
files nobody has read back.

Follow `docs/runbooks/restore.md`. Do not improvise this segment — it is
destructive, and the runbook exists because the sequence matters.

The two points to draw out while it runs:

- The archive is restored from the **copy held off the node**. The scheduled
  job writes to a volume on the same virtual disk as the database it protects,
  which covers a dropped table but not a lost disk. Copying it off is what makes
  it a backup.
- Verification is not row counts. ActiveStorage records an MD5 for every stored
  file; after the restore, the checksum in the database matches the checksum of
  the file on disk. The recovered attachment is byte-identical to the original,
  not merely present at the right size.

Finish by opening the application and showing the conversation served back.

## Closing: what this does not do

Ending on the limits is stronger than ending on the demo, and every item here
is already measured or reasoned in `docs/resilience.md`:

- **No node failure tolerance.** One node, no HA. Losing the VM means restoring
  onto a rebuilt one, which is the extended path below.
- **Pod loss costs 34 seconds.** Fixing it needs a second replica and therefore
  more memory.
- **No point-in-time recovery.** Backups are daily; anything written since the
  last one is lost. There is no WAL archiving.
- **Off-node copying is manual.** Until an operator runs the fetch script, the
  newest archive shares a disk with the database.

---

## Extended path — destroy and rebuild

Rebuilding the VM from nothing is the strongest version of segment 1, and the
only one that proves the whole bootstrap actually works. It is also the segment
most likely to go wrong live, because three things do not survive a rebuild.

**Rehearse this before performing it.** Not because the steps are hard, but
because none of them are recoverable by improvisation once the old cluster is
gone.

Preconditions, all three mandatory:

1. A verified backup set **and** `backup/keys-current.env` on this machine.
   Without the escrowed keys, the restored database keeps its encrypted columns
   permanently unreadable — and every other check still passes, so nothing will
   tell you. See `docs/runbooks/restore.md`.
2. Time for a full image pull. The application image is roughly 675 MB; on a
   slow connection this dominates the rebuild.
3. Nothing else needed from the running cluster.

The sequence:

```bash
terraform -chdir=infra destroy      # destructive, and the point
terraform -chdir=infra apply
cd infra/ansible && ansible-playbook site.yml
export KUBECONFIG=$PWD/.artifacts/kubeconfig
```

Then bootstrap, in this order — the order matters:

```bash
gitops/argocd/install.sh
kubectl apply -f gitops/applications/secrets/controller.yaml
```

Recreate the application secret from the escrow copy **before** registering the
application, so it never starts against a database it cannot decrypt, then
re-seal it against the new controller. Both procedures are in
`docs/runbooks/restore.md` under "Restoring into a rebuilt cluster".

```bash
kubectl apply -f gitops/applications/chatwoot/application.yaml
kubectl apply -f gitops/applications/backup/application.yaml
kubectl apply -f gitops/applications/observability/
kubectl apply -f gitops/observability/traefik-tracing.yaml   # not an Argo application
```

Finally restore the data per the restore runbook.

The three things that do not survive, stated once more because each one is a
silent failure rather than an error:

- **The sealing key.** SealedSecret manifests in Git can only be decrypted by
  the controller that sealed them. A new controller cannot read them, and will
  simply fail to unseal.
- **The ingress tracing configuration.** Traefik is managed by k3s, not Argo CD,
  so `gitops/observability/traefik-tracing.yaml` must be re-applied by hand or
  traces stop at the ingress.
- **Application registration.** There is no app-of-apps; each application
  manifest is applied once to register it.

The node address is DHCP-assigned and will likely differ after a rebuild.
Re-read it from `terraform output -raw k3s_node_ip` — every hostname in this
runbook derives from it.
