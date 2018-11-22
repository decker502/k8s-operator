#!/usr/bin/env bash

# deploy the add-on services after the cluster is available

set -e

KUBE_ROOT=$(cd $(dirname "${BASH_SOURCE}") && pwd)

if [ $# -le 0 ];then
  echo -e "Environment para should be set" >&2
  exit 1
fi

envfile=$1
if [ -f "${KUBE_ROOT}/env/${envfile}.sh" ]; then
  source "${KUBE_ROOT}/env/${envfile}.sh"
else
  echo -e "Canot find Environment file  ${KUBE_ROOT}/env/${envfile}.sh " >&2
  exit 1
fi

source ${KUBE_ROOT}/utils/util.sh
source ${KUBE_ROOT}/utils/common.sh

function deploy_coredns() {
  echo "[INFO] Deploying coredns"
  envsubst <  ${KUBE_ROOT}/templates/coredns.yaml > ${KUBE_ROOT}/addons/coredns.yaml
  kubectl_retry apply -f ${KUBE_ROOT}/addons/coredns.yaml  > /dev/null 2>&1

  echo
}

function deploy_dashboard {
  echo "Deploying Kubernetes Dashboard"


  echo
}

if [ "${ENABLE_CLUSTER_DNS}" == true ]; then
  deploy_coredns
fi

if [ "${ENABLE_CLUSTER_UI}" == true ]; then
  deploy_dashboard
fi

