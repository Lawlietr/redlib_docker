# AGENTS.md

## Project Overview

This repository contains Docker build configurations for Redlib, a lightweight Reddit alternative built with Rust. The actual Rust source code is cloned from an external repository (https://github.com/redlib-org/redlib.git) during the Docker build process.

This repository's own configuration files and scripts are licensed under the MIT License (see `LICENSE`). The bundled Redlib source (built at Docker build time) retains its own upstream license (AGPL-3.0).

## Repository Layout

- `Dockerfile` / `docker-compose.yaml` (repo root) — the redlib image build. Single-app repo; the former `redlib/` app subdirectory (dir name = image name) was retired 2026-09-18.
- `redlib-prs.txt` — **single source of truth** for the still-open upstream PRs baked into the source tree at build time. Read by both build paths (`Dockerfile` and `.forgejo/scripts/build_and_push.sh`) via `.build/apply_redlib_prs.sh`. Rationale/tiers: `design/upstream-pr-bake.md`.
- `.build/apply_redlib_prs.sh` — fetches `pull/<n>/head` and merges each listed PR into the cloned redlib tree (`--no-ff`, no `-X ours`).
- `TODO.md` — **Work progress and priority only** (P0/P1/P2/P3). Each entry = 做什麼 + 為什麼/範圍 + 優先級 + 指向 `design/` 的連結。禁止出現在此：redlib 源碼檔案/代碼標識符、route 路徑、env 變數名、分步流程、驗證步驟（這些一律入 `design/` 並由 TODO 引用；repo 自有檔案如 `build_and_push.sh` 可提）。優先級定義見檔頭。
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

- **Trigger**: Changes to `Dockerfile`, `Dockerfile.pack`, `redlib-prs.txt`, `.build/**`, or `.forgejo/scripts/build_and_push.sh`; or manual dispatch (`workflow_dispatch`) from the local Forgejo UI
- **Platform**: `linux/amd64`, `linux/arm64` (musl static, native cross-compile)
- **Compile host**: the runner container `forgejo-runner` on Ubox-02 (192.168.1.12). Based on `rust:1.98-slim-trixie` (Debian 13) with musl-cross-make aarch64-musl toolchain, clang, cmake, docker CLI, buildx, and compose plugins; see `design/multi-arch-build.md` §5.
  > **工具鏈安裝與驗證全在 12 runner 執行。本地不裝任何工具鏈、不碰本地 Forgejo。**
- **Push target**: `codeberg.org/lawlietr/redlib` (lowercase namespace). Tags: `latest` + `<git-sha>` (multi-platform manifest lists), plus per-platform `amd64`/`arm64`. Login uses the `CODEBERG_PAT` repo secret (write:packages), username `Lawlietr` (the Codeberg account, not the local Forgejo owner).
- Disk guard (`.forgejo/scripts/disk_guard.sh`) + `docker image prune -a` after push keep the 30GB runner box clean
- Gotchas: `build_and_push.sh` sets `CXX_*`/`AR_*`/`CC_*`/`BINDGEN_EXTRA_CLANG_ARGS` for the arm target — without them boring-sys2's C++ source compiles with the host `g++` and the arm linker fails with "file in wrong format (EM: 62)"; bindgen needs glibc multiarch headers on Debian trixie. Details: `design/multi-arch-build.md`, `design/forgejo-runner-workflow.md`, `design/forgejo-runner-deployment.md`


### GitHub Actions Workflow (amd64 compile + ghcr mirror)

`.github/workflows/build.yml` is guarded with `if: ${{ github.server_url == 'https://github.com' }}` so it only runs when the repo is hosted on GitHub (it does — see Repository Remotes):
- **Trigger**: push to `main` touching `Dockerfile`, `redlib-prs.txt`, `.build/**`, `.github/**`; or `workflow_dispatch`
- **Compile**: `ubuntu-latest` (native amd64), `docker build -f Dockerfile` → same source tree as the local build (main + `redlib-prs.txt`)
- **Registry**: `ghcr.io/{owner}/redlib:latest` via `.github/scripts/build_and_push.sh` (login uses `GITHUB_TOKEN`)
- Multi-arch (arm64) on GitHub is a separate item: `design/multi-arch-build.md` §11

Manual trigger: GitHub Actions → "Build container images" → "Run workflow"

## Dockerfile Guidelines

### Structure

Multi-stage build:
1. **Builder**: `rust:1.98-slim-bookworm` — clone upstream `main` (`--depth 300`), merge the PRs listed in `redlib-prs.txt` (`.build/apply_redlib_prs.sh`), then `cargo rustc` with `+crt-static`/`relocation-model=static`/`link-args=-static` (flags only on final crate, not in `.cargo/config.toml`)
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

### Repository Remotes

本 repo 三宿：`origin` = 本地 Forgejo（`lawliet/redlib_docker`），`codeberg` = `codeberg.org/Lawlietr/redlib_docker`，`github` = `github.com/Lawlietr/redlib_docker`（GitHub 是 GitHub Actions 的編譯入口）。**每次 push 都推所有 remote**。

### Redlib Source

- Source: https://github.com/redlib-org/redlib.git, `REDLIB_BRANCH=main`
- **Bake**: upstream `main` alone is NOT enough. Still-open PRs are merged on top at build time; the list lives in `redlib-prs.txt` and is applied by `.build/apply_redlib_prs.sh` (both the Dockerfile and the multi-arch CI path read the same list). Tiers, review data, drift procedure: `design/upstream-pr-bake.md`.
  - Current Tier 1: #549 (CMAF + rich:video), #542 (0-comment panic), #521 (default post sort), #560 (`/u/:name/s/:id`), #539 (lazy-load images).
  - ⚠ The 2026-09-18 note claiming those PRs were "merged into upstream main (up to `8167e00`)" was **wrong**: `8167e00` was our own in-build merge tip, not an upstream commit. Upstream `main` (HEAD `a4d36e9`, 2026-04-24) contains none of them — re-verified 2026-10-07 with `git cherry` + content grep.
  - #509 (hyper-tls) stays out: superseded by main's wreq migration.
- Build: `cargo build --release --locked --bin redlib`

### Environment Variables (Runtime)

常見變數（完整清單見 repo 內 `.env.example` 與上游文件）：

| 變數 | 預設 | 說明 |
|------|------|------|
| `PORT` | `8080` | 伺服器埠 |
| `REDLIB_DEFAULT_THEME` | `system` | 預設主題（system/light/dark/black/dracula/nord/laserwave/violet/gold/rosebox/gruvboxdark/gruvboxlight） |
| `REDLIB_DEFAULT_FRONT_PAGE` | `default` | 預設首頁（default/popular/all） |
| `REDLIB_DEFAULT_LAYOUT` | `card` | 預設版面（card/clean/compact） |
| `REDLIB_DEFAULT_POST_SORT` | `hot` | 預設文章排序（hot/new/top/rising/controversial） |
| `REDLIB_DEFAULT_COMMENT_SORT` | `confidence` | 預設留言排序（confidence/top/new/controversial/old） |
| `REDLIB_DEFAULT_SHOW_NSFW` | `off` | 預設顯示 NSFW 內容 |
| `REDLIB_DEFAULT_FILTERS` | (empty) | 預設過濾 subreddit（格式：sub1+sub2+sub3） |
| `REDLIB_DEFAULT_SUBSCRIPTIONS` | (empty) | 預設訂閱 subreddit（格式：sub1+sub2+sub3） |
| `REDLIB_BANNER` | (empty) | 執行個體橫幅訊息 |
| `REDLIB_SFW_ONLY` | `off` | SFW-only 模式 |
| `REDLIB_ROBOTS_DISABLE_INDEXING` | `off` | 關閉搜尋引擎索引 |





## Conventions

- Shell: `set -euo pipefail`, quote variables, `&&` chaining, `printf` over `echo`
- Git: `--depth 1`, verify upstream compiles on branch bump
- CI scripts: `trap 'docker image prune -a -f' EXIT` for cleanup

## External References

- Redlib: https://github.com/redlib-org/redlib
- Rust Docker: https://hub.docker.com/_/rust
- Debian Docker: https://hub.docker.com/_/debian
