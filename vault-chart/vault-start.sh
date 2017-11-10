#!/bin/busybox sh
#set -x

#printenv

# XXX this whole script needs to be parameterized from template
#cat /etc/vault/cfg/config.json

pubkey_asc=/var/tmp/pubkey.asc
pubkey_b64=/var/tmp/pubkey.b64

export VAULT_ADDR=http://127.0.0.1:8200

# XXX uncomment this for prod
#/usr/local/bin/vault server -config /etc/vault/cfg/config.json &
#v_init_data=$(vault init)
v_init_data=$(cat startup.txt)
v_ecode=$?

## This will need to be fixed. Since Vault runs in HA mode
## the first vault will init the quorum. The remaining nodes
## will fail to init because the quorum is already initialized
## so we don't want to stop on a false positive. Furthermore,
## vault exits with error code 2 on normal exit. *shrug* will
## need to dig into that further.
if [[ $v_ecode == 0 ]]
then
  key_threshold=$(echo "$v_init_data" | grep "Key Threshold:" | awk -F ':' '{print $2}')
  failed=0
  ctr=0

  [[ -z "$VAULT_INIT_VARS" ]] && \
    {
      echo >&2 "Cannot continue because \$VAULT_INIT_VARS do not exist."
      exit 1
    }

  echo "INFO: Key threshold for this vault is: $key_threshold"

  # iterate over each unseal key
  for key in $(echo "$v_init_data" | grep -E "Unseal Key [0-9]:" | awk '{print $4}')
  do
    # for each key, determine the corresponding key holder from values.yaml
    master_key_holder="$(echo $VAULT_INIT_VARS | jq -rM --arg i $ctr '.vault.init.key_masters[($i | tonumber)].email')"

    # master_key_holder is not "null" or empty
    if [[ -n "$master_key_holder" && $master_key_holder != "null" ]]
    then
      # grab master_key_holder's public key
      echo "$VAULT_INIT_VARS" | jq -rM --arg i $ctr '.vault.init.key_masters[($i | tonumber)].pubkey' > $pubkey_b64

      # if $pubkey_b64 exists and is not empty
      if [[ -s $pubkey_b64 ]]
      then
        echo "INFO: Now associating key at index $ctr with key holder: $master_key_holder"

        # decode it
        base64 -d $pubkey_b64 > $pubkey_asc

        echo "INFO: Importing key:"
        cat $pubkey_asc
        echo

        # import it
        if [[ -s $pubkey_asc ]]
        then
          if gpg --import $pubkey_asc
          then
            # XXX un-echo this for prod
            # Unseal the vault with the $key we're currently on
            if echo vault unseal $key
            then

              # send an email to key holder with an ascii armored encrypted
              # copy of the their part of the master key.
              if echo "$key" | \
                 gpg -a -r $master_key_holder --encrypt | \
                 mail -vs 'Your master key part for Vault' $master_key_holder
              then
                echo "INFO: PGP encrypted key-part at index $ctr sent to $master_key_holder successfully"
              else
                echo >&2 "ERROR: Failed to send PGP encrypted key-part to $master_key_holder: gpg exit code $?"
              fi
            else
              echo >&2 "ERROR: Unseal command for key at index $ctr failed to unseal vault."
              let failed++
            fi

            ## AND DO WHAT WITH THE ROOT TOKEN?
          else
            echo >&2 "ERROR: Unable to import public key for $master_key_holder. GPG error was $?: Skipping."
            let failed++
          fi
        else
          echo >&2 "ERROR: ASCII armored public key does not exist. Cannot continue with this key."
        fi

        let ctr++
        rm $pubkey_b64 $pubkey_asc 2>/dev/null
      else
        echo >&2 "INFO: Skipping import for $master_key_holder because no associated public key exists."
        continue
      fi
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

    echo
  done
else
  echo >&2 "ERROR: VAULT START FAILED: error code was: $v_ecode"
fi
exit
fg 2>/dev/null
