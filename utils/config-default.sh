#!/usr/bin/env bash

readonly root=$(dirname "${BASH_SOURCE}")/..

## Contains configuration values for the CentOS cluster
# The user should have sudo privilege
export MASTER=${MASTER:-""}
export MASTER_IP=${MASTER#*@}

# Define all your master nodes,
# And separated with blank space like <user_1@ip_1> <user_2@ip_2> <user_3@ip_3>.
# The user should have sudo privilege
export MASTERS="${MASTERS:-$MASTER}"

# length-of <arg0>
# Get the length of specific arg0, could be a space-separate string or array.
function length-of() {
  local len=0
  for part in $1; do
    let ++len
  done
  echo $len
}
# Number of nodes in your cluster.
export NUM_MASTERS="${NUM_MASTERS:-$(length-of "$MASTERS")}"

# Get default master advertise address: first master node.
function default-advertise-address() {
  # get the first master node
  local masters_array=(${MASTERS})
  local master=${masters_array[0]}
  echo ${master#*@}
}

# Define advertise address of masters, could be a load balancer address.
# If not provided, the default is ip of first master node.
export MASTER_ADVERTISE_ADDRESS="${MASTER_ADVERTISE_ADDRESS:-$(default-advertise-address)}"
export MASTER_ADVERTISE_IP="${MASTER_ADVERTISE_IP:-$(getent hosts "${MASTER_ADVERTISE_ADDRESS}" | awk '{print $1; exit}')}"

# Define all your minion nodes,
# And separated with blank space like <user_1@ip_1> <user_2@ip_2> <user_3@ip_3>.
# The user should have sudo privilege
export NODES="${NODES:-"centos@172.10.0.12 centos@172.10.0.13"}"

# Number of nodes in your cluster.
export NUM_NODES="${NUM_NODES:-$(length-of "$NODES")}"

# Should be removed when NUM_NODES is deprecated in validate-cluster.sh
export NUM_NODES="${NUM_NODES}"

export SCALE_NODES="${SCALE_NODES:-""}"

export REMOVE_NODES="${REMOVE_NODES:-""}"

LOCAL_ADDONS_DIR="${LOCAL_ADDONS_DIR:-${root}/addons}"
mkdir -p "${LOCAL_ADDONS_DIR}"

LOCAL_CERT_DIR=${LOCAL_CERT_DIR:-"${root}/cert"}
mkdir -p "${LOCAL_CERT_DIR}"
# LOCAL_CERT_DIR path must be absolute.
export LOCAL_CERT_DIR="$(cd "${LOCAL_CERT_DIR}"; pwd)"

# kubernetes 服务 IP (预分配，一般是 SERVICE_CIDR 中第一个IP)
export CLUSTER_KUBERNETES_SVC_IP=${CLUSTER_KUBERNETES_SVC_IP:-"10.96.0.1"}
# define the IP range used for service cluster IPs.
# according to rfc 1918 ref: https://tools.ietf.org/html/rfc1918 choose a private ip range here.
export SERVICE_CLUSTER_IP_RANGE=${SERVICE_CLUSTER_IP_RANGE:-"10.96.0.0/12"}
export NODE_PORT_RANGE=${NODE_PORT_RANGE:-"20000-40000"}

# DNS_SERVER_IP must be a IP in SERVICE_CLUSTER_IP_RANGE
export DNS_SERVER_IP=${DNS_SERVER_IP:-"10.96.0.10"}
export DNS_DOMAIN=${DNS_DOMAIN:-"cluster.local"}
export KUBE_DOMAINS=${KUBE__DOMAINS:-"kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.${DNS_DOMAIN} localhost"}

# Optional: Install cluster DNS.
ENABLE_CLUSTER_DNS="${KUBE_ENABLE_CLUSTER_DNS:-true}"

# Optional: Install Kubernetes UI
ENABLE_CLUSTER_UI="${KUBE_ENABLE_CLUSTER_UI:-false}"


# Admission Controllers to invoke prior to persisting objects in cluster.
# MutatingAdmissionWebhook should be the last controller that modifies the
# request object, otherwise users will be confused if the mutating webhooks'
# modification is overwritten.
# If we included ResourceQuota, we should keep it at the end of the list to
# prevent incrementing quota usage prematurely.
export ADMISSION_CONTROL=${ADMISSION_CONTROL:-"Initializers,NamespaceLifecycle,LimitRanger,ServiceAccount,PersistentVolumeClaimResize,DefaultTolerationSeconds,Priority,StorageObjectInUseProtection,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota,DefaultStorageClass,NodeRestriction"}

# Extra options to set on the Docker command line.
# This is useful for setting --insecure-registry for local registries.
export DOCKER_OPTS=${DOCKER_OPTS:-""}

# set CONTEXT and KUBE_SERVER values for create-kubeconfig() and get-password()
export CONTEXT="dev"
export KUBE_SERVER="https://${MASTER_ADVERTISE_ADDRESS}:6443"
export CA_CERT="${LOCAL_CERT_DIR}/ca.pem"
export KUBE_CERT="${LOCAL_CERT_DIR}/admin.pem"
export KUBE_KEY="${LOCAL_CERT_DIR}/admin-key.pem"

# Timeouts for process checking on master and minion
export PROCESS_CHECK_TIMEOUT=${PROCESS_CHECK_TIMEOUT:-180} # seconds.

export KUBE_BIN_DIR=${KUBE_BIN_DIR:-"/opt/kubernetes/bin"}
export CNI_BIN_DIR=${CNI_BIN_DIR:-"/opt/cni/bin"}
export CNI_ETC_DIR=${CNI_ETC_DIR:-"/etc/cni/net.d"}
export CFG_DIR=${CFG_DIR:-"/etc/kubernetes"}
export CERT_DIR=${CERT_DIR:-"$CFG_DIR/cert"}

export LOCAL_ETCD_CERT_DIR=${LOCAL_ETCD_CERT_DIR:-"${root}/etcd-cert"}
export ETCD_CERT_DIR=${ETCD_CERT_DIR:-"${CFG_DIR}/etcd-cert"}
export ETCD_SERVERS=${ETCD_SERVERS:-"https://10.200.0.15,https://10.200.0.14,https://10.200.0.13"}

export KUBE_ETCD_CAFILE=${KUBE_ETCD_CAFILE:-"${ETCD_CERT_DIR}/ca.pem"}
export KUBE_ETCD_CERTFILE=${KUBE_ETCD_CERTFILE:-"${ETCD_CERT_DIR}/client.pem"}
export KUBE_ETCD_KEYFILE=${KUBE_ETCD_KEYFILE:-"${ETCD_CERT_DIR}/client-key.pem"}

export OIDC_ISSUER_URL=${OIDC_ISSUER_URL:-"https://example.com/auth/realms/kubernetes"}
export OIDC_USERNAME_CLAIM=${OIDC_USERNAME_CLAIM:-"username"}

export KUBECTL_PATH=${KUBECTL_PATH:-"${root}/binaries/master/bin/kubectl"}
export CLUSTER_CIDR=${CLUSTER_CIDR:-"10.24.0.0/12"}

export REGISTRY_DOMAIN=${REGISTRY_DOMAIN:-"registry.example.com"}
export IMAGE_PATH=${IMAGE_PATH:-"kube"}
export POD_INFRA_CONTAINER_IMAGE=${POD_INFRA_CONTAINER_IMAGE:-"${REGISTRY_DOMAIN}/${IMAGE_PATH}/pause-amd64:3.0"}
export COREDNS_IMAGE=${COREDNS_IMAGE:-"${REGISTRY_DOMAIN}/${IMAGE_PATH}/coredns:1.0.6"}
export CALICO_NODE_IMAGE=${CALICO_NODE_IMAGE:-"${REGISTRY_DOMAIN}/${IMAGE_PATH}/calico-node:v3.0.3"}
export CALICO_CNI_IMAGE=${CALICO_CNI_IMAGE:-"${REGISTRY_DOMAIN}/${IMAGE_PATH}/calico-cni:v2.0.1"}
export CALICO_POLICY_IMAGE=${CALICO_POLICY_IMAGE:-"${REGISTRY_DOMAIN}/${IMAGE_PATH}/calico-kube-controllers:v2.0.1"}

export KUBELET_EXTRA_ARGS=${KUBELET_EXTRA_ARGS:-""}

unset -f default-advertise-address concat-etcd-servers length-of concat-etcd-initial-cluster
