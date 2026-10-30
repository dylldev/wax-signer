# Publishing under protected main

The old `scripts/publish-main.sh` and orphan-producing `publish-prep.sh` are not the new publishing route. They must not be used to update protected main. Force pushes remain blocked. The security PR must add this replacement recipe to the public publishing instructions and flag the old helper as retired.

Use the correct repository checkout. The source repo is `dylldev/wax-signer`; the download/site repo is `dylldev/wax`. Each has its own reviewed snapshot. Never copy the source tree into the download repo. Do not publish uncommitted files, private IPAs, real credentials or private working history. The existing private denylist remains mandatory.

## Preparation

1. Finish tests and commit only intended source/public-site files on the private working branch. Leave unrelated changes alone. Stop if tracked changes remain uncommitted.
2. Fetch the selected public repo's main. Compare its current files with the proposed snapshot and preserve any public-only changes. A whole-tree snapshot can otherwise revert newer public work; stop if the diff contains unexpected removals or reversions.
3. Scan the tracked snapshot with the existing private denylist, and inspect the proposed file list for private artifacts. The denylist alone is not a complete secrets detector. Do not print secret matching lines.

## Reviewed recipe for the source repository

Run only after those checks. This creates a new commit with the reviewed snapshot's tree and **public main as its sole parent**. It does not switch or rewrite the private working branch. Use a repository-scoped no-reply author. The existing audit PR used this method successfully.

```bash
set -euo pipefail
repo_name=dylldev/wax-signer
publish_branch="codex/publish-$(date -u +%Y%m%d-%H%M%S)"
denylist_file="$HOME/projects/Local IOS Signer/scripts/denylist.txt"
test -f "$denylist_file"
git diff --quiet
git diff --cached --quiet
test "$(git remote get-url publish)" = "https://github.com/$repo_name.git"
pattern_file=$(mktemp)
trap 'rm -f "$pattern_file"' EXIT
sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$denylist_file" > "$pattern_file"
test -s "$pattern_file"
scan_status=0
git grep -I -l -F -f "$pattern_file" HEAD -- . || scan_status=$?
case "$scan_status" in
  0) echo "Stop: private-pattern match in tracked files" >&2; exit 1 ;;
  1) ;; # No matches.
  *) echo "Stop: privacy scan failed" >&2; exit "$scan_status" ;;
esac
git fetch publish refs/heads/main:refs/remotes/publish/main
public_parent=$(git rev-parse refs/remotes/publish/main)
snapshot_tree=$(git rev-parse HEAD^{tree})
git diff --stat "$public_parent" HEAD
# Inspect the complete diff before continuing. Keep public-only work intact.
public_commit=$(GIT_AUTHOR_NAME=dylldev \
  GIT_AUTHOR_EMAIL=266615607+dylldev@users.noreply.github.com \
  GIT_COMMITTER_NAME=dylldev \
  GIT_COMMITTER_EMAIL=266615607+dylldev@users.noreply.github.com \
  git commit-tree "$snapshot_tree" -p "$public_parent" -m "Prepare reviewed Wax update")
git update-ref "refs/heads/$publish_branch" "$public_commit" 0000000000000000000000000000000000000000
git merge-base --is-ancestor "$public_parent" "$public_commit"
git push publish "refs/heads/$publish_branch:refs/heads/$publish_branch"
gh pr create --repo "$repo_name" --base main --head "$publish_branch" --draft \
  --title "Review Wax update" --body "Prepared from a reviewed snapshot on public main. Verify checks and the full diff before merging."
```

For the download repository, run from its own checkout and set `repo_name=dylldev/wax`; its `publish` remote must point to that repo. Do not reuse the source tree, branch or parent commit. A PR does not publish an app release. The owner reviews and merges only after passing checks and the required review gate; publishing releases remains a separate authorization.

## Failure and recovery

A blocked direct-main/force push is expected after protection. Do not disable protection to make the old script work. If the new branch name exists, choose a new name; do not overwrite it. If public main advances during review, refresh the candidate against that public work and rerun checks. Retain the private branch unchanged. No force push or protected-ref deletion is part of this recipe.
