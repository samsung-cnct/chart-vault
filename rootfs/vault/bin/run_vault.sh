#!/bin/sh

printenv

if [[ $ENVIRONMENT == test ]]
then
  /var/tmp/vault.sh
else
  cat /etc/vault/cfg/config.json
  echo
  /usr/local/bin/vault server -config /etc/vault/cfg/config.json
fi
