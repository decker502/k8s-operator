#!/usr/bin/env bash

# Bring up a Kubernetes cluster.
#
# If the full release name (gs://<bucket>/<release>) is passed in then we take
# that directly.  If not then we assume we are doing development stuff and take
# the defaults in the release config.

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
source ${KUBE_ROOT}/utils/common.sh

echo
echo -en "${color_red}Warning: All data will be delete (结点所有数据都将被删除)!!! Are you sure you want to delete nodes state? Type 'y' to delete nodes.? (Y/n)${color_norm}" 
read 

if [[ ${REPLY} != "Y" && ${REPLY} != "y" ]]; then
  exit 0
fi

echo -e "${color_green}... calling verify-prereqs${color_norm}" >&2
verify-prereqs
echo

echo -e "${color_green}... calling verify-kube-binaries${color_norm}" >&2
verify-kube-binaries
echo

echo -e "${color_green}... calling remove-node${color_norm}" >&2
remove-nodes ${envfile}
echo -e "${color_green}... remove node done${color_norm}" >&2
echo

