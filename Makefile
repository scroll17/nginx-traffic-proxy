# Two interchangeable nginx backends behind the HAProxy edge.
NGINX_BACKENDS ?= nginx_blue nginx_green

.PHONY: domains test reload up validate roll roll-one

## Regenerate maps + reload on BOTH backends (zero downtime; HAProxy keeps routing).
domains:
	@for c in $(NGINX_BACKENDS); do \
	  echo "==> $$c"; \
	  docker exec $$c /docker-entrypoint.d/10-generate-maps.sh && \
	  docker exec $$c nginx -t && \
	  docker exec $$c nginx -s reload; \
	done

## Validate config on both backends + the HAProxy config.
validate:
	@for c in $(NGINX_BACKENDS); do echo "==> $$c"; docker exec $$c nginx -t; done
	docker exec nginx_lb haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

## Graceful config reload on both backends (no regeneration).
reload:
	@for c in $(NGINX_BACKENDS); do docker exec $$c nginx -s reload; done

## Bring everything up.
up:
	docker compose up -d

## Zero-downtime image/config roll: update one backend at a time, wait healthy.
## HAProxy serves from the other backend throughout. Usage: make roll
roll:
	docker compose pull nginx_blue nginx_green || true
	$(MAKE) roll-one BACKEND=nginx_blue
	$(MAKE) roll-one BACKEND=nginx_green

roll-one:
	@echo "==> rolling $(BACKEND)"
	docker compose up -d --no-deps $(BACKEND)
	@echo "   waiting for $(BACKEND) to become healthy..."
	@for i in $$(seq 1 30); do \
	  s=$$(docker inspect -f '{{.State.Health.Status}}' $(BACKEND) 2>/dev/null); \
	  if [ "$$s" = "healthy" ]; then echo "   $(BACKEND) healthy"; exit 0; fi; \
	  sleep 2; \
	done; \
	echo "   TIMEOUT: $(BACKEND) not healthy — aborting before touching the other backend"; exit 1
