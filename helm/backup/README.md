# backup

Scheduled backups of the Chatwoot database and attachment volume.

A CronJob in the `chatwoot` namespace runs `pg_dump` against the database
Service and tars the ActiveStorage volume, writing both to a dedicated
PersistentVolumeClaim.

## What it produces

Each run writes three files sharing one UTC timestamp:

| File | Contents |
|---|---|
| `db-<ts>.dump` | `pg_dump` custom format — compressed, restorable with `pg_restore` |
| `attachments-<ts>.tar.gz` | the attachments volume |
| `manifest-<ts>.sha256` | checksums for both |

Archives are written to `.part` and renamed on success, so an interrupted run
never leaves a file that looks like a complete backup.

## Configuration

| Value | Default | Notes |
|---|---|---|
| `schedule` | `30 2 * * *` | daily, 02:30 UTC |
| `retentionDays` | `7` | bounds the in-cluster volume only |
| `storage.size` | `5Gi` | archive volume |
| `image` | `pgvector/pgvector:pg16` | matches the database image so `pg_dump` is never older than the server |
| `target.*` | — | names of the database Service, Secret, and attachments claim it backs up |

The chart addresses its target by name rather than deriving names from the
application chart's helpers, so the two charts stay independent.

## This is only half a backup

The archive volume is local-path storage: it sits on the same virtual disk as
the database it protects. That covers logical loss — a dropped table, a bad
migration, a mistaken deletion — but not the loss of the node or its disk.

`scripts/fetch-backup.sh` copies archives off the node and verifies their
checksums. Until that has run, there is one disk between you and data loss.

## Operating

```bash
# Run a backup now rather than waiting for the schedule.
kubectl -n chatwoot create job backup-now --from=cronjob/chatwoot-backup
kubectl -n chatwoot logs job/backup-now -f

# What is on the archive volume.
scripts/fetch-backup.sh --list

# Copy the newest set to this machine, checksums verified.
scripts/fetch-backup.sh
```

Restoring is documented in `docs/runbooks/restore.md`.

## Notes

- `concurrencyPolicy: Forbid` — a slow run must not overlap the next one; two
  concurrent dumps against a 512Mi database container is how a backup becomes
  an outage.
- The attachments volume is mounted read-only. ReadWriteOnce is not a problem
  on a single node, where this pod co-mounts alongside web and Sidekiq.
- The archive PVC carries `helm.sh/resource-policy: keep` and Argo CD's
  `Delete=false`, so removing this application does not delete the backups.
