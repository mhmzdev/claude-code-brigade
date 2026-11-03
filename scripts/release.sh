#!/usr/bin/env bash
# =============================================================================
# scripts/release.sh [--dry-run] — open the release PR.
#
# main is protected, so a version can only arrive in a PR. Cooks never bump it: each PR that
# changes more than docs/ adds a fragment to changelog.d/ (scripts/release-check.sh). This
# collects every fragment on origin/main into one CHANGELOG entry, bumps plugin.json and the
# formula's url (a minor if any fragment says `level: minor`, else a patch), deletes the
# fragments and opens a PR from release/v<version>. Merging it is the release: release.yml
# tags it. It builds from origin/main in a throwaway worktree and touches none of this
# checkout's files, so it can be run again if main moves.
#
# --dry-run builds the branch locally and stops before the push.
# =============================================================================

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
MANIFEST=plugins/bk/.claude-plugin/plugin.json
FRAGDIR=changelog.d
DRY=false
[[ "${1:-}" == --dry-run ]] && DRY=true

git fetch origin main --quiet
frags=$(git ls-tree -r --name-only origin/main -- "$FRAGDIR" | grep -v "^$FRAGDIR/README.md$" | sort || true)
if [[ -z "$frags" ]]; then echo "Nothing to release: no fragments in $FRAGDIR/ on origin/main."; exit 0; fi

cur=$(git show "origin/main:$MANIFEST" | sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' | head -1)
level="patch"
for f in $frags; do
  [[ "$(git show "origin/main:$f" | head -1)" == "level: minor" ]] && level=minor
done
IFS=. read -r a b c <<<"$cur"
if [[ "$level" == minor ]]; then new="$a.$((b + 1)).0"; else new="$a.$b.$((c + 1))"; fi
branch="release/v$new"
if [[ -n "$(git ls-remote --heads origin "$branch")" ]]; then
  echo "$branch is already on origin: merge or close that release PR first." >&2; exit 1
fi

# a leftover local branch from an earlier dry run is only ever generated here
git branch -D "$branch" >/dev/null 2>&1 || true
wt=$(mktemp -d "${TMPDIR:-/tmp}/brigade-release.XXXXXX")
trap 'git worktree remove --force "$wt" 2>/dev/null || true; rm -rf "$wt"' EXIT
git worktree add -q -b "$branch" "$wt" origin/main
(
  cd "$wt"
  entry=$(mktemp)
  {
    printf '## [%s] - %s\n' "$new" "$(date +%F)"
    for f in $frags; do printf '\n'; sed '1,/^$/d' "$f"; done
  } >"$entry"
  awk -v ef="$entry" '/^## \[/ && !d { while ((getline l < ef) > 0) print l; print ""; d=1 } { print }' CHANGELOG.md >CHANGELOG.md.new
  mv CHANGELOG.md.new CHANGELOG.md
  sed "s/\"version\": *\"$cur\"/\"version\": \"$new\"/" "$MANIFEST" >manifest.new && mv manifest.new "$MANIFEST"
  sed "s#/archive/refs/tags/v$cur\.tar\.gz#/archive/refs/tags/v$new.tar.gz#" Formula/bk.rb >formula.new && mv formula.new Formula/bk.rb
  # shellcheck disable=SC2086
  git rm -q $frags
  git add "$MANIFEST" CHANGELOG.md Formula/bk.rb
  git commit -q -m "release: v$new"
)
echo "release: v$new ($level), from: $(echo $frags)"
if $DRY; then echo "dry run: $branch exists locally only"; exit 0; fi
git push -q -u origin "$branch"
gh pr create --base main --head "$branch" --title "release: v$new" \
  --body "Releases the changes waiting in $FRAGDIR/: $(echo $frags). Merging this tags v$new."
