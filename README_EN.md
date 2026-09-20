[中文](README.md)

# Redlib Docker

A lightweight Reddit alternative, deployed via Docker.

- The build clones upstream `main` (https://github.com/redlib-org/redlib) directly;
  the previously hand-baked PRs (#506/#509/#521/#560/#539/#549) no longer need baking:
  #506/#521/#560/#539/#549 have been merged into upstream `main`, while #509 (hyper-tls)
  was superseded by the wreq migration on `main` (#544, which emulates common TLS fingerprints).
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

> If you'd rather build locally from source (without waiting for CI), just use the
> `docker-compose.yaml` in the repo root: `docker compose up -d --build`
> (builds the root `Dockerfile` with this repo as the context).

### 3. Build from source (manual build)

```bash
docker build -t redlib .
docker run -p 8080:8080 -d --name redlib redlib

# Specify the Redlib branch (defaults to main)
docker build --build-arg REDLIB_BRANCH=main -t redlib .
# Specify the upstream git source
docker build --build-arg REDLIB_SRC=https://github.com/redlib-org/redlib.git -t redlib .
```

> **Reproducibility note**: The Dockerfile clones the state of upstream `main`
> **at build time**. Our pushed `latest` is built from a specific version of upstream `main`;
> building yourself yields "the same build process + that day's redlib version",
> but is not guaranteed to be bit-for-bit identical to our image. To pin a fixed version,
> use `--build-arg REDLIB_BRANCH=<commit or tag>`.

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

## CI/CD

- Trigger: changes to `Dockerfile` or a manual "Run workflow".
- Execution environment: a locally self-hosted Forgejo Runner (`redlib` label) with BuildKit + cargo cache mount (incremental builds).
- Push target: `codeberg.org/lawlietr/redlib`. Each build produces two multi-platform
  manifest lists — `latest` (rolling) and `<git-sha>` (reproducible pin) — both containing
  `linux/amd64` and `linux/arm64`.
- Details and troubleshooting: `design/forgejo-runner-workflow.md`, `design/forgejo-runner-deployment.md`.

## Troubleshooting

- **Build failure**: Ensure the network connection is healthy (the build clones upstream and fetches Rust crates);
  boring-sys2 (BoringSSL) requires cmake + a C compiler + libclang, all preinstalled in the builder image.
- **Container fails to start**: Check whether port 8080 is in use; inspect the logs with `docker logs redlib`.

## Project Information

- Source: https://github.com/redlib-org/redlib
- Personal Docker implementation, not an official project
- License: the repo's own files (Dockerfile, scripts, config) are MIT; upstream redlib retains AGPL-3.0
