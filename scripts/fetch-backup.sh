#!/usr/bin/env bash
# Copy backup archives off the cluster node onto this machine.
#
# Why this exists: the CronJob writes to a local-path volume, which sits on the
# same virtual disk as the database it protects. That covers logical loss — a
# dropped table, a bad migration — but not the loss of the node or its disk.
# Running this is what turns a schedule into a backup you can actually rely on.
#
# Usage:
#   scripts/fetch-backup.sh            # newest archive set
#   scripts/fetch-backup.sh --all      # every set on the volume
#   scripts/fetch-backup.sh --list     # show what is there, copy nothing
#
# Requires KUBECONFIG to point at the cluster.
set -euo pipefail

ns=chatwoot
pvc=chatwoot-backup-archive
pod=backup-fetch
# Reuses an image the node already has, so this never waits on a registry pull.
image=pgvector/pgvector:pg16
mode=latest

while [ $# -gt 0 ]; do
  case "$1" in
    --all)  mode=all ;;
    --list) mode=list ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

dest="$(git rev-parse --show-toplevel)/backup"

command -v kubectl >/dev/null || { echo "kubectl not found" >&2; exit 1; }
kubectl -n "$ns" get pvc "$pvc" >/dev/null || {
  echo "archive volume $pvc not found in namespace $ns — has the backup application synced?" >&2
  exit 1
}

cleanup() { kubectl -n "$ns" delete pod "$pod" --ignore-not-found --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

# A short-lived reader rather than a permanently running pod: the node's memory
# budget is tight, and this only needs to exist for the length of a copy.
cleanup
kubectl -n "$ns" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${pod}
  labels:
    app.kubernetes.io/name: backup
    app.kubernetes.io/component: fetch
spec:
  restartPolicy: Never
  containers:
    - name: reader
      image: ${image}
      command: ["sleep", "600"]
      resources:
        requests: {cpu: 20m, memory: 32Mi}
        limits: {memory: 128Mi}
      volumeMounts:
        - name: archive
          mountPath: /archive
          readOnly: true
  volumes:
    - name: archive
      persistentVolumeClaim:
        claimName: ${pvc}
        readOnly: true
EOF

echo "waiting for reader pod..."
kubectl -n "$ns" wait --for=condition=Ready "pod/${pod}" --timeout=120s >/dev/null

if [ "$mode" = list ]; then
  kubectl -n "$ns" exec "$pod" -- ls -lh /archive
  exit 0
fi

if [ "$mode" = all ]; then
  files=$(kubectl -n "$ns" exec "$pod" -- sh -c 'cd /archive && ls -1 db-*.dump attachments-*.tar.gz manifest-*.sha256 2>/dev/null')
else
  # One timestamp identifies a matching database/attachments/manifest set.
  stamp=$(kubectl -n "$ns" exec "$pod" -- sh -c 'cd /archive && ls -1 db-*.dump 2>/dev/null | sort | tail -1 | sed "s/^db-//; s/\.dump$//"')
  [ -n "$stamp" ] || { echo "no archives on the volume yet" >&2; exit 1; }
  echo "newest set: ${stamp}"
  files="db-${stamp}.dump attachments-${stamp}.tar.gz manifest-${stamp}.sha256"
fi

mkdir -p "$dest"
# shellcheck disable=SC2086
kubectl -n "$ns" exec "$pod" -- tar cf - -C /archive $files | tar xf - -C "$dest"

echo "verifying checksums..."
rc=0
for m in $(cd "$dest" && ls -1 manifest-*.sha256 2>/dev/null); do
  ( cd "$dest" && sha256sum -c "$m" ) || rc=1
done
[ "$rc" -eq 0 ] || { echo "CHECKSUM MISMATCH — do not trust these copies" >&2; exit 1; }

echo
echo "copied to ${dest}:"
ls -lh "$dest"
echo
echo "These files are gitignored. Keep them somewhere that is not this laptop"
echo "if they are the only copy."
