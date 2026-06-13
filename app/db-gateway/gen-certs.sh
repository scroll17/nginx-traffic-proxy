#!/usr/bin/env bash
#
# Generates the mTLS material for the DB gateways:
#   certs/ca.pem            - private CA (trust anchor for both sides)
#   certs/server-cert.pem   - server cert presented by ghostunnel (SAN = DB subdomains)
#   certs/server-key.pem
#   client/client.pem       - client cert (CN=db-client) used by ghostunnel client / stunnel
#   client/client-key.pem
#
# Config comes from ./.env (see .env.sample). Run once per app; keep certs/ on the
# server and client/ on the developer machine.
#
# GUARD: refuses to run if certs/ or client/ already exist (so you don't silently
# clobber certificates the running gateways already trust). To rotate, pass FORCE=1.
set -euo pipefail
cd "$(dirname "$0")"

# --- 1. Load details from .env ---------------------------------------------
if [ -f .env ]; then
    set -a            # export everything sourced, so child openssl calls inherit it
    . ./.env
    set +a
else
    echo "ERROR: .env not found. Copy .env.sample to .env first:" >&2
    echo "  cp .env.sample .env" >&2
    exit 1
fi

# Defaults for anything the .env didn't set.
DB_GATEWAY_SANS="${DB_GATEWAY_SANS:-}"
DB_CLIENT_CN="${DB_CLIENT_CN:-db-client}"
DB_CA_CN="${DB_CA_CN:-db-gateway-ca}"
DB_SERVER_CN="${DB_SERVER_CN:-db-gateway}"
DB_CERT_DAYS="${DB_CERT_DAYS:-3650}"
DB_KEY_BITS="${DB_KEY_BITS:-4096}"

if [ -z "$DB_GATEWAY_SANS" ]; then
    echo "ERROR: DB_GATEWAY_SANS is empty — set it in .env (e.g. pg.example.com,mongo.example.com)" >&2
    exit 1
fi

# Turn "a.com, b.com" into the openssl SAN form "DNS:a.com,DNS:b.com".
SERVER_SANS="$(echo "$DB_GATEWAY_SANS" | awk -F, '{
    for (i = 1; i <= NF; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i); if ($i != "") printf "%sDNS:%s", (i > 1 ? "," : ""), $i }
}')"

# --- 2. Guard: do not overwrite existing material ---------------------------
if [ -d certs ] || [ -d client ]; then
    if [ "${FORCE:-0}" != "1" ]; then
        echo "ERROR: certs/ or client/ already exists — refusing to overwrite." >&2
        echo "       The running gateways trust the current CA; regenerating breaks them." >&2
        echo "       To rotate intentionally, re-run with: FORCE=1 ./gen-certs.sh" >&2
        exit 1
    fi
    echo "WARN: FORCE=1 set — removing existing certs/ and client/ and regenerating."
    rm -rf certs client
fi

mkdir -p certs client

echo "Generating mTLS material (SAN=${SERVER_SANS}, client CN=${DB_CLIENT_CN}, ${DB_CERT_DAYS}d)..."

# --- CA ---------------------------------------------------------------------
openssl genrsa -out certs/ca-key.pem "$DB_KEY_BITS"
openssl req -x509 -new -nodes -key certs/ca-key.pem -sha256 -days "$DB_CERT_DAYS" \
  -subj "/CN=${DB_CA_CN}" -out certs/ca.pem

# --- Server cert (used by ghostunnel `server`) ------------------------------
openssl genrsa -out certs/server-key.pem "$DB_KEY_BITS"
openssl req -new -key certs/server-key.pem -subj "/CN=${DB_SERVER_CN}" -out certs/server.csr
openssl x509 -req -in certs/server.csr -CA certs/ca.pem -CAkey certs/ca-key.pem \
  -CAcreateserial -days "$DB_CERT_DAYS" -sha256 \
  -extfile <(printf "subjectAltName=%s\nextendedKeyUsage=serverAuth" "$SERVER_SANS") \
  -out certs/server-cert.pem

# --- Client cert (used by ghostunnel `client` / stunnel on the dev machine) --
openssl genrsa -out client/client-key.pem "$DB_KEY_BITS"
openssl req -new -key client/client-key.pem -subj "/CN=${DB_CLIENT_CN}" -out client/client.csr
openssl x509 -req -in client/client.csr -CA certs/ca.pem -CAkey certs/ca-key.pem \
  -CAcreateserial -days "$DB_CERT_DAYS" -sha256 \
  -extfile <(printf "extendedKeyUsage=clientAuth") \
  -out client/client.pem

# The client side also needs the CA to verify the server.
cp certs/ca.pem client/ca.pem

rm -f certs/*.csr client/*.csr certs/*.srl
echo "Done. Server material in ./certs , client bundle in ./client (copy to dev machine)."
