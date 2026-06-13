#!/bin/sh
# Generate the http (:80) and stream (:443) SNI maps from a single source file.
# Runs automatically at container start (nginx image executes /docker-entrypoint.d/*.sh
# before launching nginx), and can be re-run via `docker exec` to hot-reload domains.
set -eu

SRC=/etc/nginx/domains.map
OUT=/etc/nginx/generated
mkdir -p "$OUT"

HTTP="$OUT/http_upstream.map"
STREAM="$OUT/stream_backend.map"

# --- :80 http -> map $host $proxy_upstream { domain container; ... default ""; }
{
    echo '# AUTO-GENERATED from domains.map by 10-generate-maps.sh — DO NOT EDIT.'
    echo 'map $host $proxy_upstream {'
    awk 'NF && $1 !~ /^#/ { printf "    %-28s %s;\n", $1, $2 }' "$SRC"
    echo '    default                  "";'
    echo '}'
} > "$HTTP"

# --- :443 stream -> map $ssl_preread_server_name $backend_name { ... :443; }
{
    echo '# AUTO-GENERATED from domains.map by 10-generate-maps.sh — DO NOT EDIT.'
    echo 'map $ssl_preread_server_name $backend_name {'
    echo '    ""                       reject_sni;   # no SNI (raw IP) -> reject'
    awk 'NF && $1 !~ /^#/ { printf "    %-28s %s:443;\n", $1, $2 }' "$SRC"
    echo '    default                  reject_sni;'
    echo '}'
} > "$STREAM"

echo "[10-generate-maps] wrote $HTTP and $STREAM from $SRC"
