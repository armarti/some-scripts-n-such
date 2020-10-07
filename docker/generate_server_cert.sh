#!/usr/bin/env bash
# https://docs.docker.com/engine/security/certificates/
set -eo pipefail

if [ $UID -ne 0 ]; then
    echo "You must run this script as root."
    exit 1
fi

SRV_HOST="$1"
SRV_PORT="$2"
SRV_IP="$3"
THIS_FILE="$( realpath "${BASH_SOURCE[0]}" )"
THIS_BNAME="$( basename "$THIS_FILE" )"

if [[ "$SRV_HOST" == "" ]] || \
   [[ "$SRV_PORT" == "" ]] || \
   [[ $SRV_PORT -lt 1 ]] || \
   [[ "$SRV_IP" == "" ]] || \
   [[ "$SRV_HOST" == '\-h' ]] || \
   [[ "$SRV_HOST" == '\-\-help' ]]
then
    echo -e "\n\tUSAGE: $THIS_BNAME [ -h | --help ] <SERVER_HOSTNAME> <SERVER_PORT> <SERVER_IP>\n"
    exit 1
fi

CERTS_D_DIR=/etc/docker/certs.d
CRT_DIR="$CERTS_D_DIR/${SRV_HOST}:${SRV_PORT}"
PVT_DIR="$CRT_DIR/private"
mkdir -p "$PVT_DIR"

CA="$CRT_DIR/ca.crt"
CA_KEY="$CRT_DIR/ca.key"
SRV_CRT="$PVT_DIR/server.crt"
SRV_KEY="$PVT_DIR/server.key"
SRV_EXT="$PVT_DIR/server-extfile.conf"
SRV_CSR="$PVT_DIR/server.csr"

openssl rand -writerand /root/.rnd
openssl genrsa -aes256 -out "$CA_KEY" 4096
openssl req -new -x509 -days 365 \
    -subj "/C=AQ/ST=Adelie Land/L=Dumont DUrville/O=Armarti Industries/CN=$SRV_HOST/OU=homeserver" \
    -key "$CA_KEY" -sha256 -out "$CA"
echo HERE
echo "subjectAltName = DNS:$SRV_HOST,IP:$SRV_IP,IP:127.0.0.1" > "$SRV_EXT"
echo 'extendedKeyUsage = serverAuth' >> "$SRV_EXT"
openssl genrsa -out "$SRV_KEY" 4096
openssl req -subj "/CN=$SRV_HOST" -new -key "$SRV_KEY" -out "$SRV_CSR"
openssl x509 -req -days 365 -sha256 -in "$SRV_CSR" -CA "$CA" -CAkey "$CA_KEY" -CAcreateserial -out "$SRV_CRT" -extfile "$SRV_EXT"
rm "$SRV_CSR" "$SRV_EXT"
chmod 0400 "$SRV_KEY" "$CA_KEY"
chmod 0444 "$SRV_CRT" "$CA"

echo -e "\nNew server TLS certs:"
echo "> '$CRT_DIR'"
ls -Flash "$CRT_DIR"
echo "> '$PVT_DIR'"
ls -Flash "$PVT_DIR"
echo

exit 0
