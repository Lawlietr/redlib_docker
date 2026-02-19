# supported versions here: https://hub.docker.com/_/rust
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
  && git merge pr506 --no-ff -m "Merge PR#506 into pr509"
RUN cargo build --release --locked --bin redlib
RUN echo "finished building redlib from ${REDLIB_SRC}/${REDLIB_BRANCH}!"

FROM alpine:${ALPINE_VERSION} AS release

RUN apk add --no-cache ca-certificates

COPY --from=builder /redlib/target/release/redlib /usr/local/bin/redlib

RUN adduser --home /nonexistent --no-create-home --disabled-password redlib
USER redlib

EXPOSE 8080

HEALTHCHECK --interval=1m --timeout=3s CMD wget --spider -q http://localhost:8080/settings || exit 1

CMD ["redlib"]
