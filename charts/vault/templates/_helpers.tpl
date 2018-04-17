{{/* vim: set filetype=mustache: */}}
{{/*
Create a name for vault dns.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "vault.name" -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a name for vault dns.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "vault.access" -}}
{{- printf "%s-%s" .Release.Name "access" | trunc 63 | trimSuffix "-" -}}
{{- end -}}