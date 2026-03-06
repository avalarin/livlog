# Deployment Guide

## Architecture Overview

The CI/CD pipeline consists of three GitHub Actions workflows:

```
Push to main (backend/** changes)
        |
        v
  build.yml
  - Lint (golangci-lint)
  - Test (go test -race)
  - Build & push Docker image
    ghcr.io/avalarin/livlog:latest
    ghcr.io/avalarin/livlog:<version>-<short-sha>
        |
        v
  deploy-dev.yml (workflow_run trigger)
  - SSH into dev server
  - Pull latest image from GHCR
  - Replace running container (config from Docker volume)
  - Health check with rollback on failure

Push tag v*
        |
        v
  build.yml
  - Lint, Test, Build & push Docker image
    ghcr.io/avalarin/livlog:<tag>
    ghcr.io/avalarin/livlog:latest
        |
        v
  deploy-prod.yml (workflow_run trigger)
  - Placeholder (not yet configured)
```

## Configuration

Application configuration, JWT keys, and TLS certificates are stored in a Docker volume named `livlog-data` on the server. The volume is mounted read-only into the container at `/app/data`. See `backend/config.deploy.example.yaml` for the config template.

Environment variables with the `LIVLOG_` prefix can still override any config value (e.g. `LIVLOG_DATABASE_PASSWORD`).

## GitHub Secrets

Configure these secrets in the GitHub repository under **Settings > Secrets and variables > Actions**.

### Shared

| Secret | Description |
|--------|-------------|
| `GHCR_PAT` | GitHub Personal Access Token with `read:packages` scope. Used by the deploy server to pull images from GHCR. Create at https://github.com/settings/tokens |

### Dev Environment

| Secret | Description |
|--------|-------------|
| `DEV_SSH_HOST` | IP address or hostname of the dev server |
| `DEV_SSH_USER` | SSH user on the dev server (e.g. `root` or a deploy user) |
| `DEV_SSH_KEY` | SSH private key (PEM format) with access to the dev server |

### Prod Environment (future)

| Secret | Description |
|--------|-------------|
| `PROD_SSH_HOST` | IP address or hostname of the production server |
| `PROD_SSH_USER` | SSH user on the production server |
| `PROD_SSH_KEY` | SSH private key with access to the production server |

## Server Setup

These steps must be performed once on each server before the first automated deploy.

### 1. Install Docker

```bash
curl -fsSL https://get.docker.com | sh
```

### 2. Create Docker volume and populate it

```bash
# Create the named volume
docker volume create livlog-data

# Find the volume mount point
docker volume inspect livlog-data --format '{{ .Mountpoint }}'
# Typically: /var/lib/docker/volumes/livlog-data/_data

# Create subdirectories inside the volume
VOLUME_PATH=$(docker volume inspect livlog-data --format '{{ .Mountpoint }}')
mkdir -p "$VOLUME_PATH/keys"
mkdir -p "$VOLUME_PATH/certs"
```

### 3. Create config file

Copy `backend/config.deploy.example.yaml` from the repository and fill in the real values:

```bash
VOLUME_PATH=$(docker volume inspect livlog-data --format '{{ .Mountpoint }}')
vi "$VOLUME_PATH/config.yaml"
```

The config file contains all application settings: database credentials, API keys, server hostname, etc. See `backend/config.deploy.example.yaml` for the full list of fields with comments.

### 4. Generate JWT RSA keys

The application uses RSA keys to sign and verify JWT tokens. Generate them once. They are mounted read-only into the container at `/app/data/keys`.

```bash
VOLUME_PATH=$(docker volume inspect livlog-data --format '{{ .Mountpoint }}')
openssl genrsa -out "$VOLUME_PATH/keys/private_key.pem" 2048
openssl rsa -in "$VOLUME_PATH/keys/private_key.pem" -pubout -out "$VOLUME_PATH/keys/public_key.pem"
```

### 5. Place database CA certificate (if using managed database with TLS)

```bash
VOLUME_PATH=$(docker volume inspect livlog-data --format '{{ .Mountpoint }}')
cp ca-certificate.crt "$VOLUME_PATH/certs/ca-certificate.crt"
```

### 6. Set file ownership

The container runs as user `livlog` (UID 1100, GID 1100). All files in the volume must be owned by this user so the container can read them:

```bash
VOLUME_PATH=$(docker volume inspect livlog-data --format '{{ .Mountpoint }}')
chown -R 1100:1100 "$VOLUME_PATH"
chmod 600 "$VOLUME_PATH/config.yaml"
chmod 600 "$VOLUME_PATH/keys/private_key.pem"
chmod 644 "$VOLUME_PATH/keys/public_key.pem"
chmod 600 "$VOLUME_PATH/certs/ca-certificate.crt" 2>/dev/null || true
```

### Volume layout

```
livlog-data volume (/var/lib/docker/volumes/livlog-data/_data):
  config.yaml              # Application config (from config.deploy.example.yaml)
  keys/
    private_key.pem        # JWT signing key
    public_key.pem         # JWT verification key
  certs/
    ca-certificate.crt     # Database CA certificate (optional)
```

Inside the container, this is mounted at `/app/data/`.

## Container Configuration

Container settings are defined in `backend/deploy/dev.env` (container name, network, volume, command, restart policy, health check URL).

The deploy logic lives in `backend/deploy/docker-rollout.sh` — a generic script shared by dev and prod. It accepts `--env <path>` and `--image <image>` arguments. The script uses a blue-green strategy: starts a new container alongside the old one, health checks it, then swaps. If the health check fails, the new container is removed and the old one keeps running.

Both files are copied to `/opt/livlog/` on the server during each deploy.

The `webserver` Docker network must exist on the server before the first deploy:

```bash
docker network create webserver
```

## Triggering Deployments

### Deploy to Dev (automatic)

Merge any backend change to `main`. The `build.yml` workflow runs first; once it succeeds, `deploy-dev.yml` fires automatically and deploys the new image to the dev server.

### Deploy to Dev (manual from local machine)

Build and deploy the current commit directly from your laptop:

```bash
DEV_SSH_HOST=<server-ip> ./deploy/deploy-local.sh
```

The script will:
1. Check that the git working tree is clean (all changes committed)
2. Build the Docker image locally (linux/amd64) tagged with version and commit hash
3. Push it to GHCR
4. Copy deploy files (env file + rollout script) to the server
5. SSH into the dev server and run `docker-rollout.sh`

Prerequisites:
- Docker running locally
- Logged into GHCR: `echo "<PAT>" | docker login ghcr.io -u <user> --password-stdin`
- SSH access to the dev server

You can also set `DEV_SSH_USER` (defaults to `root`).

### Deploy to Prod

Create and push a semver tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

`build.yml` detects the tag, builds and pushes the image tagged `v1.0.0` and `latest`, then `deploy-prod.yml` triggers. (Production deploy is currently a placeholder — see `deploy-prod.yml` for the steps to enable it.)

## Changing Configuration

To update config on a running server:

```bash
VOLUME_PATH=$(docker volume inspect livlog-data --format '{{ .Mountpoint }}')
vi "$VOLUME_PATH/config.yaml"

# Restart the container to pick up changes
docker restart livlog-backend
```

## Rolling Back

To roll back the dev deployment to a specific image:

```bash
# SSH into the server
ssh <user>@<host>

# List available image tags (previously pulled)
docker images ghcr.io/avalarin/livlog

# Roll back using docker-rollout.sh with the desired image (replace 1.0.0-abc1234 with the target tag)
/opt/livlog/docker-rollout.sh --env /opt/livlog/dev.env --image ghcr.io/avalarin/livlog:1.0.0-abc1234
```

To pull a specific tag from GHCR before running:

```bash
echo "<GHCR_PAT>" | docker login ghcr.io -u avalarin --password-stdin
docker pull ghcr.io/avalarin/livlog:1.0.0-abc1234
```

## Troubleshooting

### Check container logs

```bash
docker logs livlog-backend
docker logs --tail 100 -f livlog-backend
```

### Check container status

```bash
docker ps -a
docker inspect livlog-backend
```

### Test the health endpoint

```bash
curl http://localhost:8080/api/v1/health
```

### Inspect volume contents

```bash
VOLUME_PATH=$(docker volume inspect livlog-data --format '{{ .Mountpoint }}')
ls -la "$VOLUME_PATH"
ls -la "$VOLUME_PATH/keys"
```

### View recent GitHub Actions runs

Navigate to **Actions** tab in the GitHub repository to see the status of `build.yml` and `deploy-dev.yml` runs, including full logs for each step.
