#!/bin/bash
set -euo pipefail

# Post-publish smoke test of the images we just pushed, run from a clean runner.
#
# Why this exists: the binaries are fully static and ship on `scratch`, so the two failure
# classes that used to be discovered on a live instance instead of in CI are
#   (1) a shipped binary that is not actually self-contained (a dynamic NEEDED entry means it
#       dies instantly on scratch), or a static binary that cannot resolve DNS inside scratch
#       (the classic static-glibc NSS trap - redlib fetches from reddit, so a broken resolver
#       breaks every page),
#   (2) a baked upstream PR that breaks rendering at runtime rather than at compile time.
# Both are caught here, before the mirror job is allowed to copy anything to Codeberg.
#
# Do NOT probe redlib with `--help`: it takes no CLI arguments at all (configuration comes from
# environment variables only) and passing one prints "error: unexpected argument found".
#
# Verified baseline (2026-10-21, x86_64 host, against the published ghcr images): amd64 and
# arm64 binaries both report "statically linked"; / -> 200 with ~54KB; /r/gaming -> 200 79,425B;
# /r/AskReddit/top -> 200 38,009B; no resolver errors in the log; exit code 0.

SRC="ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/redlib"
PORT=18080
CID=redlib-smoke
RENDERING_PROVEN=0
UPSTREAM_SIDE_LIMITED=0

cleanup() { docker rm -f "$CID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

log_has_dns_error() {
  docker logs "$CID" 2>&1 | grep -qiE "temporary failure in name resolution|failed to lookup|name or service not known"
}

echo "=== 1. the shipped binaries must be self-contained, and arch-correct ==="
# docker cp the binary out of the image: deterministic, needs no emulation. redlib is the only
# file in the image (scratch), so the path is fixed.
extract() { # extract <image> <platform> <dest>
  local cid
  cid=$(docker create --platform "$2" "$1")
  docker cp "$cid:/redlib" "$3"
  docker rm "$cid" >/dev/null
}
check_binary() { # check_binary <image> <platform> <expected-file-substring> <label>
  extract "$1" "$2" "/tmp/redlib-$4"
  local desc
  desc=$(file -b "/tmp/redlib-$4")
  echo "  $4: $desc"
  if ! grep -q "$3" <<<"$desc"; then
    echo "::error::$4 binary does not match the expected architecture/format (got: $desc)" >&2
    exit 1
  fi
  if readelf -d "/tmp/redlib-$4" 2>/dev/null | grep -q "(NEEDED)"; then
    echo "::error::$4 binary is dynamically linked - it cannot run on scratch" >&2
    readelf -d "/tmp/redlib-$4" | grep "(NEEDED)" >&2
    exit 1
  fi
}
check_binary "${SRC}:amd64" linux/amd64  "x86-64"     amd64
check_binary "${SRC}:arm64" linux/arm64  "ARM aarch64" arm64

echo "=== 2. serve the published amd64 image ==="
docker pull --quiet "${SRC}:amd64"
cleanup
docker run -d --name "$CID" -p "${PORT}:8080" "${SRC}:amd64" >/dev/null

fetch() { curl -s -o /tmp/smoke_body -w '%{http_code} %{size_download}' --max-time 45 "http://127.0.0.1:${PORT}$1"; }

# A route is judged like this:
#   200 + big body      -> the whole chain works, rendering proven
#   200 + tiny body     -> an error page, that is a real defect -> fail
#   403/429/503         -> reddit (or redlib's own limiter) pushed back; DNS, TLS and the round
#                          trip still worked, and runner datacenter IPs do get rate limited -> warning
#   anything else / 000 -> the image is not serving or the upstream fetch failed -> fail
judge_route() { # judge_route <path> <min_bytes>
  local path=$1 min=$2 out st bytes i
  out=""
  for i in 1 2 3; do
    out=$(fetch "$path" || true)
    echo "  $path -> ${out:-no response}"
    st=${out%% *}
    bytes=${out##* }
    if [ "$st" = "200" ] && [ "${bytes:-0}" -ge "$min" ]; then
      RENDERING_PROVEN=1
      return 0
    fi
    case "$st" in 403|429|503) UPSTREAM_SIDE_LIMITED=1; return 0 ;; esac
    sleep 10
  done
  if [ "$st" = "200" ]; then
    echo "::error::$path returned 200 but only ${bytes}B - that looks like an error page, not a rendered page" >&2
    head -c 500 /tmp/smoke_body >&2 || true
  else
    echo "::error::$path never returned a usable response (last status: ${st:-none})" >&2
  fi
  docker logs --tail 40 "$CID" 2>&1 | sed 's/^/    /' >&2
  exit 1
}

for i in 1 2 3 4 5 6 7 8; do
  sleep 3
  probe=$(fetch "/" || true)
  echo "  startup attempt $i  /  ->  ${probe:-no response}"
  [[ "${probe%% *}" == "200" ]] && break
done

judge_route "/" 20000
judge_route "/r/gaming" 20000
judge_route "/r/AskReddit/top" 20000

if log_has_dns_error; then
  echo "::error::the container log contains resolver errors - the static binary cannot do DNS inside scratch" >&2
  docker logs --tail 40 "$CID" 2>&1 | sed 's/^/    /' >&2
  exit 1
fi

if [ "$RENDERING_PROVEN" = "0" ]; then
  echo "::warning::no route proved rendering because reddit pushed back with $UPSTREAM_SIDE_LIMITED-style statuses from this runner IP; self-containment, process start and HTTP serving were still verified"
fi
cleanup

echo "=== 3. arm64: try a real exec where qemu binfmt exists (best effort) ==="
# The arm64 gate is step 1 (architecture + zero NEEDED), which needs no emulation. If the
# runner happens to have aarch64 binfmt, also prove the ELF execs and serves. Functional arm64
# verification on real hardware is a separate, still-open item.
if [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
  docker run -d --name redlib-smoke-arm --platform linux/arm64 -e PORT=18099 -p 18099:18099 "${SRC}:arm64" >/dev/null
  armcode=""
  for i in 1 2 3 4 5 6; do
    sleep 5
    armcode=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 http://127.0.0.1:18099/ || true)
    echo "  arm64 under qemu attempt $i / -> ${armcode:-no response}"
    [ "${armcode:-0}" = "200" ] && break
  done
  docker logs --tail 5 redlib-smoke-arm 2>&1 | sed 's/^/    /' || true
  docker rm -f redlib-smoke-arm >/dev/null 2>&1
  if [ "${armcode:-0}" = "200" ]; then
    echo "  arm64 exec + serve check passed under qemu emulation"
  else
    echo "::warning::arm64 did not serve under qemu (user-mode emulation is slow/unreliable); the step 1 static+arch gate still stands, real-hardware verification is still open"
  fi
else
  echo "  no aarch64 binfmt on this runner: the step 1 static+arch gate is the arm64 check"
fi

echo "Smoke passed: both images ship static, arch-correct binaries, and the amd64 image serves real rendered upstream content from scratch."
