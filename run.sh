#!/usr/bin/env bash
#
# Build and run n8n-chrome container with SSL support
# - Prunes old n8n images (>1 week)
# - Builds new image (timestamp + latest tags)
# - Removes old container if exists
# - Starts new container from timestamp tag

# Configuration
IMAGE_REPO="n8n-chrome"
IMAGE_NAME="${IMAGE_REPO}:latest"
CONTAINER_NAME="n8n"
BUILD_DIR="."
N8N_DOMAIN="n8n.replikanti.xyz"

TIMESTAMP_TAG="$(date +'%s')"
TIMESTAMP_IMAGE="${IMAGE_REPO}:${TIMESTAMP_TAG}"
LATEST_IMAGE="${IMAGE_REPO}:latest"

echo "==> Pruning old n8n images (older than 1 week)..."

# Najdi staré image (n8n*) a vezmi jejich ID
old_images=$(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.CreatedSince}}' --filter=reference='n8n*' 2>/dev/null \
  | grep -E '([0-9]+) (weeks|months|years)' \
  | awk '{print $2}')

if [[ -z "${old_images}" ]]; then
  echo "No old n8n images found."
else
  echo "Found old images (IDs):"
  echo "${old_images}"
fi

# Zjisti, jestli nějaký starý image má běžící container
needs_prebuild=false
if [[ -n "${old_images}" ]]; then
  for img_id in ${old_images}; do
    if docker ps -q --filter "ancestor=${img_id}" | grep -q .; then
      needs_prebuild=true
      break
    fi
  done
fi

# Pokud běží kontejnery na starých imagích, nejdřív vybuildíme novou image
if [[ "${needs_prebuild}" == true ]]; then
  echo "==> Running containers found on old images. Building new image ${TIMESTAMP_IMAGE} first..."
  docker build -t "${TIMESTAMP_IMAGE}" -f Dockerfile "${BUILD_DIR}"
fi

# Teď stopneme/smažeme kontejnery na starých imagích a smažeme staré imagy
if [[ -n "${old_images}" ]]; then
  for img_id in ${old_images}; do
    echo "==> Cleaning up old image: ${img_id}"

    containers=$(docker ps -aq --filter "ancestor=${img_id}")
    if [[ -n "${containers}" ]]; then
      echo "  - Stopping containers using image ${img_id}: ${containers}"
      docker stop ${containers} >/dev/null 2>&1 || true

      echo "  - Removing containers using image ${img_id}: ${containers}"
      docker rm ${containers} >/dev/null 2>&1 || true
    else
      echo "  - No containers using image ${img_id}"
    fi

    echo "  - Removing image ${img_id}"
    docker rmi -f "${img_id}" >/dev/null 2>&1 || echo "  - Failed to remove image ${img_id}"
  done
fi

# Zjisti, jestli po pruningu existuje nějaký n8n-chrome image
hasImage=$(docker images | grep -E "^${IMAGE_REPO}\s" | wc -l || true)

# Pokud neexistuje žádný image a ještě jsme nic nebuildili, postavíme timestamp image
if [[ ${hasImage} -eq 0 && "${needs_prebuild}" != true ]]; then
  echo "==> No existing ${IMAGE_REPO} images, building ${TIMESTAMP_IMAGE}..."
  docker build -t "${TIMESTAMP_IMAGE}" -f Dockerfile "${BUILD_DIR}"
fi

# Ujisti se, že timestamp tag existuje (když jsme nebuildili, otagujeme z existujícího image)
if ! docker images "${TIMESTAMP_IMAGE}" --format '{{.Repository}}:{{.Tag}}' | grep -q .; then
  base_image=""
  if docker images "${LATEST_IMAGE}" --format '{{.Repository}}:{{.Tag}}' | grep -q .; then
    base_image="${LATEST_IMAGE}"
  else
    # vezmeme první image z daného repa
    base_image=$(docker images "${IMAGE_REPO}" --format '{{.Repository}}:{{.Tag}}' | head -n1)
  fi

  if [[ -n "${base_image}" ]]; then
    echo "==> Tagging ${base_image} as ${TIMESTAMP_IMAGE}"
    docker tag "${base_image}" "${TIMESTAMP_IMAGE}"
  else
    # fallback (teoreticky by neměl nastat)
    echo "==> No base image found for ${IMAGE_REPO}, building ${TIMESTAMP_IMAGE}..."
    docker build -t "${TIMESTAMP_IMAGE}" -f Dockerfile "${BUILD_DIR}"
  fi
fi

# V každém případě: timestamp + latest tag na stejné image
echo "==> Tagging ${TIMESTAMP_IMAGE} as ${LATEST_IMAGE}"
docker tag "${TIMESTAMP_IMAGE}" "${LATEST_IMAGE}"

RUN_IMAGE="${TIMESTAMP_IMAGE}"

echo "==> Removing old container if exists..."
docker ps -aq --filter "name=^${CONTAINER_NAME}$" | xargs -r docker rm -f

echo "==> Starting new container: ${CONTAINER_NAME} (image: ${RUN_IMAGE})..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  -p 127.0.0.1:5678:5678 \
  -e GENERIC_TIMEZONE="Europe/Prague" \
  -e TZ="Europe/Prague" \
  -e N8N_PROTOCOL=https \
  -e N8N_HOST="${N8N_DOMAIN}" \
  -e WEBHOOK_URL="https://${N8N_DOMAIN}/" \
  -e N8N_PROXY_HOPS=1 \
  -e N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true \
  -e N8N_RUNNERS_ENABLED=true \
  -e N8N_SECURE_COOKIE=false \
  -e N8N_BLOCK_ENV_ACCESS_IN_NODE=false \
  -e N8N_GIT_NODE_DISABLE_BARE_REPOS=true \
  -e DB_TYPE=postgresdb \
  -e DB_POSTGRESDB_HOST=ep-flat-wind-ag3jl0bm-pooler.c-2.eu-central-1.aws.neon.tech \
  -e DB_POSTGRESDB_PORT=5432 \
  -e DB_POSTGRESDB_DATABASE=neondb \
  -e DB_POSTGRESDB_USER=neondb_owner \
  -e DB_POSTGRESDB_PASSWORD=npg_E6TmXVuvyiA3 \
  -e DB_POSTGRESDB_SSL_ENABLED=true \
  -e DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false \
  -e EXECUTIONS_DATA_SAVE_ON_SUCCESS=true \
  -e EXECUTIONS_DATA_SAVE_ON_ERROR=true \
  -e EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true \
  -e EXECUTIONS_DATA_PRUNE=true \
  -e EXECUTIONS_DATA_MAX_AGE=48 \
  -e EXECUTIONS_DATA_PRUNE_MAX_COUNT=100 \
  -v n8n_data:/home/node/.n8n \
  -v /srv/n8n-ruian:/data/ruian \
  --restart unless-stopped \
  "${RUN_IMAGE}"

echo "==> Container started successfully!"
docker ps --filter "name=^${CONTAINER_NAME}$"
echo "==> Access n8n at: https://${N8N_DOMAIN}"
echo ""
echo "==> To view logs, run:"
echo "    docker logs -f ${CONTAINER_NAME}"
