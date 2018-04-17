#!/bin/bash -
#title          :generate-certs.sh
#author         :Samsung SDSRA
#====================================================================
set -o errexit
set -o nounset
set -o pipefail

my_dir=$(dirname "${BASH_SOURCE}")

POSITIONAL=()

function warn {
  echo -e "\033[1;33mWARNING: $1\033[0m"
}

function error {
  echo -e "\033[0;31mERROR: $1\033[0m"
}

function inf {
  echo -e "\033[0;32m$1\033[0m"
}

# CSR OPTIONS
COUNTRY="US"
CITY="Seattle"
ORGANIZATION="Samsung SDS"
SUB_ORGANIZATION="CNCT"
STATE="Washington"
BITS=2048
ALGO="rsa"

# DEPLOYMENT VARS (INIT VARS)
if [ -z ${GEN_NAMESPACE+x} ]; then
  GEN_NAMESPACE="default"
fi

if [ -z ${GEN_CLIENT_SECRET_NAME+x} ]; then
  GEN_CLIENT_SECRET_NAME="vault-client-tls"
fi

if [ -z ${GEN_STATEFULSET_NAME_VAULT+x} ]; then
  GEN_STATEFULSET_NAME_VAULT="vault"
fi

if [ -z ${GEN_ACCESS_SERVICE_NAME+x} ]; then
  GEN_ACCESS_SERVICE_NAME="${GEN_STATEFULSET_NAME_VAULT}-access"
fi

if [ -z ${GEN_IDENTITY_SERVICE_NAME+x} ]; then
  GEN_IDENTITY_SERVICE_NAME="${GEN_STATEFULSET_NAME_VAULT}"
fi

if [ -z ${GEN_MAX_PODS+x} ]; then
  GEN_MAX_PODS=3
fi

GEN_HOSTS_CLIENT="127.0.0.1"
GEN_CLUSTER_DOMAIN="cluster.local"
CLIENT_HOSTNAMES="${GEN_HOSTS_CLIENT},"
CLIENT_HOSTNAMES+="${GEN_ACCESS_SERVICE_NAME},"
CLIENT_HOSTNAMES+="${GEN_ACCESS_SERVICE_NAME}.${GEN_NAMESPACE},"
CLIENT_HOSTNAMES+="${GEN_ACCESS_SERVICE_NAME}.${GEN_NAMESPACE}.svc.${GEN_CLUSTER_DOMAIN},"
CLIENT_HOSTNAMES+="${GEN_IDENTITY_SERVICE_NAME},"
CLIENT_HOSTNAMES+="${GEN_IDENTITY_SERVICE_NAME}.${GEN_NAMESPACE},"
CLIENT_HOSTNAMES+="${GEN_IDENTITY_SERVICE_NAME}.${GEN_NAMESPACE}.svc.${GEN_CLUSTER_DOMAIN}"

function checkPREREQS() {
    PRE_REQS="cfssljson cfssl kubectl"

    for pr in $PRE_REQS
    do
      if ! which $pr >/dev/null 2>&1
      then
        echo >&2 "prerequisite application called '$pr' is not found on this system"
        return=1
      fi
    done

    return 0
}


EXIT_CODE=$(checkPREREQS)

[[ $EXIT_CODE > 0 ]] && exit $EXIT_CODE

DIR_PATH="${my_dir}/../generated-certs"

# make sure the DIR_PATH exists.
if [ ! -d "$DIR_PATH" ]; then
    mkdir -p $DIR_PATH
fi

echo $DIR_PATH
cd $DIR_PATH

if [[ ! -e ca-key.pem ]]; then
cat <<EOF > ca-config.json
{
    "signing": {
        "default": {
            "expiry": "43800h"
        },
        "profiles": {
            "server": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            },
            "client": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            },
            "peer": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }
    }
}
EOF

# CA CSR
cat <<EOF > ca-csr.json
{
    "CN": "vault CA",
    "key": {
        "algo": "$ALGO",
        "size": $BITS
    },
    "names": [
        {
            "C": "${COUNTRY}",
            "L": "${CITY}",
            "O": "${ORGANIZATION}",
            "OU": "${SUB_ORGANIZATION}",
            "ST": "${STATE}"
        }
    ]
}
EOF
fi

# Client CSR
cat <<EOF > vault-client.json
{
    "CN": "vault-client",
    "hosts": [""],
    "key": {
        "algo": "$ALGO",
        "size": $BITS
    },
    "names": [
        {
            "C": "${COUNTRY}",
            "L": "${CITY}",
            "O": "${ORGANIZATION}",
            "OU": "${SUB_ORGANIZATION}",
            "ST": "${STATE}"
        }
    ]
}
EOF

# generate certs
if [[ ! -e ca-key.pem ]]; then
  inf "generating CA certs..."
  inf 'cfssl gencert -initca ca-csr.json | cfssljson -bare ca'

  cfssl gencert -initca ca-csr.json | cfssljson -bare ca
else
  warn "skipping ca creation, already found."
fi

inf "generating client certs..."
for ((i = 0; i < GEN_MAX_PODS; i++)); do
    inf "Adding pod host name: ${GEN_STATEFULSET_NAME_VAULT}-${i},${GEN_STATEFULSET_NAME_VAULT}-${i}.${GEN_IDENTITY_SERVICE_NAME},${GEN_STATEFULSET_NAME_VAULT}-${i}.${GEN_IDENTITY_SERVICE_NAME}.${GEN_NAMESPACE}.svc.${GEN_CLUSTER_DOMAIN} ..."
    CLIENT_HOSTNAMES="${CLIENT_HOSTNAMES},${GEN_STATEFULSET_NAME_VAULT}-${i},${GEN_STATEFULSET_NAME_VAULT}-${i}.${GEN_IDENTITY_SERVICE_NAME},${GEN_STATEFULSET_NAME_VAULT}-${i}.${GEN_IDENTITY_SERVICE_NAME}.${GEN_NAMESPACE}.svc.${GEN_CLUSTER_DOMAIN}"
done

inf "cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -hostname=${CLIENT_HOSTNAMES} \
      -profile=client vault-client.json | cfssljson -bare vault-client"
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=${CLIENT_HOSTNAMES} \
  -profile=client vault-client.json | cfssljson -bare vault-client

# delete old secrets
inf "deleting old secrets..."
inf "kubectl -n ${GEN_NAMESPACE} delete secret ${GEN_CLIENT_SECRET_NAME} || true"
kubectl -n ${GEN_NAMESPACE} delete secret ${GEN_CLIENT_SECRET_NAME} || true

# create secret
inf "creating secret"
inf "kubectl -n ${GEN_NAMESPACE} create secret generic \
  ${GEN_CLIENT_SECRET_NAME} \
  --from-file=ca.pem\
  --from-file=vault-client.pem \
  --from-file=vault-client-key.pem"
kubectl -n ${GEN_NAMESPACE} create secret generic \
  ${GEN_CLIENT_SECRET_NAME} \
  --from-file=ca.pem\
  --from-file=vault-client.pem \
  --from-file=vault-client-key.pem