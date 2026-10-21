# AGENTS.md

## Project Overview

This repository contains Docker build configurations for Redlib, a lightweight Reddit alternative built with Rust. The actual Rust source code is cloned from an external repository (https://github.com/redlib-org/redlib.git) during the Docker build process.

**This is a merge-and-packaging repo, not a fork.** There is no redlib source here and no patched
branch: the build clones upstream `main` and merges upstream's own not-yet-merged PRs (the list lives
in `redlib-prs.txt`), then packages the result. Every functional change therefore comes from upstream —
this repo only owns the bake chain, CI, Docker config and docs. Say so in user-facing docs
(`README.md` / `README_EN.md` open with this statement; keep it there).

**Where things live** (the names differ on purpose):

| Item | Location |
|------|----------|
| This repo (Docker config, CI, docs) | https://codeberg.org/Lawlietr/redlib_docker (primary; also mirrored to `github.com/Lawlietr/redlib_docker` as the GitHub Actions build entry point) |
| Container images | **primary: `ghcr.io/lawlietr/redlib`** — multi-arch + `<git-sha>`, built by GitHub Actions on native amd64/arm64 hosted runners (glibc-static). **fallback: `codeberg.org/lawlietr/redlib`** — same tag scheme, musl-static, refreshed **only by a manual** `.forgejo/workflows/build.yml` run, so its tags lag on purpose. Both namespaces are lowercase (registry requirement) |
| Visibility | both remotes and both registries are **public** since 2026-10-21 (the ghcr package used to inherit the private repo, which made anonymous pulls look like "the image does not exist"). Consequence: **git history is public** — never commit `CODEBERG_PAT`, registration `uuid`/`token`, `ghp_…`/`gho_…` tokens or keys; CI reads them only through `${{ secrets.* }}`. |

**Publishing policy (2026-10-21).** Future images are compiled and published by **GitHub Actions**
(`.github/workflows/build.yml` → `ghcr.io/lawlietr/redlib`). The Forgejo runner workflow is **kept, not
deleted** — its `push` trigger was removed so it now runs only via `workflow_dispatch`; use it as the
fallback when GitHub is unavailable, as the only musl-static producer, or to resync the
`codeberg.org/lawlietr/redlib` tags. Local `docker build` + running the container is an explicitly
supported way to test changes (host architecture only; see the smoke checks under Build Commands). Never
publish from a local machine — publishing happens in CI only.

This repository's own configuration files and scripts are licensed under the MIT License (see `LICENSE`). The bundled Redlib source (built at Docker build time) retains its own upstream license (AGPL-3.0).

## Repository Layout

- `Dockerfile` / `docker-compose.yaml` (repo root) — the redlib image build. Single-app repo; the former `redlib/` app subdirectory (dir name = image name) was retired 2026-09-18.
- `redlib-prs.txt` — **single source of truth** for the still-open upstream PRs baked into the source tree at build time. Read by both build paths (`Dockerfile` and `.forgejo/scripts/build_and_push.sh`) via `.build/apply_redlib_prs.sh`. Rationale/tiers: `design/upstream-pr-bake.md`.
- `.build/apply_redlib_prs.sh` — fetches `pull/<n>/head` and merges each listed PR into the cloned redlib tree (`--no-ff`, no `-X ours`).
- `TODO.md` — **Work progress and priority only** (P0/P1/P2/P3). Each entry = 做什麼 + 為什麼/範圍 + 優先級 + 指向 `design/` 的連結。禁止出現在此：redlib 源碼檔案/代碼標識符、route 路徑、env 變數名、分步流程、驗證步驟（這些一律入 `design/` 並由 TODO 引用；repo 自有檔案如 `build_and_push.sh` 可提）。優先級定義見檔頭。
- `design/` — **Implementation guidelines** for each task (deployment steps, config, gotchas). Detailed/longer explanations live here, referenced from `TODO.md`. Keep sensitive info (registration `uuid`/`token`, `CODEBERG_PAT`) out of these files; use placeholders and note where the real value must be entered.
- `design/error-triage-playbook.md` — **SOP for runtime error reports** (使用者回報 redlib 執行期錯誤): map the message to the upstream call site, check a candidate upstream PR's base/cleanliness, then prove the fix with a two-image end-to-end A/B (never bare curl), run the fixed regression list with negative controls, and file the tier decision. Start here on any "broken page / parse error" report.

## Build Commands

```bash
docker build -t redlib .                          # local build (host arch only)
# docker build --build-arg REDLIB_BRANCH=dev -t redlib .  # specific branch
docker run -p 8080:8080 -d --name redlib redlib  # run

# Compose has two image sources (same service, switched by REDLIB_IMAGE):
docker compose up -d --build                      # B) local build (PR bake included)
REDLIB_IMAGE=ghcr.io/lawlietr/redlib:latest \
  docker compose up -d --pull always --no-build   # A) run the CI image (primary registry, no build)
REDLIB_IMAGE=codeberg.org/lawlietr/redlib:latest \
  docker compose up -d --pull always --no-build   # A2) fallback registry (manual runs only)
# NOTE: with a `build:` key present, a plain `up -d` uses the locally built image and
# never pulls the registry one -> always pass --no-build for mode A/A2.

# Local smoke test after any change (full list: design/upstream-pr-bake.md §7):
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/
curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:8080/r/<sub>/comments/<id>/<title>/"   # expect 200
curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:8080/r/__no_such_sub__/comments/<id>/x/"  # negative control: 404/400
docker logs redlib 2>&1 | grep -ci panic          # expect 0
```

> **Local build limits**: it builds the **host architecture** only, and this dev box has no qemu binfmt
> (`tonistiigi/binfmt --install arm64` does not work here), so `--platform linux/arm64` fails with
> `exec format error`. Arm64 runtime checks need real arm64 hardware. Local builds publish nothing.

Test build: `docker build --target builder -t redlib-test .` then
`docker run --rm --entrypoint /redlib redlib-test --help`.

## CI/CD

### Forgejo Actions (kept as a manual-only fallback)

`.forgejo/workflows/build.yml` — runs on the self-hosted runner (label `redlib`, Ubox-02 192.168.1.12; docker via mounted socket + BuildKit). **Since 2026-10-21 the `push` trigger is removed: it only runs through `workflow_dispatch`** (optional `reason` input). Keep it: it is the fallback when GitHub Actions is down and the only producer of musl-static binaries; the runner infrastructure and its docs stay current.

**Workflow principle: compile on the 12 runner, then push.** Multi-arch binaries are cross-compiled natively on the runner (no QEMU), each packed into `scratch` via `Dockerfile.pack`, pushed per-platform, then merged into a multi-platform manifest list and pushed to the registry.

- **Trigger**: `workflow_dispatch` only (manual, from the local Forgejo UI). Re-add the `push` path filter only if the Codeberg registry is meant to lead again.
- **Platform**: `linux/amd64`, `linux/arm64` (musl static, native cross-compile)
- **Compile host**: the runner container `forgejo-runner` on Ubox-02 (192.168.1.12). Based on `rust:1.98-slim-trixie` (Debian 13) with musl-cross-make aarch64-musl toolchain, clang, cmake, docker CLI, buildx, and compose plugins; see `design/multi-arch-build.md` §5.
  > **工具鏈安裝與驗證全在 12 runner 執行。本地不裝任何工具鏈、不碰本地 Forgejo。**
- **Push target**: `codeberg.org/lawlietr/redlib` (lowercase namespace). Tags: `latest` + `<git-sha>` (multi-platform manifest lists), plus per-platform `amd64`/`arm64`. Login uses the `CODEBERG_PAT` repo secret (write:packages), username `Lawlietr` (the Codeberg account, not the local Forgejo owner).
- Disk guard (`.forgejo/scripts/disk_guard.sh`) + `docker image prune -a` after push keep the 30GB runner box clean
- Gotchas: `build_and_push.sh` sets `CXX_*`/`AR_*`/`CC_*`/`BINDGEN_EXTRA_CLANG_ARGS` for the arm target — without them boring-sys2's C++ source compiles with the host `g++` and the arm linker fails with "file in wrong format (EM: 62)"; bindgen needs glibc multiarch headers on Debian trixie. Details: `design/multi-arch-build.md`, `design/forgejo-runner-workflow.md`, `design/forgejo-runner-deployment.md`


### GitHub Actions Workflow (primary publish path — amd64 + arm64 → ghcr)

`.github/workflows/build.yml` is guarded with `if: ${{ github.server_url == 'https://github.com' }}` so it only runs when the repo is hosted on GitHub (it does — see Repository Remotes):
- **Trigger**: push to `main` touching `Dockerfile`, `redlib-prs.txt`, `.build/**`, `.github/**`; or `workflow_dispatch`. Runs are serialized by `concurrency: ghcr-publish` so the manifest merge can never pair an old `:amd64` with a new `:arm64`.
- **Compile**: a 2-entry matrix — amd64 on `ubuntu-latest`, arm64 on `ubuntu-24.04-arm` (standard GitHub-hosted arm64 runner, free for public repositories since 2025-08-07). Each job runs `docker build -f Dockerfile` natively on its own architecture (no QEMU, no cross toolchain) → same source tree as the local build (main + `redlib-prs.txt`)
- **Registry**: `.github/scripts/build_and_push.sh` pushes `ghcr.io/{owner}/redlib:amd64` and `:arm64`; then `.github/scripts/merge_manifest.sh` merges them into `:latest` and `:<git-sha>` manifest lists with `docker buildx imagetools create` (login uses `GITHUB_TOKEN`; the short sha is derived exactly like the `.forgejo/` script so both registries carry the same tag strings)
- **Binaries differ from the `.forgejo/` path on purpose**: ghcr publishes glibc + `+crt-static` binaries, Codeberg publishes musl-static ones. Same `scratch` runtime, different files — never compare digests across registries.
- Fork note: the namespace comes from `GITHUB_REPOSITORY_OWNER` (lowercased), so a fork pushes to its own ghcr namespace with zero edits and no secrets; package visibility inherits the repo's. Details: `design/github-actions-workflow.md` §3-§5, and the fork section in `README.md`/`README_EN.md`.

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
  - Current Tier 1: #549 (CMAF + rich:video), #542 (0-comment panic), #521 (default post sort), #560 (`/u/:name/s/:id` share links — **known broken, upstream's id-length guard rejects current 7-char post ids; deliberately deferred, do not claim this works**, see `design/upstream-pr-bake.md` §8.9), #539 (lazy-load images), #592 (thread pages: percent-encode the single `/comments` slash — **a workaround for Reddit's anonymous-thread block, not a real fix**; see `design/upstream-pr-bake.md` §8.8).
  - ⚠ The 2026-09-18 note claiming those PRs were "merged into upstream main (up to `8167e00`)" was **wrong**: `8167e00` was our own in-build merge tip, not an upstream commit. Upstream `main` (HEAD `a4d36e9`, 2026-04-24) contains none of them — re-verified 2026-10-07 with `git cherry` + content grep.
  - #509 (hyper-tls) stays out: superseded by main's wreq migration.
- Build: `cargo build --release --locked --bin redlib`

### Error Triage (runtime bug reports)
When a user reports a broken page or a runtime error message, follow `design/error-triage-playbook.md` instead of reasoning from the message alone. Key rules learned from the 2026-10-21 thread-page incident:
- redlib's error strings are symptoms (a parse error usually means Reddit returned non-JSON, e.g. a 403 block page) — locate the failing upstream call site first.
- "restart the container / rotate the token" is not a diagnosis: Reddit's block can be a **path rule** (same token, same IP: listings 200, thread route 403).
- An upstream PR's claimed mechanism must be reproduced in **our** environment. The accepted proof is two images (with / without the candidate PR) built from the same list, run side by side, with the control image reproducing the exact reported message. Bare `curl` probing is unreliable because without a correctly-minted token both the plain and the encoded URL return the same block page (false negative).
- Classify every accepted fix as **root fix** or **workaround** and record its re-break trigger plus the observable message to grep next time.

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

- **Commit messages: English** (conventional-commit-style subject, e.g. `fix(build): …`; body in English).
  Repo docs stay bilingual: `README.md` zh-TW, `README_EN.md` English, `RELEASE_NOTES.md` English, `design/*.md` zh-TW.
- Shell: `set -euo pipefail`, quote variables, `&&` chaining, `printf` over `echo`
- Git: `--depth 1`, verify upstream compiles on branch bump
- CI scripts: `trap 'docker image prune -a -f' EXIT` for cleanup

## External References

- Redlib: https://github.com/redlib-org/redlib
- Rust Docker: https://hub.docker.com/_/rust
- Debian Docker: https://hub.docker.com/_/debian
