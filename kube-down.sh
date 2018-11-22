#!/usr/bin/env bash

# Tear down a Kubernetes cluster.

set -o errexit
set -o nounset
set -o pipefail

KUBE_ROOT=$(dirname "${BASH_SOURCE}")

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

echo
echo -en "${color_red}Warning: All data will be delete (集群所有数据都将被删除)!!! Are you sure? (Y/n)${color_norm}" 
read 

if [[ ${REPLY} != "Y" && ${REPLY} != "y" ]]; then
  exit 0
fi

echo -e "${color_green}Bringing down cluster ${color_norm}"

echo -e "${color_green}... calling verify-prereqs${color_norm}" >&2
verify-prereqs
echo

echo -e "${color_green}... calling kube-down${color_norm}" >&2
kube-down

echo -e "${color_green}Done${color_norm}"
echo