# Build args, PR bake chain, and cache mounts: see AGENTS.md and
# design/forgejo-runner-workflow.md.
# Note: the build host must reach codeberg.org registry via its local
# cbgproxy workaround (design/forgejo-runner-workflow.md, section 6).
# Manual "Run workflow" (no input) now builds all apps in the tree.
# Runner container needs --group-add <docker-gid> so job docker login
# reaches the daemon (client-side fallback hits the edge directly).
# Login step now retries 6x across codeberg edge kill windows.
ARG ALPINE_VERSION=3.22

FROM rust:alpine${ALPINE_VERSION} AS builder

ARG REDLIB_SRC=https://github.com/redlib-org/redlib.git
ARG REDLIB_BRANCH=main

RUN apk add --no-cache git make musl-dev perl

WORKDIR /redlib

RUN git clone --depth 300 --branch "${REDLIB_BRANCH}" "${REDLIB_SRC}" . \
  && git fetch origin pull/506/head:pr506 \
  && git fetch origin pull/509/head:pr509 \
  && git fetch origin pull/521/head:pr521 \
  && git fetch origin pull/560/head:pr560 \
  && git fetch origin pull/539/head:pr539 \
  && git fetch origin pull/549/head:pr549 \
  && git checkout pr509 \
  && git -c user.email="builder" -c user.name="builder" merge pr506 --no-ff -m "Merge PR#506" \
  && git -c user.email="builder" -c user.name="builder" merge -X ours pr521 --no-ff -m "Merge PR#521" \
  && git -c user.email="builder" -c user.name="builder" merge -X ours pr560 --no-ff -m "Merge PR#560" \
  && git -c user.email="builder" -c user.name="builder" merge -X ours pr539 --no-ff -m "Merge PR#539" \
  && git -c user.email="builder" -c user.name="builder" merge -X ours pr549 --no-ff -m "Merge PR#549"

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
