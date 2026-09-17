# AGENTS.md

## Project Overview

This repository contains Docker build configurations for Redlib, a lightweight Reddit alternative built with Rust. The actual Rust source code is cloned from an external repository (https://github.com/redlib-org/redlib.git) during the Docker build process.

## Build Commands

### Local Docker Build

```bash
docker build -f redlib/Dockerfile -t redlib .
```

### Build with Specific Alpine Version

```bash
docker build --build-arg ALPINE_VERSION=3.22 -f redlib/Dockerfile -t redlib .
```

### Build with Specific Redlib Branch

```bash
docker build --build-arg REDLIB_BRANCH=main -f redlib/Dockerfile -t redlib .
```

### Run the Container

```bash
docker run -p 8080:8080 -d --name redlib redlib
```

### Test Build (Builder Stage Only)

```bash
docker build --target builder -f redlib/Dockerfile -t redlib-test .
```

### Test Binary in Container

```bash
docker run --rm --entrypoint /redlib redlib-test --help
```

## CI/CD

### GitHub Actions Workflow

Automated builds via GitHub Actions:
- **Trigger**: Changes to any `*/Dockerfile` file
- **Platforms**: linux/amd64 and linux/arm64
- **Registry**: ghcr.io/{owner}/containers:{app-name}

Manual trigger: GitHub Actions → "Build container images" → enter app names → "Run workflow"

## Dockerfile Guidelines

### Structure

Multi-stage build:
1. **Builder**: Clone Redlib, apply PRs, build with Cargo
2. **Release**: Copy binary, minimal Alpine runtime

### Build Arguments

| ARG | Default | Description |
|-----|---------|-------------|
| `ALPINE_VERSION` | `3.22` | Alpine version for builder |
| `REDLIB_SRC` | `https://github.com/redlib-org/redlib.git` | Redlib git source |
| `REDLIB_BRANCH` | `main` | Branch to clone |

### Best Practices

- Use `--no-cache` for apk installs
- Use `--locked` for Cargo builds
- Static linking via `crt-static` target feature
- Non-root user (UID 1000:1000)
- Minimal scratch base for release stage
- Explicit ARG defaults

### Code Style

- Uppercase for all ARGs
- Concise comments, descriptive
- Group related operations in single RUN
- Use `printf` for .cargo/config.toml generation
- Follow Alpine package naming

## Project-Specific Notes

### Redlib Source Management

- Source: https://github.com/redlib-org/redlib.git
- `REDLIB_BRANCH=main` so any upstream PR already merged into `main` is auto-included. Only still-OPEN PRs are baked manually (via the Dockerfile RUN chain below).
- Baked PRs (still-open PRs fetched at build time and merged into `main`):
  - Baseline: #506 (CMAF video format + `/vid/:id/cmaf/:size` proxy route), #509 (media/download handling)
  - #521 (default post_sort applied immediately via `setting()`), #560 (user profile `/u/:name/s/:id` share links), #539 (lazy-load post images, drop SVG), #549 (`rich:video` support + CMAF regex, complements #506)
- Bake mechanism (in `redlib/Dockerfile` builder RUN): clone → `git fetch origin pull/<n>/head:pr<N>` for each → `git checkout pr509` → `merge pr506` (plain) → `merge -X ours pr521 pr560 pr539 pr549`.
  - `-X ours` is required for #521/#560/#539/#549: these branches predate `main`'s migration to the `wreq` HTTP/TLS backend, so `-X ours` keeps `main`'s current `client.rs` while applying each PR's own change. Verify the merged tree compiles (`cargo build --bin redlib`) before committing.
- Build: `cargo build --release --locked --bin redlib`
- Static binary for minimal footprint

### Environment Variables (Runtime)

- `PORT` - Server port (default: 8080)
- `DOMAIN` - Domain name
- `REDIS_URL` - Redis connection (optional)

### Current State

- Binary: `/redlib` in container
- Port: 8080 (exposed)
- Health checks: Not configured (add if needed)

## Testing

### Build Validation

```bash
# Validate build without push
docker build --target builder -f redlib/Dockerfile -t redlib-test .

# Test binary execution
docker run --rm --entrypoint /redlib redlib-test --help
```

### Container Testing

```bash
# Run and verify
docker run -p 8080:8080 -d --name redlib-test redlib
docker ps
docker logs redlib-test
```

### Cross-Platform

```bash
# Build for different architectures
docker buildx build --platform linux/amd64,linux/arm64 -f redlib/Dockerfile -t redlib .
```

## Code Style Guidelines

This repository contains Dockerfiles and build scripts (no Rust source in this repo):

### Dockerfile Conventions

- Follow official Dockerfile best practices
- Multi-stage builds for smaller images
- Explicit ARG defaults
- Clear stage names
- Sparse comments

### Shell Script Conventions

- Use `set -euo pipefail` for error handling
- Quote variables: `"${VAR}"`
- Use `&&` for command chaining in single RUN
- Prefer `printf` over `echo` for portability

### Git Operations

- Shallow clone: `--depth 300` (deep enough to reach the merge base of old-based PRs like #521/#549; `--depth 1` fails 3-way merges for those. Bump if `main` advances past the PR bases.)
- PR merging: Use temporary refs (`pull/<n>/head:pr<N>`), merge in a fixed order (baseline first), `-X ours` for PRs based on pre-`wreq` `main`
- Set user email/name for git operations: `-c user.email="builder" -c user.name="builder"`

## External References

- Redlib: https://github.com/redlib-org/redlib
- Rust Docker: https://hub.docker.com/_/rust
- Alpine Docker: https://hub.docker.com/_/alpine
