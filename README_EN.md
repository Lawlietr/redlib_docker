| 🇬🇧 | English |
| 🇹🇼 | [繁體中文](README.md) |

# Redlib Docker

A lightweight Reddit alternative, deployed via Docker.

- The build clones upstream `main` (https://github.com/redlib-org/redlib) and then bakes the upstream PRs that are **still not merged upstream**:
  the list lives in `redlib-prs.txt` (currently #549/#542/#521/#560/#539 → CMAF video + `rich:video`,
  the 0-comment permalink panic, default post sort taking effect, user post share links, lazy-loaded images),
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

All tags are multi-platform manifest lists (`linux/amd64` + `linux/arm64`):

| Tag | Description |
|-----|-------------|
| `latest` | Latest build (rolling tag) |
| `<git-sha>` | Reproducible version pinned to a git commit SHA |

> **Note**: `amd64` and `arm64` tags also exist in the registry but are used
> internally for CI manifest merging. Users should pull `latest` or `<git-sha>`.
>
> A mirror built by GitHub Actions also exists: `ghcr.io/lawlietr/redlib:latest`
> (**amd64 only**; the repo is private, so the package is private and pulling needs a `read:packages` token).

## CI/CD

- Trigger: changes to `Dockerfile`, `Dockerfile.pack`, `redlib-prs.txt`, `.build/**`, `.forgejo/scripts/build_and_push.sh`, or a manual "Run workflow".
- Execution: a locally self-hosted Forgejo Runner (`redlib` label) cross-compiles musl for amd64/arm64 natively (no QEMU), with BuildKit + cargo cache mount (incremental builds).
- Push target: `codeberg.org/lawlietr/redlib`. Each build produces two multi-platform
  manifest lists — `latest` (rolling) and `<git-sha>` (reproducible pin) — both containing
  `linux/amd64` and `linux/arm64`.
- GitHub Actions (`.github/workflows/build.yml`): builds the **same** `Dockerfile` and the same PR bake on `ubuntu-latest` (amd64) → `ghcr.io/lawlietr/redlib:latest`. Details: `design/github-actions-workflow.md`.
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
