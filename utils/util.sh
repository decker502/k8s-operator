#!/usr/bin/env bash

# exit on any error
set -e

if [ $# -le 0 ];then
  echo -e "Environment para should be set" >&2
  exit 1
fi

envfile=$1

SSH_OPTS="-oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=ERROR -C"

# Use the config file specified in $KUBE_CONFIG_FILE, or default to
# config-default.sh.
readonly ROOT=$(cd $(dirname "${BASH_SOURCE}")/.. && pwd)
source "${ROOT}/${KUBE_CONFIG_FILE:-"utils/config-default.sh"}"

source "${ROOT}/utils/common.sh"

# Directory to be used for master and node provisioning.
KUBE_TEMP="~/kube_temp"


# Get master IP addresses and store in KUBE_MASTER_IP_ADDRESSES[]
# Must ensure that the following ENV vars are set:
#   MASTERS
function detect-masters() {
  KUBE_MASTER_IP_ADDRESSES=()
  for master in ${MASTERS}; do
    KUBE_MASTER_IP_ADDRESSES+=("${master#*@}")
  done
  echo "KUBE_MASTERS: ${MASTERS}" 1>&2
  echo "KUBE_MASTER_IP_ADDRESSES: [${KUBE_MASTER_IP_ADDRESSES[*]}]" 1>&2
}

# Get node IP addresses and store in KUBE_NODE_IP_ADDRESSES[]
function detect-nodes() {
  KUBE_NODE_IP_ADDRESSES=()
  for node in ${NODES}; do
    KUBE_NODE_IP_ADDRESSES+=("${node#*@}")
  done
  echo "KUBE_NODE_IP_ADDRESSES: [${KUBE_NODE_IP_ADDRESSES[*]}]" 1>&2
}

# Verify prereqs on host machine
function verify-prereqs() {
  local rc
  rc=0
  ssh-add -L 1> /dev/null 2> /dev/null || rc="$?"
  # "Could not open a connection to your authentication agent."
  if [[ "${rc}" -eq 2 ]]; then
    eval "$(ssh-agent)" > /dev/null
    trap-add "kill ${SSH_AGENT_PID}" EXIT
  fi
  rc=0
  ssh-add -L 1> /dev/null 2> /dev/null || rc="$?"
  # "The agent has no identities."
  if [[ "${rc}" -eq 1 ]]; then
    # Try adding one of the default identities, with or without passphrase.
    ssh-add || true
  fi
  rc=0
  # Expect at least one identity to be available.
  if ! ssh-add -L 1> /dev/null 2> /dev/null; then
    echo "Could not find or add an SSH identity."
    echo "Please start ssh-agent, add your identity, and retry."
    exit 1
  fi
}

# Install handler for signal trap
function trap-add {
  local handler="$1"
  local signal="${2-EXIT}"
  local cur

  cur="$(eval "sh -c 'echo \$3' -- $(trap -p ${signal})")"
  if [[ -n "${cur}" ]]; then
    handler="${cur}; ${handler}"
  fi

  trap "${handler}" ${signal}
}

# Validate a kubernetes cluster
function validate-cluster() {
  # by default call the generic validate-cluster.sh script, customizable by
  # any cluster provider if this does not fit.
  set +e
  "${ROOT}/utils/validate-cluster.sh" ${envfile}
  if [[ "$?" -ne "0" ]]; then
    for master in ${MASTERS}; do
      troubleshoot-master ${master}
    done
    for node in ${NODES}; do
      troubleshoot-node ${node}
    done
    exit 1
  fi
  set -e
}

function troubleshoot-master() {
  # Troubleshooting on master if all required daemons are active.
  echo "[INFO] Troubleshooting on master $1"
  local -a required_daemon=("kube-apiserver" "kube-controller-manager" "kube-scheduler")
  local daemon
  local daemon_status
  printf "%-24s %-10s \n" "PROCESS" "STATUS"
  for daemon in "${required_daemon[@]}"; do
    local rc=0
    kube-ssh "${1}" "sudo systemctl is-active ${daemon}" >/dev/null 2>&1 || rc="$?"
    if [[ "${rc}" -ne "0" ]]; then
      daemon_status="inactive"
    else
      daemon_status="active"
    fi
    printf "%-24s %s\n" ${daemon} ${daemon_status}
  done
  printf "\n"
}

function troubleshoot-node() {
  # Troubleshooting on node if all required daemons are active.
  echo "[INFO] Troubleshooting on node ${1}"
  local -a required_daemon=("kube-proxy" "kubelet" "docker")
  local daemon
  local daemon_status
  printf "%-24s %-10s \n" "PROCESS" "STATUS"
  for daemon in "${required_daemon[@]}"; do
    local rc=0
    kube-ssh "${1}" "sudo systemctl is-active ${daemon}" >/dev/null 2>&1 || rc="$?"
    if [[ "${rc}" -ne "0" ]]; then
      daemon_status="inactive"
    else
      daemon_status="active"
    fi
    printf "%-24s %s\n" ${daemon} ${daemon_status}
  done
  printf "\n"
}

function create-bootstrap-token() {
  echo "[INFO] create-bootstrap-token"
  # https://mritd.me/2018/08/28/kubernetes-tls-bootstrapping-with-bootstrap-token/
  load-or-gen-kube-bootstrap-token
  MAX_ATTEMPTS=100
  attempt=0
  while true; do
    n=$(KUBE_BOOTSTRAP_TOKEN_ID=${KUBE_BOOTSTRAP_TOKEN_ID} \
      KUBE_BOOTSTRAP_TOKEN_SECRET=${KUBE_BOOTSTRAP_TOKEN_SECRET} \
      envsubst <  ${ROOT}/templates/bootstrap-token-secret.yaml \
      | kubectl_retry create -f - ; ret=$?; echo .; exit "$ret") && res="$?" || res="$?"
    if [ "${res}" -eq "0" ];then
      break
    fi

    if [[ "${attempt}" -gt "${last_run:-$MAX_ATTEMPTS}" ]]; then
      echo -e "${color_red} Failed to create bootstrap token secret.${color_norm}"
      exit 1
    else
      attempt=$((attempt+1))
      continue
    fi
  done
  
}

function provision-calico() {
  echo "[INFO] provision-calico"
  kubectl_retry apply -f ${ROOT}/templates/calico-rbac.yaml  > /dev/null 2>&1

  CALICO_ETCD_CA=$(cat ${LOCAL_ETCD_CERT_DIR}/ca.pem | base64 -w0) \
  CALICO_ETCD_CERT=$(cat ${LOCAL_ETCD_CERT_DIR}/client.pem | base64 -w0) \
  CALICO_ETCD_KEY=$(cat ${LOCAL_ETCD_CERT_DIR}/client-key.pem | base64 -w0) \
  envsubst <  ${ROOT}/templates/calico.yaml > ${ROOT}/addons/calico.yaml
  
  kubectl_retry apply -f ${ROOT}/addons/calico.yaml  > /dev/null 2>&1
}

function kube-up-nodes() {
  local nodes=("$@")

  num_nodes="${#nodes[@]}"

  if [[ "${num_nodes}" -gt 0 ]];then
    create-bootstrap-token
  fi

  for node in ${nodes}; do
    provision-node "${node}" "${KUBE_BOOTSTRAP_TOKEN_ID}" "${KUBE_BOOTSTRAP_TOKEN_SECRET}"
  done

  for node in ${nodes}; do
    echo "[INFO] start service for ${node}"

    kube-ssh "${node}" "sudo systemctl daemon-reload;"

    services=("kubelet kube-proxy docker")
    for service in ${services}; do
      kube-ssh "${node}" "sudo systemctl enable ${service};"
      kube-ssh "${node}" "sudo systemctl restart ${service}" &
    done
  done

  wait
}

# Instantiate a kubernetes cluster
function kube-up() {

  if [[ "${NUM_MASTERS}" -gt 0 ]];then
    detect-masters
    make-ca-cert

    for master in ${MASTERS}; do
      # 需要并发执行，否则etcd 多实例时会出现超时，集群无法启动
      provision-master "${master}" 
    done

    for master in ${MASTERS}; do
      echo "[INFO] start service for ${master}"
      services=("kube-apiserver kube-controller-manager kube-scheduler")
      for service in ${services}; do
        kube-ssh "${master}" "sudo systemctl daemon-reload; sudo systemctl enable ${service};"
        kube-ssh "${master}" "sudo systemctl restart ${service}" &
      done
    done

    wait

    create-kubeconfig
    provision-calico
    kubectl_retry apply -f ${ROOT}/templates/clusterrole.yaml  > /dev/null 2>&1
  fi

  kube-up-nodes "${NODES[@]}"

}

# Scale up  kubernetes cluster
function kube-scale() {

  kube-up-nodes "${SCALE_NODES[@]}"

}

# Generate the CA certificates for k8s components
function make-ca-cert() {
  echo "[INFO] make-ca-cert"
  source ${ROOT}/utils/make-ssl.sh
  make-ssl
}

# Provision master
#
# Assumed vars:
#   $1 (master)
#   KUBE_TEMP
#   ETCD_SERVERS
#   SERVICE_CLUSTER_IP_RANGE
#   MASTER_ADVERTISE_ADDRESS
function provision-master() {
  echo "[INFO] Provision master on $1"
  local master="$1"
  local master_ip="${master#*@}"

  ensure-setup-dir "${master}"

  echo "[INFO] Scp files"
  kube-scp "${master}" "${ROOT}/binaries/kube-apiserver \
    ${ROOT}/binaries/kube-controller-manager \
    ${ROOT}/binaries/kube-scheduler \
    ${ROOT}/binaries/kubectl"  "${KUBE_BIN_DIR}"
    
  kube-scp "${master}" "${LOCAL_CERT_DIR}/*" "${CERT_DIR}"
  kube-scp "${master}" "${LOCAL_ETCD_CERT_DIR}/ca.pem \
    ${LOCAL_ETCD_CERT_DIR}/client.pem \
    ${LOCAL_ETCD_CERT_DIR}/client-key.pem" "${ETCD_CERT_DIR}"

  kube-ssh-pipe "${master}" "NAME=kube-controller-manager MASTER_ADDRESS=127.0.0.1 CERT_DIR=${CERT_DIR} \
    envsubst <  ${ROOT}/templates/kubeconfig.tpl" \
    "sudo cat > ${CFG_DIR}/kube-controller-manager.kubeconfig"

  kube-ssh-pipe "${master}" "NAME=kube-scheduler MASTER_ADDRESS=127.0.0.1 CERT_DIR=${CERT_DIR} \
    envsubst <  ${ROOT}/templates/kubeconfig.tpl" \
    "sudo cat > ${CFG_DIR}/kube-scheduler.kubeconfig"

  kube-scp "${master}" "${ROOT}/templates/audit-policy.yaml" "${CFG_DIR}"

  echo "[INFO] Setup"

  components="kube-apiserver.service kube-controller-manager.service kube-scheduler.service"
  for component in ${components};do
    kube-ssh-pipe "${master}" "MASTER_ADDRESS=${master_ip} envsubst <  ${ROOT}/templates/${component}" " \
      sudo cat > /etc/systemd/system/${component}"
  done

  kube-ssh "${master}" "sudo chmod -R +x ${KUBE_BIN_DIR} "
}

# Provision node
#
# Assumed vars:
#   $1 (node)
#   KUBE_TEMP
#   MASTER_ADVERTISE_ADDRESS
#   DOCKER_OPTS
#   DOCKER_SELINUX
#   DNS_SERVER_IP
#   DNS_DOMAIN
function provision-node() {
  echo "[INFO] Provision node on $1"
  local node=$1
  local bootstrap_token_id=$2
  local bootstrap_token_secret=$3
  local node_ip=${node#*@}
  local dns_ip=${DNS_SERVER_IP#*@}
  local dns_domain=${DNS_DOMAIN#*@}
  ensure-setup-dir ${node}

  kube-scp "${node}" "${ROOT}/binaries/kubelet ${ROOT}/binaries/kube-proxy" "${KUBE_BIN_DIR}"
  kube-scp "${node}" "${LOCAL_CERT_DIR}/ca*.pem ${LOCAL_CERT_DIR}/kube-proxy*.pem" "${CERT_DIR}"

  components="kubelet.service kube-proxy.service"
  for component in ${components};do
    NODE_ADDRESS=${node_ip} \
    kube-ssh-pipe "${node}" "envsubst <  ${ROOT}/templates/${component}" " \
      sudo cat > /etc/systemd/system/${component}"
  done

  if [[ -n "${DOCKER_OPTS}" ]]; then
    kube-ssh-pipe "${node}" "envsubst <  ${ROOT}/templates/docker-opts.conf" " \
      sudo cat > /etc/systemd/system/docker.service.d/docker-opts.conf"
  fi

  if [[ -n "${DOCKER_SELINUX}" ]]; then
    kube-ssh-pipe "${node}" "envsubst <  ${ROOT}/templates/docker-selinux.conf" " \
      sudo cat > /etc/systemd/system/docker.service.d/docker-selinux.conf"
  fi

  kube-ssh-pipe "${node}" "envsubst <  ${ROOT}/templates/${component}" " \
      sudo cat > /etc/systemd/system/${component}"

  kube-ssh-pipe "${node}" "KUBE_BOOTSTRAP_TOKEN_ID=${bootstrap_token_id} \
    KUBE_BOOTSTRAP_TOKEN_SECRET=${bootstrap_token_secret} \
    envsubst <  ${ROOT}/templates/bootstrap.kubeconfig" " \
      sudo cat > ${CFG_DIR}/bootstrap.kubeconfig"

  kube-ssh-pipe "${node}" "NAME=kube-proxy MASTER_ADDRESS=${MASTER_ADVERTISE_ADDRESS} CFG_DIR=${CFG_DIR} \
    envsubst <  ${ROOT}/templates/kubeconfig.tpl" \
    "sudo cat > ${CFG_DIR}/kube-proxy.kubeconfig"

  NODE_ADDRESS=${node_ip} \
  kube-ssh-pipe "${node}" "envsubst <  ${ROOT}/templates/kubelet-config.yaml" " \
      sudo cat > ${CFG_DIR}/kubelet-config.yaml"

  kube-ssh "${node}" "sudo chmod -R +x ${KUBE_BIN_DIR}"
}

function provision-bootstrap-token() {
  echo "[INFO] Provision bootstrap token on $1"
}

function remove-nodes() {

  for node in ${REMOVE_NODES[@]}; do
    remove-node "${node}" &
  done

  wait
}

# Remove a node
function remove-node() {
  echo "[INFO] Remove node on $1"
  local node=$1
  local node_ip=${node#*@}

  kubectl_retry drain \
      --force \
      --ignore-daemonsets \
      --grace-period 300 \
      --timeout 360s \
      --delete-local-data ${node_ip} 

  tear-down-node ${node_ip}

  kubectl_retry delete node ${node_ip} 
}

# Delete a kubernetes cluster
function kube-down() {

  for node in ${NODES}; do
    tear-down-node ${node}
  done

  for master in ${MASTERS}; do
    tear-down-master ${master}
  done


}

# Clean up on master
function tear-down-master() {
  echo "[INFO] tear-down-master on $1"
  for service_name in kube-apiserver kube-controller-manager kube-scheduler ; do
      service_file="/etc/systemd/system/${service_name}.service"
      kube-ssh "$1" " \
        if [[ -f $service_file ]]; then \
          sudo systemctl stop $service_name; \
          sudo systemctl disable $service_name; \
          sudo rm -f $service_file; \
        fi"
  done

  kube-ssh "$1" "sudo rm -rf ${KUBE_BIN_DIR}"
  kube-ssh "${1}" "sudo rm -rf ${CFG_DIR}"
}

# Clean up on node
function tear-down-node() {
echo "[INFO] tear-down-node on $1"
  for service_name in kube-proxy kubelet ; do
      service_file="/etc/systemd/system/${service_name}.service"
      kube-ssh "$1" " \
        if [[ -f $service_file ]]; then \
          sudo systemctl stop $service_name; \
          sudo systemctl disable $service_name; \
          sudo rm -f $service_file; \
        fi"
  done

  docker ps -aq | xargs -r docker rm -fv

  kube-ssh "$1" "sudo systemctl stop docker; \
    sudo systemctl disable docker; "

  kube-ssh "$1" "sudo rm -rf ${KUBE_BIN_DIR} \ 
    sudo rm -rf ${CFG_DIR}; \
    sudo rm -rf ${CNI_ETC_DIR}; \
    sudo rm -rf /etc/systemd/system/docker.service.d "
  
  kube-ssh "$1" "sudo mount | grep /var/lib/kubelet/ | awk '{print \$3}' |xargs umount -f"
}


# Create dirs that'll be used during setup on target machine.
#
# Assumed vars:
#   KUBE_TEMP
function ensure-setup-dir() {
  kube-ssh "${1}" "sudo mkdir -p ${CNI_BIN_DIR} ${CNI_ETC_DIR} ${KUBE_BIN_DIR} /etc/systemd/system/docker.service.d/; \
                   sudo mkdir -p ${CFG_DIR} ${CERT_DIR} ${ETCD_CERT_DIR}"
}

# Run command over ssh
function kube-ssh() {
  local host="$1"
  shift
  ssh ${SSH_OPTS} -t "${host}" "$@" >/dev/null 2>&1
}

# Run command over ssh pipe
function kube-ssh-pipe() {
  local host="$1"
  local pipe="$2"
  shift 2
  eval "${pipe}" | ssh ${SSH_OPTS} -t "${host}" "$@" >/dev/null 2>&1
}

# Copy file recursively over ssh
function kube-scp() {
  local host="$1"
  local src=($2)
  local dst="$3"
  rsync -avzuq  ${src[*]} "${host}:${dst}"
}

