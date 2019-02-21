# [Deprecated] A Helm Chart for Hashicorp Vault

## Summary
This chart installs [Hashicorp Vault](https://www.vaultproject.io) backed by either in-memory storage or with etcd, with HA. Vault is brought up and, optionally, initialized, unsealed and setup with several secrets and auth backends.

If setup to unseal, the secret with master key shards and root token will be generated in the same namespace as your helm release.

Note, that if a secret with the same name already exists, it will be deleted and replaced.

## Installation
Install this in your cluster with [Helm](https://github.com/kubernetes/helm):

```
git clone git@github.com:samsung-cnct/chart-vault.git
helm registry dep --overwrite
helm dep build
helm install ./chart-vault/vault
```

Should result in something similar to:

```
Pulled package: quay.io/samsung_cnct/vault-etcd (0.0.6-2-0)
 -> appr_charts/samsung_cnct
Updated requirements.yaml

Hang tight while we grab the latest from your chart repositories...
...
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
...

NOTES:
Thank you for installing vault.

Your release is named vault.

Your Vault server located at https://vault-access.default.svc.cluster.local.
It has been:
* Initialized
* Unsealed
* Set up with auth backends
* Set up with secrets backends

Unseal keys and root token are in the 'vault' cluster secret.

To learn more about the release, try:

  $ helm status vault
  $ helm get vault
```

## Configuration

| Parameter | Description | Default|
| ---| --- | --- |
| vault.image | Vault docker image to use. | "quay.io/samsung_cnct/vault:prod" |    
| vault.imagePullPolicy | Pull policy for the docker image. | "Always" |
| vault.nodePort | Override service node port with a preset value. | N/A |
| vault.listenerPort | Vault client listener port. | 8200 |
| vault.clusterListenerPort | Vault cluster listener port. | 8201 |
| vault.backend | Vault storage backend. | "etcd" |
| vault.enableDebug | Enable vault debug output. | "false" |
| vault.replicas | Number of vault instances to use. | 3 |
| vault.secretShares | Number of vault master unseal keys to generate. | 5 |
| vault.unsealShares | Number of vault master unseal keys required to unseal. | 3 |
| vault.initBackoff | Backoff limit in seconds for vault initialization failures. | 10 |
| vault.initDeadline | Total max time for vault init in seconds. | 180 |
| vault.pgpKeys | If desired, array of base64-encoded pgp keys to encrypt master unseal keys with. Size must match secretShares. If set, unseal and backend setup will not happen | N/A |
| vault.rootPgpKey | If desired, base64-encoded pgp key to encrypt root token with. If set, backend setup will not happen. | N/A |
| vault.cpu | Pod cpu millicores | "500m" |
| vault.memory | Pod memory | "200mi" |

### Automatically initializing and unsealing

*THIS FUNCTIONALITY IS NOT RECOMMENDED FOR PRODUCTION USE!*  

Chart can automatically initialize and unseal Vault on deployment. This will result in a cluster secret being created with all of the master unseal key shards and root access token. 

As a compromise you can set the chart to auto-initialize, but also provide `vault.pgpKeys` and `vault.rootPgpKey` parameters, in which case the resulting unseal secret will be encrypted with the provided keys. This makes auto-unsealing impossible however. 

Note that unseal `vault.setup.masterSecret` secret will remain in the helm release namespace until deleted manually.


| Parameter | Description | Default|
| ---| --- | --- |
| vault.setup.init | Perform vault init after deployment. | "true" | 
| vault.setup.unseal | Perform vault unseal after deployment. | "true" |
| vault.setup.masterSecret | Store unseal keys and root token in the secret, if auto-unsealing. | Name of the helm release | 

### Client TLS support 

TLS support for client communication requires a pre-existing cluster secret with TLS certs.

| Parameter | Description| Default |
| --- | --- | ---- |
| vault.tls.enabled | Enable TLS for vault client communication. | false |  
| vault.tls.enabled | Enable TLS for vault client communication. | false |  
| vault.tls.secret.name | Vault tls secret name to mount. | N/A |
| vault.tls.secret.mountPath | Mount secret at this path in pods. | N/A |
| vault.tls.secret.certFile | Vault tls secret cert file key. | N/A |
| vault.tls.secret.keyFile | Vault tls secret key file key. | N/A |
| vault.tls.secret.caFile | Vault tls secret ca file key. | N/A |

There is a [helper script](vault/tls-generator/generate-certs.sh) to generate a client CA, cert and key.  
To use the script, export the following environment variables:

| Variable | Description| Default |
| --- | --- | ---- |
| GEN_NAMESPACE | Release namespace  | "default" | 
| GEN_CLIENT_SECRET_NAME | client tls secret name to create  | "vault-client-tls" | 
| GEN_STATEFULSET_NAME_VAULT | Name of the stateful set to be created by chart (release name)  | "vault" | 
| GEN_NAMESPACE | Release namespace  | "default" | 
| GEN_ACCESS_SERVICE_NAME | Name of the loadbalancing service (Release Name - access) | "access-vault" |
| GEN_IDENTITY_SERVICE_NAME | Headless service name (Release Name) | "vault" |
| GEN_MAX_PODS | Stateful set size (number of replicas) | 3 |
| GEN_CLUSTER_DOMAIN | Cluster domain name | "cluster.local" |

Then run `./generate-certs.sh`:

```
generating CA certs...
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
[INFO] generating a new CA key and certificate from CSR
[INFO] generate received request
[INFO] received CSR
[INFO] generating key: rsa-2048
[INFO] encoded CSR
[INFO] signed certificate with serial number 410998069836753123844768520587372714450635418352
generating client certs...
cfssl gencert       -ca=ca.pem       -ca-key=ca-key.pem       -config=ca-config.json       -hostname=127.0.0.1,vault-access,vault-access.default,vault-access.default.svc.cluster.local       -profile=client vault-client.json | cfssljson -bare vault-client
[INFO] generate received request
[INFO] received CSR
[INFO] generating key: rsa-2048
[INFO] encoded CSR
[INFO] signed certificate with serial number 443766618904816722146416065615646002853886711474
deleting old secrets...
kubectl -n default delete secret vault-client-tls || true
secret "vault-client-tls" deleted
creating secret
kubectl -n default create secret generic   vault-client-tls   --from-file=ca.pem  --from-file=vault-client.pem   --from-file=vault-client-key.pem
secret "vault-client-tls" created
```

### etcd Backend

Note: ha_enabled is automatically set to true if replicas is > 1 and the backend supports it.

| Parameter | Description| Default |
| --- | --- | ---- |
| etcdBackend.address | IP address of the backend  | "vault-etcd-vault-etcd.vault-etcd-staging" |    
| etcdBackend.port | etcd client port to use  | 3379 |    
| etcdBackend.etcdApi | API version of etcd. Highly recommend using v3 | "v3" |     
| etcdBackend.sync | Specifies whether to sync the list of available Etcd services on startup | "false" |    
| etcdBackend.username | Specifies the username to use when authenticating with the etcd server | N/A |    
| etcdBackend.password | Specifies the password to use when authenticating with the etcd server | N/A |    
| etcdBackend.disableClustering | Specifies whether clustering features such as request forwarding are enabled. | "false"     
| etcdBackend.tls.enabled | Enable TLS for etcd backend. | false |    
| etcdBackend.tls.secret.name | Etcd tls secret name to mount. | N/A |
| etcdBackend.tls.secret.certFile | Etcd tls secret cert file key. | N/A |
| etcdBackend.tls.secret.keyFile | Etcd tls secret key file key. | N/A |
| etcdBackend.tls.secret.caFile | Etcd tls secret ca file key. | N/A |    
| etcdBackend.clientKey | Specifies the path to the key certificate used for Etcd communication. | N/A |
| etcdBackend.path | Etcd path for vault storage. | "release-namespace/release-name/" |    


### Setting up backends

If you setup the chart to auto-initialize and auto-unseal, you can also set it up to automatically mount vault auth and secrets backends.


### Auth Backends

| Parameter | Description| Default |
| --- | --- | ---- |
| vault.backends.auth | Dictionary of vault auth backend objects | N/A |

Dictionary key is used as a mount point. Value is a dictionary of [auth backend mount parameters](https://www.vaultproject.io/api/system/auth.html). For example:

```
backends:
  auth:
    github:
      configure:
        organization: samsung-cnct
      enable: 
        type: github
        description: GitHub Auth backend
        config:
          plugin_name: ""
          local: false
        
```

Will result in an [AppRole](https://www.vaultproject.io/api/auth/approle/index.html) backend to be mounted at `/sys/auth/approle'

### Secrets backends

| Parameter | Description| Default |
| --- | --- | ---- |
| vault.backends.secrets | Dictionary of vault secrets backend objects | N/A |

Dictionary key is used as a mount point. Value is a dictionary of [secrets backend mount parameters](https://www.vaultproject.io/api/system/mounts.html):

```
backends:
  secrets:
    aws:
      type: aws
      description: AWS secret backend
      config:
        plugin_name: ""
        default_lease_ttl: 0
        max_lease_ttl: 0
        force_no_cache: false
        local: false
        seal_wrap: false
```

Will result in an [AWS](https://www.vaultproject.io/api/secret/aws/index.html) secret backend to be mounted at `/sys/mounts/aws'


## Contributing

1. Fork it!
2. Create your feature branch: `git checkout -b my-new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin my-new-feature`
5. Submit a pull request :D

## Credit

Created and maintained by the Samsung Cloud Native Computing Team.
