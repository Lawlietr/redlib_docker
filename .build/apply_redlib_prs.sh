#!/bin/bash
set -euo pipefail

# Bake the still-open upstream redlib PRs listed in redlib-prs.txt into a
# freshly cloned redlib source tree.
#
# Usage: apply_redlib_prs.sh <repo-dir> <prs-file>
#
# Each line of the PR file is "<pr-number> [expected-head-sha]"; blank lines and
# lines starting with # are ignored. PR heads are fetched from the clone's
# `origin` (so REDLIB_SRC must be the GitHub repo, which publishes refs/pull/*).
#
# Merges are plain --no-ff: every listed PR applies cleanly against current
# main, so a conflict here means upstream drifted and the list must be
# re-reviewed (design/upstream-pr-bake.md §5) instead of being papered over
# with -X ours.
#
# Used by: Dockerfile (local + GitHub Actions amd64 build) and
# .forgejo/scripts/build_and_push.sh (multi-arch build).

repo_dir="${1:?usage: apply_redlib_prs.sh <repo-dir> <prs-file>}"
prs_file="${2:?usage: apply_redlib_prs.sh <repo-dir> <prs-file>}"

# Resolve both arguments to absolute paths BEFORE the cd below: the PR file is
# read after we have entered the source dir, so a relative path (as passed by
# .forgejo/scripts/build_and_push.sh) would no longer resolve.
repo_dir="$(realpath -- "${repo_dir}")"
prs_file="$(realpath -- "${prs_file}")"

if [ ! -f "${prs_file}" ]; then
  echo "error: PR list not found: ${prs_file}" >&2
  exit 1
fi

cd "${repo_dir}"
git config user.email "builder@ci.invalid"
git config user.name "builder"

count=0
while read -r pr sha _; do
  [ -z "${pr:-}" ] && continue
  case "${pr}" in \#*) continue ;; esac

  # --depth keeps the shallow clone shallow while still reaching the merge base
  # of PRs branched from older main (300 is comfortably past what we need).
  git fetch --no-tags --depth 300 origin "pull/${pr}/head:baked-${pr}"
  head_sha="$(git rev-parse "baked-${pr}")"

  if [ -n "${sha:-}" ]; then
    case "${head_sha}" in
      "${sha}"*) : ;;
      *)
        echo "warning: PR #${pr} head moved: listed ${sha}, fetched ${head_sha}" >&2
        echo "         re-run the review in design/upstream-pr-bake.md §5" >&2
        ;;
    esac
  fi

  echo "Merging PR #${pr} -> ${head_sha}"
  git merge --no-ff "baked-${pr}" -m "Merge PR#${pr}"
  count=$((count + 1))
done < "${prs_file}"

echo "Baked ${count} PR(s). Resulting history on top of $(git rev-parse --short HEAD~"${count}" 2>/dev/null || echo '?'):"
git log --oneline -n $((count + 1))
