# Preparing Nodes

## Install Ubuntu

Download Ubuntu Server 21.04 ISO and install Ubuntu on each node.

!!! abstract "VLAN Config"

    === "Physical devices (amd64)"

        Select the required VLAN (100) during the server setup

    === "Raspberry Pi (arm)"

        !!! info "For raspberry pi/ARM edit the file"
        ```sh
        sudo vi /etc/netplan/50-cloud-init.yaml
        ```
        
        !!! info "Update the yaml file with the content"
        ```yaml
        # /etc/netplan/50-cloud-init.yaml
        network:
          ethernets:
            eth0:
              dhcp4: true
          vlans:
            vlan100:
              id: 100
              link: eth0
              dhcp4: true
          version: 2
        ```
        !!! info "Validate the network settings"
        ```sh
        sudo netplan try
        ```        
        !!! info "Save the network settings"
        ```sh
        sudo netplan apply
        ```        
        


## Generate SSH Key on host machine

```sh
ssh-keygen -t ed25519 -C "rogerrum@gmail.com"
```

## Copy over SSH key from the host machine

```sh
ssh-copy-id -i ~/.ssh/id_rsa.pub rsr@192.168.50.100
```

## Ubuntu use all partition space

```sh
lsblk
```
```sh
sudo parted /dev/sda print
```
```sh
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
```
```sh
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
```

## Prepare Disks for Longhorn

!!! info "Prepare/mount the additional disks for Longhorn"

```sh
wget https://raw.githubusercontent.com/rogerrum/homelab-infrastructure/main/k3s/ha/setup-disks.sh \
 -O setup-disks.sh  && chmod +x setup-disks.sh
```

!!! info "run `setup-disks.sh` for each additional disk"

```sh
./setup-disks.sh sdb storage
```

