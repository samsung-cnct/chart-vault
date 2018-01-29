#!/bin/sh

ADDR="${MY_POD_NAME}.${FQDN}"
VAULT_API_ADDR="$SCHEME://$ADDR:$CLIENT_LISTENER_PORT"
VAULT_CLUSTER_ADDR="$ADDR:$CLUSTER_LISTENER_PORT"

export ADDR VAULT_API_ADDR VAULT_CLUSTER_ADDR

# print current environment
printenv

cat /etc/vault/cfg/config.hcl
echo "RUNNING VAULT WITH: vault server -config=/etc/vault/cfg/config.hcl $VAULT_STARTUP_OPTIONS"

# start vault server
vault server -config=/etc/vault/cfg/config.hcl "$VAULT_STARTUP_OPTIONS"
