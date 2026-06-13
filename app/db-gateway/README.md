# DB access via subdomain (closed ports + TLS/mTLS)

Reach internal databases through the front proxy by **subdomain over TLS**, so the
raw DB ports (5432 / 27017 / ...) are never published to the host.

```
client  --TLS(SNI=pg.synergate.space, client-cert)-->  front nginx :7443
        --(SNI passthrough)-->  pg_gateway:8443 (ghostunnel, mTLS)
        --plaintext-->  database:5432
```

## 1. DNS

Point the DB subdomains at the server (same IP as the apps):

```
pg.synergate.space     A   195.189.226.50
mongo.synergate.space  A   195.189.226.50
```

These are routed in the front proxy's `nginx/nginx.conf` (`$db_backend` map) — add a
line there for every new DB subdomain. **No HTTP/ACME cert is needed** for them: TLS
is terminated by the gateway with the private CA below, not by Let's Encrypt.

## 2. Generate certs (once, on the server)

```bash
cd app/db-gateway
./gen-certs.sh
```

- `certs/` stays on the server (mounted read-only into the gateways).
- `client/` (`client.pem`, `client-key.pem`, `ca.pem`) is copied to each developer
  machine. Whoever holds it can connect — treat it like an SSH key.

## 3. Bring the stack up

```bash
docker compose -f app/docker-compose.prod.yaml up -d
```

The gateways join `nginx-proxy-network`, so the front proxy resolves
`synergate_pg_gateway` / `synergate_mongo_gateway` by name.

## 4. Connect from a client machine

Install ghostunnel locally, open a TLS tunnel, then use the DB as if it were local.

**Postgres** (psql does plaintext SSLRequest first, so it MUST go through a tunnel):

```bash
ghostunnel client \
  --listen localhost:5432 \
  --target pg.synergate.space:7443 \
  --cert client.pem --key client-key.pem --cacert ca.pem

psql "host=localhost port=5432 dbname=app user=app"
```

**MongoDB**:

```bash
ghostunnel client \
  --listen localhost:27017 \
  --target mongo.synergate.space:7443 \
  --cert client.pem --key client-key.pem --cacert ca.pem

mongosh "mongodb://user:pass@localhost:27017/db?directConnection=true"
```

> Mongo also supports native `tls=true` (implicit TLS) and could connect straight to
> `mongo.synergate.space:7443` without the local tunnel — but the tunnel gives uniform
> **mTLS** for both DBs, so prefer it.

`stunnel` works the same way if you prefer it over ghostunnel — point `connect` at
`pg.synergate.space:7443` with the client cert/key and CA.

## Adding another app

1. Add `*_pg_gateway` / `*_mongo_gateway` services (copy from
   `docker-compose.prod.yaml`), on the app network + `nginx-proxy-network`.
2. Add the subdomain → `*_gateway:8443` lines to the front `nginx.conf` `$db_backend` map.
3. Add DNS A records and reload the front proxy.
