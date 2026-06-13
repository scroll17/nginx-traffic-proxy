#!/usr/bin/env bash
#
# Opens a local plaintext port that tunnels over mTLS+SNI to the DB gateway,
# so GUI clients (Compass / DataGrip / redis-cli) connect to localhost.
# Reads settings from ./.env (see .env.sample). Keep running while you work; Ctrl-C to stop.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v ghostunnel >/dev/null 2>&1; then
    echo "ERROR: ghostunnel not found. Install it: brew install ghostunnel" >&2
    exit 1
fi

if [ ! -f .env ]; then
    echo "ERROR: .env not found. Copy the sample first:  cp .env.sample .env" >&2
    exit 1
fi

set -a; . ./.env; set +a

: "${REMOTE_HOST:?set REMOTE_HOST in .env}"
: "${REMOTE_PORT:?set REMOTE_PORT in .env}"
: "${LOCAL_HOST:?set LOCAL_HOST in .env}"
: "${LOCAL_PORT:?set LOCAL_PORT in .env}"
: "${CLIENT_CERT:?set CLIENT_CERT in .env}"
: "${CLIENT_KEY:?set CLIENT_KEY in .env}"
: "${CA_CERT:?set CA_CERT in .env}"

for f in "$CLIENT_CERT" "$CLIENT_KEY" "$CA_CERT"; do
    [ -f "$f" ] || { echo "ERROR: cert file not found: $f (run ../gen-certs.sh or copy the client bundle)" >&2; exit 1; }
done

echo "Tunnel: ${LOCAL_HOST}:${LOCAL_PORT}  ->  ${REMOTE_HOST}:${REMOTE_PORT}  (mTLS). Ctrl-C to stop."
exec ghostunnel client \
    --listen "${LOCAL_HOST}:${LOCAL_PORT}" \
    --target "${REMOTE_HOST}:${REMOTE_PORT}" \
    --cert "${CLIENT_CERT}" \
    --key  "${CLIENT_KEY}" \
    --cacert "${CA_CERT}"
