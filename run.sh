#!/usr/bin/env bash
#
# Build and run n8n with Redis queue mode using docker-compose
# - Prunes old n8n images (>1 week)
# - Builds new image with timestamp tag
# - Stops old containers and starts new stack
#

set -e

IMAGE_REPO="n8n-chrome"
TIMESTAMP_TAG="$(date +'%s')"
TIMESTAMP_IMAGE="${IMAGE_REPO}:${TIMESTAMP_TAG}"
LATEST_IMAGE="${IMAGE_REPO}:latest"

echo "==> Pruning old n8n images (older than 1 week)..."

# Najdi staré images (n8n*) a vezmi jejich ID
old_images=$(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.CreatedSince}}' --filter=reference='n8n*' 2>/dev/null \
  | grep -E '([0-9]+) (weeks|months|years)' \
  | awk '{print $2}')

if [[ -z "${old_images}" ]]; then
  echo "No old n8n images found."
else
  echo "Found old images (IDs):"
  echo "${old_images}"

  for img_id in ${old_images}; do
    echo "==> Removing old image: ${img_id}"

    # Zastavit containery na tomto image
    containers=$(docker ps -aq --filter "ancestor=${img_id}")
    if [[ -n "${containers}" ]]; then
      echo "  - Stopping containers: ${containers}"
      docker stop ${containers} >/dev/null 2>&1 || true
      echo "  - Removing containers: ${containers}"
      docker rm ${containers} >/dev/null 2>&1 || true
    fi

    # Smazat image
    echo "  - Removing image ${img_id}"
    docker rmi -f "${img_id}" >/dev/null 2>&1 || echo "  - Failed to remove image ${img_id}"
  done
fi

echo "==> Building new image with timestamp tag: ${TIMESTAMP_IMAGE}"
docker build -t "${TIMESTAMP_IMAGE}" -t "${LATEST_IMAGE}" -f Dockerfile .

echo "==> Stopping existing docker-compose stack..."
docker-compose down || true

echo "==> Starting new stack with docker-compose..."
docker-compose up -d

echo ""
echo "==> Stack started successfully!"
echo "==> Services:"
docker-compose ps

echo ""
echo "==> Access n8n at: https://n8n.replikanti.xyz"
echo ""
echo "==> To view logs:"
echo "    docker-compose logs -f n8n-main"
echo "    docker-compose logs -f n8n-worker"
echo "    docker-compose logs -f n8n-webhook"
echo "    docker-compose logs -f redis"
echo ""
echo "==> To monitor Redis queue:"
echo "    docker exec -it n8n-redis redis-cli INFO stats"
echo "    docker exec -it n8n-redis redis-cli KEYS 'bull:*'"
