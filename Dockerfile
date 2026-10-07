# Build args, PR bake chain (retired 2026-09-18), and cache mounts: see
# AGENTS.md and design/forgejo-runner-workflow.md.
# Anyone can build this locally: `docker build -t redlib .` (repo root).
#
# CI multi-arch build (amd64/arm64, musl static) does NOT use this file:
# it cross-compiles natively and packs via Dockerfile.pack (see
# .forgejo/scripts/build_and_push.sh and design/multi-arch-build.md). This
# Dockerfile stays as the single-command local amd64 build.
# (network access to github.com + crates.io; NO secrets needed — none are
# used by this file). Image content = upstream `main` + the still-open PRs
# listed in redlib-prs.txt, as of build time; pin REDLIB_BRANCH to a
# commit/tag for a bit-for-bit reproducible build.
#
# The lines below are OUR-CI-specific (self-hosted runner pushing to
# codeberg.org) and are NOT needed for a local build:
# - the build host reaches the codeberg.org registry only via its local
#   cbgproxy workaround (design/forgejo-runner-workflow.md, section 6);
# - manual "Run workflow" (no input) builds all apps in the tree;
# - the runner container needs --group-add <docker-gid> so the job's
#   `docker login` reaches the daemon (client-side fallback hits the edge);
# - the login step retries 6x across codeberg edge kill windows and fails
#   fast with a clear error if CODEBERG_PAT is unset.
# - the runner container needs Node.js (for actions/checkout@v4); it is
#   installed on the runner image (see /opt/forgejo-runner/Dockerfile).
# Builder is glibc-based (slim bookworm), NOT alpine/musl: wreq (upstream
# redlib's current HTTP/TLS stack) pulls boring-sys2 (BoringSSL), whose
# build script needs cmake + a C compiler + libclang, and bindgen dlopens
# libclang — impossible in the static musl build-script environment.
# The final binary is fully static (see build flags below), so the release
# stage stays `scratch`.
FROM rust:1.98-slim-bookworm AS builder

ARG REDLIB_SRC=https://github.com/redlib-org/redlib.git
ARG REDLIB_BRANCH=main

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential cmake clang libclang-dev perl pkg-config git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /redlib

# Bake still-OPEN upstream PRs (list: redlib-prs.txt, rationale + review tiers:
# design/upstream-pr-bake.md). They are NOT in upstream main — verified
# 2026-10-07 against main HEAD a4d36e9, where none of them is an ancestor or
# patch-applied. (The 2026-09-18 "all merged upstream" note was wrong: the
# commit it cited, 8167e00 "Merge PR#549", was this build's own local merge
# tip, not an upstream commit.)
# --depth 300 keeps the clone shallow while still reaching the merge base of
# PRs branched from older main. Merges are plain --no-ff (no -X ours): a
# conflict means upstream drifted and the list must be re-reviewed, so the
# build fails loudly instead of silently dropping upstream changes.
COPY redlib-prs.txt .build/apply_redlib_prs.sh /tmp/redlib-build/
RUN git clone --depth 300 --branch "${REDLIB_BRANCH}" "${REDLIB_SRC}" . \
    && bash /tmp/redlib-build/apply_redlib_prs.sh . /tmp/redlib-build/redlib-prs.txt

# BuildKit cache mounts persist cargo state on the host between builds
# (incremental rebuilds). Cache content is NOT part of the stage image,
# so the binary is copied out of the mounted target dir into dist/.
RUN --mount=type=cache,id=redlib-cargo-registry,target=/root/.cargo \
    cargo fetch

# Fully static glibc binary. The static flags are passed ONLY to the final
# crate via `cargo rustc -- ...` — putting them in .cargo/config.toml
# `[target.<host>] rustflags` (or the RUSTFLAGS env) also applies them to
# proc-macro crates and breaks the build ("cannot produce proc-macro" / PIE
# link errors).
#   +crt-static           statically link the C runtime
#   relocation-model=static  glibc's static CRT is not PIE-compatible
#   link-args=-static     link libc.a (glibc ships /usr/lib/x86_64-linux-gnu/libc.a)
RUN --mount=type=cache,id=redlib-cargo-registry,target=/root/.cargo \
    --mount=type=cache,id=redlib-cargo-target,target=/cache/target \
    cargo rustc --release --locked --bin redlib --target-dir /cache/target -- \
        -C target-feature=+crt-static \
        -C relocation-model=static \
        -C link-args=-static \
    && mkdir -p dist \
    && cp /cache/target/release/redlib dist/redlib

FROM scratch AS release

COPY --from=builder /redlib/dist/redlib /redlib
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

USER 1000:1000

EXPOSE 8080

ENTRYPOINT ["/redlib"]
