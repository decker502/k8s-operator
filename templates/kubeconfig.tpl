apiVersion: v1
clusters:
- cluster:
    certificate-authority: ${CERT_DIR}/ca.pem
    server: https://${MASTER_ADDRESS}:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: ${NAME}
  name: default
current-context: default
kind: Config
preferences: {}
users:
- name: ${NAME}
  user:
    as-user-extra: {}
    client-certificate: ${CERT_DIR}/${NAME}.pem
    client-key: ${CERT_DIR}/${NAME}-key.pem
