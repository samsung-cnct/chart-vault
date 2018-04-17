FROM vault:0.9.3
ARG KUBECTL_VERSION=v1.9.2

LABEL maintainer   "Samsung SDS - J. Conner <snafu.x@gmail.com>"
LABEL purpose      "Hashicorp Vault container build for Samsung SDS auto-init chart"

# Set up base tools
RUN apk add --no-cache curl jq git

# Setup kubectl
RUN wget https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl && chmod +x ./kubectl && mv ./kubectl /usr/local/bin/kubectl