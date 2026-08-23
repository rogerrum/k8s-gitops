#!/bin/bash

REPO_ROOT=$(git rev-parse --show-toplevel)

die() {
  echo "$*" 1>&2 ; exit 1;
}

need() {
    which "$1" &>/dev/null || die "Binary '$1' is missing but required"
}

need "kubectl"
need "op"

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
#  . "$REPO_ROOT"/setup/.env

  op whoami > /dev/null 2>&1
  OP_SIGNEDIN=$?
  if [ $OP_SIGNEDIN != 0 ]; then
    echo -e "1password (op CLI) is not signed-in, aborting!"
    exit 1
  fi

  message "fetching secrets from 1Password vault"

  OP_ACCESS_TOKEN=$(op read "op://kubernetes/RSR Homelab Access Token/credential")
  #DOCKER_USERNAME=$(op read "op://kubernetes/docker/username")
  #DOCKER_TOKEN=$(op read "op://kubernetes/docker/add more/DOCKER_TOKEN")
  #DOCKER_EMAIL=$("op read op://kubernetes/docker/add more/email")

  message "installing manual secrets and objects"

  ##########
  # secrets
  ##########
  kubectl -n kube-system delete secret op-credentials > /dev/null 2>&1
  kubectl -n kube-system delete secret onepassword-token > /dev/null 2>&1

  #kubectl -n kube-system create secret docker-registry registry-creds-secret --namespace kube-system --docker-username=$DOCKER_USERNAME --docker-password=$DOCKER_TOKEN --docker-email=$DOCKER_EMAIL
  # Write credentials to temp file so kubectl uses single base64 encoding (required for connect chart 2.3.0+)
  op document get "RSR Homelab Credentials File" > /tmp/1password-credentials.json
  kubectl -n kube-system create secret generic op-credentials --from-file=1password-credentials.json=/tmp/1password-credentials.json
  rm /tmp/1password-credentials.json
  kubectl -n kube-system create secret generic onepassword-token --from-literal=token="$(echo $OP_ACCESS_TOKEN)"

}

export KUBECONFIG="$REPO_ROOT/setup/kubeconfig"
installManualObjects

message "all done!"


