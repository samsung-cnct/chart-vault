#! /usr/local/bin/bash -ex
# don't regenerate secrets for staging if they are already present
if kubectl get secret vault-client-tls -n staging; then
  exit 0;
fi

export PATH=$PATH:/usr/local/go/bin:/go/bin
export GOPATH=/go

# setup tls for vault
GEN_NAMESPACE="${PIPELINE_STAGE_NAMESPACE}"
GEN_CLIENT_SECRET_NAME="vault-client-tls"
GEN_STATEFULSET_NAME_VAULT="vault-${PIPELINE_TEST_NAMESPACE}"
GEN_ACCESS_SERVICE_NAME="${GEN_STATEFULSET_NAME_VAULT}-access"
GEN_IDENTITY_SERVICE_NAME=${GEN_STATEFULSET_NAME_VAULT}
GEN_MAX_PODS=3

# create the namespace
echo "Creating namespace ${GEN_NAMESPACE}"
kubectl create namespace ${GEN_NAMESPACE} || true

# generate tls secrets for vault in GEN_NAMESPACE
echo "Generating etcd TLS certificates"
${PIPELINE_WORKSPACE}/charts/vault/tls-generator/generate-certs.sh