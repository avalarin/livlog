#!/usr/bin/env bash
set -euo pipefail

# Deploy dev environment from local machine.
# Builds Docker image locally, pushes to GHCR, then copies deploy files to the server
# and runs docker-rollout.sh.
#
# Prerequisites:
#   - Docker running locally
#   - Logged into GHCR: echo "<PAT>" | docker login ghcr.io -u <user> --password-stdin
#   - SSH access to the dev server (configure DEV_SSH_HOST / DEV_SSH_USER below or via env)
#
# Usage:
#   DEV_SSH_HOST=1.2.3.4 ./deploy/deploy-dev.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE="ghcr.io/avalarin/livlog"

# SSH connection — override via environment if needed
DEV_SSH_HOST="${DEV_SSH_HOST:-}"
DEV_SSH_USER="${DEV_SSH_USER:-root}"

# ---------- pre-flight checks ----------

if [ -z "$DEV_SSH_HOST" ]; then
  echo "ERROR: DEV_SSH_HOST is not set"
  echo "Export it or pass inline: DEV_SSH_HOST=1.2.3.4 ./deploy/deploy-dev.sh"
  exit 1
fi

# Ensure no uncommitted changes in tracked files
if ! git -C "$REPO_ROOT" diff --quiet || ! git -C "$REPO_ROOT" diff --cached --quiet; then
  echo "ERROR: Git working tree has uncommitted changes. Commit or stash before deploying."
  git -C "$REPO_ROOT" status --short
  exit 1
fi

# Get version and commit hash
APP_VERSION="$(cat "${REPO_ROOT}/VERSION" | tr -d '[:space:]')"
COMMIT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
IMAGE_TAG="${APP_VERSION}-${COMMIT_SHA}"
FULL_IMAGE="${IMAGE}:${IMAGE_TAG}"
echo "Version: ${APP_VERSION}"
echo "Commit:  ${COMMIT_SHA}"
echo "Image:   ${FULL_IMAGE}"

# ---------- build & push ----------

echo ""
echo "==> Building Docker image..."
docker build \
  --platform linux/amd64 \
  --build-arg APP_VERSION="${APP_VERSION}" \
  --build-arg APP_COMMIT="${COMMIT_SHA}" \
  -t "${FULL_IMAGE}" \
  -t "${IMAGE}:latest" \
  -f "${REPO_ROOT}/Dockerfile" \
  "${REPO_ROOT}"

echo ""
echo "==> Pushing to GHCR..."
docker push "${FULL_IMAGE}"
docker push "${IMAGE}:latest"

# ---------- deploy via SSH ----------

REMOTE_DIR="/opt/livlog"

echo ""
echo "==> Copying deploy files to server..."
scp "${DEPLOY_DIR}/docker-dev.env" "${DEPLOY_DIR}/docker-rollout.sh" \
  "${DEV_SSH_USER}@${DEV_SSH_HOST}:${REMOTE_DIR}/"

echo ""
echo "==> Deploying to ${DEV_SSH_USER}@${DEV_SSH_HOST} ('${FULL_IMAGE}')..."
ssh "${DEV_SSH_USER}@${DEV_SSH_HOST}" \
  "chmod +x ${REMOTE_DIR}/docker-rollout.sh && ${REMOTE_DIR}/docker-rollout.sh --env ${REMOTE_DIR}/docker-dev.env --image '${FULL_IMAGE}'"

echo ""
echo "Done! Deployed ${FULL_IMAGE} to ${DEV_SSH_HOST}"
