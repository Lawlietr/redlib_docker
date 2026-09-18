# Build args, PR bake chain, and cache mounts: see AGENTS.md and
# design/forgejo-runner-workflow.md.
# Note: the build host must reach codeberg.org registry via its local
# cbgproxy workaround (design/forgejo-runner-workflow.md, section 6).
# Manual "Run workflow" (no input) now builds all apps in the tree.
# Runner container needs --group-add <docker-gid> so job docker login
# reaches the daemon (client-side fallback hits the edge directly).
# Login step now retries 6x across codeberg edge kill windows.
# Login step also fails fast with a clear error if CODEBERG_PAT is unset.
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

# NOTE: as of 2026-09-18 the formerly-baked PRs (#506, #521, #560, #539,
# #549) have all been merged into upstream main (up to 8167e00 "Merge
# PR#549"), so main alone contains everything. The old bake chain is
# retired; REDLIB_BRANCH=main picks it up automatically.
# (#509 hyper-tls is superseded by main's wreq migration — do not re-add.)
RUN git clone --depth 1 --branch "${REDLIB_BRANCH}" "${REDLIB_SRC}" .

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
