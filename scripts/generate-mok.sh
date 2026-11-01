#!/bin/bash
# scripts/generate-mok.sh
# Generates a dynamic UEFI MOK (Machine Owner Key) cryptographic keypair
# Compatible with sbsigntool, shim, and MokManager (mmx64.efi)

set -euo pipefail

KEY_FILE="${1:-mok/mok.key}"
CRT_FILE="${2:-mok/mok.crt}"
DER_FILE="${3:-mok/mok.der}"

OUT_DIR=$(dirname "$KEY_FILE")
mkdir -p "$OUT_DIR"

CNF_FILE="$(mktemp /tmp/mok-openssl-XXXXXX.cnf)"

trap 'rm -f "$CNF_FILE"' EXIT

echo "Generating OpenSSL configuration for Secure Boot MOK..."

cat << 'EOF' > "$CNF_FILE"
[ req ]
default_bits            = 2048
distinguished_name      = req_distinguished_name
prompt                  = no
string_mask             = utf8only
x509_extensions         = v3_mok

[ req_distinguished_name ]
O                       = Lenovo 300e Custom Debian
CN                      = Debian Secure Boot MOK
emailAddress            = root@lenovo300e.local

[ v3_mok ]
basicConstraints        = critical,CA:FALSE
keyUsage                = digitalSignature
extendedKeyUsage        = codeSigning,1.3.6.1.4.1.2312.16.1.2
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always,issuer
EOF

echo "Creating RSA 2048-bit private key and X.509 certificate (valid for 10 years)..."
openssl req -new -x509 -newkey rsa:2048 \
    -nodes \
    -days 3650 \
    -sha256 \
    -keyout "$KEY_FILE" \
    -out "$CRT_FILE" \
    -config "$CNF_FILE"

echo "Converting PEM certificate to DER format for UEFI MokManager enrollment..."
openssl x509 -in "$CRT_FILE" -outform DER -out "$DER_FILE"

chmod 600 "$KEY_FILE"
chmod 644 "$CRT_FILE" "$DER_FILE"

echo "=== MOK Keypair Generated Successfully ==="
echo "Private Key: $KEY_FILE"
echo "Public CRT:  $CRT_FILE"
echo "Public DER:  $DER_FILE"
openssl x509 -in "$CRT_FILE" -noout -subject -issuer -fingerprint -sha256
