{{- define "molecular-audit-core.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "molecular-audit-core.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "molecular-audit-core.labels" -}}
app.kubernetes.io/name: {{ include "molecular-audit-core.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: glassbox-marketplace
{{- end -}}

{{- define "molecular-audit-core.serviceAccountName" -}}
{{- if .Values.serviceAccount.name -}}
{{- .Values.serviceAccount.name -}}
{{- else -}}
{{- printf "%s-sa" (include "molecular-audit-core.fullname" .) -}}
{{- end -}}
{{- end -}}
