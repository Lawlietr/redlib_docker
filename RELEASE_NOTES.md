# Release Notes

English only (this file is the image changelog consumers read; the design docs in
`design/` carry the reproduction detail).

---

## 2026-10-27 — #599 pin moved to `26c02193`; and an honest note about what the pin is worth

**What changed.** Only the `599` line in `redlib-prs.txt`: the pinned upstream head moved from
`0db637cd` to `26c02193`. #599 gained three commits since we first baked it, all of them about the
comments crawler being punished by Reddit's edge:

| Commit | What it fixes |
|---|---|
| `1d55e3e` | Reddit's `rdt` bot-check answers some clients with a `302` to the same shreddit path; that used to surface as `Reddit returned 302 Found`. Now followed up to 3 times, restricted to `/svc/shreddit/` on www.reddit.com. The expansion crawler also switched from a batch barrier to a `JoinSet`, so one slow "more comments" request no longer stalls its batch. |
| `a12eaf6` | Comment media was wrapped in Reddit's `<shreddit-player>` element, which only renders through Reddit's JavaScript → an empty clickable box. It now becomes a native `<video>` of the same proxied MP4 (`/preview/external-pre/…?format=mp4`); GIFs autoplay, loop and stay muted. |
| `26c0219` | **The one that matters for our published images.** Reddit's edge started answering "more comments" POSTs that carry no `Origin`/`Referer` with its *blocked by network security* 403, and shreddit serves mobile-emulated clients 10 comments per fragment instead of 25. Shreddit requests now send the browser headers and use their own desktop-platform client (the OAuth API client keeps its emulation). Upstream's own measurement: a 7.5k-comment post went from ~10 visible comments to ~285, and "More replies" started working. |

Nothing else in the bake list moved. The new head touches only `src/client.rs` and `src/shreddit.rs`
(**`Cargo.toml`/`Cargo.lock` unchanged** → same dependency set, same image size), and merging it under
the other five PRs is still a clean six-way `--no-ff`. Four new unit tests ship with it.

**Still broken after this bump (do not claim otherwise):** comment images overflowing their container
(reported upstream 2026-10-27, no commit after `26c0219` addresses it), the 200-comment crawl cap,
no author flair/awards on comments, 1–31 upstream requests per uncached thread page, and the
instance-wide shared shreddit cookie session. Full list: the 2026-10-23 entry below.

**A caveat about the pin column.** Building revealed that the SHA in `redlib-prs.txt` was only ever a
*drift warning*: `apply_redlib_prs.sh` fetches `refs/pull/<n>/head`, which can only ever be the PR's
current head, so an "A/B against the old pin" silently builds the new head — the only clue is the
`warning: PR #599 head moved` line in the build log. Consequence for you: **`<git-sha>` tags are the
reliable way to get an identical build; the pin column does not freeze the code.** `.build/apply_redlib_prs.sh`
now has an explicit `--at-listed-sha` mode (exposed as `--build-arg BAKE_ARGS=--at-listed-sha`) that
really builds at the listed SHA, for reproducing a past bake combination.

**Not a fix for instances on datacenter IPs.** An instance whose egress IP is a hosting ASN (we hit this
on an Oracle Cloud box, `<o3 公網 IP>`, AS31898) gets `Reddit returned 403 Forbidden | /svc/shreddit/comments/...`
on every thread page from the very first fragment, while the *same image digest* works from a residential
line. That failure mode is egress IP reputation, not code, and a pin bump cannot repair it; a Cloudflare
CDN in front of the instance does not help either, because the request to Reddit leaves the box itself.
Symptom mapping and the two-box probe procedure: `design/error-triage-playbook.md` §4.2.

**The shreddit path is load-bearing — measured, not inferred.** Upstream formally closed the older
percent-encoding PR (the one this repo already retired on 2026-10-22) **unmerged** on 2026-10-21, which needs
no action here: its commits are still not patch-equivalent in `main` (`git cherry -v` shows them as `+`), and
upstream supplies the equivalent trick as its own commit. The same check also settled an open question: an image
built from the identical bake list with the shreddit PR **removed** returns no comments at all — 404 plus a parse
error on every thread, on both of our instances. So upstream's `%2F` workaround is dead in our environment too,
and **the shreddit PR must not be dropped just because it is a workaround**.

**Upstream #603 (GraphQL comment fetch) was evaluated and deliberately not baked** — no image content change.
It replaces the shreddit path rather than adding to it (both edit the same fetch line; merging both conflicts in
either order), it still renders 0 comments on the instance whose egress IP Reddit blocks, and it swaps one
undocumented Reddit dependency for another (an Android persisted-query hash, `gql-fed.reddit.com`). Measured
upsides, for the record: on a host with a working egress it renders correctly, is 2.7-4x faster per thread page,
and really paginates past the 200-comment ceiling via a `cursor` link. Re-evaluation triggers:
`design/upstream-pr-bake.md` §8.14.

---

## 2026-10-23 — thread pages work again via upstream PR #599 (**workaround, and not a complete one**)

**Symptom.** Thread pages were broken again on every instance:
`Failed to parse page JSON data: expected value at line 1 column 1 | /r/<sub>/comments/<id>/<slug>/.json?&raw_json=1`,
while `/`, `/r/popular` and subreddit listings kept returning 200. This is the same *class* of failure as the
2026-10-21 note below — Reddit's block is path-based — but this time it also defeats the **`%2F` encoding**
workaround that upstream v0.40.0 ships as the direct commit `0a3e9cd`. Upstream `main` had **no commits after
v0.40.0** (HEAD `ba116c1`), i.e. upstream had not fixed it at all at the time of writing.

**What changed.** `redlib-prs.txt` now bakes six open upstream PRs: the previous five
(#549, #542, #521, #560, #539) plus [#599](https://github.com/redlib-org/redlib/pull/599)
(head pinned to `0db637cd`). #599 does not patch the blocked API call — it stops using it:

1. the post itself is fetched from `/by_id/t3_<id>.json` (still JSON, still unblocked at the time of writing);
2. comments are rebuilt from the **HTML fragments Reddit's own web frontend uses**
   (`/svc/shreddit/comments/r/<sub>/t3_<id>[/t1_<comment>]`), parsed with `scraper` back into the JSON shape
   `parse_comments`/`query_comments` already expect, so the templates are unchanged;
3. "More replies" placeholders are expanded breadth-first through `/svc/shreddit/more-comments/...` POSTs
   carrying a hidden `cursor`, bounded to 200 comments / 30 expansions / 10 requests in flight, cached for 30s;
4. because cookieless requests get a reCAPTCHA page after roughly 10 requests, these fragment requests share
   their own `wreq` cookie jar (`cookies` feature), rotated when `x-ratelimit-remaining < 20`, on a 429, or when
   a captcha page is detected, with a single retry.

Local x86-64 build and a running container passed the regression run: the reported post
(`/r/masseffect/comments/1xbt0if/its_over/`) returns 200 with **206 non-empty comment bodies**; comment
permalinks with `?context=3` work; `?sort=confidence|new|top` really produce different comment sets; a
0-comment post does not panic; panic count 0; listings and `/r/popular` unaffected.

**⚠ It does not fully solve the problem.** It converts "the page is dead" into "the page works with losses":

| Loss / risk | Detail (measured locally unless stated) |
|---|---|
| Still a workaround, **more fragile than #592** | It depends on Reddit's **undocumented internal fragment endpoint**; if Reddit turns it off or changes the markup, thread pages die again. |
| Brittle throttle handling | Captcha detection matches the literal page title `Reddit - Prove your humanity`. If that string changes, the challenge page is parsed as if it were comment content. |
| **Request amplification** | 1–31 Reddit requests per **uncached** thread page; measured **3.07s cold / 0.019s hot** (a listing is 0.74s for comparison). The cache lives only 30s. |
| One shared session per instance | The fragment cookie session is process-global, so all visitors of an instance share one quota and can exhaust it for each other. Upstream #597 / #446 already complain about rate limits. When this bites you see: `Reddit is rate limiting comment requests. Try refreshing in a few seconds.` |
| **200-comment cap** | Anything beyond 200 comments stays as unexpanded "More replies" stubs (93–106 stubs left on the big threads we tested). |
| Missing comment metadata | Author flair and awards are not present in the fragments, so comments render without them. `?context=` permalinks and nesting do work. |
| **The subreddit name is no longer validated** | The post now comes from `by_id`, which ignores the subreddit: a wrong subreddit plus a valid post id returns **200 and renders the other post** (`/r/__totally_wrong_sub__/comments/1xbt0if/x/` → the r/masseffect post). Upstream `main` returns 404 for such a URL. |
| Untested / out of scope | shreddit behaviour for quarantined subreddits is untested; the front-page feed parse error (#589) and Anubis PoW (#567) are untouched. |
| Still depends on `by_id` | If Reddit blocks `/by_id/t3_<id>.json` too, thread pages die completely again — and the old parse-error string is what you will see. |
| Size and supply chain | 25 new crates (`scraper`, `html5ever`, `cssparser`, `phf`, …); image 13.5MB → 14.8MB. |
| Trust surface | Comment `body_html` is now produced from the fragment's `inner_html()`. redlib renders `body_html` unescaped and has no sanitizer, so the trusted producer changes from "Reddit's API `body_html`" to "Reddit's frontend fragment". |
| Review status | The upstream PR is **AI-generated, has 0 reviews and 0 CI check runs** — upstream never compiled it. Our own build (`--locked`) compiles it, which is the only build evidence that exists. |

**How to tell which layer broke** (see `design/error-triage-playbook.md`):
`Reddit returned <status> | /svc/shreddit/...` (fragment endpoint blocked),
`Reddit is rate limiting comment requests. Try refreshing in a few seconds.` (shared quota exhausted), or the old
`Failed to parse page JSON data: expected value at line 1 column 1 …` (even `by_id` is blocked now).

**Rolling it back.** Delete the `599 …` line from `redlib-prs.txt` and rebuild (or run an older `<git-sha>`).
That restores upstream v0.40.0's behaviour, i.e. the broken thread pages, so only roll back if #599 misbehaves
worse than a dead page.

**Image.** Built by GitHub Actions into `ghcr.io/lawlietr/redlib` and mirrored verbatim into
`codeberg.org/lawlietr/redlib` (same tags, same digests). Tag carrying this change: `<git-sha>` of the commit that
adds the `599 …` line; `latest` is rolling.

---

## 2026-10-22 — retire redlib PR #592 from the bake (upstream ships the same thread-403 workaround)

**What changed.** The bake list (`redlib-prs.txt`) no longer bakes upstream
[redlib PR #592](https://github.com/redlib-org/redlib/pull/592). The remaining
baked PRs are the five: #549, #542, #521, #560, #539.

**Why #592 was retired.** #592 was a workaround for the thread-page 403 block
(described in the 2026-10-21 note below): it percent-encodes the single slash
joining the subreddit to `comments` so Reddit's edge stops matching the literal
`/r/<sub>/comments/...` path. On 2026-10-22 upstream released **v0.40.0**, which
carries an **equivalent direct commit** (`0a3e9cd fix: encode anonymous comments
request paths`) that percent-encodes the same slash. #592 as a PR was never
merged upstream, but keeping it in our bake would only conflict with `0a3e9cd`
in `src/client.rs` for no functional gain — both do exactly the same thing.
So #592 was removed from the list and the thread-403 workaround is now supplied
by upstream `0a3e9cd`.

**No behaviour change.** The thread pages #592 used to restore keep loading; the
mechanism is identical (a `%2f` encoding workaround, not a root fix). The same
caveats from the 2026-10-21 note still apply: it is a stopgap, the re-break
trigger is Reddit normalising `%2f` back to `/`, and the signal that it has died
is the explicit `Reddit blocked this request (403 Forbidden): …` string, not a
parse error. Nothing here makes redlib able to authenticate as a session.

**Image.** Built and published by GitHub Actions into `ghcr.io/lawlietr/redlib`
and mirrored identically to `codeberg.org/lawlietr/redlib` (same tags and
digests). Tag carrying this change: `<git-sha> 0c5050d` (`latest` is rolling).

**Rolling it back.** Re-add the `592 …` line to `redlib-prs.txt` and rebuild, or
run an image from an earlier `<git-sha>` tag. Re-adding #592 on top of
`0a3e9cd` will conflict in `src/client.rs` and must be resolved manually.

---

## 2026-10-21 — thread pages are loading again (workaround, **not** a fix)

**Affected**: all instances. Symptom was that clicking any post opened an error
page reading
`Failed to parse page JSON data: expected value at column 1`, while subreddit
listings, search and user pages kept working.

**What changed.** The image now bakes upstream
[redlib PR #592](https://github.com/redlib-org/redlib/pull/592)
(on top of the five already-baked open PRs — the list stays in `redlib-prs.txt`).
It does two things:

1. Percent-encodes the **single** slash that joins the subreddit to `comments`
   when redlib fetches a thread: `/r/<sub>/comments/<id>/.json` becomes
   `/r/<sub>%2fcomments/<id>/.json`. Reddit's edge matches the literal
   `/r/<sub>/comments/...` path and answers it with an HTML "You've been blocked
   by network security" page for anonymous / app-only OAuth tokens (the only
   tokens redlib can mint). The encoded path is not matched and returns exactly
   the same JSON. Verified end-to-end on our own build: control image without the
   change reproduces the reported parse error; the new image returns the thread
   with comments, and listings / search / user / duplicates are unaffected.
2. Reclassifies the error message. A blocked response is now reported as
   `Reddit blocked this request (403 Forbidden): Reddit now requires a
   logged-in session for this endpoint | <path>` instead of a misleading JSON
   parse error.

**⚠ This is a stopgap, not a fix.** It sidesteps a path-matching rule on
Reddit's side; it does not change the underlying policy, which is moving this
data behind logged-in access. Nothing here makes redlib able to authenticate as
a session. Two consequences to accept:

- **If Reddit starts normalising `%2f` back to `/` before matching, thread pages
  break again** — at which point the message will be the explicit
  `Reddit blocked this request (403 Forbidden): …` string above, not a parse
  error. That message, not a restart, is the signal that this workaround has
  died. Rotating the OAuth token (restarting the container) does **not** help:
  the block is path-based, confirmed with one token, one IP, one second —
  listing `200`, thread route `403`.
- The upstream PR is **still open, unreviewed**. Its head can be force-pushed;
  we pin the reviewed head SHA in `redlib-prs.txt` and the build warns if it
  moves.

**Not addressed by this change** (upstream flags them as out of scope; they were
working in our own test run, but do not assume they are fixed):

- parse errors on the front-page feed (`/r/popular/hot.json`) — upstream #589
- Anubis PoW challenge blocking programmatic access — upstream #567

**Confirmed in production on 2026-10-21**: instances on both `linux/amd64` and
`linux/arm64` are running this image and thread pages work on both.

**Found while verifying this build (pre-existing, not introduced by it)**: post
share links are effectively dead. Both `/u/<user>/s/<post id>` and
`/r/<sub>/s/<post id>` return 404 `Nothing here`, because the upstream route
guard only accepts post ids of **8–12 characters** while current Reddit post
ids are **7 characters** (e.g. `1x89e79`). The route itself is registered and
runs — an 8-character probe id produces the different message
`Post ID is invalid. It may point to a post on a user that has been banned.` —
so only the length condition is wrong. Reproduced identically on the amd64 and
arm64 instances and in a local container from the same image, so this is not a
regression from this release; it just means baking that upstream PR does not
actually restore share links.

**Primary image location changed (2026-10-21).** Images are now built and published by **GitHub
Actions** into `ghcr.io/lawlietr/redlib` (dual-arch, `latest` + `<git-sha>`, public/anonymous pull).
`codeberg.org/lawlietr/redlib` **keeps publishing**: the same CI run mirrors the finished images into it
with a registry-side copy (`docker buildx imagetools create`, no rebuild), so **tags and digests are
identical in both registries** and a digest pin is valid either way. The self-hosted Forgejo pipeline is
kept but no longer triggers on push — it is an emergency fallback (its musl cross-compiled binaries are an
implementation detail of that path, no longer a separate artifact line: `design/github-actions-workflow.md` §11);
running it by hand repoints the Codeberg tags at those builds until the next CI mirror.
If you currently pull from `codeberg.org/lawlietr/redlib`, nothing changes for you.

Local builds are explicitly supported for testing (`docker build -t redlib .`, then run the container
and the per-feature checks in `design/upstream-pr-bake.md` §7); a local build never publishes anything.
The pipeline also gained a `smoke` job that runs the **published** image on a clean runner (front page plus
two subreddit routes, checking status codes, body sizes and resolver errors in the container log) before the
mirror step is allowed to copy anything to Codeberg — this is the guard for the static-binary-inside-`scratch`
class of failure, see `design/github-actions-workflow.md` §10. The gate is live: run `39551016403`
(`51d0d7e`) finished with all five jobs green, and the mirror step printed identical child digests on both
registries (`12105bec...` amd64, `d77e9225...` arm64).

**How to pull / pin.** Tags carrying this change:
`codeberg.org/lawlietr/redlib:latest` and `:15cc3c1` (multi-arch, amd64 + arm64).
The GitHub-side mirror **is now multi-arch too and is also pinnable**: as of 2026-10-21 it publishes
`ghcr.io/lawlietr/redlib:{latest,<git-sha>,amd64,arm64}`, built natively on amd64 and arm64
GitHub-hosted runners, and the repository/package are public so it pulls anonymously (verified from a
clean Docker configuration; the pulled digest matched the digest the Actions run pushed).
The two registries now carry the **same bytes**: the Codeberg tags are a registry-side copy of the GitHub
build, so a tag or a digest is interchangeable between them (verified 2026-10-21: identical child manifest
digests for `latest` and `<git-sha>`). Only a manual fallback (Forgejo) build makes them diverge, and only
until the next CI run re-mirrors. The earliest `<git-sha>` tag on ghcr is `d572b2e`; earlier
ghcr builds only ever had `latest`. `ghcr.io/lawlietr/redlib:d572b2e` and
`codeberg.org/lawlietr/redlib:15cc3c1` contain the same baked redlib source (the commits differ only
in CI files), so either one carries this change.
`latest` is a rolling tag, so a re-pull plus container recreation is required;
a plain `docker compose up -d` with a `build:` key present will *not* pull the
registry image. To keep a reproducible deployment across future bake changes,
pin the `<git-sha>` tag instead of `latest`:

```bash
REDLIB_IMAGE=codeberg.org/lawlietr/redlib:<git-sha> \
  docker compose up -d --pull always --no-build
```

**Rolling it back.** Delete the `592 …` line from `redlib-prs.txt` and rebuild,
or run an image built from an earlier `<git-sha>` tag. Rolling back restores the
broken thread pages, so only do it if the encoding itself starts causing worse
behaviour.
