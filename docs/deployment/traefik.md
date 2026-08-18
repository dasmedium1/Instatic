# Deploy Behind Traefik

Instatic can sit behind an **existing Traefik** reverse proxy instead of the bundled Caddy overlay (`compose.tls.yml`). The `compose.traefik.yml` override layers on top of `compose.prod.yml` (+ `compose.sqlite.yml` for SQLite) and lets Traefik terminate TLS and route to the app container.

This guide covers the Compose layer. Automated deploys from GitHub Actions are documented in [github-actions-deploy.md](github-actions-deploy.md).

---

## TL;DR

```sh
# SQLite + Traefik
docker compose -f compose.prod.yml -f compose.sqlite.yml -f compose.traefik.yml up -d

# Postgres + Traefik
docker compose -f compose.prod.yml -f compose.traefik.yml up -d
```

Set `DOMAIN` in `.env` (required — e.g. `example.com`) and make sure Traefik already runs with a `websecure` entrypoint, a `letsencrypt` cert resolver, and an external Docker network named `traefik_web`.

## Prerequisites

1. **Traefik already running** on the same Docker host with:
   - a `websecure` entrypoint (HTTPS),
   - a `letsencrypt` certificate resolver (HTTP-01 or DNS-01),
   - an external Docker network named `traefik_web`.
2. **DNS** A/AAAA records for your domain pointing at the server.
3. **Ports 80/443** reachable (Traefik handles the ACME challenge; DNS-01 still needs 443 open for serving).

## What the override does

- Removes the `app` host port mapping (`ports: !reset []`) so Traefik is the only public surface.
- Attaches `app` to the external `traefik_web` network (and keeps it on the compose `default` network so a future Postgres service stays reachable).
- Adds Traefik labels:
  - router `instatic` on `Host(\`${DOMAIN}\`)` → `websecure` entrypoint, `letsencrypt` cert resolver,
  - service `instatic` → `app:3001`, with a `/health` load-balancer health check.
- Sets `PUBLIC_ORIGIN=https://${DOMAIN}` so the CSRF/Origin check (both the HTTP API and the real-time co-editing WebSocket) matches the public URL even though Traefik hands the container plain HTTP.
- Sets `TRUSTED_PROXY_CIDRS` to the Docker bridge range (`172.16.0.0/12`) so audit logs and rate-limit keys attribute the real client IP from Traefik's `X-Forwarded-For`. This is client-IP attribution only — **not** CSRF.

## WebSocket / real-time co-editing

The editor's real-time co-editing uses a WebSocket at `/admin/api/cms/site-socket`. Traefik passes WebSocket upgrades through HTTP routers natively — no extra label is required. The handshake is cookie-authenticated and Origin-checked, so `PUBLIC_ORIGIN` must be correct or the socket is rejected.

## Customizing

The labels are the only Traefik-specific surface. Adjust them if your Traefik uses different names:

| Value | Where | Default |
|---|---|---|
| Network | `networks.traefik.name` + `traefik.docker.network` | `traefik_web` |
| Entrypoint | `traefik.http.routers.instatic.entrypoints` | `websecure` |
| Cert resolver | `traefik.http.routers.instatic.tls.certResolver` | `letsencrypt` |
| Host | `traefik.http.routers.instatic.rule` | `Host(\`${DOMAIN}\`)` |
| Health path | `traefik.http.services.instatic.loadbalancer.healthcheck.path` | `/health` |

To serve multiple hosts, change the router rule to `Host(\`cms.example.com\`, \`www.cms.example.com\`)`. To use Traefik's basic-auth or IP allowlist middleware, add `traefik.http.routers.instatic.middlewares` labels pointing at Traefik middlewares defined in your Traefik configuration.

## Verifying

```sh
curl -I https://<domain>/health
# → HTTP/2 200
```

Check Traefik routing without hitting the public DNS by reading Traefik's dashboard or `docker logs <traefik-container>` for router/service errors.

## Related

- [github-actions-deploy.md](github-actions-deploy.md) — automated GitHub Actions deploys
- [vps.md](vps.md) — VPS Compose install commands (base `compose.prod.yml` / `compose.sqlite.yml`)
- [tls-caddy.md](tls-caddy.md) — the bundled Caddy alternative
- [backup-restore.md](backup-restore.md) — backing up app and uploads volumes
- `compose.traefik.yml` — Traefik override
