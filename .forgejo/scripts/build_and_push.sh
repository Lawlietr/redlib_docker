#!/bin/bash
set -euo pipefail

APP=redlib
REGISTRY=codeberg.org
# Codeberg account owning the registry namespace (NOT the local Forgejo owner).
CODEBERG_USER=lawlietr  # namespace must be lowercase (docker rule); login uses the real account name

# Dockerfile uses RUN --mount=type=cache (cargo caches) which requires BuildKit
# (docker 29 on the runner still defaults to the classic builder for `docker build`).
export DOCKER_BUILDKIT=1

image="${REGISTRY}/${CODEBERG_USER}/${APP}:latest"
echo "Building and pushing image for ${APP} (docker, amd64)"
docker build \
	--platform linux/amd64 \
	-t "$image" \
	-f Dockerfile .
docker push "$image"
