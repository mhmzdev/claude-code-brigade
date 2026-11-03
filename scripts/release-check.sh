#!/usr/bin/env bash
# =============================================================================
# scripts/release-check.sh — step 5 of scripts/check.sh: is this tree releasable?
#
#  1. plugin.json's version is the top CHANGELOG.md entry and the one Formula/bk.rb
#     downloads.
#  2. On a branch, by what it changes against its merge base with origin/main:
#       only docs/**   no release: there is nothing to carry
#       a release      only plugin.json, CHANGELOG.md, Formula/bk.rb and changelog.d/
#                      deletions: it must raise the version and consume every fragment
#       anything else  adds changelog.d/<id>-<slug>.md and leaves the version, the formula
#                      url and every `## [x.y.z]` heading alone: the release PR
#                      (scripts/release.sh) assigns the version, so main moving never costs
#                      a cook a re-bump
#
# main is protected, so a version can only arrive in a PR; see AGENTS.md, "Releasing".
# Exit 0 = releasable.
# =============================================================================

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
MANIFEST=plugins/bk/.claude-plugin/plugin.json
FRAGDIR=changelog.d
FAILED=0
fail() { echo "   ✗ $1"; FAILED=1; }
version_of() { sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' | head -1; }
newer() {  # newer A B: A > B, both X.Y.Z
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<<"$1"; IFS=. read -r b1 b2 b3 <<<"$2"
  (( a1 > b1 || (a1 == b1 && (a2 > b2 || (a2 == b2 && a3 > b3))) ))
}
not_readme() { grep -v "^$FRAGDIR/README.md$" || true; }

version=$(version_of <"$MANIFEST")
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "$MANIFEST: version '$version' isn't X.Y.Z"
  exit 1
fi
top=$(grep -m1 '^## \[' CHANGELOG.md 2>/dev/null)
[[ "$top" =~ ^"## [$version] - "[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
  || fail "CHANGELOG.md: top entry is '${top:-missing}', want '## [$version] - YYYY-MM-DD'"
grep -q "/archive/refs/tags/v$version.tar.gz\"" Formula/bk.rb \
  || fail "Formula/bk.rb: url must download v$version (the release workflow fills in the sha256)"

if ! git rev-parse -q --verify origin/main >/dev/null; then
  echo "   ! no origin/main: the branch rule is not checked"
else
  base=$(git merge-base HEAD origin/main)
  # what this branch changes: committed, staged or not, and new files (the gate runs before the commit)
  changed=$( { git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u )
  main_version=$(git show "origin/main:$MANIFEST" | version_of)
  base_version=$(git show "$base:$MANIFEST" | version_of)   # what this branch started from: main may have released since
  if [[ -z "$changed" ]]; then
    :  # main itself, or a checkout behind it: nothing new to release
  else
    docs_only=true; release_files=true
    while IFS= read -r p; do
      case "$p" in docs/*) ;; *) docs_only=false ;; esac
      case "$p" in "$MANIFEST"|CHANGELOG.md|Formula/bk.rb|"$FRAGDIR"/*) ;; *) release_files=false ;; esac
    done <<<"$changed"
    if $docs_only; then
      echo "   · only docs/ changes: no release to carry"
    elif [[ "$version" != "$base_version" ]]; then
      if ! $release_files; then
        fail "this PR bumps the version ($base_version → $version) and changes more than the release files: drop the bump in $MANIFEST, CHANGELOG.md and Formula/bk.rb, and add $FRAGDIR/<id>-<slug>.md; the release PR (scripts/release.sh) assigns the version"
      else
        newer "$version" "$main_version" \
          || fail "release: version $version must be higher than origin/main's $main_version"
        left=$(ls "$FRAGDIR"/*.md 2>/dev/null | not_readme)
        [[ -z "$left" ]] || fail "release: fragments left in $FRAGDIR/ (a release consumes them): $(echo $left)"
      fi
    else
      new=$( { git diff --name-only --diff-filter=A "$base" -- "$FRAGDIR"; git ls-files --others --exclude-standard -- "$FRAGDIR"; } | sort -u | not_readme )
      if [[ -z "$new" ]]; then
        fail "this PR changes more than docs/ and adds no fragment: add $FRAGDIR/<id>-<slug>.md (first line 'level: minor' or 'level: patch', then the paragraph for the head chef)"
      fi
      for f in $new; do
        [[ -f "$f" ]] || continue
        head -1 "$f" | grep -qE '^level: (minor|patch)$' || fail "$f: the first line must be 'level: minor' or 'level: patch'"
        [[ -n "$(sed '1,/^$/d' "$f")" ]] || fail "$f: no paragraph after the level line"
      done
      if git diff "$base" -- CHANGELOG.md | grep -qE '^\+## \['; then
        fail "CHANGELOG.md: this PR adds a '## [x.y.z]' entry; entries are written by the release PR from the fragments"
      fi
    fi
  fi
  pending=$(git ls-tree -r --name-only origin/main -- "$FRAGDIR" | not_readme | wc -l | tr -d ' ')
  (( pending == 0 )) || echo "   · $pending change(s) on main wait for a release: scripts/release.sh"
fi
(( FAILED == 0 )) && echo "   ✓ v$version"
exit "$FAILED"
