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
> | Mirrored images | `codeberg.org/lawlietr/redlib` — **mirrored by GitHub Actions with a registry-side copy** (no rebuild), so tags **and digests match ghcr**; the manual fallback path (`.forgejo/workflows/build.yml`) temporarily repoints those tags at its own binaries until the next CI run re-mirrors them |
>
> The two names differ on purpose: the repo is `Lawlietr/redlib_docker`, while image paths are
> lowercase (`lawlietr/redlib`) — required by the ghcr registry, and the Codeberg namespace is lowercase too.

- The build clones upstream `main` (https://github.com/redlib-org/redlib) and then bakes the upstream PRs that are **still not merged upstream**:
  the list lives in `redlib-prs.txt` (currently #549/#542/#521/#560/#539/#599 → CMAF video + `rich:video`,
  the 0-comment permalink panic, default post sort taking effect, user post share links
  (**#560's id-length condition is wrong, so they still do not work** — see `design/upstream-pr-bake.md` §8.9), lazy-loaded images,
  and comments rebuilt from Reddit's own frontend HTML fragments — **a workaround for Reddit's block on the
  comments API, not a fix, and not a complete one**; see the "Upstream status" note below and `RELEASE_NOTES.md`),
  applied by `.build/apply_redlib_prs.sh`. Evidence, review tiers and the re-review procedure: `design/upstream-pr-bake.md`.
  (#509 hyper-tls is superseded by the wreq migration on `main` (#544) and is not baked.)
- The artifact is a fully static binary; the final image is based on `scratch` (~13.5MB; ~14.8MB once #599's HTML parser dependencies are in).
- **From 2026-10-21 all images are compiled by GitHub Actions and pushed to the primary registry
  `ghcr.io/lawlietr/redlib`** (dual-platform `linux/amd64` + `linux/arm64`). The local Forgejo runner
  pipeline is **kept but no longer triggers on push** (manual-only emergency fallback), while the
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
>
> **Upstream status (v0.40.0, verified 2026-10-22 — five PRs then, six since 2026-10-23, see the note below)**:
> the five bake PRs in the list at that time were **still not merged upstream as PRs**, so all kept being baked. #592 (the thread-page 403 workaround)
> has an **equivalent direct commit** in upstream `main` (`0a3e9cd fix: encode anonymous comments request
> paths`, percent-encoding the slash between subreddit and `comments` as `%2F`). This repo does
> "merge-and-packaging", not a fork, and the criterion is "was the PR merged upstream"; #592 as a PR was
> never integrated, but upstream now supplies the same workaround, and keeping #592 would only conflict with
> `0a3e9cd` in `src/client.rs` for no gain — so **#592 has been retired from the bake list**. The remaining
> five (#549, #542, #521, #560, #539) are not in v0.40.0 at all and bake as normal. #592's thread-403
> workaround is now supplied by upstream — it remains a workaround, not a root fix, with the same
> re-break risk and observable (block / parse error in `client.rs`).
>
> **2026-10-27: upstream formally closed #592 (unmerged) — nothing to do here.** The maintainer closed it on
> 2026-10-21 (`mergeable=false`, 0 reviews) and its two commits are **still not** patch-equivalent in `main`
> (`git cherry -v` shows both as `+`), so our 2026-10-22 decision to retire it in favour of upstream's own
> equivalent commit remains correct. The same round also **confirmed upstream's `%2F` workaround is dead**:
> an image built from the same list with the shreddit PR **removed** returns no comments at all on both boxes
> and all four threads (404 + parse error) → **the shreddit PR is load-bearing** and must not be dropped just
> because it is a workaround.
>
> **Added bake on 2026-10-23: #599 (⚠ it does not fully solve the problem)**
>
> The `%2F` encoding workaround above **has since been defeated by Reddit**: our production instance started
> returning `Failed to parse page JSON data: expected value at line 1 column 1 | /r/<sub>/comments/<id>/<slug>/.json?&raw_json=1`
> again, while upstream `main` has **no commits after v0.40.0** (HEAD `ba116c1`) — i.e. upstream had not fixed it at all.
> So we bake upstream [#599](https://github.com/redlib-org/redlib/pull/599): it stops touching the comments API at all.
> The post is fetched from `/by_id/t3_<id>.json`, and **comments are taken from the HTML fragments Reddit's own frontend
> uses** (`/svc/shreddit/comments/...`), parsed back into the original JSON shape with `scraper`, so `parse_comments`
> and the templates need no changes.
>
> A local x86-64 build plus a running container passed (post page 200 with real comment bodies, permalink +
> `?context=3` works, comment sorting really takes effect, 0-comment posts do not panic, panic count 0).
> **But it only turns "the whole page is broken" into "works with losses" — these are the known costs:**
>
> 1. **Still a workaround, and more fragile than #592**: it relies on Reddit's **undocumented internal fragment
>    endpoint**; if Reddit switches it off, everything breaks again. The PR is **AI-generated, has 0 reviews, and
>    upstream CI has never run it** (head `26c02193`, 0 check runs; it was `0db637cd` when we first baked it on 2026-10-23).
> 2. **Fragile anti-throttling**: captcha detection matches the literal `<title>Reddit - Prove your humanity</title>`,
>    plus a 429 or `x-ratelimit-remaining < 20` rotates the cookie session. Change that string and the challenge page
>    gets parsed as if it were comment content.
> 3. **Request amplification**: every uncached post page costs **1–31** Reddit requests (measured locally:
>    **3.07s cold / 0.019s hot**, listings 0.74s) and the cache lasts only 30 seconds; the shreddit cookie session is
>    **process-global**, so every visitor of an instance shares one quota and they exhaust each other's budget
>    (upstream #597 / #446 already complain about rate limits). The message when this bites:
>    `Reddit is rate limiting comment requests. Try refreshing in a few seconds.`
> 4. **Comments are capped at 200**: the rest stay as "More replies" stubs (measured on big threads locally:
>    93–106 unexpanded stubs left).
> 5. **Comments lose author flair and awards** (those fields are not in the fragments); shreddit behaviour for
>    quarantined subreddits is untested.
> 6. **The subreddit name is no longer validated**: the post now comes from `by_id`, which ignores the subreddit →
>    a wrong subreddit plus a valid post id still returns 200 and renders a different post (measured locally:
>    `/r/__totally_wrong_sub__/comments/1xbt0if/x/` → 200 showing the r/masseffect post). Upstream `main` returns 404
>    for such a URL.
> 7. **Out of scope**: the front-page feed parse error (upstream #589) and Anubis PoW blocking programmatic access
>    (#567) are unchanged; and the whole mechanism still depends on `by_id/t3_<id>.json` not being blocked —
>    if that route gets blocked too, thread pages die completely again.
> 8. Size and supply chain: 25 new crates (`scraper`/`html5ever`/`cssparser`/`phf`…), image 13.5MB → 14.8MB.
>
> **Observables to grep when it breaks again** (see `design/error-triage-playbook.md`):
> `Reddit returned <status> | /svc/shreddit/...`, `Reddit is rate limiting comment requests...`,
> `Refusing to fetch non-shreddit path`, or the old parse-error string (meaning `by_id` is blocked as well).
> Tier and rationale: `design/upstream-pr-bake.md` §2, §8.12.
>
> **2026-10-27 evaluation: upstream #603 (comments via Reddit's Android persisted GraphQL) — decided NOT to bake.**
> It **replaces** the #599 path instead of complementing it (both edit the same comment-fetch line, so baking both
> always conflicts) — it is a binary choice, not an addition. Measured with three images from the same bake chain on
> two boxes: on a host whose egress Reddit accepts, #603 **works and is 2.7-4x faster** (same thread: 1.02s vs 2.42s;
> 1.13s vs 3.06s) and really breaks the 200-comment ceiling with a `cursor` link (next page 200 / 58,810 B / 0.36s);
> but on the instance whose egress IP Reddit blocks it still renders **0 comments**, it swaps one undocumented Reddit
> dependency (HTML fragments) for another (a GraphQL persisted-query hash), and comments per page drop 240 → 200.
> Trigger conditions and the full data: `design/upstream-pr-bake.md` §8.14.

> **Pin bump on 2026-10-27 (`0db637cd` → `26c02193`)**: #599 gained three commits after we first baked it —
> the `rdt` bot-check `302` is now followed instead of erroring out, comment GIFs/videos stop being an empty
> clickable box (they become a native `<video>`), and **the one that matters for our published images**:
> Reddit's edge started answering "more comments" POSTs that carry no `Origin`/`Referer` with a *blocked by
> network security* 403, and shreddit gives mobile-emulated clients 10 comments per fragment instead of 25.
> The new head sends the browser headers and gives shreddit its own desktop client. In other words: **the
> image we published with pin `0db637cd` is currently in the degraded state** (expansion blocked, ~10 comments
> per fragment). The new head touches only `src/client.rs` and `src/shreddit.rs`; **`Cargo.toml`/`Cargo.lock`
> are unchanged**, so the dependency set and the image size do not change. **Still unfixed:** comment images
> overflowing their container (reported upstream 2026-10-27, no commit after `26c02193`), the 200-comment cap,
> and the rest of §8.12.

> ⚠ **The SHA column in `redlib-prs.txt` is only a drift warning, not a version pin**: a build always takes the
> PR's **current** head (`refs/pull/<n>/head` can only ever be the head). To reproduce a past bake combination use
> `docker build --build-arg BAKE_ARGS=--at-listed-sha`; to get a reproducible artifact **pin the `<git-sha>` tag or
> the digest**. Details: the 2026-10-27 entry in `RELEASE_NOTES.md`, `design/upstream-pr-bake.md` §6.

> ⚠ **A pin bump will not fix an instance whose egress is a datacenter IP.** The very same image digest still
> returns 404 on thread pages on our Oracle Cloud box, with `Reddit returned 403 Forbidden |
> /svc/shreddit/comments/r/<sub>/t3_<id>` in the page, while a residential-line box serving the same digest works
> fine. That is **egress IP reputation, not code**. A Cloudflare CDN in front of the instance does not help either:
> the CDN only fronts the **inbound** direction, while redlib's request to Reddit leaves the box itself.
> Triage procedure: `design/error-triage-playbook.md` §4.2 and `design/upstream-pr-bake.md` §8.13.
> **A reverse proxy, ZeroTier or a VPN only sit on the *inbound* leg** and never change the egress IP Reddit
> sees: all three of our cloud hosts (o1/o2/o3, every one of them `AS31898` Oracle Tokyo) have more than enough
> resources for redlib (idle RSS about 43MB) yet every thread page there returns
> `Reddit returned 403 Forbidden | /svc/shreddit/...`, while the instance inside our LAN (Ubox-02 / "123") works
> and the front door on o3 merely forwards the request into the ZeroTier network. Topology and measurements:
> `design/reverse-proxy-front.md`.

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
> repoints those tags at its own binaries (different digests) until the next CI build re-mirrors them.
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

The full changelog lives in **`RELEASE_NOTES.md`**. Highlights of the last rounds:

- **2026-10-27 — #599 pin moved to `26c02193`**: comment expansion stops being blocked ("more comments" POSTs now
  carry `Origin`/`Referer`/`Sec-Fetch-*`) and shreddit now uses a desktop client (10 → 25 comments per fragment);
  the `rdt` bot-check redirect is followed and comment media becomes a native `<video>`. Also documented: **the pin
  column never froze the code** (it is a drift warning; `--at-listed-sha` was added for real reproduction), and
  the **egress-IP failure mode** that no code change can fix.

- **2026-10-23 — #599 baked, comments are back on thread pages**: comments no longer come from the comments API but
  from Reddit's frontend `/svc/shreddit/comments/...` HTML fragments. ⚠ **Incomplete and not a root fix**: comments are
  capped at 200, author flair and awards are missing, every uncached thread page costs 1–31 requests (3s cold),
  one shreddit cookie session is shared by all visitors of an instance, the subreddit name is no longer validated,
  and it targets an undocumented internal endpoint — point by point: the "Upstream status" note above and `RELEASE_NOTES.md`.
- **2026-10-22 — #592 retired**: upstream v0.40.0 supplies the equivalent `%2F` encoding workaround as a direct commit
  (`0a3e9cd`), so keeping #592 would only conflict.
- ⚠ **The 2026-10-21 `%2f` encoding workaround is dead**: Reddit now blocks the encoded path as well (observed: thread
  pages on the production instance were back to the parse error). Restarting the container (rotating the OAuth token)
  was never a solution — the block is path-based, not token-based.
- Out of scope (upstream says so explicitly): #589 (front-page feed parse errors) and #567 (Anubis PoW blocking
  programmatic access).

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
  is unavailable (or when you deliberately want to rebuild inside your own network). It produces
  musl-cross-compiled binaries, which is only an **implementation detail of that path** (musl is the
  cheapest way to cross-compile arm64 on an x86 box), **not a promised binary format**: the product is
  the glibc-static build on ghcr, which Codeberg receives by mirroring. The runner infrastructure and disk discipline (30GB host,
  `disk_guard.sh` + prune) are fully preserved: `design/forgejo-runner-workflow.md`,
  `design/forgejo-runner-deployment.md`, `design/multi-arch-build.md`.
- **`codeberg.org/lawlietr/redlib` is maintained by the same CI run**: after the manifest merge, the
  `mirror-codeberg` job copies `:latest`/`:<git-sha>`/`:amd64`/`:arm64` over with
  `docker buildx imagetools create` (verbatim, no rebuild, ~13MB), so tags and digests match.
  That job needs the `CODEBERG_PAT` GitHub secret (`write:packages`) and **fails loudly when it is missing**
  rather than skipping. Details: `design/github-actions-workflow.md` §9.
- **A `smoke` job gates the publish** (`needs: manifest`): it starts the freshly pushed `:amd64` image on a clean
  runner and hits `/`, `/r/gaming` and `/r/AskReddit/top`, first requiring the shipped binaries to be fully static and
  arch-correct, then checking status codes and body sizes and grepping the log for resolver errors. It targets the two failure classes that used to surface only on a live instance: a static binary
  that cannot resolve DNS inside `scratch`, and a baked upstream PR that breaks at runtime. `mirror-codeberg` has
  `needs: smoke`, so a failing image is never mirrored. Details: `design/github-actions-workflow.md` §10.
- ⚠ A **manual** Forgejo fallback build repoints the Codeberg tags at its own binaries until the next GitHub
  build re-mirrors them.
- How to verify each step: `design/error-triage-playbook.md`; per-feature regression list:
  `design/upstream-pr-bake.md` §7.

## Local build and testing (recommended around any change)

CI is not the only entry point: building locally and running the container is an **explicitly
supported** workflow (run it around any change; the CI `smoke` job applies the same class of checks to
the published image):

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
- **Thread pages broken again / comments come up empty / a rate-limit message appears**: work out which layer failed —
  `Reddit returned <status> | /svc/shreddit/...` (the fragment endpoint #599 uses is blocked),
  `Reddit is rate limiting comment requests. Try refreshing in a few seconds.` (the shared cookie session's quota is
  used up), or the old `Failed to parse page JSON data...` (even `by_id` is blocked now).
  Root-cause SOP: `design/error-triage-playbook.md`.
- **Same image, works on box A but every thread page fails on box B**: first compare `docker images --digests` to
  confirm both run the **same manifest digest**; then probe `/svc/shreddit/comments/r/<sub>/t3_<id>` from both hosts
  with **browser-grade headers**: residential IP → 200, hosting ASN (Oracle/Hetzner/Vultr/AWS…) → 403 means the
  **egress IP is blocked by Reddit**. Rebuilding, changing env vars or restarting the container changes nothing, and
  a Cloudflare CDN does not rescue it either (it only fronts inbound traffic).
  Procedure: `design/error-triage-playbook.md` §4.2.
- **Build merge conflict / `warning: PR #<n> head moved`**: upstream or the PR drifted — re-review `redlib-prs.txt`
  per `design/upstream-pr-bake.md` §5. Note the default behaviour is **only a warning**: the build still merges the
  PR's current head (the SHA column is not a version lock). To really reproduce a historical combination:
  `docker build --build-arg BAKE_ARGS=--at-listed-sha`.

## Project Information

- Source: https://github.com/redlib-org/redlib
- Personal Docker implementation, not an official project
- License: the repo's own files (Dockerfile, scripts, config) are MIT; upstream redlib retains AGPL-3.0
