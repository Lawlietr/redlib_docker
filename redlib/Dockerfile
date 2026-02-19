ARG ALPINE_VERSION=3.22

FROM rust:alpine${ALPINE_VERSION} AS builder

ARG REDLIB_SRC=https://github.com/redlib-org/redlib.git
ARG REDLIB_BRANCH=main

RUN apk add --no-cache git make musl-dev perl

WORKDIR /redlib

RUN git clone --depth 1 --branch "${REDLIB_BRANCH}" "${REDLIB_SRC}" . \
  && git fetch origin pull/506/head:pr506 \
  && git fetch origin pull/509/head:pr509 \
  && git checkout pr509 \
  && git -c user.email="builder" -c user.name="builder" merge pr506 --no-ff -m "Merge PR#506"

RUN cargo fetch

RUN TARGET=$(rustc -vV | grep host | cut -d' ' -f2) && \
  mkdir -p .cargo && printf '%s\n' \
  "[target.$TARGET]" \
  'rustflags = ["-C", "target-feature=+crt-static"]' \
  > .cargo/config.toml \
  && cargo build --release --locked --bin redlib --target "$TARGET"

FROM scratch AS release

COPY --from=builder /redlib/target/*/release/redlib /redlib
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

USER 1000:1000

EXPOSE 8080

ENTRYPOINT ["/redlib"]
