# Build args, PR bake chain, and cache mounts: see AGENTS.md and
# design/forgejo-runner-workflow.md.
# Note: the build host must reach codeberg.org registry via its local
# cbgproxy workaround (design/forgejo-runner-workflow.md, section 6).
# Manual "Run workflow" (no input) now builds all apps in the tree.
# Runner container needs --group-add <docker-gid> so job docker login
# reaches the daemon (client-side fallback hits the edge directly).
# Login step now retries 6x across codeberg edge kill windows.
# Login step also fails fast with a clear error if CODEBERG_PAT is unset.
ARG ALPINE_VERSION=3.22

FROM rust:alpine${ALPINE_VERSION} AS builder

ARG REDLIB_SRC=https://github.com/redlib-org/redlib.git
ARG REDLIB_BRANCH=main

RUN apk add --no-cache git make musl-dev perl

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

RUN --mount=type=cache,id=redlib-cargo-registry,target=/root/.cargo \
    --mount=type=cache,id=redlib-cargo-target,target=/cache/target \
    TARGET=$(rustc -vV | grep host | cut -d' ' -f2) && \
    mkdir -p .cargo dist && printf '%s\n' \
    "[target.$TARGET]" \
    'rustflags = ["-C", "target-feature=+crt-static"]' \
    > .cargo/config.toml \
    && cargo build --release --locked --bin redlib --target "$TARGET" --target-dir /cache/target \
    && cp "/cache/target/$TARGET/release/redlib" dist/redlib

FROM scratch AS release

COPY --from=builder /redlib/dist/redlib /redlib
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

USER 1000:1000

EXPOSE 8080

ENTRYPOINT ["/redlib"]
