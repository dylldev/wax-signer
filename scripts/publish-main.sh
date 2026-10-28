#!/usr/bin/env bash
# Publishes the current commit's tracked files as ONE clean commit on the public remote's main, safely.
#   scripts/publish-main.sh [remote]      (default remote: publish)
# Refuses to push anything that is not a single commit by the no-reply author, and always returns to the branch you were on.
set -euo pipefail
REMOTE="${1:-publish}"
AUTHOR="dylldev <266615607+dylankirkgirg@users.noreply.github.com>"
NOREPLY="266615607+dylankirkgirg@users.noreply.github.com"
start="$(git branch --show-current)"
trap 'git checkout -q "$start" 2>/dev/null || true' EXIT
[ "$(git config user.email)" = "$NOREPLY" ] || { echo "abort: git user.email is not the no-reply address" >&2; exit 1; }
bash scripts/publish-prep.sh --author "$AUTHOR" >/dev/null     # exits non-zero on any denylist hit or dirty tree
b="$(git branch --show-current)"
case "$b" in publish-*) ;; *) echo "abort: not on a publish- branch ($b)" >&2; exit 1;; esac
[ "$(git rev-list --count HEAD)" = 1 ] || { echo "abort: not a single commit" >&2; exit 1; }
[ "$(git log -1 --format=%ae)" = "$NOREPLY" ] && [ "$(git log -1 --format=%ce)" = "$NOREPLY" ] || { echo "abort: author or committer is not the no-reply address" >&2; exit 1; }
git fetch -q "$REMOTE"
if current="$(git rev-parse --verify -q "$REMOTE/main")"; then lease="--force-with-lease=main:$current"; else lease=""; fi   # first publish has no main yet
git push $lease "$REMOTE" "$b":main
git checkout -q "$start"; git branch -q -D "$b"
echo "published one clean commit to $REMOTE/main"
