# Bootstrapping

## Installation (one-time actions)

Once a cluster is in-place, checkout the code on the master node and then run `bootstrap-cluster.sh
`
```sh
cd setup && ./bootstrap-cluster.sh
```

This [script](setup/bootstrap-cluster.sh) does several things:

1. Installs ArgoCD 
2. Init the ArgoCD to automate deployments
3. Bootstraps the vault-secret-operator with the auto-unwrap token
4. Bootstraps cert-manager with letsencrypt information
5. Bootstraps vault (see [bootstrap-vault.sh](setup/bootstrap-vault.sh) for more detail)
   * Initializes vault if it has not already been initialized
   * Unseals vault
   * Configures vault to accept requests from vault-secrets-operator
   * Writes all secrets (held locally in the `.env` file) to vault for vault-secrets-operator to act on
6. Bootstraps vault cert manager

## Cluster maintenance

After initial bootstrapping, it will be necessary to run scripts to apply manual changes that can't be natively handled via ArgoCD.  This is for yaml files that need `envsubst` prior to application to the cluster.  This is also for updates to values stored in **vault**.

### `.env` file

There are references to the `.env` file in the below scripts. This file is automatically sourced in order to populate secrets and sensitive information used in the scripts at runtime. This file is also prevented from commits via `.gitignore`.

A sample [.env.sample](setup/.env.sample) file is provided as reference. To use this, `cp .env.sample .env` and make the necessary modifications for the secrets for your particular configuration.

### Objects

To apply necessary changes to kubernetes native objects, run [bootstrap-objects.sh](setup/bootstrap-objects.sh):

```shell
cd setup && ./bootstrap-objects.sh
```

### Vault updates

To apply new additions or updates to vault, run [bootstrap-vault.sh](setup/bootstrap-vault.sh):

```shell
cd setup && ./bootstrap-vault.sh
```
