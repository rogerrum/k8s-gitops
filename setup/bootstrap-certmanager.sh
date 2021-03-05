#!/bin/bash

# trap "exit" INT TERM
# trap "kill 0" EXIT

export REPO_ROOT=$(git rev-parse --show-toplevel)

need() {
  if ! command -v "$1" &>/dev/null; then
    echo "Binary '$1' is missing but required"
    exit 1
  fi
}

need "vault"
need "kubectl"
need "sed"
need "jq"

. "$REPO_ROOT"/setup/.env

message() {
  echo -e "\n######################################################################"
  echo "# $1"
  echo "######################################################################"
}

portForwardVault() {
  message "port-forwarding vault"
  kubectl -n kube-system port-forward svc/vault 8200:8200 >/dev/null 2>&1 &
  export VAULT_FWD_PID=$!

  sleep 5
}

loginVault() {
  message "logging into vault"
  if [ -z "$VAULT_ROOT_TOKEN" ]; then
    echo "VAULT_ROOT_TOKEN is not set! Check $REPO_ROOT/setup/.env"
    exit 1
  fi

  vault login -no-print "$VAULT_ROOT_TOKEN" || exit 1

  vault auth list >/dev/null 2>&1
  if [[ "$?" -ne 0 ]]; then
    echo "not logged into vault!"
    echo "1. port-forward the vault service (e.g. 'kubectl -n kube-system port-forward svc/vault 8200:8200 &')"
    echo "2. set VAULT_ADDR (e.g. 'export VAULT_ADDR=http://localhost:8200')"
    echo "3. login: (e.g. 'vault login <some token>')"
    exit 1
  fi
}

createRootCert() {
  vault secrets enable pki
  vault secrets tune -max-lease-ttl=87600h pki

  vault write -field=certificate pki/root/generate/internal common_name="rsr.net" ttl=87600h >CA_cert.crt

  vault write pki/config/urls issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"
}

createIntCert() {
  vault secrets enable -path=pki_int pki
  vault secrets tune -max-lease-ttl=43800h pki_int

  vault write -format=json pki_int/intermediate/generate/internal common_name="rsr.net Intermediate Authority" jq -r '.data.csr' >pki_intermediate.csr

  vault write -format=json pki/root/sign-intermediate csr=@pki_intermediate.csr format=pem_bundle ttl="43800h" jq -r '.data.certificate' >intermediate.cert.pem

  vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem
}

createRole() {
  vault write pki_int/roles/rsr-dot-net allowed_domains="rsr.net" allow_subdomains=true max_ttl="8760h"
}

setupPolicy() {

  # create read-only policy for kubernetes
  cat <<EOF | vault policy write vault-cert-issuer  -

  # Enable secrets engine
  path "sys/mounts/*" {
    capabilities = [ "create", "read", "update", "delete", "list" ]
  }

  # List enabled secrets engine
  path "sys/mounts" {
    capabilities = [ "read", "list" ]
  }

  # Work with pki secrets engine
  path "pki*" {
    capabilities = [ "create", "read", "update", "delete", "list", "sudo" ]
  }

  path "secrets/data/*" {
    capabilities = ["read"]
  }
EOF

}

setupAuth() {
  vault write auth/kubernetes/role/vault-cert-issuer \
    bound_service_account_names="cert-manager" \
    bound_service_account_namespaces="cert-manager" \
    policies=vault-cert-issuer \
    ttl=24h

  vault write pki/config/urls \
    issuing_certificates="http:///vault.kube-system.svc:8200/v1/pki/ca" \
    crl_distribution_points="http:///vault.kube-system.svc:8200/v1/pki/crl"
}

cleanCertManager() {

  vault write pki_int/tidy \
    safety_buffer=5s \
    tidy_cert_store=true \
    tidy_revocation_list=true

  vault secrets disable pki
  vault secrets disable pki_int

}


export KUBECONFIG="$REPO_ROOT/setup/kubeconfig"
export VAULT_ADDR='http://127.0.0.1:8200'

portForwardVault
loginVault

cleanCertManager

createRootCert
createIntCert
createRole
setupPolicy
setupAuth

#  # mount on other nodes
#    mount -t nfs -o proto=tcp,port=2049 192.168.50.108:/export/dell-nfs /dell-nfs

kill $VAULT_FWD_PID
