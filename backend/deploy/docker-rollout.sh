#!/usr/bin/env bash
set -euo pipefail

# Roll out a Docker image using plain docker run.
# Generic script shared by dev and prod deployments.
#
# Strategy: start a new container alongside the old one, health check it,
# then replace the old container. If the health check fails, the old container
# keeps running and the new one is removed.
#
# Usage:
#   ./docker-rollout.sh --env <path> --image <image>
#
# Options:
#   --env    Path to env file with container config (CONTAINER_NAME, NETWORK, VOLUME, etc.)
#   --image  Full image reference (e.g. ghcr.io/avalarin/livlog:1.0.0-abc1234)

# ---------- parse arguments ----------

ENV_FILE=""
IMAGE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --env)   ENV_FILE="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$ENV_FILE" ] || [ -z "$IMAGE" ]; then
  echo "Usage: docker-rollout.sh --env <path> --image <image>"
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: Env file not found at ${ENV_FILE}"
  exit 1
fi

# Load config
# shellcheck source=/dev/null
source "$ENV_FILE"

if [ -z "${CONTAINER_NAME:-}" ]; then
  echo "ERROR: CONTAINER_NAME not set in ${ENV_FILE}"
  exit 1
fi

NEW_CONTAINER="${CONTAINER_NAME}-new"

# ---------- deploy ----------

# Pull the new image
docker pull "$IMAGE"

# Build docker run arguments
RUN_ARGS=(-d --name "$NEW_CONTAINER" --restart "${RESTART_POLICY:-unless-stopped}")

if [ -n "${NETWORK:-}" ]; then
  RUN_ARGS+=(--network "$NETWORK")
fi

if [ -n "${VOLUME:-}" ]; then
  RUN_ARGS+=(-v "$VOLUME")
fi

# Start new container alongside the old one
echo "Starting new container: ${NEW_CONTAINER}"
docker run "${RUN_ARGS[@]}" "$IMAGE" ${COMMAND:-}

# Health check the new container
HEALTH_ENDPOINT="${HEALTH_URL:-http://localhost:8080/api/v1/health}"
echo "Waiting for health check..."
HEALTHY=false
for i in 1 2 3 4 5; do
  sleep 3
  if docker exec "$NEW_CONTAINER" wget -qO- "$HEALTH_ENDPOINT" 2>/dev/null; then
    echo "Health check passed"
    HEALTHY=true
    break
  fi
  echo "Attempt $i failed, retrying..."
done

if [ "$HEALTHY" = false ]; then
  echo "ERROR: Health check failed after 5 attempts"
  echo "New container logs:"
  docker logs --tail 50 "$NEW_CONTAINER"
  echo "Removing failed container..."
  docker rm -f "$NEW_CONTAINER"
  echo "Old container is still running."
  exit 1
fi

# Swap: stop old container, rename new one
echo "Swapping containers..."
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
docker rename "$NEW_CONTAINER" "$CONTAINER_NAME"

# Cleanup old images
docker image prune -f

echo "Deploy complete: ${IMAGE}"
