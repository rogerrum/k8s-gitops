# Installing Kubernetes


## Cluster Init

!!! info "Download the script to init the cluster on first node"
```sh
wget https://raw.githubusercontent.com/rogerrum/homelab-infrastructure/main/k3s/ha/setupMainNode.sh \
 -O setupMainNode.sh  && chmod +x setupMainNode.sh
```
!!! info "Create cluster and get token to setup the remaining nodes"
```sh
./setupMainNode.sh
```

## Additional master nodes for HA

!!! info "Download the script on HA nodes"
```sh
wget https://raw.githubusercontent.com/rogerrum/homelab-infrastructure/main/k3s/ha/setupHANode.sh \
 -O setupHANode.sh  && chmod +x setupHANode.sh
```
!!! info "Use the token from the First master node to join the cluster"
```sh
./setupHANode.sh <Token>
```


## Add worker nodes

!!! info "Download the script"
```sh
wget https://raw.githubusercontent.com/rogerrum/homelab-infrastructure/main/k3s/ha/setupWorkerNode.sh \
 -O setupWorkerNode.sh  && chmod +x setupWorkerNode.sh
```
!!! info "Use the token from the First master node to join the cluster"
```sh
./setupWorkerNode.sh <Token>
```

## Add worker nodes (arm)

!!! info "Download the script"
```sh
wget https://raw.githubusercontent.com/rogerrum/homelab-infrastructure/main/k3s/ha/setupWorkerNodeArm.sh \
 -O setupWorkerNodeArm.sh  && chmod +x setupWorkerNodeArm.sh
```
!!! info "Use the token from the First master node to join the cluster"
```sh
./setupWorkerNodeArm.sh <Token>
```

## Add worker nodes (arm64)

!!! info "Download the script"
```sh
wget https://raw.githubusercontent.com/rogerrum/homelab-infrastructure/main/k3s/ha/setupWorkerNodeArm64.sh \
 -O setupWorkerNodeArm64.sh  && chmod +x setupWorkerNodeArm64.sh
```
!!! info "Use the token from the First master node to join the cluster"
```sh
./setupWorkerNodeArm64.sh <Token>
```




