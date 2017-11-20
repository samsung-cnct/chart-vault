#!/bin/busybox sh

set -x 
PREREQS="curl jo jq vault base64 gpg mailx"
TMPSTORE="/var/tmp/init.out"
VAULT_CONFIG="/etc/vault/cfg/config.json"
DEBUG=0

check_args()
{
  case $DEBUG in
    FALSE|False|false|0|f|no)
      DEBUG=0;;
    TRUE|True|true|1|t|yes)
      DEBUG=1;;
    *)
      DEBUG=0;;
  esac
}

validate_tmpstore()
{
  if [[ -e $TMPSTORE ]]
  then
    echo "CHECK ME: $(grep -c "Unseal Key" $TMPSTORE)"
    cat $TMPSTORE
    if [[ $(grep -c "Unseal Key" $TMPSTORE) -gt 0 ]]
    then
      return 0 
    else
      return 2
    fi
  else
    return 1
  fi
}

start_vault()
{
  start_time=$(date +s)
  max_time_allowed=$((3 * 60))

  printenv >&2
  cat >&2 $VAULT_CONFIG

  # if etcd is not up and running yet, then vault will not start.
  # so let's give etcd a little bit to start up.
  while true
  do
    vault server -config $VAULT_CONFIG &
    V_ECODE=$?

    if pidof vault
    then
      sleep 2
      break
    fi

    if [[ $(($(date +%s) - $start_time)) -ge $max_time_allowed ]]
    then
      return 9
    fi

    sleep 1
  done

  # there are a few use cases here to worry about. 
  # happening across multiple containers potentially.
  # is vault already running or not.
  # has vault attempted to init yet or not
  # one of the vaults in the cluster will initialize, but
  #  since these guys don't have IPC, the right hand won't
  #  know what the left hand is doing. So this is a poor man's
  #  way of trying to figure it out.
  validate_tmpstore
  INIT_ECODE=$?

  if [[ $INIT_ECODE == 0 ]]
  then
    V_INIT_DATA=$(cat $TMPSTORE)
    return 0
  else
    echo "INFO: initializing Vault!"
    vault init > $TMPSTORE 2>&1
    validate_tmpstore
    INIT_ECODE=$?
  fi

  # now if $TMPSTORE is still empty (meaning vault is already inited and `vault init`
  # returned an error) then this vault does not have the key data.
  if [[ $INIT_ECODE != 0 ]]
  then
    echo >&2 """
    INFO: this container does not hold the keys (exit code 
    from validate_tmpstore() was $INIT_ECODE). Moving on.
    """
    return $INIT_ECODE
  else
    V_INIT_DATA=$(cat $TMPSTORE)
    return 0
  fi

  return 0
}

vault_unseal()
{
  key=$1
  pl=""

  if [[ -n "$key" ]]
  then
    pl=$(jo key=$key)
  else
    echo >&2 "WARN: usage:  vault_unseal() <master key part>"
    return 256
  fi

  if [[ -n "$pl" ]] 
  then
    # {
    #   "sealed":false,
    #   "t":3,
    #   "n":5,
    #   "progress":0,
    #   "nonce":"",
    #   "version":"0.8.3",
    #   "cluster_name":"vault-cluster-e59ba2fe",
    #   "cluster_id":"7bedd850-6629-fa6f-d109-14330d1a3125"
    # }
    raw_status="$(curl --write-out %{http_code} --silent -X PUT $VAULT_ADDR/v1/sys/unseal -d $pl)"
    json_response="$(echo "$raw_status" | head -1)"
    status_code="$(echo "$raw_status" | tail -1)"

    if [[ $(echo "$status_code" | grep -cE '^[345]..') -gt 0 ]]
    then
      echo """
      FATAL: unsealing failed and vault is not 
      responding properly. HTTP STATUS CODE was: 
      $status_code
      """
      return 201
    fi
  else
    echo >&2 "WARN: payload key for unseal was empty."
    return 200
  fi

  echo "$raw_status"
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
  echo "$VAULT_INIT_VARS" | jq -rM --arg i $ctr '.recipients[($i | tonumber)].pubkey' > $pubkey_b64

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
       mailx -s 'Your master key part for Vault' $rcpt
    then
      rm $pubkey_b64 $pubkey_asc 2>/dev/null

      echo "INFO: PGP encrypted key-part at index $ctr sent to $rcpt successfully"
      return 0
    else
      echo >&2 "ERROR: Failed to send PGP encrypted key-part to $rcpt: gpg exit code $?"
      return 1
    fi
  else
    if echo "$key" | mailx -s 'Your master key part for Vault' $rcpt
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

while [[ $# != 0 ]]
do
  case $1 in
    --debug) 
      shift
      DEBUG=$1
    ;;
    *)
      DEBUG=${enableDebug:-0}
      shift
    ;;
  esac
done

if [[ $DEBUG == 1 ]]
then
  set -x 

  VAULT_INIT_VARS=$(yaml2json ~/projects/cyklops-config-vault/chart-vault-values.yaml | jq '.vault.init')
  VAULT_ADDR=http://127.0.0.1:80
else
  vl_proto="$VAULT_LISTENER_PROTO"
  vl_addr="$VAULT_LISTENER_ADDR"
  vl_port="$VAULT_LISTENER_PORT"

  VAULT_ADDR=$vl_proto://$vl_addr:$vl_port
fi

export VAULT_ADDR VAULT_INIT_VARS

echo "VAULT_ADDR is: $VAULT_ADDR"

check_args
check_prereqs
start_vault; rc=$?
vault_status

echo "return code from start_vault()"
echo "$rc"
num_tries=0
echo "rc is: $rc"
while [[ $rc != 5 && $num_tries -le 3 ]]
do
  ctr=0

  encrypt_msg=$(echo "$VAULT_INIT_VARS" | jq -rM '.encrypt_key_to_rcpt')
  auth_backends="$(echo $VAULT_INIT_VARS | jq -rM '.auth_backends[]')"

  if [[ -n "$V_INIT_DATA" ]]
  then
    root_token="$(echo "$V_INIT_DATA" | \
                  grep 'Initial Root Token' | \
                  cut -d : -f 2 | tr -d ' ')"
  else
    echo >&2 "WARN: vault init returned no output. Skipping."
    let num_tries++
    continue
  fi


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
      master_key_holder="$(echo $VAULT_INIT_VARS | jq -rM --arg i $ctr '.recipients[($i | tonumber)].email')"

      # master_key_holder is not "null" or empty
      if [[ -n "$master_key_holder" && $master_key_holder != "null" ]]
      then
        if [[ "$encrypt_msg" == "true" ]]
        then
          if prepare_pubkey $master_key_holder $ctr
          then
            if vault_unseal $key > /dev/null 2>&1
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
          if vault_unseal $key >/dev/null 2>&1
          then
            if ! email_key $key $master_key_holder 0 $ctr
            then
              echo >&2 "Quitting..."
              exit 99
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

  let num_tries++
done

#  echo >&2 "ERROR: VAULT START FAILED: error code was: $V_ECODE"

tail -f /dev/null
