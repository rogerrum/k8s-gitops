#!/bin/bash

REPO_ROOT=$(git rev-parse --show-toplevel)

die() {
  echo "$*" 1>&2 ; exit 1;
}

need() {
    which "$1" &>/dev/null || die "Binary '$1' is missing but required"
}

need "kubectl"

message() {
  echo -e "\n######################################################################"
  echo "# $1"
  echo "######################################################################"
}

kapply() {
  if output=$(envsubst < "$@"); then
    printf '%s' "$output" | kubectl apply -f -
  fi
}

installManualObjects(){
  . "$REPO_ROOT"/setup/.env

  message "installing manual secrets and objects"

  ##########
  # secrets
  ##########
  kubectl -n kube-system create secret generic kms-vault --from-literal=account.json="$(echo $VAULT_KMS_ACCOUNT_JSON)"
  kubectl -n kube-system create secret docker-registry registry-creds-secret --namespace kube-system --docker-username=$DOCKER_USERNAME --docker-password=$DOCKER_TOKEN --docker-email=$EMAIL

}

export KUBECONFIG="$REPO_ROOT/setup/kubeconfig"
installManualObjects

message "all done!"
