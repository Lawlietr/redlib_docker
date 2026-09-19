# AGENTS.md

## Project Overview

This repository contains Docker build configurations for Redlib, a lightweight Reddit alternative built with Rust. The actual Rust source code is cloned from an external repository (https://github.com/redlib-org/redlib.git) during the Docker build process.

This repository's own configuration files and scripts are licensed under the MIT License (see `LICENSE`). The bundled Redlib source (built at Docker build time) retains its own upstream license (AGPL-3.0).

## Repository Layout

- `Dockerfile` / `docker-compose.yaml` (repo root) — the redlib image build. Single-app repo; the former `redlib/` app subdirectory (dir name = image name) was retired 2026-09-18.
- `TODO.md` — **Work progress and priority only** (P0/P1/P2/P3). Records what is done and what is pending; keeps implementation details out. See the priority legend at the top of the file.
- `design/` — **Implementation guidelines** for each task (deployment steps, config, gotchas). Detailed/longer explanations live here, referenced from `TODO.md`. Keep sensitive info (registration `uuid`/`token`, `CODEBERG_PAT`) out of these files; use placeholders and note where the real value must be entered.

## Build Commands

### Local Docker Build

```bash
docker build -t redlib .
```

### Build with Specific Redlib Branch

```bash
docker build --build-arg REDLIB_BRANCH=main -t redlib .
```

### Run the Container

```bash
docker run -p 8080:8080 -d --name redlib redlib
```

### Test Build (Builder Stage Only)

```bash
docker build --target builder -t redlib-test .
```

### Test Binary in Container

```bash
docker run --rm --entrypoint /redlib redlib-test --help
```

## CI/CD

### Forgejo Actions (primary)

`.forgejo/workflows/build.yml` — runs on the self-hosted runner (label `redlib`, Ubox-02 192.168.1.12; docker via mounted socket + BuildKit):
- **Trigger**: Changes to `Dockerfile`, or manual dispatch from the local Forgejo UI
- **Platform**: linux/amd64
- **Registry**: `codeberg.org/lawlietr/redlib:latest` (lowercase namespace; login with the `CODEBERG_PAT` repo secret, write:packages scope)
- Disk guard (`.forgejo/scripts/disk_guard.sh`) + `docker image prune -a` after push keep the 10GB runner box clean
- Details: `design/forgejo-runner-workflow.md`, `design/forgejo-runner-deployment.md`

### GitHub Actions Workflow (guarded backup)

`.github/workflows/build.yml` is guarded with `if: ${{ github.server_url == 'https://github.com' }}` so it only runs when the repo is hosted on GitHub:
- **Platforms**: linux/amd64 and linux/arm64
- **Registry**: ghcr.io/{owner}/containers:{app-name}

Manual trigger: GitHub Actions → "Build container images" → "Run workflow"

## Dockerfile Guidelines

### Structure

Multi-stage build:
1. **Builder**: Clone Redlib (upstream `main`), build a fully static glibc binary with Cargo (wreq/BoringSSL needs glibc; musl is a dead end)
2. **Release**: Copy binary + CA bundle, `scratch` runtime

### Build Arguments

| ARG | Default | Description |
|-----|---------|-------------|
| `REDLIB_SRC` | `https://github.com/redlib-org/redlib.git` | Redlib git source |
| `REDLIB_BRANCH` | `main` | Branch to clone |

### Best Practices

- `apt-get --no-install-recommends`, drop package lists after install
- Use `--locked` for Cargo builds
- Fully static binary via `cargo rustc --` flags (`+crt-static`, `relocation-model=static`, `link-args=-static`) — only on the final crate; putting them in `.cargo/config.toml` breaks proc-macro builds
- Non-root user (UID 1000:1000)
- Minimal scratch base for release stage
- Explicit ARG defaults

### Code Style

- Uppercase for all ARGs
- Concise comments, descriptive
- Group related operations in single RUN

## Project-Specific Notes

### Redlib Source Management

- Source: https://github.com/redlib-org/redlib.git
- `REDLIB_BRANCH=main`. As of 2026-09-18 the formerly-baked PRs (#506, #521, #560, #539, #549) are all merged into upstream `main` (up to `8167e00` "Merge PR#549"), so no manual baking is needed — `main` alone contains everything. The old bake chain was retired for this reason (it had also rotted: PR-branch `Cargo.lock` checksum drift broke `cargo fetch`, and the pr509-based tree silently kept pre-wreq `client.rs`).
- #509 (hyper-tls backend) was never needed on the wreq-based main — superseded by main's wreq migration; do not re-add it.
- Build: `cargo build --release --locked --bin redlib`
- Static binary for minimal footprint

### Environment Variables (Runtime)

- `PORT` - Server port (default: 8080)
- `REDLIB_FULL_URL` - Optional; builds absolute URLs only for RSS feeds (enable with REDLIB_ENABLE_RSS=on). Not needed for normal browsing.

### Current State

- Binary: `/redlib` in container
- Port: 8080 (exposed)
- Health checks: Not configured (add if needed)

## Testing

### Build Validation

```bash
# Validate build without push
docker build --target builder -t redlib-test .

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
docker buildx build --platform linux/amd64,linux/arm64 -t redlib .
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

- Shallow clone: `--depth 1` (no PR baking anymore; bump only if a merge chain is re-introduced)
- Verify upstream main compiles (`cargo build --bin redlib`) when bumping `REDLIB_BRANCH`
- Set user email/name for git operations: `-c user.email="builder" -c user.name="builder"`

## External References

- Redlib: https://github.com/redlib-org/redlib
- Rust Docker: https://hub.docker.com/_/rust
- Debian Docker: https://hub.docker.com/_/debian
