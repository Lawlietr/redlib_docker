#!/bin/bash
set -euo pipefail

APP=redlib
REGISTRY=ghcr.io

# ghcr.io namespace is the GitHub repository owner (the account/org that owns
# this repo). On GitHub this is the correct owner via $GITHUB_REPOSITORY_OWNER,
# but registry repository names must be LOWERCASE (an owner like "Lawlietr"
# fails docker's tag validation), so force it down.
OWNER="${GITHUB_REPOSITORY_OWNER,,}"

image="${REGISTRY}/${OWNER}/${APP}:latest"
echo "Building and pushing image for ${APP} (docker, amd64) -> ${image}"
docker build \
	--platform linux/amd64 \
	-t "$image" \
	-f Dockerfile .
docker push "$image"
