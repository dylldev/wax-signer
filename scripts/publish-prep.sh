#!/usr/bin/env bash
# Prepares the code for publishing without personal details.
#   scripts/publish-prep.sh [--denylist FILE] [--author "Name <email>"]
# 1. Refuses to run with uncommitted changes.
# 2. Searches the current commit for every line of the denylist (default scripts/denylist.txt, which is never
#    committed: put your server address, team IDs and email there, one per line) and stops at the first hit.
# 3. Makes a new branch with ONE commit holding today's tracked files (untracked files are never included), so old history (which may still contain those
#    details) is not published. Push that branch, not your working branch.
set -euo pipefail

DENY="scripts/denylist.txt"
AUTHOR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --denylist) DENY="${2:-}"; shift 2 ;;
    --author) AUTHOR="${2:-}"; shift 2 ;;     # "Name <email>": use a no-reply address so a private email is not published
    *) echo "unknown option $1" >&2; exit 1 ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "uncommitted changes: commit or stash them first"
[ -f "$DENY" ] || die "no denylist at $DENY. Create it with one private string per line (server address, team IDs, email)."

patterns="$(mktemp)"; trap 'rm -f "$patterns"' EXIT
grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$DENY" >"$patterns" || true
[ -s "$patterns" ] || die "the denylist has no entries"

if hits="$(git grep -n -I -F -f "$patterns" HEAD -- . ':!scripts/denylist.txt' || true)"; [ -n "$hits" ]; then
  echo "$hits" | cut -d: -f2- | cut -c1-160 >&2
  die "the lines above contain denylisted strings. Remove them, commit, and run again."
fi

branch="publish-$(date +%Y%m%d-%H%M%S)"
git checkout -q --orphan "$branch"      # keeps the index: exactly the tracked files, nothing untracked
if [ -n "$AUTHOR" ]; then git commit -q --author "$AUTHOR" -m "Wax: free, open-source IPA signer for iPhone"
else git commit -q -m "Wax: free, open-source IPA signer for iPhone"; fi
echo "Created $branch with one commit. Push it as the public main branch, for example:"
echo "  git push <remote> $branch:main"
