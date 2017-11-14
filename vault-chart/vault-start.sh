#!/bin/busybox sh

DEBUG=${1:-0}
PREREQS="jo jq vault base64 gpg"

# XXX this whole script needs to be parameterized from template
cat /etc/vault/cfg/config.json

if [[ $DEBUG ]]
then
  :
  #set -x
fi

start_vault()
{
  printenv

  if [[ ! $DEBUG ]]
  then
    vault_listener_proto={{- if .Values.vault.enableTLS }}"https"{{- else }}"http"{{- end }}
    vault_listener_addr={{ .Values.vault.listenerAddress }}
    vault_listener_port={{ .Values.vault.listenerPort }}

    VAULT_ADDR=$vault_listener_proto://$vault_listener_addr:$vault_listener_port
  else
    VAULT_INIT_VARS=$(yaml2json ~/projects/cyklops-config-vault/vault-svc-values.yaml | jq '.vault.init')
    VAULT_ADDR=http://127.0.0.1:80
  fi

  export VAULT_ADDR VAULT_INIT_VARS

  # some day these paths should be parameterized.
  echo "VAULT_ADDR is: $VAULT_ADDR"

  vault server -config /etc/vault/cfg/config.json &
  sleep 2

  V_INIT_DATA=$(vault init)
  V_ECODE=$?
}

prepare_pubkey()
{
  local pubkey_asc=/var/tmp/pubkey.asc
  local pubkey_b64=/var/tmp/pubkey.b64

  key_holder=$1
  ctr=$2

  if [[ -z $key_holder || -z $ctr ]]
  then
    echo >&2 'prepare_pubkey() is missing one, some, or all of $key_holder, and/or $ctr'
    return 32
  fi

  # grab master_key_holder's base64 encoded public key 
  # and store it in a file preparing it for import
  echo "$VAULT_INIT_VARS" | jq -rM --arg i $ctr '.key_masters[($i | tonumber)].pubkey' > $pubkey_b64

  # if $pubkey_b64 exists and is not empty
  if [[ -s $pubkey_b64 ]]
  then
    echo "INFO: Now associating key at index $ctr with key holder: $key_holder"

    # base64 decode it
    base64 -d $pubkey_b64 > $pubkey_asc

    echo "INFO: Importing key:"
    cat $pubkey_asc
    echo

    # import it
    if [[ -s $pubkey_asc ]]
    then
      if gpg --import $pubkey_asc
      then
        return 0
      else
        echo >&2 "ERROR: Unable to import public key for $key_holder. GPG error was $?: Skipping."
        return 1
      fi
    else
      echo >&2 "ERROR: ASCII armored public key does not exist. Cannot continue with this key."
      return 2
    fi
  else
    echo >&2 """
    FATAL: Supposed to encrypt but pubkey for $key_holder is empty or not found. 
    No associated public key exists, so quitting.
    """
    return 4
  fi
}

# since busybox is not 1:1 to gnu tools, 
# some alternate methods were required 
# to accomplish the goal here.
vault_status()
{
  jo_me=""
  status=$(vault status 2>/dev/null | \
           grep -E '[a-z]' | \
           sed -e 's#: #:#g' -e 's/^.*\t//g' | \
           tr ' ' '_')

  if [[ $? == 0 ]]
  then
    for l in $status
    do
      k=$(echo $l | cut -d : -f 1 | awk '{print (tolower($0))}')
      v=$(echo $l | cut -d : -f 2 | awk '{print (tolower($0))}')
      jo_me="$jo_me $k=$v "
    done

    if [[ -n "$jo_me" ]]
    then
      V_STATUS=$(jo $jo_me)

      KEY_THRESHOLD=$(echo "$V_STATUS" | jq -rM '.key_threshold')
      TOTAL_KEYS=$(echo "$V_STATUS"    | jq -rM '.key_shares')
      SEALED=$(echo "$V_STATUS"        | jq -rM '.sealed')
     #echo $V_STATUS
    else
      echo "{}"
    fi

    return 0
  else
    return 1
  fi
}

email_key()
{
  key=$1
  rcpt=$2
  enc=$3
  ctr=$4

  if [[ -z $key || -z $rcpt || -z $enc || -z $ctr ]]
  then
    echo >&2 'email_key() missing one, some, or all of $key, $rcpt, $enc, and/or $ctr'
    return 16
  fi

  # send an email to key holder with an ascii armored encrypted
  # copy of the their part of the master key.
  if [[ $enc == 1 ]]
  then
    if echo "$key"               | \
       gpg -a -r $rcpt --encrypt | \
       mail -s 'Your master key part for Vault' $rcpt
    then
      rm $pubkey_b64 $pubkey_asc 2>/dev/null

      echo "INFO: PGP encrypted key-part at index $ctr sent to $rcpt successfully"
      return 0
    else
      echo >&2 "ERROR: Failed to send PGP encrypted key-part to $rcpt: gpg exit code $?"
      return 1
    fi
  else
    if echo "$key" | mail -s 'Your master key part for Vault' $rcpt
    then
      echo "INFO: PLAIN TEXT key-part at index $ctr sent to $rcpt successfully"
      return 0
    else
      echo >&2 "ERROR: Failed to send PLAIN TEXT key-part to $rcpt: mail cmd exit code $?"
      return 8
    fi
  fi
}

check_prereqs()
{
  for pr in $PREREQS
  do
    if ! which $pr > /dev/null 2>&1
    then
      echo >&2 "Prereq '$pr' not found in container. Cannot continue."
      exit 100
    fi
  done
}

# Vault status can only work if the server has been started
# and init'ed. If status works then there is noneed to proceed.
if vault init -check
then
  echo >&2 "INFO: Vault is already running and initialized."
  exit 0
fi

check_prereqs
start_vault 
vault_status

if [[ $V_ECODE == 0 ]]
then
  encrypt_msg=$(echo "$VAULT_INIT_VARS" | jq -rM '.encrypt_key_to_rcpt')
  auth_backends="$(echo $VAULT_INIT_VARS | jq -rM '.auth_backends[]')"
  root_token="$(echo "$V_INIT_DATA" | grep 'Initial Root Token' | cut -d : -f 2 | tr -d ' ')"

  failed=0
  ctr=0

  [[ -z "$VAULT_INIT_VARS" ]] && \
    {
      echo >&2 "Cannot continue because \$VAULT_INIT_VARS do not exist."
      exit 1
    }

  echo "INFO: Key threshold for this vault is: $KEY_THRESHOLD"

  # iterate over each unseal key
  for key in $(echo "$V_INIT_DATA" | grep -E "Unseal Key [0-9]:" | awk '{print $4}')
  do
    [[ -z $key || "$key" == "" ]] && \
      {
        echo >&2 "FATAL: Hmm. Unable to extract keys from vault output. Cannot continue."
        exit 10
      }

    vault_status

    if [[ $SEALED == true ]]
    then
      # for each key, determine the corresponding key holder from values.yaml
      master_key_holder="$(echo $VAULT_INIT_VARS | jq -rM --arg i $ctr '.key_masters[($i | tonumber)].email')"

      # master_key_holder is not "null" or empty
      if [[ -n "$master_key_holder" && $master_key_holder != "null" ]]
      then
        if [[ "$encrypt_msg" == "true" ]]
        then
          if prepare_pubkey $master_key_holder $ctr
          then
            if vault unseal $key > /dev/null 2>&1
            then
              if ! email_key $key $master_key_holder 1 $ctr
              then
                echo >&2 "Quitting..."
              fi
            else
              echo >&2 "ERROR: Unseal command for key at index $ctr failed to unseal vault."
            fi
          else
            exit $?
          fi
        else
          if vault unseal $key >/dev/null 2>&1
          then
            if ! email_key $key $master_key_holder 0 $ctr
            then
              echo >&2 "Quitting..."
            fi
          else
            echo >&2 "ERROR: Unseal command for key at index $ctr failed to unseal vault."
          fi
        fi

        ## AND DO WHAT WITH THE ROOT TOKEN?
        let ctr++
      else
        if [[ $ctr -gt 0 ]]
        then
          echo >&2 "INFO: Exhausted all key masters for available keys. Moving on."
          break
        else
          echo >&2 "INFO: No master key holders were found in \$VAULT_INIT_VARS"
          exit 2
        fi
      fi
    else
      echo "INFO: Vault is unsealed."
      break
    fi

    echo
  done

  if [[ -n "$auth_backends" && -n $ROOT_TOKEN ]]
  then
    vault auth $root_token

    for authbackend in $auth_backends
    do
      if vault auth-enable $authbackend
      then
        echo "INFO: auth backend '$authbackend' enabled successfully"
      else
        echo >&2 "WARN: auth backend '$authbackend' FAILED to intialized"
      fi
    done
  fi
else
  echo >&2 "ERROR: VAULT START FAILED: error code was: $V_ECODE"
fi

tail -f /dev/null
