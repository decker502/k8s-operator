#!/bin/bash

set -o errexit
set -o pipefail

function make-ssl() {


    if [ -z ${KUBE_MASTER_IP_ADDRESSES} ]; then
        echo "ERROR: Environmental variables MASTERS should be set to generate keys for each host."
        exit 1
    fi

    if [ -z ${CLUSTER_KUBERNETES_SVC_IP} ]; then
        echo "ERROR: Environmental variables CLUSTER_KUBERNETES_SVC_IP should be set ."
        exit 1
    fi

    if [ -z ${LOCAL_CERT_DIR} ]; then
        LOCAL_CERT_DIR="/etc/kubernetes/certs"
    fi

    tmpdir=$(mktemp -d /tmp/kubernetes_cacert.XXXXXX)
    trap 'rm -rf "${tmpdir}"' EXIT
    cd "${tmpdir}"

    mkdir -p "${LOCAL_CERT_DIR}"

    # Root CA
    if [ -e "$LOCAL_CERT_DIR/ca-key.pem" ]; then
        # Reuse existing CA
        cp $LOCAL_CERT_DIR/{ca.pem,ca-key.pem} .
    else
        openssl genrsa -out ca-key.pem 2048 > /dev/null 2>&1
        openssl req -x509 -new -nodes -key ca-key.pem -days 10000 -out ca.pem -subj "/CN=kube-ca" > /dev/null 2>&1
    fi

    gen_key_and_cert() {
        local name=$1
        local subject=$2
        local config="
        [req]
        req_extensions = v3_req
        distinguished_name = req_distinguished_name
        [req_distinguished_name]
        [ v3_req ]
        basicConstraints = CA:FALSE
        keyUsage = nonRepudiation, digitalSignature, keyEncipherment
        extendedKeyUsage = clientAuth, serverAuth
        subjectAltName = ${SAN}
        "

        openssl genrsa -out ${name}-key.pem 2048 > /dev/null 2>&1

        openssl req -new -key ${name}-key.pem -out ${name}.csr -subj "${subject}" -config <(echo -e "${config}") > /dev/null 2>&1
        openssl x509 -req -in ${name}.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out ${name}.pem -days 10000 -extensions v3_req -extfile <(echo -e "${config}") > /dev/null 2>&1
    }

    # Admins

    IP=""
    DNS=""

    for domain in $KUBE_DOMAINS; do
        DNS="${DNS}DNS:${domain},"
    done

    for host in $KUBE_MASTER_IP_ADDRESSES; do
        IP="${IP}IP:${host},"
    done

    IP="${IP}IP:127.0.0.1,IP:${CLUSTER_KUBERNETES_SVC_IP}"

    export SAN=${DNS}${IP}

    # kube-apiserver
    # Generate only if we don't have existing ca and apiserver certs
    if ! [ -e "$LOCAL_CERT_DIR/ca-key.pem" ] || ! [ -e "$LOCAL_CERT_DIR/kube-apiserver-key.pem" ]; then
        gen_key_and_cert "kube-apiserver" "/CN=kube-apiserver"
        cat ca.pem >> kube-apiserver.pem
    fi

    # If any host requires new certs, just regenerate scheduler and controller-manager master certs
    # kube-scheduler
    gen_key_and_cert "kube-scheduler" "/CN=system:kube-scheduler"
    # kube-controller-manager
    gen_key_and_cert "kube-controller-manager" "/CN=system:kube-controller-manager"

    gen_key_and_cert "admin" "/CN=kube-admin/O=system:masters"


    # system:node-proxier
    gen_key_and_cert "kube-proxy" "/CN=system:kube-proxy/O=system:node-proxier"

    # Install certs
    mv -n *.pem ${LOCAL_CERT_DIR}/
}