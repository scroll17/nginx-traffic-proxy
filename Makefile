NGINX_CONTAINER ?= nginx_proxy

.PHONY: domains reload test up

## Regenerate both maps from nginx/domains.map inside the running container, then reload
domains:
	docker exec $(NGINX_CONTAINER) /docker-entrypoint.d/10-generate-maps.sh
	docker exec $(NGINX_CONTAINER) nginx -t
	docker exec $(NGINX_CONTAINER) nginx -s reload

## Validate config only
test:
	docker exec $(NGINX_CONTAINER) nginx -t

## Reload nginx without regenerating
reload:
	docker exec $(NGINX_CONTAINER) nginx -s reload

## (Re)create the front proxy
up:
	docker compose up -d
