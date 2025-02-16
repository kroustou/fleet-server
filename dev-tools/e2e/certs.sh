#!/bin/bash

set -eu

openssl version -a

REPO_ROOT=$(cd $(dirname $(readlink -f "$0"))/../.. && pwd)
CERT_DIR=${REPO_ROOT}/build/e2e-certs

mkdir -p ${CERT_DIR}

# Create CA
openssl req -x509 \
    -sha256 -days 356 \
    -nodes \
    -newkey rsa:2048 \
    -subj "/CN=e2e-test-ca" \
    -keyout ${CERT_DIR}/e2e-test-ca.key -out ${CERT_DIR}/e2e-test-ca.crt \
    2>/dev/null

# Make encrypted private key
echo -n abcd1234 > ${CERT_DIR}/passphrase

openssl genpkey -algorithm RSA \
    -aes-128-cbc \
    -pkeyopt rsa_keygen_bits:2048 \
    -pass file:${CERT_DIR}/passphrase \
    -out ${CERT_DIR}/fleet-server-key \
    2>/dev/null

# Ensure PKCS#1 format is used (https://github.com/elastic/elastic-agent-libs/issues/134)
if [ "$(openssl version | cut -f2 -d' ' | cut -f1 -d.)" -ge 3 ]; then
openssl rsa -aes-128-cbc \
    -traditional \
    -in ${CERT_DIR}/fleet-server-key \
    -out ${CERT_DIR}/fleet-server.key  \
    -passin pass:abcd1234 \
    -passout file:${CERT_DIR}/passphrase \
    2>/dev/null
else
openssl rsa -aes-128-cbc \
    -in ${CERT_DIR}/fleet-server-key \
    -out ${CERT_DIR}/fleet-server.key  \
    -passin pass:abcd1234 \
    -passout file:${CERT_DIR}/passphrase \
    2>/dev/null
fi

# Make CSR
openssl req -new \
    -key ${CERT_DIR}/fleet-server.key \
    -passin file:${CERT_DIR}/passphrase \
    -subj "/CN=localhost" \
    -addext "subjectAltName=IP:127.0.0.1,DNS:localhost,DNS:fleet-server" \
    -out ${CERT_DIR}/fleet-server.csr \
    2>/dev/null

# Sign CSR with CA
openssl x509 -req \
    -in ${CERT_DIR}/fleet-server.csr \
    -days 356 \
    -extfile <(printf "subjectAltName=IP:127.0.0.1,DNS:localhost,DNS:fleet-server") \
    -CA ${CERT_DIR}/e2e-test-ca.crt \
    -CAkey ${CERT_DIR}/e2e-test-ca.key \
    -CAcreateserial \
    -out ${CERT_DIR}/fleet-server.crt \
    2>/dev/null

# Sanity checks
openssl verify -verbose \
    -CAfile ${CERT_DIR}/e2e-test-ca.crt \
    ${CERT_DIR}/fleet-server.crt

openssl rsa -check -noout \
    -in ${CERT_DIR}/fleet-server.key \
    -passin file:${CERT_DIR}/passphrase

go run ./dev-tools/e2e/validatecerts.go ${CERT_DIR}
