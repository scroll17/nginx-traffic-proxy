#!/bin/sh
# Generate the nginx maps from single source files:
#   domains.map     -> http :80 ($proxy_upstream) + stream :443 ($backend_name)
#   db-domains.map  -> stream :7443 DB gateways ($db_backend)
# Runs automatically at container start (nginx image executes /docker-entrypoint.d/*.sh
# before launching nginx), and can be re-run via `docker exec` to hot-reload domains.
set -eu

SRC=/etc/nginx/domains.map
DB_SRC=/etc/nginx/db-domains.map
OUT=/etc/nginx/generated
mkdir -p "$OUT"

HTTP="$OUT/http_upstream.map"
STREAM="$OUT/stream_backend.map"
DB_STREAM="$OUT/stream_db_backend.map"

# --- :80 http -> map $host $proxy_upstream { domain container; ... default ""; }
{
    echo '# AUTO-GENERATED from domains.map by generate-maps.sh — DO NOT EDIT.'
    echo 'map $host $proxy_upstream {'
    awk 'NF && $1 !~ /^#/ { printf "    %-28s %s;\n", $1, $2 }' "$SRC"
    echo '    default                  "";'
    echo '}'
} > "$HTTP"

# --- :443 stream -> map $ssl_preread_server_name $backend_name { ... :443; }
{
    echo '# AUTO-GENERATED from domains.map by generate-maps.sh — DO NOT EDIT.'
    echo 'map $ssl_preread_server_name $backend_name {'
    echo '    ""                       reject_sni;   # no SNI (raw IP) -> reject'
    awk 'NF && $1 !~ /^#/ { printf "    %-28s %s:443;\n", $1, $2 }' "$SRC"
    echo '    default                  reject_sni;'
    echo '}'
} > "$STREAM"

# --- :7443 stream -> map $ssl_preread_server_name $db_backend { ... :8443; }
# db-domains.map is optional; if absent the map only rejects.
{
    echo '# AUTO-GENERATED from db-domains.map by generate-maps.sh — DO NOT EDIT.'
    echo 'map $ssl_preread_server_name $db_backend {'
    if [ -f "$DB_SRC" ]; then
        awk 'NF && $1 !~ /^#/ { printf "    %-28s %s:8443;\n", $1, $2 }' "$DB_SRC"
    fi
    echo '    default                  reject_sni;'
    echo '}'
} > "$DB_STREAM"

echo "[generate-maps] wrote $HTTP, $STREAM, $DB_STREAM"
