# Runbook — restore from backup

Restores the Chatwoot database and attachment volume from an archive produced
by the `chatwoot-backup` CronJob.

Read this end to end before starting. The database step is destructive: it
drops existing objects before recreating them.

## What a backup set is

Every run writes three files, sharing one UTC timestamp:

| File | Contents |
|---|---|
| `db-<ts>.dump` | `pg_dump` custom-format archive of `chatwoot_production` |
| `attachments-<ts>.tar.gz` | the ActiveStorage volume (`/app/storage`) |
| `manifest-<ts>.sha256` | checksums for the two above |

They live on the `chatwoot-backup-archive` volume in the `chatwoot` namespace,
and on any machine `scripts/fetch-backup.sh` has copied them to.

## Before you start

```bash
export KUBECONFIG=infra/ansible/.artifacts/kubeconfig

# What is available, newest last.
scripts/fetch-backup.sh --list
```

If restoring from a copy held off the node, verify it first — a corrupt archive
discovered halfway through a restore is a much worse day:

```bash
cd backup && sha256sum -c manifest-<ts>.sha256
```

Confirm the archive is readable and contains what you expect before touching
anything live:

```bash
pg_restore --list backup/db-<ts>.dump | grep -c 'TABLE DATA'
```

## 1. Stop the writers

Chatwoot must not be writing while the schema is dropped, and `pg_restore`
cannot drop objects that open sessions hold.

```bash
kubectl -n chatwoot scale deploy/chatwoot-web deploy/chatwoot-sidekiq --replicas=0
kubectl -n chatwoot rollout status deploy/chatwoot-web --timeout=120s
kubectl -n chatwoot rollout status deploy/chatwoot-sidekiq --timeout=120s
```

Argo CD self-heals drift, so it will scale these back up on its next sync. Either
work quickly, or pause auto-sync for the duration:

```bash
kubectl -n argocd patch app chatwoot --type merge -p '{"spec":{"syncPolicy":null}}'
```

Restore it afterwards — see step 5.

## 2. Restore the database

Run from a pod that can see both the archive volume and the database.

```bash
kubectl -n chatwoot apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: restore}
spec:
  restartPolicy: Never
  containers:
    - name: restore
      image: pgvector/pgvector:pg16
      command: ["sleep", "1800"]
      env:
        - name: PGHOST
          value: chatwoot-postgres
        - name: PGUSER
          value: postgres
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef: {name: chatwoot-secrets, key: POSTGRES_PASSWORD}
      volumeMounts:
        - {name: archive, mountPath: /archive, readOnly: true}
  volumes:
    - name: archive
      persistentVolumeClaim: {claimName: chatwoot-backup-archive, readOnly: true}
EOF

kubectl -n chatwoot wait --for=condition=Ready pod/restore --timeout=120s
```

Terminate any sessions left over, then restore:

```bash
kubectl -n chatwoot exec restore -- bash -c '
  psql -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity
                       WHERE datname = '"'"'chatwoot_production'"'"' AND pid <> pg_backend_pid();"
  pg_restore --clean --if-exists --no-owner --no-privileges \
             -d chatwoot_production /archive/db-<ts>.dump
'
```

`--clean --if-exists` drops each object before recreating it, so this works
against a populated database. Expect warnings about objects that did not exist;
those are normal. Errors mentioning `must be owner` or `permission denied` are
not — stop and investigate.

Delete the helper when finished:

```bash
kubectl -n chatwoot delete pod restore
```

## 3. Restore the attachments

Only needed if attachment files were lost. The tarball unpacks into the live
volume, which web and Sidekiq mount at `/app/storage`.

Scale web back to 1 temporarily so there is a pod holding the volume:

```bash
kubectl -n chatwoot scale deploy/chatwoot-web --replicas=1
kubectl -n chatwoot rollout status deploy/chatwoot-web --timeout=300s
pod=$(kubectl -n chatwoot get pod -l app.kubernetes.io/component=web -o name | head -1)

# Replaces files of the same name; leaves anything newer in place.
kubectl -n chatwoot exec -i "$pod" -- tar xzf - -C /app/storage < backup/attachments-<ts>.tar.gz
```

To restore the volume to exactly its backed-up state, clear it first — do this
only when you are certain the archive is the authority:

```bash
kubectl -n chatwoot exec "$pod" -- bash -c 'rm -rf /app/storage/* /app/storage/.[!.]*'
```

## 4. Bring the application back

```bash
kubectl -n chatwoot scale deploy/chatwoot-web deploy/chatwoot-sidekiq --replicas=1
kubectl -n chatwoot rollout status deploy/chatwoot-web --timeout=300s
kubectl -n chatwoot rollout status deploy/chatwoot-sidekiq --timeout=300s
```

## 5. Re-enable GitOps

If auto-sync was paused in step 1:

```bash
kubectl -n argocd patch app chatwoot --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

Confirm Argo CD agrees with Git again:

```bash
kubectl -n argocd get app chatwoot \
  -o custom-columns=SYNC:.status.sync.status,HEALTH:.status.health.status
```

## 6. Verify

Row counts should match the state the backup was taken from:

```bash
kubectl -n chatwoot exec deploy/chatwoot-postgres -- \
  psql -U postgres -d chatwoot_production -tAc \
  "select 'users='||(select count(*) from users),
          'inboxes='||(select count(*) from inboxes),
          'conversations='||(select count(*) from conversations),
          'messages='||(select count(*) from messages);"
```

Then confirm the application itself, not just the database:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://chatwoot.10.17.3.165.nip.io/health
```

Finally, log in and open the restored conversation. A restore is not proven by
row counts alone — the application has to serve the data back.

## Notes

- **The archive volume is not disaster recovery on its own.** It is local-path
  storage on the same disk as the database. `scripts/fetch-backup.sh` is what
  puts a copy somewhere the node's failure cannot reach.
- **Encryption keys matter.** Chatwoot encrypts some columns with the
  `ACTIVE_RECORD_ENCRYPTION_*` values from the application Secret. Restoring a
  database against different keys leaves those columns unreadable. Keep the
  sealed secret and the backups in sync; see `gitops/secrets/README.md`.
- **Rebuilt cluster.** The sealing key lives only in the cluster. After a
  rebuild, restore secrets before restoring data, or the application will start
  against a database it cannot decrypt.
