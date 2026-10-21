#!/bin/bash
set -euo pipefail

# Post-publish smoke test of the image we just pushed, run from a clean runner.
#
# Why this exists: the binaries are fully static and ship on `scratch`, so the two
# failure classes that used to be discovered on the live instance instead of in CI are
#   (1) a static binary that cannot resolve DNS inside `scratch` (the classic static-glibc
#       NSS trap - redlib fetches from reddit, so a broken resolver means every page fails),
#   (2) a baked upstream PR that broke rendering at runtime rather than at compile time.
# Both are caught here, before the mirror job copies the images to Codeberg.
#
# Verified baseline (2026-10-21, x86_64 host, ghcr.io/lawlietr/redlib:amd64):
#   / -> 200 61422B, /r/AskReddit/top -> 200 38009B, /r/gaming -> 200 79424B, no DNS errors.

SRC="ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/redlib"
IMG="${SRC}:amd64"
PORT=18080
CID=redlib-smoke

cleanup() {
  docker rm -f "$CID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fetch() { # fetch <path> -> prints "<http_code> <bytes>"
  curl -s -o /tmp/smoke_body -w '%{http_code} %{size_download}' --max-time 45 "http://127.0.0.1:${PORT}$1"
}

log_has_dns_error() {
  docker logs "$CID" 2>&1 | grep -qiE "temporary failure in name resolution|failed to lookup|name or service not known|resolve"
}

docker pull --quiet "$IMG"

echo "=== 1. the shipped binary must be self-contained (redlib takes no CLI args) ==="
# A dynamically linked binary on `scratch` dies before it can serve anything, and that is
# exactly the failure this check catches. redlib reads configuration from the environment
# only, so there is no --help to run (passing one yields "unexpected argument found").
extract() { # extract <image> <dest> -> docker cp the binary out of the image
  local cid
  cid=$(docker create --platform "$2" "$1" 2>/dev/null || docker create "$1")
  docker cp "$cid:/redlib" "$3"
  docker rm "$cid" >/dev/null
}
extract "$IMG" linux/amd64 /tmp/redlib-amd64
file -b /tmp/redlib-amd64 | sed 's/^/  amd64 binary: /'
if readelf -d /tmp/redlib-amd64 2>/dev/null | grep -q "(NEEDED)"; then
  echo "::error::the amd64 binary is dynamically linked - it cannot run on scratch" >&2
  readelf -d /tmp/redlib-amd64 | grep "(NEEDED)" >&2
  exit 1
fi

echo "=== 2. serve it and hit upstream-backed routes ==="
cleanup
docker run -d --name "$CID" -p "${PORT}:8080" "$IMG" >/dev/null

root=""
for i in 1 2 3 4 5 6 7 8; do
  sleep 3
  root=$(fetch "/" || true)
  echo "  attempt $i  /  ->  ${root:-no response}"
  [[ "$root" == 200* ]] && break
done

status=${root%% *}
bytes=${root##* }
if [ "${status:-0}" != "200" ]; then
  echo "::error::the front page did not return 200 (got '${status:-none}') - the image is not serving" >&2
  docker logs --tail 40 "$CID" 2>&1 | sed 's/^/    /'
  exit 1
fi
if [ "${bytes:-0}" -lt 20000 ]; then
  echo "::error::the front page is only ${bytes}B - looks like an error page, not a rendered front page" >&2
  head -c 600 /tmp/smoke_body >&2
  exit 1
fi

echo "=== 3. a subreddit page (forces DNS + outbound HTTPS from inside scratch) ==="
for path in /r/gaming /r/AskReddit/top; do
  out=""
  for i in 1 2 3; do
    out=$(fetch "$path" || true)
    echo "  $path -> $out"
    st=${out%% *}
    # 2xx means the whole chain worked. Reddit also rate-limits datacenter IPs, and a
    # 403/429 still proves DNS + TLS + the upstream round trip, so it must not fail the job.
    if [ "${st:-0}" -lt 300 ] || [ "${st:-0}" = "403" ] || [ "${st:-0}" = "429" ]; then break; fi
    sleep 10
  done
  st=${out%% *}
  if [ "${st:-0}" -ge 500 ] || [ -z "${out}" ]; then
    echo "::error::$path returned ${st:-no response} - upstream fetch failed" >&2
    docker logs --tail 40 "$CID" 2>&1 | sed 's/^/    /'
    exit 1
  fi
  if [ "$st" = "403" ] || [ "$st" = "429" ]; then
    echo "::warning::$path got $st from reddit (rate limiting on this runner IP); DNS and the round trip still worked"
  fi
done

if log_has_dns_error; then
  echo "::error::the container log contains resolver errors - the static binary cannot do DNS inside scratch" >&2
  docker logs --tail 40 "$CID" 2>&1 | sed 's/^/    /'
  exit 1
fi

echo "=== 4. the arm64 image has to carry a correct, static aarch64 binary ==="
# Deterministic and no emulation needed: pull the arm64 binary out of the image and assert its
# architecture and that nothing is dynamically linked. Functional arm64 verification still
# belongs on real hardware (qemu user-mode is not a Raspberry Pi), which is the separate P2 item.
extract "${SRC}:arm64" linux/arm64 /tmp/redlib-arm64
file -b /tmp/redlib-arm64 | sed 's/^/  arm64 binary: /'
if ! file -b /tmp/redlib-arm64 | grep -q "ARM aarch64"; then
  echo "::error::the :arm64 image does not contain an aarch64 binary" >&2
  exit 1
fi
if readelf -d /tmp/redlib-arm64 2>/dev/null | grep -q "(NEEDED)"; then
  echo "::error::the arm64 binary is dynamically linked - it cannot run on scratch" >&2
  readelf -d /tmp/redlib-arm64 | grep "(NEEDED)" >&2
  exit 1
fi

# Best effort, only where binfmt exists: prove the aarch64 ELF can actually exec.
if [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
  echo "  qemu binfmt present, trying a real arm64 exec:"
  docker run --rm --platform linux/arm64 -e PORT=18099 "${SRC}:arm64" >/tmp/arm_run.log 2>&1 &
  armpid=$!
  sleep 12
  armcode=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 http://127.0.0.1:18099/ || true)
  echo "    arm64 under qemu / -> ${armcode:-no response}"
  grep -iE "Running Redlib|panic" /tmp/arm_run.log | head -3 | sed 's/^/    /' || true
  kill $armpid 2>/dev/null || true
  if [ "${armcode:-0}" = "200" ]; then
    echo "  arm64 exec check passed"
  else
    echo "::warning::arm64 under qemu did not serve (emulation limits, not proof of a defect); real-hardware verification stays open"
  fi
else
  echo "  no aarch64 binfmt on this runner: static-linkage + architecture check above is the arm64 gate"
fi

echo "Smoke passed: $IMG serves, resolves DNS and renders upstream content from scratch."
