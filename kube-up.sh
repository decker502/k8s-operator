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

echo -e "${color_green}... calling verify-prereqs${color_norm}" >&2
verify-prereqs
echo

echo -e "${color_green}... calling verify-kube-binaries${color_norm}" >&2
verify-kube-binaries
echo

echo -e "${color_green}... calling kube-up${color_norm}" >&2
kube-up ${envfile}
echo -e "${color_green}... kube-up done${color_norm}" >&2

echo

echo -e "${color_green}... calling validate-cluster${color_norm}" >&2
# Override errexit
(validate-cluster) && validate_result="$?" || validate_result="$?"

# We have two different failure modes from validate cluster:
# - 1: fatal error - cluster won't be working correctly
# - 2: weak error - something went wrong, but cluster probably will be working correctly
# We just print an error message in case 2).
if [[ "${validate_result}" == "1" ]]; then
	exit 1
elif [[ "${validate_result}" == "2" ]]; then
	echo "...ignoring non-fatal errors in validate-cluster" >&2
fi
