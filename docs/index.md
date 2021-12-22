# Home Cluster

This repository _is_ my home Kubernetes cluster in a declarative state. [ArgoCD](https://github.com/argoproj/argo-cd/) watches my repo and makes the changes to my cluster based on the YAML manifests.

Feel free to open a [Github issue](https://github.com/rogerrum/k8s-gitops/issues/new/choose) if you have any questions.


## Cluster setup

My cluster is [k3s](https://k3s.io/) provisioned overtop Ubuntu 20.04. 
This is a semi hyper-converged cluster, workloads and block storage are sharing the same available resources on my nodes while I have a separate server for (NFS) file storage.

## Cluster components

- [metallb](https://metallb.universe.tf/): For internal cluster networking using BGP.
- [longhorn](https://longhorn.io): Provides persistent volumes, allowing any application to consume block storage.
- [cert-manager](https://cert-manager.io/docs/): Configured to create TLS certs for all ingress services automatically using LetsEncrypt.
- [ingress-nginx](https://kubernetes.github.io/ingress-nginx/): My preferred ingress controller to expose traffic to pods over DNS.
- [vault](https://www.vaultproject.io/): Hashicorp Vault to Manage Secrets & Protect Sensitive Data and internal self-signed TLS certs

## Repository structure

The Git repository uses the ArgoCD with App of Apps Pattern. 
The `apps` folder is the root folder which starts the ArgoCD and the ArgoCD handles all other workloads.

- **apps** directory is the root application for ArgoCD, it bootstraps argoCD, infrastructure, main and system-upgrade
- **argocd** directory contains ArgoCD
- **infrastructure** directory are important infrastructure applications that are needed by the main applications
- **main** directory (depends on **infrastructure**) is where your common applications could be placed, ArgoCD will prune resources here if they are not tracked by Git anymore

```
./
├── ./apps
├── ./argocd
├── ./infrastructure
└── ./main
    ├── ./homelab
    ├── ./logs
    └── ./monitoring
```

## Automate all the things!

- [Github Actions](https://docs.github.com/en/actions) for checking code formatting
- Rancher [System Upgrade Controller](https://github.com/rancher/system-upgrade-controller) to apply updates to k3s
- [Renovate](https://github.com/renovatebot/renovate) with the help of the [k8s-at-home/renovate-helm-releases](https://github.com/k8s-at-home/renovate-helm-releases) Github action keeps my application charts and container images up-to-date


## Tools

| Tool                                                   | Purpose                                                   |
|--------------------------------------------------------|-----------------------------------------------------------|
| [k9s](https://github.com/derailed/k9s)                 | Kubernetes CLI To Manage Your Cluster                     |
| [pre-commit](https://github.com/pre-commit/pre-commit) | Enforce code consistency and verifies no secrets are pushed |
| [stern](https://github.com/stern/stern)                | Tail logs in Kubernetes                                   |

## Thanks

A lot of inspiration for this repo came from [billimek/k8s-gitops](https://github.com/billimek/k8s-gitops) and the people that have shared their clusters over at [awesome-home-kubernetes](https://github.com/k8s-at-home/awesome-home-kubernetes)
