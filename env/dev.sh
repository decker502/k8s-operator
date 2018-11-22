#!/usr/bin/env bash

set -e

readonly ENV_ROOT=$(cd $(dirname "${BASH_SOURCE}")/.. && pwd)

export MASTERS=("10.200.0.15 10.200.0.14 10.200.0.13")
export NODES=("10.200.0.14")
export SCALE_NODES=("10.200.0.11")
export REMOVE_NODES=("10.200.0.11")

export MASTER_ADVERTISE_ADDRESS="10.200.0.15"
# export KUBE_SERVER="https://${MASTER_ADVERTISE_ADDRESS}:6443"

export ETCD_SERVERS="https://10.200.0.15:2379,https://10.200.0.14:2379,https://10.200.0.13:2379"

export LOCAL_ETCD_CERT_DIR="${ENV_ROOT}/../etcd/cert/dev"

export REGISTRY_DOMAIN="ccr.ccs.tencentyun.com"
export IMAGE_PATH="mzkube"
export POD_INFRA_CONTAINER_IMAGE="${REGISTRY_DOMAIN}/${IMAGE_PATH}/pause-amd64:3.0"
export COREDNS_IMAGE="${REGISTRY_DOMAIN}/${IMAGE_PATH}/coredns:1.0.6"
export CALICO_NODE_IMAGE="${REGISTRY_DOMAIN}/${IMAGE_PATH}/calico-node:v3.0.3"
export CALICO_CNI_IMAGE="${REGISTRY_DOMAIN}/${IMAGE_PATH}/calico-cni:v2.0.1"
export CALICO_POLICY_IMAGE="${REGISTRY_DOMAIN}/${IMAGE_PATH}/calico-kube-controllers:v2.0.1"

export DOCKER_OPTS="--insecure-registry=$REGISTRY_DOMAIN --exec-opt native.cgroupdriver=cgroupfs --storage-driver=overlay2 --log-opt max-size=100m --log-opt max-file=5"
export DOCKER_SELINUX="--selinux-enabled=false"

# export OIDC_ISSUER_URL="https://keycloak.example.com/auth/realms/kubernetes"

export KUBELET_EXTRA_ARGS="--eviction-hard=memory.available<500Mi,nodefs.available<1Gi,imagefs.available<1Gi \
  --eviction-max-pod-grace-period=40 \
  --eviction-minimum-reclaim=memory.available=300Mi,nodefs.available=1Gi,imagefs.available=1Gi \
  --eviction-soft-grace-period=memory.available=30s,nodefs.available=2m,imagefs.available=2m \
  --eviction-soft=memory.available<500Mi,nodefs.available<2Gi,imagefs.available<2Gi \
  --system-reserved=cpu=100m,memory=1G "