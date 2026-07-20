# Resilience — what was tested, and what it cost

Every figure here comes from a test run against the live deployment, measured
by polling the ingress health endpoint roughly three times a second. Nothing in
this document is estimated.

The deployment is single-node and single-replica by design. That is a real
trade, and the point of measuring is to state its price rather than imply a
resilience the architecture does not have.

## Summary

| Scenario | Recovery | Requests failed |
|---|---|---|
| Web pod deleted | 34s to serving again | 111 probes (1× 502, 110× 503) |
| Rolling deployment | no wait — new pod ready before old exits | 3 probes (502) at cutover, ~1.3s |
| Manual scale to 3 replicas | reverted in 40s | none |
| Database and attachments destroyed | restored from archive | app offline for the restore |

## Pod loss is an outage, not a blip

Deleting the web pod took the application down for **34.4 seconds** — one 502
while the ingress dropped the backend, then 110 consecutive 503s until the
replacement passed its readiness probe.

This is the expected consequence of one replica: there is no second pod to
absorb the traffic, so recovery time is Rails boot time. It is automatic and
needs no operator, but it is not zero-impact, and calling it "self-healing"
without the number attached would be misleading.

Running two web replicas would remove this outage. It is not done here because
the node's memory budget does not allow a second Rails process alongside
Sidekiq, PostgreSQL, and the observability stack. That is the trade.

## Rolling deployments are nearly seamless

A `rollout restart` of the same deployment cost **3 failed probes, about 1.3
seconds**, all at the moment the old pod was removed.

The difference from pod deletion is entirely in the strategy. With one replica,
Kubernetes' default `RollingUpdate` resolves to `maxSurge=1, maxUnavailable=0`:
the replacement is created and becomes Ready *before* the old pod is
terminated, so the two overlap and traffic keeps flowing. The residual 502s are
the brief window where the ingress still holds a connection to the pod that is
going away.

Worth noting for a node this size: during the overlap both pods are scheduled at
once. Requests stay within allocatable memory, but container *limits* reach
about 121% of node capacity for the duration. That is permitted — limits may
overcommit — and it held here, but it is the reason the web memory limit cannot
grow much further without making rollouts risky.

## Declared state wins

Scaling the web deployment to 3 replicas by hand was reverted to the declared 1
replica in **40 seconds**, with no operator action. Argo CD's `selfHeal` detects
that the cluster disagrees with Git and corrects the cluster, not Git.

The practical consequence is that manual `kubectl scale` is not a way to change
this system. Changing the replica count means changing the chart values in Git.

This also has an operational edge worth knowing: any deliberate temporary change
— such as scaling the application down to restore a database — will be undone
mid-procedure unless auto-sync is paused first. The restore runbook does exactly
that, in its first step.

## Data loss is recoverable, and that was proven

The restore procedure in `docs/runbooks/restore.md` was executed as a
destructive test rather than a rehearsal:

1. The attachment blob was deleted from the storage volume.
2. The conversation, its seven messages, and the attachment row were deleted
   from the database.
3. Both were restored from an archive that had been **copied off the node** —
   the recovery path a disk failure would force, not the convenient one.

`pg_restore` completed with exit code 0 and no errors. Afterwards every row
count matched the pre-deletion state, message contents were intact, and the
application served the conversation again.

The strongest single piece of evidence: ActiveStorage records an MD5 checksum
for every stored file, and the checksum in the restored database row matched the
checksum of the restored file on disk. The recovered attachment is byte-identical
to the original — not merely a file of the right size in the right place.

## What is explicitly not covered

- **Node failure.** One node, no HA. Losing the VM means restoring from backup
  onto a rebuilt node, not failing over.
- **Zero-downtime pod loss.** Measured above at 34 seconds. Fixing it needs a
  second replica and therefore more memory.
- **Point-in-time recovery.** Backups are daily snapshots. Data written between
  the last backup and a failure is lost; there is no WAL archiving.
- **Automated off-node copying.** `scripts/fetch-backup.sh` is run by an
  operator. Until it runs, the newest archive shares a disk with the database.
