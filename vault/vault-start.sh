#!/bin/busybox sh

# Static globals

# TODO add shred and mailx
PREREQS="curl jo jq vault base64 gpg"
TMPSTORE="/var/tmp/init.out"
VAULT_CONFIG="/etc/vault/cfg/config.json"
DEBUG=0

# Jim's project test thing.
proj_debug_values=~/projects/cyklops-config-vault/chart-values/vault-values.yaml

# standardize a way to represent true/false from arguments.
check_bargs()
{
  local arg=$1

  [[ -z "$arg" ]] && \
    {
      echo >&2 "check_bargs() requires arg passed from caller."
      echo "unk"
    }

  case $arg in
    [Ff][Aa][Ll][Ss][Ee]|0|[Nn][Oo])
      echo 0;;
    [Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss])
      echo 1;;
    *)
      echo 0;;
  esac
}

# tmpstore is a temporary place that vault stores its
# output on invocation. What we're really interested in
# is the unseal keys, however, depending on which 
# container vault is running from and whether the vault
# is already initialized, $tmpstore might just be garbage
# output (something we're not really interested in) -- so
# we shouldn't attempt to read gobbledeegook from the file
# unless this function returns 0.
validate_tmpstore()
{
  if [[ -e $TMPSTORE ]]
  then
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

# this starts the vault process. there's logic here that
# attempts to make sure that vault really does get started
# by overcoming some known race conditions between whether
# etcd is up and running. This will hopefully be whittled
# down as a tighter understanding of the pods and how they
# play together gets perfected.
start_vault()
{
  local start_time=$(date +%s)
  local max_secs_allowed=$((3 * 60))

  printenv >&2
  cat >&2 $VAULT_CONFIG

  # if etcd is not up and running yet, then vault will not start.
  # so let's give etcd a little bit to start up.
  while true
  do
    vault server -config $VAULT_CONFIG &

    local now_secs=$(date +%s)
    local vault_rc=$(pidof vault > /dev/null 2>&1; echo $?)

    if [[ $vault_rc == 1 ]]
    then
      echo >&2 """
      INFO: waiting for Vault to start. This usually means
      the storage backend e.g. etcd or consul, is not fully up yet.
      """
    else
      sleep 2
      break
    fi

    if [[ $((now_secs - start_time)) -ge $max_secs_allowed ]]
    then
      echo >&2 """
      WARN: Vault could not start after attempting to start
      for $((max_secs_allowed * 60))
      """

      return 9
    fi

    sleep 5
  done

  # there are a few use cases here to worry about. 
  # happening across multiple containers potentially.
  # is vault already running or not.
  # has vault attempted to init yet or not
  # one of the vaults in the cluster will initialize, but
  #  since these guys don't have IPC, the right hand won't
  #  know what the left hand is doing. So this is a poor man's
  #  way of trying to figure it out.
  if [[ $SKIP_INIT ]]
  then
    echo >&2 'INFO: skipping initialization as requested.'
    return 0
  else
    validate_tmpstore
    local init_ecode=$?

    if [[ $init_ecode == 0 ]]
    then
      V_INIT_DATA=$(cat $TMPSTORE)
      return 0
    else
      echo "INFO: initializing Vault!"
      vault init > $TMPSTORE 2>&1
      validate_tmpstore
      init_ecode=$?
    fi
  fi

  # now if $TMPSTORE is still empty (meaning vault is already inited and `vault init`
  # returned an error) then this vault does not have the key data.
  if [[ $init_ecode != 0 ]]
  then
    echo >&2 """
    INFO: this container does not hold the keys (exit code 
    from validate_tmpstore() was $init_ecode). Moving on.
    """
    return $init_ecode
  else
    V_INIT_DATA=$(cat $TMPSTORE)
  fi

  return 0
}

# unseals the vault. at first we used the vault binary on the container
# to do the unsealing, however, there was a TTY error that was rather
# annoying to get rid of. So now we resort to calling the API directly
# which works.
vault_unseal()
{
  local key=$1
  local pl=""

  if [[ -n "$SKIP_UNSEAL" && "$SKIP_UNSEAL" == 1 ]]
  then
    echo 'INFO: Skipping unseal because "$SKIP_UNSEAL" is true'
    return 46
  fi

  if [[ -n "$key" ]]
  then
    pl=$(jo key=$key)
  else
    echo >&2 "WARN: usage:  vault_unseal() <master key part>"
    return 256
  fi

  if [[ -n "$pl" ]] 
  then
    # return JSON object from init
    #
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

    local raw_status="$(curl --write-out %{http_code} --silent -X PUT $VAULT_ADDR/v1/sys/unseal -d $pl)"
    local json_response="$(echo "$raw_status" | head -1)"
    local status_code="$(echo "$raw_status" | tail -1)"

    if [[ $(echo "$status_code" | grep -cE '^[345]..') -gt 0 ]]
    then
      echo >&2 """
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

# this function only imports the public keys provided in the
# chart values.yaml file into the local public key store used
# by gpg.
prepare_pubkey()
{
  if [[ -n "$ENCRYPT_MSG" ]]
  then
    [[ "$ENCRYPT_MSG" == 0 ]] && return
  fi

  local pubkey_asc=/var/tmp/pubkey.asc
  local pubkey_b64=/var/tmp/pubkey.b64

  local key_holder=$1
  local ctr=$2

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
    echo >&2 "INFO: Now associating key at index $ctr with key holder: $key_holder"

    # base64 decode it
    base64 -d $pubkey_b64 > $pubkey_asc

    echo >&2 "INFO: Importing key:"
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
        return 21
      fi
    else
      echo >&2 "ERROR: ASCII armored public key does not exist. Cannot continue with this key."
      return 22
    fi
  else
    echo >&2 """
    FATAL: Supposed to encrypt but pubkey for $key_holder is empty or not found. 
    No associated public key exists, so quitting.
    """
    return 23
  fi
}

# since busybox is not 1:1 to gnu tools, 
# some alternate methods were required 
# to accomplish the goal here.
vault_status()
{
  local jo_me=""
  local status=$(vault status 2>/dev/null | \
                 grep -E '[a-z]' | \
                 sed -e 's#: #:#g' -e 's/^.*\t//g' | \
                 tr ' ' '_')

  if [[ -z "$status" ]]
  then
    # vault is not yet initialized so status will give bupkiss
    SEALED=1
    return 1
  else
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
      SEALED="$(check_bargs $(echo "$V_STATUS"        | jq -rM '.sealed'))"
      #echo >&2 $V_STATUS
    fi

    return 0
  fi
}

# this function performs the actual emailing of the key to
# an intended recipient. More logic needs to be added to 
# dynamically validate recipients to keys as the number of
# required by vault for unsealing can be dynamically set 
# at runtime. however, no code currently does that so it's
# fairly safe that the defaults for vault are sane enough
# to use at this point (3/5). 
# right now, the problem we have is that containers in pods
# in a cluster do not have a mail forwarder to use to which
# to send emails out of the cluster, so emails fail to send.
#
# this function uses PGP public keys to encrypt the master key
# to its recipients in an ascii armored message body. This should
# be refactored a bit to use the vault pgp backend which will allow
# to identify the master key holders more accurately
# https://www.vaultproject.io/docs/concepts/pgp-gpg-keybase.html
# until then, this will work. The public keys are provided in the
# helm chart values file for now.
email_key()
{
  local key=$1
  local rcpt=$2
  local enc=$3
  local ctr=$4

  if [[ $SKIP_EMAIL == 1 ]]
  then
    echo 'INFO: Skipping sending master keys via email because "$SKIP_EMAIL" is true'
    return 45
  fi

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

# checks to make sure that prereq applications/binaries that this 
# script requires to run are on the system.
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

master_key_holder()
{
  ctr=$1

  [[ -z $ctr ]] && \
    {
      echo >&2 'master_key_holder(): require iteration counter from recipients list.'
      return 32
    }

  local mkh="$(echo "$VAULT_INIT_VARS" | \
                jq -rM --arg i $ctr '.recipients[($i | tonumber)].email')"

  # if master_key_holder is not "null" or empty
  if [[ -n "$mkh" && "$mkh" != "null" ]]
  then
    echo "$mkh"
  fi
}

enable_auth_backends()
{
  if [[ -n "$AUTH_BACKENDS" && -n $ROOT_TOKEN ]]
  then
    vault auth $ROOT_TOKEN

    for ab in $AUTH_BACKENDS
    do
      if vault auth-enable $ab
      then
        echo "INFO: auth backend '$ab' enabled successfully"
      else
        echo >&2 "WARN: auth backend '$ab' FAILED to intialized"
      fi
    done
  fi
}

usage()
{
  cat <<-E
  Usage: $0 [--debug] [--help]
E

}

cleanup()
{
  :
  #echo >&2 'Cleaning up!'
  #shred -z -n3 -u $TMPSTORE
}

# ******************************************************************8
#          START the work!
# ******************************************************************8

# may not work for busybox sh
trap cleanup EXIT

# Check command line args. Right now, only one exists.
while [[ $# != 0 ]]
do
  case $1 in
    --debug) 
      shift
      DEBUG=1
    ;;
    --help)
      shift
      usage
      exit 0
    ;;
    *)
      # enableDebug is an env var.
      DEBUG=${enableDebug:-"false"}
      shift
    ;;
  esac
done

# each boolean variable set to commandline args should
# checked here:
DEBUG=$(check_bargs "$DEBUG")

# set up necessary variables here for runtime.
if [[ $DEBUG == 1 ]]
then
  echo "INFO: DEBUG MODE ON"

  #set -x 
  VAULT_INIT_VARS=$(yaml2json $proj_debug_values | jq '.vault.init')
  VAULT_ADDR=http://127.0.0.1:80
else
  vl_proto="$VAULT_LISTENER_PROTO"
  vl_addr="$VAULT_LISTENER_ADDR"
  vl_port="$VAULT_LISTENER_PORT"

  VAULT_ADDR=$vl_proto://$vl_addr:$vl_port
fi

export VAULT_ADDR VAULT_INIT_VARS

# The following variables are seeded by template/deployment.yaml and 
# the values.yaml file are used by the deployment to give the proper
# values per deployment.
SKIP_INIT="$(check_bargs $(echo "$VAULT_INIT_VARS"            | jq -rM '.skip_init_vault'))"
SKIP_UNSEAL="$(check_bargs $(echo "$VAULT_INIT_VARS"          | jq -rM '.skip_unseal_vault'))"
SKIP_EMAIL="$(check_bargs $(echo "$VAULT_INIT_VARS"           | jq -rM '.skip_sending_email'))"
ENCRYPT_MSG="$(check_bargs $(echo "$VAULT_INIT_VARS"          | jq -rM '.encrypt_key_to_rcpt'))"
ENABLE_AUTH_BACKENDS="$(check_bargs $(echo "$VAULT_INIT_VARS" | jq -rM '.enable_auth_backends'))"
AUTH_BACKENDS="$(echo $VAULT_INIT_VARS          | jq -rM '.auth_backends[]')"

# AAAnnnd...
# Now, do all the work.
echo "INFO: VAULT_ADDR is: $VAULT_ADDR"

check_prereqs
start_vault; start_rc=$?

if [[ $SKIP_INIT == 0 ]]
then

  vault_status

  NUM_TRIES=0

  while [[ $start_rc != 5 && $NUM_TRIES -le 3 ]]
  do
    echo "INFO: Key threshold for this vault is: $KEY_THRESHOLD"

    if [[ -n "$V_INIT_DATA" ]]
    then
      ROOT_TOKEN="$(echo "$V_INIT_DATA" | \
                    grep 'Initial Root Token' | \
                    cut -d : -f 2 | tr -d ' ')"
    else
      echo >&2 "WARN: vault init returned no output. Skipping."
      let NUM_TRIES++
      continue
    fi

    [[ -z "$VAULT_INIT_VARS" ]] && \
      {
        echo >&2 "Cannot continue because \$VAULT_INIT_VARS do not exist."
        exit 1
      }

    if [[ ! $SKIP_UNSEAL ]]
    then
      # iterate over each unseal key
      for key in $(echo "$V_INIT_DATA" | grep -E "Unseal Key [0-9]:" | awk '{print $4}')
      do
        key_ctr=0

        [[ -z $key || "$key" == "" ]] && \
          {
            echo >&2 "FATAL: Hmm. Unable to extract keys from vault output. Cannot continue."
            exit 10
          }

        vault_status

        if [[ -n "$SEALED" ]]
        then
          if [[ $SEALED == 0 ]]
          then
            echo "INFO: vault is not sealed. Exiting."
            exit 0
          fi
        else
          echo "FATAL: Unable to determine if vault is sealed."
          exit 99
        fi

        # for each key, determine the corresponding key holder from values.yaml
        KEY_HOLDER="$(master_key_holder $key_ctr)"

        if [[ -n "$KEY_HOLDER" ]]
        then
          if prepare_pubkey $KEY_HOLDER $key_ctr
          then
            echo "INFO: pub key prep for $KEY_HOLDER complete."
          else
            pk_ec=$?

            if [[ $pk_ec -ge 20 ]]
            then
              echo "FATAL: error occurred while importing public key. Quitting."
              exit $pk_ec
            else
              echo "WARN: pub key prep for $KEY_HOLDER skipped. Moving on."
            fi
          fi

          if vault_unseal $key
          then
            if ! email_key $key $KEY_HOLDER $ENCRYPT_MSG $key_ctr
            then
              if [[ $? == 45 ]]
              then
                # noop return code 45.
                :
              else
                echo >&2 "Quitting..."
                exit 99
              fi
            fi
          else
            if [[ $? != 46 ]]
            then
              echo >&2 "ERROR: Unseal command for key at index $key_ctr failed to unseal vault."
            fi
          fi

          ## XXX TODO AND DO WHAT WITH THE ROOT TOKEN?

          if [[ $key_ctr -ge $KEY_THRESHOLD ]]
          then
            echo >&2 "INFO: Exhausted all key masters for available keys. Moving on."
            break
          fi
        else
          echo >&2 'WARN: Unable to obtain a master key holder from recipients list.'
          exit 30
        fi

        let key_ctr++
        echo
      done

      let NUM_TRIES++
      enable_auth_backends
    else
      echo 'INFO: Skipping unseal because "$SKIP_UNSEAL" is true'
      break
    fi
  done

  cleanup
fi

tail -f /dev/null
