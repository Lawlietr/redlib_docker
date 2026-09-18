#!/bin/bash
set -euo pipefail

APP=redlib

echo "Building and pushing image for ${APP} (buildx, amd64+arm64)"
docker buildx build \
	--platform linux/amd64,linux/arm64 \
	--push \
	--tag "ghcr.io/${GITHUB_REPOSITORY_OWNER}/containers:${APP}" \
	-f Dockerfile .
