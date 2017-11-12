#!/bin/busybox sh

# XXX this whole script needs to be parameterized from template
cat /etc/vault/cfg/config.json

start_vault()
{
  printenv

  # some day these paths should be parameterized.
  /usr/local/bin/vault server -config /etc/vault/cfg/config.json
}

start_vault 
