# Release Notes

English only (this file is the image changelog consumers read; the design docs in
`design/` carry the reproduction detail).

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

**How to pull / pin.** Tags carrying this change:
`codeberg.org/lawlietr/redlib:latest` and `:15cc3c1` (both multi-arch,
amd64 + arm64); the mirror `ghcr.io/lawlietr/redlib:latest` is amd64 only.
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
