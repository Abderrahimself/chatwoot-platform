{{- define "chatwoot.fullname" -}}
{{- .Release.Name -}}
{{- end -}}

{{- define "chatwoot.labels" -}}
app.kubernetes.io/name: chatwoot
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/* Service DNS names, derived from the release name. */}}
{{- define "chatwoot.postgresHost" -}}{{ .Release.Name }}-postgres{{- end -}}
{{- define "chatwoot.redisHost" -}}{{ .Release.Name }}-redis{{- end -}}
{{- define "chatwoot.webHost" -}}{{ .Release.Name }}-web{{- end -}}

{{/*
Reusable init container that blocks until PostgreSQL accepts connections, the
Chatwoot schema is present, and Redis answers. Used by web and Sidekiq so they
never boot ahead of the migration job.
*/}}
{{- define "chatwoot.waitForDeps" -}}
- name: wait-for-deps
  image: {{ .Values.postgres.image }}
  command:
    - bash
    - -c
    - |
      set -e
      echo "waiting for postgres..."
      until pg_isready -h "$PGHOST" -U "$PGUSER" -q; do sleep 2; done
      echo "waiting for chatwoot schema..."
      until [ -n "$(psql -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" -tAc "SELECT to_regclass('public.schema_migrations')")" ]; do sleep 3; done
      echo "waiting for redis..."
      until (exec 3<>/dev/tcp/{{ include "chatwoot.redisHost" . }}/6379) 2>/dev/null; do sleep 2; done
      echo "dependencies ready"
  env:
    - name: PGHOST
      value: {{ include "chatwoot.postgresHost" . }}
    - name: PGUSER
      value: {{ .Values.postgres.username }}
    - name: PGDATABASE
      value: {{ .Values.postgres.database }}
    - name: PGPASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ .Values.existingSecret }}
          key: POSTGRES_PASSWORD
{{- end -}}
