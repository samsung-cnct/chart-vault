#!/bin/busybox sh

# print current environment
printenv

ADDR="${MY_POD_NAME}.{{ template "vault.fullname" . }}.{{ .Release.Namespace }}.svc.{{ .Values.clusterDomain }}"
VAULT_API_ADDR="$SCHEME://$ADDR:$CLIENT_LISTENER_PORT"
VAULT_CLUSTER_ADDR="$ADDR:$CLUSTER_LISTENER_PORT"

export ADDR VAULT_API_ADDR VAULT_CLUSTER_ADDR

cat /etc/vault/cfg/config.hcl

# start vault server
vault server -config=/etc/vault/cfg/config.hcl{{- if .Values.vault.enableDebug }} -log-level=debug{{- end }}
