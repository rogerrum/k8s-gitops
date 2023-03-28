#!/bin/bash

REPO_ROOT=$(git rev-parse --show-toplevel)

die() {
  echo "$*" 1>&2
  exit 1
}

need() {
  which "$1" &>/dev/null || die "Binary '$1' is missing but required"
}

need "kubectl"
need "op"
need "step"

message() {
  echo -e "\n######################################################################"
  echo "# $1"
  echo "######################################################################"
}

checkOPLogin() {
  message "Checking if signed in on 1password (OP CLI)"
  op whoami >/dev/null 2>&1
  OP_SIGNEDIN=$?
  if [ $OP_SIGNEDIN != 0 ]; then
    echo -e "1password (op CLI) is not signed-in, aborting!"
    exit 1
  fi
}

generateStepCertConfig() {

  #step certificate create "RSR Root CA" rsr_root_ca.crt rsr_root_ca.key --password-file=password.txt --profile root-ca --kty RSA
  #
  #step certificate create "RSR Intermediate CA" rsr_intermediate_ca.crt rsr_intermediate_ca_key \
  #  --profile intermediate-ca --password-file=password.txt --ca rsr_root_ca.crt --ca-key rsr_root_ca.key --ca-password-file=password.txt --kty RSA

  message "Generating Step Helm Config"
  step ca init --deployment-type=standalone \
    --name=RSR --dns=ca.rsr.net --dns=step-certificates.kube-system.svc.cluster.local --address=:9000 --provisioner=roger@rsr.net \
    --password-file=certs/password.txt --helm >certs/temp.yaml

}

extractFromStepConfigAndCreateOPEntries() {

  message "Extracting Certs"
  cat certs/temp.yaml | yq '.inject.certificates.intermediate_ca | trim' >certs/rsr_intermediate_ca.crt
  cat certs/temp.yaml | yq '.inject.certificates.root_ca | trim' >certs/rsr_root_ca.crt

  message "Extracting Cert Keys"
  cat certs/temp.yaml | yq '.inject.secrets.x509.intermediate_ca_key | trim' >certs/rsr_intermediate_ca.key
  cat certs/temp.yaml | yq '.inject.secrets.x509.root_ca_key | trim' >certs/rsr_root_ca.key

  message "Retrieving Base chart values"
  curl https://raw.githubusercontent.com/smallstep/helm-charts/master/step-certificates/values.yaml -o certs/baseValues.yaml

  message "Extracting ca.json"
  #  cat certs/temp.yaml | yq '.inject.config.files."ca.json"' -o=json > certs/ca.json
  yq '. *n load("certs/baseValues.yaml")' certs/temp.yaml | yq '.inject.config.files."ca.json"' -o=json >certs/ca.json

  message "Extracting defaults.json"
  cat certs/temp.yaml | yq '.inject.config.files."defaults.json"' -o=json >certs/defaults.json

  message "Extracting x509_leaf.tpl"
  cat certs/baseValues.yaml | yq '.inject.config.templates."x509_leaf.tpl"' >certs/x509_leaf.tpl

  message "Extracting ssh.tpl"
  cat certs/baseValues.yaml | yq '.inject.config.templates."ssh.tpl"' >certs/ssh.tpl

  message "Extracting kid"
  kid=$(cat certs/temp.yaml | yq '.inject.config.files."ca.json".authority.provisioners[0]' -o=json | jq -r .key.kid)

  message "Extracting provisioner"
  provisioner=$(cat certs/temp.yaml | yq '.inject.config.files."ca.json".authority.provisioners[0]' -o=json | jq -r .name)

  message "Extracting caBundle"
  caBundle=$(cat certs/temp.yaml | yq '.inject.certificates.root_ca | trim')

  #  fingerprint=$(cat certs/temp.yaml | yq '.inject.config.files."defaults.json".fingerprint')
  #  echo "provisioners: $provisioners" >certs/provisioners.txt
  #  echo "fingerprint: $fingerprint" >certs/fingerprint.txt

  message "Deleting OP - RSR CA Config"
  op item delete "RSR CA Config" --vault='kubernetes'  >/dev/null 2>&1

  message "Creating OP - RSR CA Config"
  op item create --category=Database --title='RSR CA Config' --vault='kubernetes' \
    "provisioner=$provisioner" "kid=$kid" "caBundle=$caBundle"

  message "Creating OP - Root CA"
  op document delete "RSR Root CA" --vault='kubernetes' >/dev/null 2>&1
  op document create "certs/rsr_root_ca.crt" --title "RSR Root CA" --vault='kubernetes'

  message "Creating OP - Root CA Key"
  op document delete "RSR Root CA Key" --vault='kubernetes' >/dev/null 2>&1
  op document create "certs/rsr_root_ca.key" --title "RSR Root CA Key" --vault='kubernetes'

  message "Creating OP - Intermediate CA"
  op document delete "RSR Intermediate CA" --vault='kubernetes' >/dev/null 2>&1
  op document create "certs/rsr_intermediate_ca.crt" --title "RSR Intermediate CA" --vault='kubernetes'

  message "Creating OP - Intermediate CA Key"
  op document delete "RSR Intermediate CA Key" --vault='kubernetes' >/dev/null 2>&1
  op document create "certs/rsr_intermediate_ca.key" --title "RSR Intermediate CA Key" --vault='kubernetes'

}

createKubeConfigMapForCerts() {
  message "Creating Kube Config - step-certificates-certs"
  kubectl -n kube-system delete configmap step-certificates-certs >/dev/null 2>&1
  kubectl -n kube-system create configmap step-certificates-certs --from-file=intermediate_ca.crt=certs/rsr_intermediate_ca.crt --from-file=root_ca.crt=certs/rsr_root_ca.crt

  message "Creating Kube Config - step-certificates-config"

  kubectl -n kube-system delete configmap step-certificates-config >/dev/null 2>&1
  kubectl -n kube-system create configmap step-certificates-config \
    --from-file=ca.json=certs/ca.json \
    --from-file=defaults.json=certs/defaults.json \
    --from-file=x509_leaf.tpl=certs/x509_leaf.tpl \
    --from-file=ssh.tpl=certs/ssh.tpl

}

getCAPassword() {

  message "Creating Certs Dir"
  mkdir -p certs

  message "Retrieving CA Password"
  password=$(op read "op://kubernetes/RSR CA Password/password")
  echo "$password" >certs/password.txt

}

export KUBECONFIG="$REPO_ROOT/setup/kubeconfig"

checkOPLogin

getCAPassword

generateStepCertConfig
extractFromStepConfigAndCreateOPEntries
createKubeConfigMapForCerts

message "all done!"
