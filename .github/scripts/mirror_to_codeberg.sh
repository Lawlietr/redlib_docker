#!/bin/bash
set -euo pipefail

# Mirror the GitHub-built images into the Codeberg registry, WITHOUT rebuilding.
#
# Why: the compile work now lives in GitHub Actions (native amd64/arm64 hosted
# runners), but the codeberg.org/lawlietr/redlib tags must still carry the new
# build. This is a registry-to-registry copy with `docker buildx imagetools
# create --from`: no cargo, no QEMU, ~13MB of blobs, and because everything is
# content-addressed the mirrored tags keep the SAME digests as on ghcr - so a
# digest pin is valid in both registries.
#
# Requires the repo secret CODEBERG_PAT (Codeberg PAT with write:packages).
# The login username is the Codeberg ACCOUNT (Lawlietr) while the registry path
# must be lowercase (lawlietr) - the same asymmetry the .forgejo/ pipeline uses.
#
# Consequence to remember: the mirrored builds are the GitHub ones, i.e.
# glibc + `+crt-static`. A manual run of .forgejo/workflows/build.yml would push
# musl-static binaries to these same tags until the next GitHub build re-mirrors
# them. Details: design/github-actions-workflow.md §9.

SRC="ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/redlib"
DST="codeberg.org/lawlietr/redlib"
CODEBERG_LOGIN="Lawlietr"
GIT_SHA="$(git rev-parse --short HEAD)"

if [ -z "${CODEBERG_PAT:-}" ]; then
  echo "::error::CODEBERG_PAT is not set as a GitHub Actions secret (Settings -> Secrets and variables -> Actions -> Repository secrets)." >&2
  echo "  Add a Codeberg PAT with write:packages, then re-run this workflow." >&2
  exit 1
fi

echo "Logging in to codeberg.org as ${CODEBERG_LOGIN} (registry path is lowercase: lawlietr)"
# Codeberg's registry edge intermittently cancels auth requests; retry with
# growing backoff (same defensive pattern the .forgejo/ pipeline uses).
for i in 1 2 3 4 5 6; do
  if echo "$CODEBERG_PAT" | docker login codeberg.org --username "$CODEBERG_LOGIN" --password-stdin; then
    break
  fi
  if [ "$i" = "6" ]; then
    echo "::error::docker login codeberg.org failed 6 times" >&2
    exit 1
  fi
  echo "login attempt $i failed, retrying in $((i * 10))s"
  sleep $((i * 10))
done

echo "Mirroring ${SRC} -> ${DST}"
# Manifest lists (rolling + pinnable pin).
docker buildx imagetools create \
  -t "${DST}:latest" -t "${DST}:${GIT_SHA}" \
  "${SRC}:latest"
# Per-platform images, so the whole tag set matches ghcr.
docker buildx imagetools create -t "${DST}:amd64" "${SRC}:amd64"
docker buildx imagetools create -t "${DST}:arm64" "${SRC}:arm64"

echo "Verifying the mirrored tags (platforms + digests):"
for tag in latest "$GIT_SHA" amd64 arm64; do
  printf '%s:%-10s ' "$DST" "$tag"
  docker buildx imagetools inspect --raw "${DST}:${tag}" | python3 -c '
import sys, json
d = json.load(sys.stdin)
ms = d.get("manifests")
if ms:
    print("manifest list:", ", ".join(m["platform"]["architecture"] for m in ms))
else:
    print("single manifest:", d.get("config", {}).get("digest", "?")[:19])
'
done

# Cross-check: every child manifest of the mirrored list must have the same digest as
# on ghcr, otherwise something re-tagged instead of copying verbatim.
export SRC DST
python3 - <<'PY'
import json, os, subprocess
SRC, DST = os.environ["SRC"], os.environ["DST"]

def children(img):
    raw = subprocess.run(["docker", "buildx", "imagetools", "inspect", "--raw", img],
                         capture_output=True, text=True)
    if raw.returncode != 0:
        return None
    d = json.loads(raw.stdout)
    return sorted((m["digest"], m["platform"]["architecture"]) for m in d.get("manifests", [])) or None

src, dst = children(SRC + ":latest"), children(DST + ":latest")
print("child digests ghcr    :", src)
print("child digests codeberg:", dst)
if src and dst and src != dst:
    raise SystemExit("::warning:: mirrored child digests differ - not a verbatim copy")
print("mirror verified: identical content")
PY

echo "Done. Published:"
echo "  ${SRC}:{latest,${GIT_SHA},amd64,arm64}   (source of truth, built here)"
echo "  ${DST}:{latest,${GIT_SHA},amd64,arm64}  (mirror, registry-side copy)"
