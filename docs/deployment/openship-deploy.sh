#!/usr/bin/env bash
#
# Deploy Instatic to OpenShip from the published Docker image.
#
# Run this as OpenShip's Docker/pull-build hook, or from any host where the
# environment variables below are already exported. It is idempotent: re-running
# it pulls the latest image and recreates the container with the same identity.
#
# Required environment (assumed provided by the run environment per OpenShip):
#   INSTATIC_IMAGE         image ref to deploy, e.g. ghcr.io/corebunch/instatic:latest
#   INSTATIC_PORT          host port to bind, e.g. 3001
#   INSTATIC_VOLUME        persistent volume name storing DB + uploads, e.g. instatic-storage
#   INSTATIC_MOUNT_ROOT    container path the volume is mounted at, e.g. /app/storage
#   DATABASE_URL           sqlite:/app/... on the volume, or postgres://...
#   UPLOADS_DIR=/app/...   directory on the volume for media/plugins/published artefacts
#   INSTATIC_SECRET_KEY    base64 32-byte key (output of bun run scripts/generate-secret-key.ts)
#   PUBLIC_ORIGIN          public origin(s) for the CSRF check behind the TLS-terminating proxy
# Optional:
#   TRUSTED_PROXY_CIDRS    comma-separated proxy CIDRs for client-IP attribution only
#
# Single-volume layout (recommended when the platform offers one persistent root):
#   INSTATIC_MOUNT_ROOT=/app/storage
#   DATABASE_URL=sqlite:/app/storage/data/cms.db
#   UPLOADS_DIR=/app/storage/uploads
#
# See docs/deployment/docker-image.md for the full runtime contract.

set -euo pipefail

: "${INSTATIC_IMAGE:?INSTATIC_IMAGE is required (e.g. ghcr.io/corebunch/instatic:latest)}"
: "${INSTATIC_PORT:?INSTATIC_PORT is required (host bind port)}"
: "${INSTATIC_VOLUME:?INSTATIC_VOLUME is required (persistent volume name)}"
: "${INSTATIC_MOUNT_ROOT:=/app/storage}"
: "${DATABASE_URL:?DATABASE_URL is required (sqlite:... or postgres://...)}"
: "${UPLOADS_DIR:?UPLOADS_DIR is required (persistent upload path on the volume)}"
: "${INSTATIC_SECRET_KEY:?INSTATIC_SECRET_KEY is required (generate with bun run scripts/generate-secret-key.ts)}"
: "${PUBLIC_ORIGIN:?PUBLIC_ORIGIN is required behind a TLS-terminating proxy}"

CONTAINER="instatic"

echo "[openship-deploy] pulling ${INSTATIC_IMAGE}"
docker pull "${INSTATIC_IMAGE}"

echo "[openship-deploy] ensuring volume ${INSTATIC_VOLUME}"
docker volume create "${INSTATIC_VOLUME}" >/dev/null

echo "[openship-deploy] removing existing container (if any)"
if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
  docker rm -f "${CONTAINER}"
fi

echo "[openship-deploy] starting container ${CONTAINER}"

docker run -d \
  --name "${CONTAINER}" \
  -p "${INSTATIC_PORT}:3001" \
  -e PORT=3001 \
  -e DATABASE_URL="${DATABASE_URL}" \
  -e UPLOADS_DIR="${UPLOADS_DIR}" \
  -e STATIC_DIR=/app/dist \
  -e INSTATIC_SECRET_KEY="${INSTATIC_SECRET_KEY}" \
  -e PUBLIC_ORIGIN="${PUBLIC_ORIGIN}" \
  ${TRUSTED_PROXY_CIDRS:+-e TRUSTED_PROXY_CIDRS="${TRUSTED_PROXY_CIDRS}"} \
  -v "${INSTATIC_VOLUME}":"${INSTATIC_MOUNT_ROOT}" \
  --restart unless-stopped \
  --health-cmd 'curl -f http://localhost:3001/health || exit 1' \
  --health-interval 30s \
  --health-timeout 5s \
  --health-start-period 20s \
  --health-retries 3 \
  "${INSTATIC_IMAGE}"

echo "[openship-deploy] done. Verify: curl http://localhost:${INSTATIC_PORT}/health"
