#!/bin/bash
set -euo pipefail

APPS=$1
REGISTRY=codeberg.org

# Convert the comma-separated string back into an array
IFS=',' read -ra apps <<< "$APPS"

for app in "${apps[@]}"; do
	if [[ -n "$app" ]]; then
		image="${REGISTRY}/${GITHUB_REPOSITORY_OWNER}/${app}:latest"
		echo "Building and pushing image for $app (docker, amd64)"
		docker build \
			--platform linux/amd64 \
			-t "$image" \
			-f "${app}/Dockerfile" "${app}"
		docker push "$image"
	fi
done
