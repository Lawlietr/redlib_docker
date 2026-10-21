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
> | This repo (Docker config, CI, docs) | **https://codeberg.org/Lawlietr/redlib_docker** |
> | Prebuilt container images | `codeberg.org/lawlietr/redlib` (multi-platform `linux/amd64` + `linux/arm64`; tags `latest` and a pinnable `<git-sha>`) |
> | GitHub mirror (also a build entry point for GitHub Actions) | https://github.com/Lawlietr/redlib_docker → image `ghcr.io/lawlietr/redlib` (**amd64 + arm64**, `latest` + `<git-sha>`; repo and package are public, so it pulls anonymously) |
>
> The two names differ on purpose: the repo is `Lawlietr/redlib_docker`, while the image path is
> lowercase `lawlietr/redlib` (the Codeberg registry requires lowercase).

- The build clones upstream `main` (https://github.com/redlib-org/redlib) and then bakes the upstream PRs that are **still not merged upstream**:
  the list lives in `redlib-prs.txt` (currently #549/#542/#521/#560/#539/#592 → CMAF video + `rich:video`,
  the 0-comment permalink panic, default post sort taking effect, user post share links
  (**#560's id-length condition is wrong, so they still do not work** — see `design/upstream-pr-bake.md` §8.9), lazy-loaded images,
  thread-page route encoding — **a workaround for Reddit's block, not a fix**, see `RELEASE_NOTES.md`),
  applied by `.build/apply_redlib_prs.sh`. Evidence, review tiers and the re-review procedure: `design/upstream-pr-bake.md`.
  (#509 hyper-tls is superseded by the wreq migration on `main` (#544) and is not baked.)
- The artifact is a fully static binary; the final image is based on `scratch` (~13.5MB).
- CI automatically builds and pushes prebuilt images to **`codeberg.org/lawlietr/redlib`**,
  supporting both **`linux/amd64`** and **`linux/arm64`** platforms.

## Deployment

### 1. Docker (pull the prebuilt image, recommended)

```bash
# If the image is private, log in first: docker login codeberg.org
docker pull codeberg.org/lawlietr/redlib:latest

docker run -d \
  --name redlib \
  -p 8080:8080 \
  --restart unless-stopped \
  codeberg.org/lawlietr/redlib:latest
```

After startup it is accessible at `http://localhost:8080`.

### 2. Docker Compose

```yaml
# docker-compose.yml
services:
  redlib:
    image: codeberg.org/lawlietr/redlib:latest
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
> # A) run the CI-built image (recommended; equivalent to the `image:` snippet above)
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

| Registry | `latest` | `<git-sha>` | per-arch tags |
|---|---|---|---|
| `codeberg.org/lawlietr/redlib` (primary, musl static) | manifest list | manifest list | `amd64` / `arm64` |
| `ghcr.io/lawlietr/redlib` (mirror, glibc static) | manifest list | manifest list (since 2026-10-21) | `amd64` / `arm64` |

| Tag | Description |
|-----|-------------|
| `latest` | Latest build (rolling tag, multi-platform manifest list) |
| `<git-sha>` | Reproducible version pinned to a git commit SHA (multi-platform) |
| `amd64` / `arm64` | Single-architecture images, mainly used for the CI manifest merge; pulling `latest` or `<git-sha>` picks the right architecture automatically |

> ⚠ **The two registries do not share digests**: the `.forgejo/` pipeline publishes musl-static
> binaries while the GitHub pipeline publishes glibc + `+crt-static` ones (both run on `scratch` and
> behave the same, but they are not the same file). When switching registries compare tags, not digests.
> Since 2026-10-21 the repository and the ghcr package are public, so **no token is needed to pull**.

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

- Trigger: changes to `Dockerfile`, `Dockerfile.pack`, `redlib-prs.txt`, `.build/**`, `.forgejo/scripts/build_and_push.sh`, or a manual "Run workflow".
- Execution: a locally self-hosted Forgejo Runner (`redlib` label) cross-compiles musl for amd64/arm64 natively (no QEMU), with BuildKit + cargo cache mount (incremental builds).
- Push target: `codeberg.org/lawlietr/redlib`. Each build produces two multi-platform
  manifest lists — `latest` (rolling) and `<git-sha>` (reproducible pin) — both containing
  `linux/amd64` and `linux/arm64`.
- GitHub Actions (`.github/workflows/build.yml`): a matrix of two build jobs plus one manifest job.
  amd64 runs on `ubuntu-latest`, arm64 on `ubuntu-24.04-arm` (a standard arm64 hosted runner, free for
  public repositories), both compiling **this same `Dockerfile`** and the same PR bake natively; each
  pushes `:amd64` / `:arm64`, then `.github/scripts/merge_manifest.sh` merges them with
  `docker buildx imagetools create` into `ghcr.io/lawlietr/redlib:{latest,<git-sha>}` (multi-platform
  manifest lists). Details: `design/github-actions-workflow.md`.
- Details and troubleshooting: `design/forgejo-runner-workflow.md`, `design/forgejo-runner-deployment.md`, `design/multi-arch-build.md`.

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
