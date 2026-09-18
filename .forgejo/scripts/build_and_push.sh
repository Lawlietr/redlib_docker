#!/bin/bash
set -euo pipefail

APPS=$1
REGISTRY=codeberg.org
# Codeberg account owning the registry namespace (NOT the local Forgejo owner).
CODEBERG_USER=lawlietr  # namespace must be lowercase (docker rule); login uses the real account name

# Dockerfile uses RUN --mount=type=cache (cargo caches) which requires BuildKit
# (docker 29 on the runner still defaults to the classic builder for `docker build`).
export DOCKER_BUILDKIT=1

# Convert the comma-separated string back into an array
IFS=',' read -ra apps <<< "$APPS"

for app in "${apps[@]}"; do
	if [[ -n "$app" ]]; then
		image="${REGISTRY}/${CODEBERG_USER}/${app}:latest"
		echo "Building and pushing image for $app (docker, amd64)"
		docker build \
			--platform linux/amd64 \
			-t "$image" \
			-f "${app}/Dockerfile" "${app}"
		docker push "$image"
	fi
done
