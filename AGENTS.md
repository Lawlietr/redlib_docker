# AGENTS.md

## Project Overview

This repository contains Docker build configurations for Redlib, a lightweight Reddit alternative built with Rust. The actual Rust source code is cloned from an external repository (https://github.com/redlib-org/redlib.git) during the Docker build process.

This repository's own configuration files and scripts are licensed under the MIT License (see `LICENSE`). The bundled Redlib source (built at Docker build time) retains its own upstream license (AGPL-3.0).

## Repository Layout

- `Dockerfile` / `docker-compose.yaml` (repo root) — the redlib image build. Single-app repo; the former `redlib/` app subdirectory (dir name = image name) was retired 2026-09-18.
- `TODO.md` — **Work progress and priority only** (P0/P1/P2/P3). Records what is done and what is pending; keeps implementation details out. See the priority legend at the top of the file.
- `design/` — **Implementation guidelines** for each task (deployment steps, config, gotchas). Detailed/longer explanations live here, referenced from `TODO.md`. Keep sensitive info (registration `uuid`/`token`, `CODEBERG_PAT`) out of these files; use placeholders and note where the real value must be entered.

## Build Commands

```bash
docker build -t redlib .                          # local build
# docker build --build-arg REDLIB_BRANCH=dev -t redlib .  # specific branch
docker run -p 8080:8080 -d --name redlib redlib  # run
```

Test build: `docker build --target builder -t redlib-test .` then
`docker run --rm --entrypoint /redlib redlib-test --help`.

## CI/CD

### Forgejo Actions (primary)

`.forgejo/workflows/build.yml` — runs on the self-hosted runner (label `redlib`, Ubox-02 192.168.1.12; docker via mounted socket + BuildKit).

**Workflow principle: compile on the 12 runner, then push.** Multi-arch binaries are cross-compiled natively on the runner (no QEMU), each packed into `scratch` via `Dockerfile.pack`, pushed per-platform, then merged into a multi-platform manifest list and pushed to the registry.

- **Trigger**: Changes to `Dockerfile`, `Dockerfile.pack`, or `.forgejo/scripts/build_and_push.sh`; or manual dispatch (`workflow_dispatch`) from the local Forgejo UI
- **Platform**: `linux/amd64`, `linux/arm64` (musl static, native cross-compile)
- **Compile host**: the runner container `forgejo-runner` on Ubox-02 (192.168.1.12). Extends Alpine with `apk add` (cross-compiler + rustup + clang); see `design/multi-arch-build.md` §5.
  > **工具鏈安裝與驗證全在 12 runner 執行。本地不裝任何工具鏈、不碰本地 Forgejo。**
- **Push target**: `codeberg.org/lawlietr/redlib` (lowercase namespace). Tags: `latest` + `<git-sha>` (multi-platform manifest lists), plus per-platform `amd64`/`arm64`. Login uses the `CODEBERG_PAT` repo secret (write:packages), username `Lawlietr` (the Codeberg account, not the local Forgejo owner).
- Disk guard (`.forgejo/scripts/disk_guard.sh`) + `docker image prune -a` after push keep the 30GB runner box clean
- Gotchas: `build_and_push.sh` sets `CXX_*`/`AR_*` for the arm target — without them boring-sys2's C++ source compiles with the host `g++` and the arm linker fails with "file in wrong format (EM: 62)". Details: `design/multi-arch-build.md`, `design/forgejo-runner-workflow.md`, `design/forgejo-runner-deployment.md`


### GitHub Actions Workflow (guarded backup)

`.github/workflows/build.yml` is guarded with `if: ${{ github.server_url == 'https://github.com' }}` so it only runs when the repo is hosted on GitHub:
- **Platforms**: linux/amd64 and linux/arm64
- **Registry**: ghcr.io/{owner}/containers:{app-name}

Manual trigger: GitHub Actions → "Build container images" → "Run workflow"

## Dockerfile Guidelines

### Structure

Multi-stage build:
1. **Builder**: `rust:1.98-slim-bookworm` — clone upstream `main`, `cargo rustc` with `+crt-static`/`relocation-model=static`/`link-args=-static` (flags only on final crate, not in `.cargo/config.toml`)
2. **Release**: `scratch` — copy binary + CA bundle

### Build Arguments

| ARG | Default | Description |
|-----|---------|-------------|
| `REDLIB_SRC` | `https://github.com/redlib-org/redlib.git` | Redlib git source |
| `REDLIB_BRANCH` | `main` | Branch to clone |

### Conventions

- `apt-get --no-install-recommends`, drop package lists after install
- `--locked` for Cargo builds; `--depth 1` for git clone
- Static flags only on final crate via `cargo rustc --` (proc-macro breakage if in `.cargo/config.toml`)
- Non-root user (UID 1000:1000), `scratch` release base
- Uppercase ARGs, concise comments, group related ops in single RUN

## Project-Specific Notes

### Redlib Source

- Source: https://github.com/redlib-org/redlib.git, `REDLIB_BRANCH=main`
- All formerly-baked PRs merged into upstream `main` (2026-09-18); bake chain retired
- Build: `cargo build --release --locked --bin redlib`

### Environment Variables (Runtime)

- `PORT` - Server port (default: 8080)
- `REDLIB_ENABLE_RSS` - Optional; off by default. Turns on RSS feeds.
- `REDLIB_FULL_URL` - Optional; builds absolute article URLs only for RSS feeds (only meaningful when RSS is on). Not needed for normal browsing.





## Conventions

- Shell: `set -euo pipefail`, quote variables, `&&` chaining, `printf` over `echo`
- Git: `--depth 1`, verify upstream compiles on branch bump
- CI scripts: `trap 'docker image prune -a -f' EXIT` for cleanup

## External References

- Redlib: https://github.com/redlib-org/redlib
- Rust Docker: https://hub.docker.com/_/rust
- Debian Docker: https://hub.docker.com/_/debian
