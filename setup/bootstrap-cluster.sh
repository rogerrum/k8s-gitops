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
need "helm"

message() {
  echo -e "\n######################################################################"
  echo "# $1"
  echo "######################################################################"
}

installArgoCd() {
  message "installing argoCD Helm Chart"

  if [ -z "$GITHUB_TOKEN" ]; then
    echo "GITHUB_TOKEN is not set!"
    exit 1
  fi

  if [ -z "$GITHUB_USER" ]; then
    echo "GITHUB_USER is not set!"
    exit 1
  fi

  kubectl create namespace argocd

  kubectl -n argocd create secret generic deployment-git-repo-credentials --from-literal=username=$GITHUB_USER --from-literal=password=$GITHUB_TOKEN

  cd $REPO_ROOT/argocd || exit
  helm repo add argo-cd https://argoproj.github.io/argo-helm
  helm dep update


  helm upgrade --install -n argocd argocd . -f values.yaml

  checkDeployment argocd-application-controller argocd
  checkDeployment argocd-repo-server argocd
  checkDeployment argocd-server argocd
  checkDeployment argocd-redis argocd

  message "argoCD Helm Chart is Ready"

}

checkDeployment() {
  READY=1
  while [ $READY != 0 ]; do
    echo "waiting for $1 to be fully ready..."
    kubectl -n $2 wait --for condition=Available deployment/$1 >/dev/null 2>&1
    READY="$?"
    sleep 5
  done
}

initArgo() {
  message "Setting up argoCD"

  cd $REPO_ROOT || exit

  helm template apps/ | kubectl apply -f -

  #kubectl delete secret -l owner=helm,name=argocd -n argocd

}

kubeConfig() {
  sudo cp /etc/rancher/k3s/k3s.yaml kubeconfig
  sudo chown $(id -u):$(id -g) kubeconfig
  sudo chmod go-r kubeconfig
  sed -i -e 's/127.0.0.1/rancher.rsr.net/g' kubeconfig
  export KUBECONFIG="$REPO_ROOT/setup/kubeconfig"
}

kubeConfig
installArgoCd
initArgo

#"$REPO_ROOT"/setup/bootstrap-objects.sh
#"$REPO_ROOT"/setup/bootstrap-vault.sh

message "all done!"
kubectl get nodes -o=wide
