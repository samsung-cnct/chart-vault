#!/bin/sh

printenv
cat /etc/vault/cfg/config.json

export VAULT_ADDR=http://127.0.0.1:8200
v=$(/usr/local/bin/vault server -config /etc/vault/cfg/config.json &)

echo "$v"

if vault init
then

  vault status

  if [[ $? == 2 ]]
  then
    exit 0
  else
    echo >&2 "TEST FAILED: vault 'status' did not exist with 0"
  fi
else
    echo >&2 "INIT FAILED: vault 'init' did not exist with 0"
fi

