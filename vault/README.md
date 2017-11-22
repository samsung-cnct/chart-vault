## A Helm Chart for CoreOS Dex

## Installation
Install this in your cluster with [Helm](https://github.com/kubernetes/helm):

```
helm repo add cnct http://atlas.cnct.io
```
```
helm install cnct/vault
```

Get Helm [here](https://github.com/kubernetes/helm/blob/master/docs/install.md).

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
        namespace: kube-secret
        values:
          Vault:
            Backend:
              Type: "consul"
              Address: <Your Consul Endpoint>
              Scheme: "http"
              Token: "token"
            Tls:
              Cert: <Your TLS Cert, base64 encoded>
              Key: <Your TLS Key, base64 encoded>
              Ca: <Your TLS CA cert, base64 encoded>
```

Get [K2](https://github.com/samsung-cnct/k2) to help you deploy a Kubernetes cluster.


## Configuration

| Parameter                    | Description                                                       | Default                    |
| -----------------------------| ----------------------------------------------------------------- | -------------------------- |
| vault.image                  | Vault docker image to use.                                        | "quay.io/samsung_cnct/vault" |    
| vault.imageTag               | Version of vault image.                                           | "0.8.3"                      |
| vault.imagePullPolicy        | Pull policy for the docker image.                                 | "Always"                     |
| vault.component              | Name to use for the component.                                    | "vault"                      |
| vault.nodePort               |                                                                   | 32443                        |
| vault.replicas               | Number of vault instances to use.                                 | 1                            |
| vault.cpu                    |                                                                   | "512m"                       |
| vault.memory                 |                                                                   | "200mi"                      |

### etcd Backend
Etcd params used from [here](https://www.vaultproject.io/docs/configuration/storage/etcd.html)

A few facts:
- do not specify protocol as it is defined by definition of Tls.
- ha_enabled is automatically set to true if replicas is > 1 and the backend supports it.


| Parameter                        | Description                                                                                         | Default              |
| ---------------------------------| ----------------------------------------------------------------------------------------------------| -------------------- |
| etcdBackend.type                 | Type of backend supporting vault                                                                    | "etcd"               |    
| etcdBackend.address              | IP address of the backened                                                                          | "etcd-vault-etcd"    |    
| etcdBackend.port                 | etcd client port to use                                                                             | 3379                 |    
| etcdBackend.etcdApi              | API version of etcd. Highly recommend using v3                                                      | "v3"                 |    
| etcdBackend.path                 | Path to store vault data.                                                                           | "vault/"             |    
| etcdBackend.sync                 | Specifies whether to sync the list of available Etcd services on startup                            | "true"               |    
| etcdBackend.username             | Specifies the username to use when authenticating with the etcd server                              | ""                   |    
| etcdBackend.password             | Specifies the password to use when authenticating with the etcd server                              | ""                   |    
| etcdBackend.scheme               | Required for consul backend, ignored by etcd.                                                       | "http"               |    
| etcdBackend.token                | Used for consul but ignored by etcd so no need to remove.                                           | "token"              |    
| etcdBackend.redirectAddr         | The address (full URL) to advertise to other Vault servers in the cluster for client redirection    | ""                   |    
| etcdBackend.clusterAddress       | The address to advertise to other Vault servers in the cluster for request forwarding               | ""                   |    
| etcdBackend.disableClustering    | Whether clustering features such as request forwarding are enabled.                                 | "false"              |    
| etcdBackend.clientCA             | Specifies the path to the CA certificate used for Etcd communication.                               |                      |    
| etcdBackend.clientCert           | Specifies the path to the cert certificate used for Etcd communication.                             |                      |    
| etcdBackend.clientKey            | Specifies the path to the key certificate used for Etcd communication.                              |                      |    



### Consul Backend

| Parameter             | Description                                                          | Default                 |
| ----------------------| -------------------------------------------------------------------- | ----------------------- |
| consulBackend.type    | Type of backend supporting vault.                                    | "consul"                |    
| consulBackend.address | IP address of the backend.                                           |                         |    
| consulBackend.token   | Token to use with backend.                                           | "token"                 |    

 


## Assets
Kubernetes Asset in the chart.

**Vault**
A tool for managing secrets.
See detail in [official site](https://www.vaultproject.io)

default values below
```
Vault:
  Image: "quay.io/samsung_cnct/vault"
  ImageTag: "0.8.3"
  ImagePullPolicy: "Always"
  Component: "vault"

  NodePort: 32443

  Backend:
    Type: "consul"
    Address: "consul.kube-system.svc.cluster.io:8500"
    Scheme: "http"
    Token: "token"

  Replicas: 1
  Cpu: "512m"
  Memory: "200Mi"

  Tls:
    Cert: <TLS Cert, base64 encoded PEM>
    Key: <TLS Key, base64 encoded PEM>
```

for backend,
it support
  - consul
  - inmem

in case of inmem, below vaules is not used
 - address
 - scheme
 - token

## Test
```
export VAULT_ADDR=$VAULT_ENDPOINT
export VAULT_CACERT=$VAULT_CA_PATH
export VAULT_CLIENT_CERT=$VAULT_CERT_PATH
export VAULT_CLIENT_KEY=$VAULT_KEY_PATH

vault init
vault status
```

## Contributing

1. Fork it!
2. Create your feature branch: `git checkout -b my-new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin my-new-feature`
5. Submit a pull request :D

## Credit

Created and maintained by the Samsung Cloud Native Computing Team.
