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
- PR merges: PR#506, PR#509 (merged into build)
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

- Shallow clone: `--depth 1`
- PR merging: Use temporary refs, clean up
- Set user email/name for git operations

## External References

- Redlib: https://github.com/redlib-org/redlib
- Rust Docker: https://hub.docker.com/_/rust
- Alpine Docker: https://hub.docker.com/_/alpine
