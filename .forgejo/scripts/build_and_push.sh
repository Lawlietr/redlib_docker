#!/bin/bash
set -euo pipefail

APPS=$1

# Convert the comma-separated string back into an array
IFS=',' read -ra apps <<< "$APPS"

for app in "${apps[@]}"; do
	if [[ -n "$app" ]]; then
		echo "Building and pushing image for $app (podman, amd64)"
		podman build \
			--platform linux/amd64 \
			-t "registry.codeberg.org/${GITHUB_REPOSITORY_OWNER}/containers:$app" \
			-f "${app}/Dockerfile" "${app}"
		podman push "registry.codeberg.org/${GITHUB_REPOSITORY_OWNER}/containers:$app"
	fi
done
