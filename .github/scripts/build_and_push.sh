#!/bin/bash
set -euo pipefail

# Build ONE platform natively and push it as a per-platform tag.
#
# The workflow matrix runs this twice: amd64 on ubuntu-latest, arm64 on
# ubuntu-24.04-arm (a standard GitHub-hosted arm64 runner, free for public
# repositories since 2025-08-07). Because each job runs on a runner matching
# its target, the build is native - no QEMU, no cross toolchain.
#
# .github/scripts/merge_manifest.sh then merges :amd64 and :arm64 into the
# multi-platform :latest and :<git-sha> manifest lists (same tag scheme as the
# codeberg.org registry published by .forgejo/scripts/build_and_push.sh).
#
# Note this path uses the Dockerfile (glibc + `+crt-static`), while the
# .forgejo/ path cross-compiles musl. Both build the SAME source tree:
# upstream main + the PRs listed in redlib-prs.txt.
# Details: design/github-actions-workflow.md, design/multi-arch-build.md §11.

APP=redlib
REGISTRY=ghcr.io

# Target platform for this job. Set by the workflow matrix; default amd64 so the
# script is also runnable by hand (`ARCH=arm64 bash .github/scripts/build_and_push.sh`).
ARCH="${ARCH:-amd64}"
case "$ARCH" in
  amd64) PLATFORM=linux/amd64 ;;
  arm64) PLATFORM=linux/arm64 ;;
  *) echo "Unsupported ARCH='$ARCH' (expected amd64 or arm64)" >&2; exit 1 ;;
esac

# ghcr.io namespace is the GitHub repository owner (the account/org that owns
# this repo). Registry repository names must be LOWERCASE (an owner like
# "Lawlietr" fails docker's tag validation), so force it down. Login itself uses
# the unmodified account name (see the workflow's login step).
OWNER="${GITHUB_REPOSITORY_OWNER,,}"

IMAGE="${REGISTRY}/${OWNER}/${APP}"
image="${IMAGE}:${ARCH}"

echo "Building and pushing image for ${APP} (${PLATFORM}) -> ${image}"
docker build \
	--platform "${PLATFORM}" \
	-t "$image" \
	-f Dockerfile .
docker push "$image"

echo "Pushed ${image}. The manifest job merges :amd64 + :arm64 into :latest and :<git-sha>."
