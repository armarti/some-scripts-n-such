#!/usr/bin/env bash
# https://docs.docker.com/engine/security/https/#daemon-modes
set -eo pipefail

if [ $UID -ne 0 ]; then
    echo "You must run this script as root."
    exit 1
fi

CLNT_HOST="$1"
CLNT_IP="$2"
SRV_HOST="$3"
SRV_PORT="$4"
THIS_FILE="$( realpath "${BASH_SOURCE[0]}" )"
THIS_BNAME="$( basename "$THIS_FILE" )"

if [[ "$CLNT_HOST" == "" ]] || \
   [[ "$CLNT_IP" == "" ]] || \
   [[ "$SRV_HOST" == "" ]] || \
   [[ "$SRV_PORT" == "" ]] || \
   [[ $SRV_PORT -lt 1 ]] || \
   [[ "$CLNT_HOST" == '\-h' ]] || \
   [[ "$CLNT_HOST" == '\-\-help' ]]
then
    echo -e "\n\tUSAGE: $THIS_BNAME [ -h | --help ] <CLNT_HOST> <CLNT_IP> <SERVER_HOST> <SERVER_PORT>\n"
    exit 1
fi

CERTS_D_DIR=/etc/docker/certs.d
CRT_SUBDIR="${SRV_HOST}:$SRV_PORT"
CRT_DIR="$CERTS_D_DIR/$CRT_SUBDIR"
PVT_DIR="$CRT_DIR/private"
CA="$CRT_DIR/ca.crt"
CA_KEY="$CRT_DIR/ca.key"
SRV_CRT="$PVT_DIR/server.crt"

MISSING=''
if [ ! -f "$CA" ]; then MISSING='CA';
elif [ ! -f "$CA_KEY" ]; then MISSING='CA key';
elif [ ! -f "$SRV_CRT" ]; then MISSING='server certificate';
fi
if [ -n "$MISSING" ]; then
    echo "Missing the ${MISSING}. Exiting."
    exit 2
fi

CLNT_EXT="$CRT_DIR/${CLNT_HOST}-extfile.conf"
CLNT_CSR="$CRT_DIR/${CLNT_HOST}.csr"
CLNT_KEY="$CRT_DIR/${CLNT_HOST}.key"
CLNT_CRT="$CRT_DIR/${CLNT_HOST}.crt"

openssl rand -writerand /root/.rnd
echo 'extendedKeyUsage = clientAuth' > "$CLNT_EXT"
openssl genrsa -out "$CLNT_KEY" 4096
openssl req -subj "/CN=$CLNT_HOST" -new -key "$CLNT_KEY" -out "$CLNT_CSR"
openssl x509 -req -days 365 -sha256 -in "$CLNT_CSR" -CA "$CA" -CAkey "$CA_KEY" -CAcreateserial -out "$CLNT_CRT" -extfile "$CLNT_EXT"
rm "$CLNT_CSR" "$CLNT_EXT"
chmod 0400 "$CLNT_KEY"
chmod 0444 "$CLNT_CRT"

SRV_HOST_NODASH="$( echo "${SRV_HOST}" | sed -E 's/[-\.]/_/g' )"
echo -e "\nNew TLS certs are in '$CRT_DIR'."
echo -e "Run these commands from the client:\n"
echo "mkdir -p ~/.docker/$CRT_SUBDIR/ && \\"
echo "  scp \"${USER:-root}@$(hostname):$CA\" ~/.docker/$CRT_SUBDIR/ca.pem && \\"
echo "  scp \"${USER:-root}@$(hostname):$SRV_CRT\" ~/.docker/$CRT_SUBDIR/server.crt && \\"
echo "  scp \"${USER:-root}@$(hostname):$CLNT_CRT\" ~/.docker/$CRT_SUBDIR/cert.pem && \\"
echo "  scp \"${USER:-root}@$(hostname):$CLNT_KEY\" ~/.docker/$CRT_SUBDIR/key.pem"
echo "echo 'function docker_host_init_${SRV_HOST_NODASH}_${SRV_PORT}() {
    export DOCKER_HOST=tcp://${SRV_HOST}:${SRV_PORT}
    export DOCKER_TLS_VERIFY=1
    export DOCKER_CERT_PATH=\"\$HOME/.docker/$CRT_SUBDIR\"
}' >> ~/.bashrc && \\"
echo "echo 'function docker_host_init_${SRV_HOST_NODASH}_${SRV_PORT} -d \"Set Docker host to ${SRV_HOST}:${SRV_PORT}\"
    set -gx DOCKER_HOST tcp://${SRV_HOST}:${SRV_PORT}
    set -gx DOCKER_TLS_VERIFY 1
    set -gx DOCKER_CERT_PATH \"\$HOME/.docker/$CRT_SUBDIR\"
end' >> ~/.config/fish/config.fish"
echo

exit 0
