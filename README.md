# A Helm Chart for Hashicorp Vault

## Summary
This chart intalls [Hashicorp Vault](https://www.vaultproject.io) backed by either in-memory storage or with ETCD, with HA. Vault is brought up initialized and sealed, with master keys and root token stored as a kubernetes secret in cluster.

Generated secret will be generated in the same namespace as your helmm release, and will be named as follows:

```
YOUR-RELEASE-NAME-vault-keys
```

Note, that if a secret with the same name already exists, it will be deleted and replaced.

## Installation
Install this in your cluster with [Helm](https://github.com/kubernetes/helm):

```
helm repo add cnct http://atlas.cnct.io
helm install cnct/vault
```
or from local copy
```
git clone git@github.com:samsung-cnct/chart-vault.git
helm install ./chart-vault/vault
```
Or add the following to your [K2](https://github.com/samsung-cnct/k2) configuration template:
```
helmConfigs:
  - &defaultHelm
    name: defaultHelm
    kind: helm
    repos:
      -
        name: atlas
        url: http://atlas.cnct.io
    charts:
      -
        name: vault
        repo: atlas
        chart: vault
        version: 0.1.0
        namespace: your-namespace
```

## Configuration

| Parameter | Description | Default|
| ---| --- | --- |
| vault.image | Vault docker image to use. | "quay.io/samsung_cnct/vault" |    
| vault.imageTag | Version of vault image. | "0.8.3" |
| vault.imagePullPolicy | Pull policy for the docker image. | "Always" |
| vault.component | Name to use for the component. | "vault" |
| vault.nodePort | Override service node port with a preset value | N/A |
| vault.listenerPort | Vault client listener port | 8200 |
| vault.clusterListenerPort | Vault cluster listener port | 8201 |
| vault.backend | Vault storage backend | "etcd" |
| vault.enableTLS | enable TLS for client communication | false |
| vault.enableDebug | Vault debug logs | false |
| vault.replicas | Number of vault instances to use. | 3 |
| vault.secretShares | Number of vault master unseal keys to generate. | 5 |
| vault.unsealShares | Number of vault master unseal keys required to unseal. | 3 |
| vault.initBackoff | Backoff limit for vault initialisation failures. | 10 |
| vault.initDeadline | Total max time for vault init in seconds. | 180 |
| vault.pgpKeys | If desired, array of base64-encoded pgp keys to encrypt master unseal keys with. Size must match secretShares. | N/A |
| vault.rootPgpKey | If desired, base64-encoded pgp key to encrypt root token with. | N/A |
| vault.cpu | Pod cpu millicores | "500m" |
| vault.memory | Pod memory | "200mi" |

### etcd Backend

Note: ha_enabled is automatically set to true if replicas is > 1 and the backend supports it.


| Parameter | Description| Default |
| --- | --- | ---- | 
| etcdBackend.address | IP address of the backened  | "vault-etcd-vault-etcd.vault-etcd-staging" |    
| etcdBackend.port | etcd client port to use  | 3379 |    
| etcdBackend.etcdApi | API version of etcd. Highly recommend using v3 | "v3" |     
| etcdBackend.sync | Specifies whether to sync the list of available Etcd services on startup | "false" |    
| etcdBackend.username | Specifies the username to use when authenticating with the etcd server | N/A |    
| etcdBackend.password | Specifies the password to use when authenticating with the etcd server | N/A |    
| etcdBackend.disableClustering | Whether clustering features such as request forwarding are enabled. | "false" |    
| etcdBackend.clientCA | Specifies the path to the CA certificate used for Etcd communication. | N/A |    
| etcdBackend.clientCert | Specifies the path to the cert certificate used for Etcd communication. | N/A |    
| etcdBackend.clientKey | Specifies the path to the key certificate used for Etcd communication. | N/A | 
| etcdBackend.path | Etcd path for vault storage. | "release-namespace/release-name/" |    


## Contributing

1. Fork it!
2. Create your feature branch: `git checkout -b my-new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin my-new-feature`
5. Submit a pull request :D

## Credit

Created and maintained by the Samsung Cloud Native Computing Team.
