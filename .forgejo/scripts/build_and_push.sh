#!/bin/bash
set -euo pipefail

# Plan B multi-arch build + push.
#
# Native cross-compile (musl static) for amd64 / arm64 / armv7, then pack each
# binary into scratch via Dockerfile.pack, push one image per platform, and
# finally merge the three into a multi-platform manifest list (latest + git
# sha) with `docker buildx imagetools create`.
#
# Sequential build -> push -> prune per arch keeps the runner disk peak low.
# On the 30GB host (originally 10GB) this is no longer required — buildx
# --platform linux/amd64,linux/arm64[,linux/arm/v7] could build all at once.
# The sequential loop is kept because it avoids running all QEMU simulators
# simultaneously (lower, more predictable memory/disk spikes, faster per-arch).
# Details: design/multi-arch-build.md

APP=redlib
REGISTRY=codeberg.org
# Codeberg account owning the registry namespace (NOT the local Forgejo owner).
# Namespace must be lowercase (docker rule); login uses the real account name.
CODEBERG_USER=lawlietr

# redlib source. Defaults to main, which already contains all formerly-baked
# PRs (as of 2026-09-18). Override via env to pin a build.
REDLIB_SRC="${REDLIB_SRC:-https://github.com/redlib-org/redlib.git}"
REDLIB_BRANCH="${REDLIB_BRANCH:-main}"

# Cross C toolchain for the musl targets.
#   apt packages: gcc-aarch64-linux-gnu, gcc-arm-linux-gnueabihf
# rustc's musl targets ship their own static musl libc, so musl-tools is not
# required for the build itself.
export CC_aarch64_unknown_linux_musl=aarch64-linux-gnu-gcc
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=aarch64-linux-gnu-gcc
export CXX_aarch64_unknown_linux_musl=aarch64-linux-gnu-g++
export AR_aarch64_unknown_linux_musl=aarch64-linux-gnu-ar
export CC_armv7_unknown_linux_musleabihf=arm-linux-gnueabihf-gcc
export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_MUSLEABIHF_LINKER=arm-linux-gnueabihf-gcc
export CXX_armv7_unknown_linux_musleabihf=arm-linux-gnueabihf-g++
export AR_armv7_unknown_linux_musleabihf=arm-linux-gnueabihf-ar
# NOTE: CXX_*/AR_* are required — boring-sys2 ships a C++ source
# (encrypted_client_hello.cc). The cc crate falls back to the HOST g++ if
# CXX_<target> is unset, producing x86_64 .cc.o files that the aarch64/armv7
# linker rejects with "file in wrong format (EM: 62)". Verified: amd64 builds
# with CC_* only; arm64/armv7 fail without CXX_*/AR_* (design/multi-arch-build.md).

# docker platform : cargo musl triple : per-arch image tag
ARCHES=(
  "linux/amd64:x86_64-unknown-linux-musl:amd64"
  "linux/arm64:aarch64-unknown-linux-musl:arm64"
  "linux/arm/v7:armv7-unknown-linux-musleabihf:armv7"
)

GIT_SHA="$(git rev-parse --short HEAD)"
SRC_DIR="redlib-src"

echo "Cloning ${REDLIB_SRC} (@${REDLIB_BRANCH}) into ${SRC_DIR}"
rm -rf "${SRC_DIR}"
git clone --depth 1 --branch "${REDLIB_BRANCH}" "${REDLIB_SRC}" "${SRC_DIR}"

# Add all three musl std targets up front (idempotent).
rustup target add x86_64-unknown-linux-musl aarch64-unknown-linux-musl armv7-unknown-linux-musleabihf

IMAGE="${REGISTRY}/${CODEBERG_USER}/${APP}"

for entry in "${ARCHES[@]}"; do
  IFS=':' read -r platform triple tag <<< "$entry"

  echo "======================================================"
  echo "Building ${tag}   (cargo target: ${triple})"
  echo "======================================================"

  # Build the binary natively for this target. --locked pins deps to Cargo.lock.
  cargo build --release --locked --target "${triple}" --manifest-path "${SRC_DIR}/Cargo.toml"

  # Thin-pack the pre-built binary into scratch (context = dist-<tag>, binary = redlib).
  local_img="${IMAGE}:${tag}"
  mkdir -p "dist-${tag}"
  cp "${SRC_DIR}/target/${triple}/release/${APP}" "dist-${tag}/${APP}"
  docker build --platform "${platform}" -t "${local_img}" -f Dockerfile.pack "dist-${tag}"
  docker push "${local_img}"

  # Prune this arch's local image to keep disk peak low (registry keeps the copy).
  docker image prune -a -f
  rm -rf "dist-${tag}"
done

# Merge the three per-arch images into a multi-platform manifest list:
#   latest (rolling) + <git-sha> (reproducible pin). Per-platform tags already pushed.
echo "Merging manifest: ${IMAGE}:latest + ${IMAGE}:${GIT_SHA}"
docker buildx imagetools create \
  -t "${IMAGE}:latest" \
  -t "${IMAGE}:${GIT_SHA}" \
  "${IMAGE}:amd64" "${IMAGE}:arm64" "${IMAGE}:armv7"

# Push the merged manifests (per-platform tags were pushed in the loop above).
docker push "${IMAGE}:latest"
docker push "${IMAGE}:${GIT_SHA}"

echo "Done. Published:"
echo "  ${IMAGE}:latest             (multi-platform manifest list)"
echo "  ${IMAGE}:${GIT_SHA}         (multi-platform manifest list, reproducible pin)"
echo "  ${IMAGE}:amd64 / :arm64 / :armv7   (per-platform)"
