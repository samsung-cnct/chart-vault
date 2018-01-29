#!/bin/sh

# remove https?:// from URL
SECRETS_NAME="$(echo "$VAULT_FULL_URL" | sed -e 's/https\?:\/\///' | cut -d '.' -f 1)-keys"

# $VAULT_FULL_URL, $VAULT_CACERT, $VAULT_CLIENT_CERT, 
# and $VAULT_CLIENT_KEY env vars are set by _containerInitVault.yaml
if [ ! -z "$VAULT_CACERT" ]; then
  CURL_SSL_OPTS="--cacert $VAULT_CACERT --cert $VAULT_CLIENT_CERT --key $VAULT_CLIENT_KEY"
else
  CURL_SSL_OPTS=""
fi

CURL_HEALTH="curl -vvv $CURL_SSL_OPTS --connect-timeout 1 -s -o /dev/null -w %{http_code} $VAULT_FULL_URL/v1/sys/health"
CURL_INIT="curl $CURL_SSL_OPTS --connect-timeout 1 -s -o output.json -w %{http_code} --request PUT --data @/etc/vault/cfg/init.json $VAULT_FULL_URL/v1/sys/init"

# curl returns 000 as status (%{http_code}) if it can't
# properly talk to the endpoint
while [ "$($CURL_HEALTH)" = "000" ]; do 
  echo >&2 """
  *** Unable to communicate with remote Vault endpoint. Curl HTTP_STATUS was 000... ***

  ### Vault environment variables ###
$(printenv | grep VAULT)
  ###                             ###

  using curl command: >> $CURL_HEALTH
  curl exit code was $?
  ...retrying in 1 second
  """
  sleep 1
done 

# wait for vault to respond with 501 (uninitialized)
while [ "$($CURL_HEALTH)" != "501" ]; do 
  echo >&2 """
  *** Vault HTTP status is not 501 yet. Retrying in 1 second. ***

  ### Vault environment variables ###
$(printenv | grep VAULT)
  ###                             ###

  using curl command: >> $CURL_HEALTH
  curl exit code was $?
  ...retrying in 1 second
  """
  sleep 1
done

echo >&2 "Vault HTTP status was 501. Initializing Vault."

# init with the json payload
while [ "$($CURL_INIT)" != "200" ]; do
  echo >&2 """
  *** Vault HTTP status is not 200. Retrying in 1 second... ***

  using curl command: >> $CURL_INIT
  curl exit code was: $?
  ...retrying in 1 second
  """
  sleep 1
done

echo >&2 "Vault initialization SUCCESSFUL! Temporarily saving master keys."
echo >&2 "******* SECRETS_NAME derived from VAULT_FULL_URL will be: $SECRETS_NAME"

# create secret out of the output.json
kubectl delete secret "$SECRETS_NAME" --namespace "$K8S_NAMESPACE" || true  

if kubectl create secret generic "$SECRETS_NAME" --from-file=./output.json --namespace "$K8S_NAMESPACE"; then
  echo >&2 "Vault master keys saved. Exiting."
else
  rc=$?
  echo >&2 "Vault failed to create master keys in k8s. Quitting"
  exit $rc
fi
