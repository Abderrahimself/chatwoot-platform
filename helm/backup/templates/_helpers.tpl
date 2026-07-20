{{- define "backup.fullname" -}}
{{- .Release.Name -}}
{{- end -}}

{{- define "backup.labels" -}}
app.kubernetes.io/name: backup
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}
