#!/usr/bin/env bash
# Checks scripts/publish-prep.sh in throwaway repositories. Run: bash scripts/test_publish_prep.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (wanted $2, got $3)"; fail=1; fi; }

new_repo() {
  R="$(mktemp -d)"; cd "$R"; git init -q -b main; git config user.email t@example.test; git config user.name t
  mkdir scripts; cp "$HERE/publish-prep.sh" scripts/
  echo "hello" > a.txt; DENY="$(mktemp)"; printf '# comment\n\nsecret-host.example\n' > "$DENY"
  git add -A; git commit -qm one
}

new_repo
echo "local only" > untracked.txt
bash scripts/publish-prep.sh --denylist "$DENY" >/dev/null 2>&1; check "clean tree passes" 0 $?
check "untracked files are not published" "" "$(git ls-tree -r --name-only HEAD | grep untracked)"
check "publish branch has one commit" 1 "$(git rev-list --count HEAD)"
check "publish branch is a new branch" "publish" "$(git rev-parse --abbrev-ref HEAD | cut -c1-7)"

new_repo
echo "see secret-host.example" > b.txt; git add -A; git commit -qm leak
bash scripts/publish-prep.sh --denylist "$DENY" >/dev/null 2>&1; check "planted denylisted string fails" 1 $?
check "no publish branch was made" "main" "$(git rev-parse --abbrev-ref HEAD)"

new_repo
echo dirty >> a.txt
bash scripts/publish-prep.sh --denylist "$DENY" >/dev/null 2>&1; check "uncommitted changes refuse" 1 $?

new_repo
bash scripts/publish-prep.sh --denylist "$DENY.missing" >/dev/null 2>&1; check "missing denylist refuses" 1 $?

exit $fail
