#! /bin/sh -ex

[ -z $CHART_NAME   ] && \
  {
    echo >&2 "Var '\$CHART_NAME' is empty. Cannot continue."
    exit 1
  }

[ ! -d ${CHART_NAME} ] && \
  {
    echo >&2 "Directory for chart '$CHART_NAME' does not exist."
    exit 1
  }

# setup kubeconfig
echo "Setting up kubeconfig file"
mkdir /root/.kube
echo ${TEST_KUBECONFIG} | base64 -d > /root/.kube/config

# setup golang
echo "Setting up golang"
wget https://redirector.gvt1.com/edgedl/go/go1.9.2.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.9.2.linux-amd64.tar.gz
mkdir /go
export PATH=$PATH:/usr/local/go/bin:/go/bin
export GOPATH=/go
mkdir /lib64 && ln -s /lib/libc.musl-x86_64.so.1 /lib64/ld-linux-x86-64.so.2
apk add --no-cache --virtual .build-deps gcc build-base libtool sqlite-dev

# setup cloudflare ssl
echo "Setting up cloudflare SSL tools"
go get -u github.com/cloudflare/cfssl/cmd/cfssl
go get -u github.com/cloudflare/cfssl/cmd/cfssljson

# setup kubectl
echo "Setting up kubectl"
wget https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl
chmod +x ./kubectl
mv ./kubectl /usr/local/bin/kubectl

# clone etcd chart repo
echo "Cloning etcd chart repository"
git clone ${ETCD_GIT_REPO} ${ETCD_GIT_FOLDER} --depth 1

# prep the environment
echo "Preparing the test environment"
helm delete --purge ${RELEASE} || /bin/echo "${RELEASE} does not exist. Environment is clean."
kubectl delete namespace ${NAMESPACE} || /bin/echo "${NAMESPACE} does not exist. Environment is clean."

# create the namespace
echo "Creating namespace ${NAMESPACE}"
kubectl create namespace ${NAMESPACE}

# generate tls secrets for etcd in GEN_NAMESPACE
echo "Generating etcd TLS certificates"
etcd-repo/vault-etcd/tls-generator/generate-certs.sh

# generate tls secrets for vault in GEN_NAMESPACE
echo "Generating Vault TLS certificates"
${CHART_NAME}/tls-generator/generate-certs.sh

# lint
helm lint ${CHART_NAME}

# deploy the test chart
echo "Deploying chart"
helm install ${CHART_NAME} \
  --name ${RELEASE} \
  --namespace ${NAMESPACE} \
  --values test/values.yaml \
  --set vault.etcdBackend.address=${GEN_STATEFULSET_NAME}.${NAMESPACE}.svc.cluster.local \
  --set vault.setup.masterSecret=${GEN_STATEFULSET_NAME_VAULT}-unseal

# run helm test
helm test ${RELEASE} --timeout 600