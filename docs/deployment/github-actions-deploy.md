# GitHub Actions Deploy

Automated continuous deployment to a server running Docker and Traefik. The workflow builds the image on the CI runner, streams it to the server over SSH, and restarts the Compose stack — no container registry, no git checkout on the server.

---

## TL;DR

On every push to `dev` (and on manual `workflow_dispatch` runs), `deploy.yml`:

1. Builds the image (`instatic:sha-<short>`) for `linux/amd64` on the GitHub-hosted runner.
2. Streams it to the server with `docker save | gzip | ssh "docker load"`.
3. Writes a `.env` (`INSTATIC_IMAGE=instatic:sha-<short>` + `INSTATIC_SECRET_KEY` + `DOMAIN`) and syncs the three Compose files.
4. Runs `docker compose up -d --force-recreate` (SQLite + Traefik stack), then prunes old images.
5. Polls `https://<domain>/health` until it returns `200`.

## One-time setup

### 1. Server

A Linux server with Docker Engine + Compose v2, plus a running Traefik (see [traefik.md](traefik.md) prerequisites). Create a deploy directory:

```sh
sudo mkdir -p /opt/instatic
```

Create an SSH user with Docker access (or add your user to the `docker` group), and install a deploy key:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/instatic_deploy -N ""
cat ~/.ssh/instatic_deploy.pub >> ~/.ssh/authorized_keys
```

### 2. GitHub secrets and variables

Repository **Settings → Secrets and variables → Actions**:

| Type | Name | Value |
|---|---|---|
| Variable | `SSH_HOST` | server hostname or IP |
| Variable | `SSH_USER` | SSH login user with Docker access |
| Secret | `SSH_KEY` | contents of `~/.ssh/instatic_deploy` (private key) |
| Secret | `INSTATIC_SECRET_KEY` | `bun run scripts/generate-secret-key.ts` |
| Variable | `DOMAIN` | required — e.g. `example.com` |
| Variable | `DEPLOY_DIR` | `/opt/instatic` (default if unset) |

`INSTATIC_SECRET_KEY` is required before adding AI provider credentials, plugin secret settings, or TOTP MFA. Generate it once and store it as the secret.

### 3. First deploy

The first run builds the image on the runner and transfers it, so it needs a few minutes of a GitHub-hosted runner's CPU and a few hundred MB over SSH. Subsequent deploys are the same shape — there is no incremental layer cache on the server, so each deploy re-transfers the full compressed image.

## How the workflow decides what to deploy

- **Push to `dev`:** builds and deploys the `:sha-<short>` image (immutable, matches the exact build).
- **Manual run:** same as a push — rebuilds the `dev` branch and deploys the sha.

There is no tagged-release rollback in this flow; to roll back, push the older commit again (its sha image is rebuilt and deployed).

## Tradeoffs vs a registry

- **No registry to learn or authenticate against** — the SSH key you already configured is the only transport.
- **Full image re-transferred each deploy** — fine for a single server; slower than a registry's layer-diff pull.
- **Server stays a dumb host** — only Compose files and `.env` live there; the build never runs on the server.

## Optional hardening

- **Protected environment:** create a `production` environment and set `environment: production` on the `deploy` job to require reviewer approval before deploy. Move `SSH_*` / `INSTATIC_SECRET_KEY` into that environment's secrets.
- **Known hosts:** replace `-o StrictHostKeyChecking=accept-new` with a strict `known_hosts` file (store it in a `SSH_KNOWN_HOSTS` secret and add `-o StrictHostKeyChecking=yes -o UserKnownHostsFile=...`) to pin the server fingerprint.

## Related

- [traefik.md](traefik.md) — the Compose/Traefik layer this workflow deploys
- [vps.md](vps.md) — base Compose stack (`compose.prod.yml`, `compose.sqlite.yml`)
- `.github/workflows/deploy.yml` — the deploy workflow
- `compose.traefik.yml` — Traefik override
