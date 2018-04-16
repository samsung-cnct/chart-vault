FROM alpine:3.6

LABEL maintainer   "Samsung SDS - J. Conner <snafu.x@gmail.com>"
LABEL purpose      "Hashicorp Vault container build for Samsung SDS auto-init chart"

# Build artifacts for jo
# Note that this is temporary until we get multi-stage builds working for our CICD system
ENV JO_VER         "1.1"
ENV JO_TARBALL     "jo-$JO_VER.tar.gz"
ENV JO_URL         "https://github.com/jpmens/jo/releases/download/v$JO_VER/$JO_TARBALL"
ENV JO_SHASUM      "63ed4766c2e0fcb5391a14033930329369f437d7060a11d82874e57e278bda5f  jo-1.1.tar.gz"
ENV TMPDIR         "/var/tmp"
ENV BUILD_DIR      "$TMPDIR/build"

# This is the release of Vault to pull in.
ENV VAULT_VERSION    0.9.3
ENV RUN_TESTS        false

# build artifacts for kubectl
ENV K8S_BASEURL=https://storage.googleapis.com/kubernetes-release/release
ENV K8S_VER=v1.9.0

# This is the release of https://github.com/hashicorp/docker-base to pull in order
# to provide HashiCorp-built versions of basic utilities like dumb-init and gosu.
ENV DOCKER_BASE_VERSION=0.0.4


# Create a vault user and group first so the IDs get set the same way,
# even as the rest of this may change over time.
RUN addgroup vault &&     adduser -S -G vault vault && \
    mkdir -p $BUILD_DIR && chmod 777 $BUILD_DIR 

WORKDIR $BUILD_DIR

# Set up certificates, our base tools, and Vault.
RUN apk add --no-cache alpine-sdk build-base msmtp mailx curl ca-certificates gnupg openssl libcap jq coreutils && \
    wget $JO_URL && echo "$JO_SHASUM" | sha256sum -c && \
    mkdir jo && zcat $JO_TARBALL | tar -C jo -x --strip-components 1 && \
    cd jo && ./configure --prefix /usr && make all && make install && cd .. && \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 91A6E7F85D05C65630BEF18951852D87348FFC4C && \
    wget https://releases.hashicorp.com/docker-base/${DOCKER_BASE_VERSION}/docker-base_${DOCKER_BASE_VERSION}_linux_amd64.zip && \
    wget https://releases.hashicorp.com/docker-base/${DOCKER_BASE_VERSION}/docker-base_${DOCKER_BASE_VERSION}_SHA256SUMS && \
    wget https://releases.hashicorp.com/docker-base/${DOCKER_BASE_VERSION}/docker-base_${DOCKER_BASE_VERSION}_SHA256SUMS.sig && \
    gpg --batch --verify docker-base_${DOCKER_BASE_VERSION}_SHA256SUMS.sig docker-base_${DOCKER_BASE_VERSION}_SHA256SUMS && \
    grep ${DOCKER_BASE_VERSION}_linux_amd64.zip docker-base_${DOCKER_BASE_VERSION}_SHA256SUMS | sha256sum -c && \
    unzip docker-base_${DOCKER_BASE_VERSION}_linux_amd64.zip && \
    cp bin/gosu bin/dumb-init /bin && \
    wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip && \
    wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS && \
    wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_SHA256SUMS.sig && \
    gpg --batch --verify vault_${VAULT_VERSION}_SHA256SUMS.sig vault_${VAULT_VERSION}_SHA256SUMS && \
    grep vault_${VAULT_VERSION}_linux_amd64.zip vault_${VAULT_VERSION}_SHA256SUMS | sha256sum -c && \
    unzip -d /bin vault_${VAULT_VERSION}_linux_amd64.zip && \
    cd /tmp && \
    rm -rf $BUILD_DIR && \
    apk del openssl alpine-sdk build-base

# /vault/logs is made available to use as a location to store audit logs, if
# desired; /vault/file is made available to use as a location with the file
# storage backend, if desired; the server will be started with /vault/config as
# the configuration directory so you can add additional config files in that
# location.
RUN mkdir -p /vault/logs && \
    mkdir -p /vault/file && \
    mkdir -p /vault/config && \
    chown -R vault:vault /vault

# install kubectl
RUN curl -o /usr/local/bin/kubectl $K8S_BASEURL/$K8S_VER/bin/linux/amd64/kubectl && \
    chmod +x /usr/local/bin/kubectl

WORKDIR /

# Expose the logs directory as a volume since there's potentially long-running
# state in there
VOLUME /vault/logs

# Expose the file directory as a volume since there's potentially long-running
# state in there
VOLUME /vault/file

# 8200/tcp is the primary interface that applications use to interact with
# Vault.
EXPOSE 8200

# The entry point script uses dumb-init as the top-level process to reap any
# zombie processes created by Vault sub-processes.
#
# For production derivatives of this container, you shoud add the IPC_LOCK
# capability so that Vault can mlock memory.
COPY bin/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]

# By default you'll get a single-node development server that stores everything
# in RAM and bootstraps itself. Don't use this configuration for production.
CMD ["server", "-dev"]
