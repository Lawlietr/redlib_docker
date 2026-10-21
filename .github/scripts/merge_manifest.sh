#!/bin/bash
set -euo pipefail

# Merge the per-platform images pushed by .github/scripts/build_and_push.sh
# into a multi-platform manifest list, published as :latest (rolling) and
# :<git-sha> (reproducible pin). Same tag scheme as the codeberg.org registry,
# so users can switch REDLIB_IMAGE between the two registries without changing
# tag conventions.
#
# `docker buildx imagetools create` works purely registry-side: it reads the two
# manifest digests and pushes a new manifest list. Nothing is executed, so this
# job can (and does) run on an amd64 runner.
# Details: design/github-actions-workflow.md §4, design/multi-arch-build.md §11.

APP=redlib
REGISTRY=ghcr.io
OWNER="${GITHUB_REPOSITORY_OWNER,,}"
GIT_SHA="$(git rev-parse --short HEAD)"

IMAGE="${REGISTRY}/${OWNER}/${APP}"

echo "Merging manifest list: ${IMAGE}:latest + ${IMAGE}:${GIT_SHA} <- ${IMAGE}:amd64 ${IMAGE}:arm64"
docker buildx imagetools create \
  -t "${IMAGE}:latest" \
  -t "${IMAGE}:${GIT_SHA}" \
  "${IMAGE}:amd64" "${IMAGE}:arm64"

echo "Done. Published:"
echo "  ${IMAGE}:latest          (multi-platform manifest list, amd64 + arm64)"
echo "  ${IMAGE}:${GIT_SHA}      (multi-platform manifest list, reproducible pin)"
echo "  ${IMAGE}:amd64 / ${IMAGE}:arm64   (per-platform, used for the merge)"
