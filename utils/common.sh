#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

KUBE_ROOT=$(cd $(dirname "${BASH_SOURCE}")/.. && pwd)

DEFAULT_KUBECONFIG="${HOME:-.}/.kube/config"

KUBECONFIG=${KUBECONFIG:-$DEFAULT_KUBECONFIG}

if [[ -z "${color_start-}" ]]; then
  declare -r color_start="\033["
  declare -r color_red="${color_start}0;31m"
  declare -r color_yellow="${color_start}0;33m"
  declare -r color_green="${color_start}0;32m"
  declare -r color_norm="${color_start}0m"
fi


# Generate kubeconfig data for the created cluster.
# Assumed vars:
#   KUBE_MASTER_IP
#   KUBECONFIG
#   CONTEXT
#
# If the apiserver supports bearer auth, also provide:
#   KUBE_BEARER_TOKEN
#
# If the kubeconfig context being created should NOT be set as the current context
# SECONDARY_KUBECONFIG=true
#
# To explicitly name the context being created, use OVERRIDE_CONTEXT
#
# The following can be omitted for --insecure-skip-tls-verify
#   KUBE_CERT
#   KUBE_KEY
#   CA_CERT
function create-kubeconfig() {
  local kubectl="${KUBE_ROOT}/binaries/kubectl"
  SECONDARY_KUBECONFIG=${SECONDARY_KUBECONFIG:-}
  OVERRIDE_CONTEXT=${OVERRIDE_CONTEXT:-}

  if [[ "$OVERRIDE_CONTEXT" != "" ]];then
      CONTEXT=$OVERRIDE_CONTEXT
  fi

  # KUBECONFIG determines the file we write to, but it may not exist yet
  OLD_IFS=$IFS
  IFS=':'
  for cfg in ${KUBECONFIG} ; do
    if [[ ! -e "${cfg}" ]]; then
      mkdir -p "$(dirname "${cfg}")"
      touch "${cfg}"
    fi
  done
  IFS=$OLD_IFS

  local cluster_args=(
      "--server=${KUBE_SERVER:-https://${KUBE_MASTER_IP}}"
  )

  if [[ -z "${CA_CERT:-}" ]]; then
    cluster_args+=("--insecure-skip-tls-verify=true")
  else
    cluster_args+=(
      "--certificate-authority=${CA_CERT}"
      "--embed-certs=true"
    )
  fi

  if [[ ! -z "${KUBE_CERT:-}" && ! -z "${KUBE_KEY:-}" ]]; then
    user_args+=(
     "--client-certificate=${KUBE_CERT}"
     "--client-key=${KUBE_KEY}"
     "--embed-certs=true"
    )
  fi

  KUBECONFIG="${KUBECONFIG}" "${kubectl}" config set-cluster "${CONTEXT}" "${cluster_args[@]}" > /dev/null 2>&1
  if [[ -n "${user_args[@]:-}" ]]; then
    KUBECONFIG="${KUBECONFIG}" "${kubectl}" config set-credentials "${CONTEXT}" "${user_args[@]}"  > /dev/null 2>&1
  fi
  KUBECONFIG="${KUBECONFIG}" "${kubectl}" config set-context "${CONTEXT}" --cluster="${CONTEXT}" --user="${CONTEXT}"  > /dev/null 2>&1

  if [[ "${SECONDARY_KUBECONFIG}" != "true" ]];then
      KUBECONFIG="${KUBECONFIG}" "${kubectl}" config use-context "${CONTEXT}"  --cluster="${CONTEXT}"  > /dev/null 2>&1
  fi


  echo "Wrote config for ${CONTEXT} to ${KUBECONFIG}"
}

# Clear kubeconfig data for a context
# Assumed vars:
#   KUBECONFIG
#   CONTEXT
#
# To explicitly name the context being removed, use OVERRIDE_CONTEXT
function clear-kubeconfig() {
  export KUBECONFIG=${KUBECONFIG:-$DEFAULT_KUBECONFIG}
  OVERRIDE_CONTEXT=${OVERRIDE_CONTEXT:-}

  if [[ "$OVERRIDE_CONTEXT" != "" ]];then
      CONTEXT=$OVERRIDE_CONTEXT
  fi

  local kubectl="${KUBE_ROOT}/binaries/kubectl"
  # Unset the current-context before we delete it, as otherwise kubectl errors.
  local cc=$("${kubectl}" config view -o jsonpath='{.current-context}')
  if [[ "${cc}" == "${CONTEXT}" ]]; then
    "${kubectl}" config unset current-context
  fi
  "${kubectl}" config unset "clusters.${CONTEXT}"
  "${kubectl}" config unset "users.${CONTEXT}"
  "${kubectl}" config unset "users.${CONTEXT}-basic-auth"
  "${kubectl}" config unset "contexts.${CONTEXT}"

  echo "Cleared config for ${CONTEXT} from ${KUBECONFIG}"
}

function gen-kube-bootstrap-token-id() {
    KUBE_BOOTSTRAP_TOKEN_ID=$(head -c 6 /dev/urandom | md5sum | head -c 6 2>/dev/null)
}

function gen-kube-bootstrap-token-secret() {
    KUBE_BOOTSTRAP_TOKEN_SECRET=$(head -c 16 /dev/urandom | md5sum | head -c 16 2>/dev/null)
}

function load-or-gen-kube-bootstrap-token() {
  gen-kube-bootstrap-token-id
  gen-kube-bootstrap-token-secret

  # Make sure they don't contain any funny characters.
  if ! [[ "${KUBE_BOOTSTRAP_TOKEN_ID}.${KUBE_BOOTSTRAP_TOKEN_SECRET}" =~ ^[a-z0-9]{6}\.[a-z0-9]{16} ]]; then
    echo "Bad KUBE_BOOTSTRAP_TOKEN string."
    exit 1
  fi
}

# Check whether required binaries exist, prompting to download
# if missing.
# If KUBERNETES_SKIP_CONFIRM is set to y, we'll automatically download binaries
# without prompting.
function verify-kube-binaries() {

  binaries=(
    "kubectl"
    "kube-apiserver"
    "kube-controller-manager"
    "kube-scheduler"
    "kubelet"
    "kube-proxy"
  )

  binary=$( (ls -t "${KUBE_ROOT}/binaries/${binaries[@]}" 2>/dev/null || true) | head -1 )

  if [[ ! -f "${binary}" ]]; then
    echo "!!! Cannot find ${binary}" >&2
    exit 1
  fi
  echo "${binary}"
  
}

# Run kubectl and retry upon failure.
function kubectl_retry() {
  tries=3
  while ! ("${KUBE_ROOT}/binaries/kubectl" "$@"); do
    tries=$((tries-1))
    if [[ ${tries} -le 0 ]]; then
      echo "('kubectl $@' failed, giving up)" >&2
      return 1
    fi
    echo "(kubectl failed, will retry ${tries} times)" >&2
    sleep 1
  done
}

# Run pushd without stack output
function pushd() {
  command pushd $@ > /dev/null
}

# Run popd without stack output
function popd() {
  command popd $@ > /dev/null
}
