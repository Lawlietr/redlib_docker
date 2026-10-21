| 🇬🇧 | English |
| 🇹🇼 | [繁體中文](README.md) |

# Redlib Docker

A lightweight Reddit alternative, deployed via Docker.

> ## What this repo actually does: **merge and package**, not a fork
>
> There is **no redlib source code here**, and this is not a branch or a fork of upstream. The build
> clones upstream `main` and then merges the PRs that **upstream itself received but has not merged**;
> the result is packaged into a Docker image. Every functional change comes from upstream and its PRs —
> this repo only **merges (bakes) and packages**, plus CI, Docker configuration and documentation.
> That is why you will not find redlib's `src/` here; to read the source or report bugs go to upstream:
> https://github.com/redlib-org/redlib
>
> **Where things live**
>
> | Item | Location |
> |------|----------|
> | This repo (Docker config, CI, docs) | **https://codeberg.org/Lawlietr/redlib_docker** (mirrored at https://github.com/Lawlietr/redlib_docker) |
> | **Prebuilt container images (primary, since 2026-10-21)** | **`ghcr.io/lawlietr/redlib`** — built automatically by **GitHub Actions**, dual-arch `linux/amd64` + `linux/arm64`; tags `latest` and a pinnable `<git-sha>`; public, **pulls anonymously** |
> | Mirrored images | `codeberg.org/lawlietr/redlib` — **mirrored by GitHub Actions with a registry-side copy** (no rebuild), so tags **and digests match ghcr**; musl-static builds only appear when you run `.forgejo/workflows/build.yml` by hand (which temporarily overwrites those tags until the next mirror) |
>
> The two names differ on purpose: the repo is `Lawlietr/redlib_docker`, while image paths are
> lowercase (`lawlietr/redlib`) — required by the ghcr registry, and the Codeberg namespace is lowercase too.

- The build clones upstream `main` (https://github.com/redlib-org/redlib) and then bakes the upstream PRs that are **still not merged upstream**:
  the list lives in `redlib-prs.txt` (currently #549/#542/#521/#560/#539/#592 → CMAF video + `rich:video`,
  the 0-comment permalink panic, default post sort taking effect, user post share links
  (**#560's id-length condition is wrong, so they still do not work** — see `design/upstream-pr-bake.md` §8.9), lazy-loaded images,
  thread-page route encoding — **a workaround for Reddit's block, not a fix**, see `RELEASE_NOTES.md`),
  applied by `.build/apply_redlib_prs.sh`. Evidence, review tiers and the re-review procedure: `design/upstream-pr-bake.md`.
  (#509 hyper-tls is superseded by the wreq migration on `main` (#544) and is not baked.)
- The artifact is a fully static binary; the final image is based on `scratch` (~13.5MB).
- **From 2026-10-21 all images are compiled by GitHub Actions and pushed to the primary registry
  `ghcr.io/lawlietr/redlib`** (dual-platform `linux/amd64` + `linux/arm64`). The local Forgejo runner
  pipeline is **kept but no longer triggers on push** (manual-only fallback and the musl-static producer), while the
  **Codeberg registry is kept current by a mirror job in the same CI run** (registry-side copy; tags and digests match);
  local `docker build` is supported as well, for testing changes and offline debugging.

## Deployment

### 1. Docker (pull the prebuilt image, recommended)

```bash
# Primary registry (ghcr is public: no docker login needed)
docker pull ghcr.io/lawlietr/redlib:latest

docker run -d \
  --name redlib \
  -p 8080:8080 \
  --restart unless-stopped \
  ghcr.io/lawlietr/redlib:latest

# Pin a build with the <git-sha> tag instead:
#   docker pull ghcr.io/lawlietr/redlib:d572b2e
# Same images are mirrored into the Codeberg registry (identical tags and digests):
#   docker pull codeberg.org/lawlietr/redlib:latest
```

After startup it is accessible at `http://localhost:8080`.

### 2. Docker Compose

```yaml
# docker-compose.yml
services:
  redlib:
    image: ghcr.io/lawlietr/redlib:latest
    container_name: redlib
    ports:
      - "8080:8080"
    environment:
      - PORT=8080
      # Optional (see .env.example for full list):
      #   - REDLIB_DEFAULT_THEME=dark
      #   - REDLIB_DEFAULT_FRONT_PAGE=popular
      #   - REDLIB_DEFAULT_LAYOUT=compact
      #   - REDLIB_DEFAULT_POST_SORT=hot
      #   - REDLIB_DEFAULT_SHOW_NSFW=on
      #   - REDLIB_BANNER=Welcome to my Redlib instance
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: "1"
          memory: 256M
        reservations:
          cpus: "0.25"
          memory: 64M
```

```bash
docker compose up -d
```

> The `docker-compose.yaml` in this repo supports both image sources (same service, switched with `REDLIB_IMAGE`):
>
> ```bash
> # A) run the CI-built image (primary path: GitHub Actions -> ghcr)
> REDLIB_IMAGE=ghcr.io/lawlietr/redlib:latest docker compose up -d --pull always --no-build
>
> # A2) Codeberg registry (mirrored by the same CI run; identical tags and digests)
> REDLIB_IMAGE=codeberg.org/lawlietr/redlib:latest docker compose up -d --pull always --no-build
>
> # B) build locally from source (this repo as the context for the root `Dockerfile`, bake included)
> docker compose up -d --build
> ```
>
> ⚠ While a service has a `build:` key, **a plain `docker compose up -d` always uses the locally built
> image and never pulls the registry one**; `latest` is a rolling tag, so moving to a new build always
> requires re-pulling and recreating the container.

### 3. Build from source (manual build)

```bash
docker build -t redlib .
docker run -p 8080:8080 -d --name redlib redlib

# Specify the Redlib branch (defaults to main)
docker build --build-arg REDLIB_BRANCH=main -t redlib .
# Specify the upstream git source
docker build --build-arg REDLIB_SRC=https://github.com/redlib-org/redlib.git -t redlib .
```

> **Bake note**: the build automatically merges the PRs listed in `redlib-prs.txt` into the cloned
> source (`.build/apply_redlib_prs.sh`, plain `--no-ff` merges). If upstream or a PR drifts, the log shows
> `warning: PR #<n> head moved` (informational) or the merge conflicts and the build fails outright —
> deliberately, so upstream changes are never silently dropped. Procedure: `design/upstream-pr-bake.md` §5.
>
> **Reproducibility note**: the Dockerfile clones the state of upstream `main` **at build time**, and PR
> heads can be force-pushed. Our pushed `latest` is a snapshot of one point in time; building yourself
> yields "the same build process + that day's redlib version", not a bit-for-bit identical image.
> To pin a fixed version, pull the registry's **`<git-sha>` tag**, or use
> `--build-arg REDLIB_BRANCH=<commit or tag>`.

## Environment Variables

See `.env.example` for the full list. Common variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | 8080 | Server port |
| `REDLIB_DEFAULT_THEME` | system | Default theme (system/light/dark/black/dracula/nord/laserwave/violet/gold/rosebox/gruvboxdark/gruvboxlight) |
| `REDLIB_DEFAULT_FRONT_PAGE` | default | Default front page (default/popular/all) |
| `REDLIB_DEFAULT_LAYOUT` | card | Default layout (card/clean/compact) |
| `REDLIB_DEFAULT_POST_SORT` | hot | Default post sort (hot/new/top/rising/controversial) |
| `REDLIB_DEFAULT_COMMENT_SORT` | confidence | Default comment sort (confidence/top/new/controversial/old) |
| `REDLIB_DEFAULT_SHOW_NSFW` | off | Default NSFW visibility |
| `REDLIB_DEFAULT_FILTERS` | (empty) | Default subreddit filters (format: sub1+sub2+sub3) |
| `REDLIB_DEFAULT_SUBSCRIPTIONS` | (empty) | Default subreddit subscriptions (format: sub1+sub2+sub3) |
| `REDLIB_BANNER` | (empty) | Instance banner message |
| `REDLIB_SFW_ONLY` | off | SFW-only mode |
| `REDLIB_ROBOTS_DISABLE_INDEXING` | off | Disable search engine indexing |

Full list: https://github.com/redlib-org/redlib/blob/main/.env.example

## Image Tags

**Both registries are now dual-architecture** (`linux/amd64` + `linux/arm64`) and use the **same tag scheme**:

| Registry | Role | `latest` | `<git-sha>` | per-arch tags |
|---|---|---|---|---|
| `ghcr.io/lawlietr/redlib` | **primary** (GitHub Actions, runs on push; glibc-static builds) | manifest list | manifest list | `amd64` / `arm64` |
| `codeberg.org/lawlietr/redlib` | **mirror** (the CI copies it with `imagetools`, registry-side; content and digests match ghcr) | manifest list | manifest list | `amd64` / `arm64` |

| Tag | Description |
|-----|-------------|
| `latest` | Latest build (rolling tag, multi-platform manifest list) |
| `<git-sha>` | Reproducible version pinned to a git commit SHA (multi-platform) |
| `amd64` / `arm64` | Single-architecture images, mainly used for the CI manifest merge; pulling `latest` or `<git-sha>` picks the right architecture automatically |

> ⚠ The Codeberg tags are now a **mirror** of the GitHub build, so **the same tag has the same digest in both
> registries** and a digest pin works across them. **Exception**: a manual `.forgejo/workflows/build.yml` run
> repoints those tags at musl-static builds (different digests) until the next CI build re-mirrors them.
> Both registries are public, so **no token is needed to pull**.

## Can a fork build its own images easily?

Yes — that is the point of keeping this repo to *merge and package* (no redlib sources): a fork gets
its own images without editing a single file.

| Item | Behaviour on a fork |
|------|---------------------|
| Local build | `docker build -t redlib .` works out of the box, **no secrets required** (the `Dockerfile` only fetches the public upstream and `pull/<n>/head`); produces the **host architecture** only |
| GitHub Actions | the guard is `github.server_url == 'https://github.com'`, which is true on your own GitHub fork → pushing to your own `main` runs the amd64 job, the arm64 job and the manifest job |
| Push target | **`ghcr.io/<your own owner, lowercased>/redlib`** — the namespace comes from `$GITHUB_REPOSITORY_OWNER`, so **no script edit is needed**, and nothing of ours is touched |
| Secrets to configure | **none**. Only `${{ secrets.GITHUB_TOKEN }}` (provided automatically); `permissions: contents/packages: write` is declared in the workflow (the package is created on first push) |
| Path that will not run | `.forgejo/**` (needs our self-hosted runner plus the `CODEBERG_PAT` secret; that workflow is also not interpreted on GitHub) |
| Changing the PR bake | edit `redlib-prs.txt` only (one line per PR: `<PR number> <reviewed head SHA> # note`). A merge conflict caused by upstream drift **fails the build loudly** instead of silently dropping changes (`design/upstream-pr-bake.md` §5) |

**Four things a fork should know**:

1. Actions are **disabled by default on forks** — enable them once from the Actions tab, otherwise pushes do not run.
2. Triggers: changes to `Dockerfile`, `redlib-prs.txt`, `.build/**` or `.github/**` (or a manual dispatch); documentation-only changes do not rebuild the image.
3. **Opening a PR from a fork does not publish an image** (the workflow does not listen to `pull_request`); only pushes to your own `main` do.
4. The ghcr package **inherits the repository visibility**: a private fork gives you a private `ghcr.io/<fork owner>/redlib`, where anonymous pulls return `denied` — that looks like "the image does not exist" but is a visibility problem (symptom table in `design/github-actions-workflow.md` §3).

## Release notes → `RELEASE_NOTES.md`

The full changelog lives in **`RELEASE_NOTES.md`**. Highlights of the latest round (2026-10-21):

- Thread pages load again: upstream #592 is baked, percent-encoding the **single** slash between
  `/r/<sub>` and `comments` (`/r/<sub>%2fcomments/…`) so it no longer matches Reddit's
  path rule for anonymous clients; a blocked response now reports an explicit 403 message.
- ⚠ **This is a stopgap, not a fix.** Reddit's direction is to require a logged-in session for
  this data. If Reddit starts normalising `%2f`, thread pages **break again** — and the message
  will then read `Reddit blocked this request (403 Forbidden): …`, not a parse error.
  Restarting the container (rotating the OAuth token) does **not** help: the block is path-based.
- Out of scope for this round (upstream says so explicitly): #589 (front-page feed parse errors)
  and #567 (Anubis PoW blocking programmatic access).

## CI/CD

**Primary path (since 2026-10-21): GitHub Actions.**

- GitHub Actions (`.github/workflows/build.yml`): runs automatically on **push to `main` touching
  `Dockerfile`, `redlib-prs.txt`, `.build/**` or `.github/**`** (or a manual "Run workflow").
  A matrix of two build jobs plus one manifest job: amd64 on `ubuntu-latest`, arm64 on
  `ubuntu-24.04-arm` (a standard arm64 hosted runner, free for public repositories), both compiling
  **this same `Dockerfile`** and the same PR bake natively; each pushes `:amd64` / `:arm64`, then
  `.github/scripts/merge_manifest.sh` merges them with `docker buildx imagetools create` into
  `ghcr.io/lawlietr/redlib:{latest,<git-sha>}` (multi-platform manifest lists). A `concurrency` group
  serialises runs so the merge can never pair an old amd64 with a new arm64.
  Details: `design/github-actions-workflow.md`.
- **Kept, but no longer automatic: the local Forgejo runner** (`.forgejo/workflows/build.yml`, the
  `redlib` label on the 12 host). Since 2026-10-21 its `push` trigger is removed and only
  `workflow_dispatch` remains (with an optional reason input). Use it as a fallback when GitHub Actions
  is unavailable, as the only producer of musl-static binaries, or to resync the
  `codeberg.org/lawlietr/redlib` tags. The runner infrastructure and disk discipline (30GB host,
  `disk_guard.sh` + prune) are fully preserved: `design/forgejo-runner-workflow.md`,
  `design/forgejo-runner-deployment.md`, `design/multi-arch-build.md`.
- **`codeberg.org/lawlietr/redlib` is maintained by the same CI run**: after the manifest merge, the
  `mirror-codeberg` job copies `:latest`/`:<git-sha>`/`:amd64`/`:arm64` over with
  `docker buildx imagetools create` (verbatim, no rebuild, ~13MB), so tags and digests match.
  That job needs the `CODEBERG_PAT` GitHub secret (`write:packages`) and **fails loudly when it is missing**
  rather than skipping. Details: `design/github-actions-workflow.md` §9.
- ⚠ A **manual** Forgejo (musl) build repoints the Codeberg tags at its own binaries until the next GitHub
  build re-mirrors them.
- How to verify each step: `design/error-triage-playbook.md`; per-feature regression list:
  `design/upstream-pr-bake.md` §7.

## Local build and testing (recommended around any change)

CI is not the only entry point: building locally and running the container is an **explicitly
supported** workflow (and the only way to test a change before it reaches either registry):

```bash
# 1) build (produces the host architecture only; includes the redlib-prs.txt PR bake)
docker build -t redlib-local .
#    different upstream branch/commit: --build-arg REDLIB_BRANCH=<branch|tag|sha>

# 2) run it (listens on 8080; use another host port if that one is taken)
docker run -d --name redlib-local -p 8090:8080 redlib-local

# 3) four quick smoke checks (full checklist: design/upstream-pr-bake.md §7)
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8090/
curl -s -o /dev/null -w '%{http_code}\n' 'http://127.0.0.1:8090/r/SteamdeckGames/comments/1xautuo/horizon_forbidden_west_should_not_be_steam_deck/'
curl -s -o /dev/null -w '%{http_code}\n' 'http://127.0.0.1:8090/r/__definitely_no_such_sub__/comments/1xautuo/x/'   # negative control: expect 404/400, never 200
docker logs redlib-local 2>&1 | grep -ci panic   # expect 0
```

Worth knowing:
- **It builds the host architecture only.** On x86_64 you do not get arm64; this host also has no qemu
  binfmt, so `--platform linux/arm64` fails with `exec format error` — arm64 runtime verification needs
  real arm64 hardware (see `TODO.md`).
- **Do not judge a change by curling the Reddit API directly** — that gives false negatives. Compare two
  images of the same code with/without the candidate change, end to end; method in
  `design/error-triage-playbook.md`.
- A local build **publishes nothing**: it never touches either registry. Publishing only happens in CI
  (or through a manual `.forgejo/` run).

## Troubleshooting

- **Build failure**: Ensure the network connection is healthy (the build clones upstream and fetches Rust crates);
  boring-sys2 (BoringSSL) requires cmake + a C compiler + libclang, all preinstalled in the builder image.
- **Container fails to start**: Check whether port 8080 is in use; inspect the logs with `docker logs redlib`.
- **Still the old build after "updating"**: `latest` is a rolling tag, so a host that already pulled it must
  `docker pull` again and recreate the container; with this repo's compose file remember `--no-build`
  (mode A above), otherwise `up -d` uses the locally built image.

## Project Information

- Source: https://github.com/redlib-org/redlib
- Personal Docker implementation, not an official project
- License: the repo's own files (Dockerfile, scripts, config) are MIT; upstream redlib retains AGPL-3.0
