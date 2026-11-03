#!/usr/bin/env bash
# =============================================================================
# tests/release.test.sh — behaviour tests for scripts/release-check.sh (step 5 of the gate)
# and scripts/release.sh (the release PR).
#
# Builds a throwaway repo with a bare "origin" and the two scripts copied in, then drives them
# the way a cook's branch, a docs-only branch and a release branch would. Nothing touches the
# real machine: git runs with GIT_CONFIG_GLOBAL=/dev/null, HOME points into the temp dir, and
# gh is a stub that logs its arguments.
#
# Usage:   tests/release.test.sh            (exit 0 = all passed)
#          KEEP=1 tests/release.test.sh     (keep the temp dir for poking at)
# =============================================================================

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/brigade-release-test.XXXXXX")"
REAL_HOME="$HOME"
export HOME="$TMP/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
  GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
  GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
mkdir -p "$HOME"
cleanup() { [[ -n "${KEEP:-}" ]] && echo "kept: $TMP" || rm -rf "$TMP"; }
trap cleanup EXIT

PASS=0; FAIL=0; N=0
ok() {  # ok <description> <command…>: passes when the command exits 0
  local desc="$1"; shift; N=$((N+1))
  if ( "$@" ) >/dev/null 2>&1; then PASS=$((PASS+1)); echo "ok $N - $desc"
  else FAIL=$((FAIL+1)); echo "not ok $N - $desc"; fi
}
has() { printf '%s' "$1" | grep -qE -- "$2"; }
section() { echo "# $1"; }

# gh stub: logs every call; `pr create` prints a URL
STUB="$TMP/stub"; mkdir -p "$STUB"
cat > "$STUB/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/gh.log"
[[ "\$1 \$2" == "pr create" ]] && echo "https://example.test/pull/1"
exit 0
EOF
chmod +x "$STUB/gh"
export PATH="$STUB:$PATH"

O="$TMP/origin.git"; W="$TMP/work"
git init -q --bare "$O"
git clone -q "$O" "$W" 2>/dev/null
git -C "$W" checkout -q -b main
mkdir -p "$W/scripts" "$W/Formula" "$W/plugins/bk/.claude-plugin" "$W/plugins/bk/skills" "$W/docs" "$W/changelog.d"
cp "$REPO/scripts/release-check.sh" "$REPO/scripts/release.sh" "$W/scripts/"
cat > "$W/plugins/bk/.claude-plugin/plugin.json" <<'EOF'
{
  "name": "bk",
  "version": "0.30.0"
}
EOF
cat > "$W/CHANGELOG.md" <<'EOF'
# Changelog

Intro text.

## [0.30.0] - 2026-11-03

The top entry.

## [0.29.1] - 2026-11-02

An older one.
EOF
cat > "$W/Formula/bk.rb" <<'EOF'
class Bk < Formula
  url "https://github.com/x/y/archive/refs/tags/v0.30.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
EOF
echo "# readme" > "$W/changelog.d/README.md"
echo "x" > "$W/docs/a.md"
echo "x" > "$W/plugins/bk/skills/s.md"
git -C "$W" add -A && git -C "$W" commit -qm "init" && git -C "$W" push -q -u origin main 2>/dev/null

chk() { bash "$W/scripts/release-check.sh" 2>&1; }
# branch <name>: a clean branch off origin/main
branch() { git -C "$W" checkout -q -f -B "$1" origin/main && git -C "$W" clean -fdq; }
commit_all() { git -C "$W" add -A && git -C "$W" commit -qm "$1"; }
frag() {  # frag <file> <first line> [paragraph]
  printf '%s\n\n%s\n' "$2" "${3-A paragraph for the head chef.}" > "$W/changelog.d/$1"
}

section "main itself"
branch main-copy
out=$(chk); rc=$?
ok "a clean tree at origin/main passes" test "$rc" = 0
ok "…and prints the version" has "$out" "v0\.30\.0"

section "a docs-only branch"
branch docs-only
echo "more" >> "$W/docs/a.md"; echo "n" > "$W/docs/new.md"; commit_all docs
out=$(chk); rc=$?
ok "docs/ only: passes with no fragment and the same version" test "$rc" = 0
ok "…and says there is no release to carry" has "$out" "only docs/ changes"
branch docs-dirty
echo "more" >> "$W/docs/a.md"
ok "docs/ only, uncommitted: still passes" bash "$W/scripts/release-check.sh"

section "a branch that changes more than docs/"
branch code-nofrag
echo "y" >> "$W/plugins/bk/skills/s.md"; commit_all code
out=$(chk); rc=$?
ok "code without a fragment fails" test "$rc" = 1
ok "…and names changelog.d/" has "$out" "adds no fragment: add changelog\.d/"
branch code-frag
echo "y" >> "$W/plugins/bk/skills/s.md"; frag 64-x.md "level: minor"; commit_all code
ok "code with a valid fragment passes" bash "$W/scripts/release-check.sh"
branch code-frag-dirty
echo "y" >> "$W/plugins/bk/skills/s.md"; frag 64-x.md "level: patch"
ok "…also before the commit (fragment untracked)" bash "$W/scripts/release-check.sh"
branch code-badlevel
echo "y" >> "$W/plugins/bk/skills/s.md"; frag 64-x.md "level: major"; commit_all code
out=$(chk); rc=$?
ok "a fragment whose first line is not minor|patch fails" test "$rc" = 1
ok "…and says which line" has "$out" "first line must be 'level: minor' or 'level: patch'"
branch code-nopara
echo "y" >> "$W/plugins/bk/skills/s.md"; printf 'level: minor\n' > "$W/changelog.d/64-x.md"; commit_all code
out=$(chk); rc=$?
ok "a fragment with no paragraph fails" test "$rc" = 1
branch code-readme-only
echo "y" >> "$W/plugins/bk/skills/s.md"; echo "edited" >> "$W/changelog.d/README.md"; commit_all code
ok "changelog.d/README.md is not a fragment" bash -c "! bash '$W/scripts/release-check.sh'"
branch mixed
echo "y" >> "$W/docs/a.md"; echo "y" >> "$W/plugins/bk/skills/s.md"; commit_all mixed
ok "docs plus one code file still needs the fragment" bash -c "! bash '$W/scripts/release-check.sh'"

section "a cook that bumps"
branch code-bump
echo "y" >> "$W/plugins/bk/skills/s.md"; frag 64-x.md "level: minor"
sed -i.bak 's/"0.30.0"/"0.30.1"/' "$W/plugins/bk/.claude-plugin/plugin.json"; rm -f "$W/plugins/bk/.claude-plugin/plugin.json.bak"
printf '# Changelog\n\n## [0.30.1] - 2026-11-04\n\nmine\n\n## [0.30.0] - 2026-11-03\n' > "$W/CHANGELOG.md"
sed -i.bak 's/v0.30.0/v0.30.1/' "$W/Formula/bk.rb"; rm -f "$W/Formula/bk.rb.bak"
commit_all bump
out=$(chk); rc=$?
ok "a PR that bumps the version and changes code fails" test "$rc" = 1
ok "…and says to drop the bump and add a fragment" has "$out" "drop the bump .* add changelog\.d/"
branch code-heading
echo "y" >> "$W/plugins/bk/skills/s.md"; frag 64-x.md "level: minor"
printf '# Changelog\n\nIntro text.\n\n## [0.30.1] - 2026-11-04\n\nmine\n\n## [0.30.0] - 2026-11-03\n\nThe top entry.\n' > "$W/CHANGELOG.md"
commit_all heading
out=$(chk); rc=$?
ok "a '## [x.y.z]' heading added to CHANGELOG.md without a bump fails" test "$rc" = 1
ok "…the release PR writes entries" has "$out" "adds a '## \[x\.y\.z\]' entry"

section "a release PR"
release_files() {  # release_files <version> [date]
  sed -i.bak "s/\"0.30.0\"/\"$1\"/" "$W/plugins/bk/.claude-plugin/plugin.json"; rm -f "$W/plugins/bk/.claude-plugin/plugin.json.bak"
  sed -i.bak "s/v0.30.0/v$1/" "$W/Formula/bk.rb"; rm -f "$W/Formula/bk.rb.bak"
  printf '# Changelog\n\nIntro text.\n\n## [%s] - 2026-11-04\n\nthe release\n\n## [0.30.0] - 2026-11-03\n\nThe top entry.\n' "$1" > "$W/CHANGELOG.md"
}
branch rel-ok
release_files 0.31.0; commit_all release
ok "only the release files, version higher, no fragment left: passes" bash "$W/scripts/release-check.sh"
branch rel-same
printf 'x\n' >> "$W/CHANGELOG.md"; commit_all release
out=$(chk); rc=$?
ok "a CHANGELOG-only change, same version, needs a fragment" test "$rc" = 1
# a release whose version is lower than main's
git -C "$W" checkout -q -f -B rel-low origin/main && git -C "$W" clean -fdq
release_files 0.29.5; commit_all release
out=$(chk); rc=$?
ok "a release that is not higher than origin/main's fails" test "$rc" = 1
ok "…and says so" has "$out" "must be higher than origin/main's 0\.30\.0"
# main carries a fragment; the release branch leaves it behind
git -C "$W" checkout -q -f -B main-with-frag origin/main && git -C "$W" clean -fdq
frag 70-pending.md "level: patch"; echo "y" >> "$W/plugins/bk/skills/s.md"
commit_all pending && git -C "$W" push -q origin HEAD:main 2>/dev/null && git -C "$W" fetch -q origin
branch rel-left
release_files 0.30.1; commit_all release
out=$(chk); rc=$?
ok "a release that leaves a fragment in changelog.d/ fails" test "$rc" = 1
ok "…and names it" has "$out" "fragments left in changelog\.d/.*70-pending\.md"
branch pending-note
echo "d" >> "$W/docs/a.md"; commit_all docs
ok "a docs-only branch reports the changes waiting for a release" has "$(chk)" "1 change\(s\) on main wait for a release"

section "scripts/release.sh"
git -C "$W" checkout -q -f -B work origin/main && git -C "$W" clean -fdq
frag 71-second.md "level: minor" "Second paragraph."; frag 72-third.md "level: patch" "Third paragraph."
commit_all frags && git -C "$W" push -q origin HEAD:main 2>/dev/null && git -C "$W" fetch -q origin
(cd "$W" && bash scripts/release.sh --dry-run) > "$TMP/dry.out" 2>&1
out=$(cat "$TMP/dry.out")
ok "any minor fragment makes it a minor: 0.31.0" has "$out" "release: v0\.31\.0 \(minor\)"
ok "…the branch exists locally only" bash -c "git -C '$W' rev-parse --verify -q release/v0.31.0 && test -z \"\$(git -C '$W' ls-remote --heads origin release/v0.31.0)\""
R="release/v0.31.0"
ok "…the entry sits above the previous top entry" bash -c "git -C '$W' show $R:CHANGELOG.md | awk '/^## \\[/ {print \$2; if (++n==2) exit}' | tr '\n' ' ' | grep -q '^\\[0.31.0\\] \\[0.30.0\\]'"
ok "…and holds every fragment's paragraph" bash -c "git -C '$W' show $R:CHANGELOG.md | grep -q 'Second paragraph\\.' && git -C '$W' show $R:CHANGELOG.md | grep -q 'Third paragraph\\.' && git -C '$W' show $R:CHANGELOG.md | grep -q 'A paragraph for the head chef\\.'"
ok "…the level lines do not leak into the entry" bash -c "! git -C '$W' show $R:CHANGELOG.md | grep -q '^level:'"
ok "…the manifest and the formula url moved" bash -c "git -C '$W' show $R:plugins/bk/.claude-plugin/plugin.json | grep -q '\"0.31.0\"' && git -C '$W' show $R:Formula/bk.rb | grep -q 'v0.31.0.tar.gz'"
ok "…the fragments are gone but README.md stays" bash -c "test \"\$(git -C '$W' ls-tree -r --name-only $R -- changelog.d)\" = changelog.d/README.md"
ok "…the checkout it ran from is untouched" test -z "$(git -C "$W" status --porcelain)"
ok "…the throwaway worktree is gone" test "$(git -C "$W" worktree list | wc -l | tr -d ' ')" = 1
git -C "$W" checkout -q -f -B rel-built "$R" && git -C "$W" clean -fdq
ok "the branch it builds passes the release check" bash "$W/scripts/release-check.sh"
git -C "$W" checkout -q -f work
(cd "$W" && bash scripts/release.sh --dry-run) > "$TMP/dry2.out" 2>&1
ok "run again after a dry run: it rebuilds the branch" has "$(cat "$TMP/dry2.out")" "release: v0\.31\.0"

: > "$TMP/gh.log"
(cd "$W" && bash scripts/release.sh) > "$TMP/real.out" 2>&1
ok "without --dry-run it pushes the branch" test -n "$(git -C "$W" ls-remote --heads origin release/v0.31.0)"
ok "…and opens the PR against main from it" bash -c "grep -q 'pr create --base main --head release/v0.31.0 --title release: v0.31.0' '$TMP/gh.log'"
(cd "$W" && bash scripts/release.sh) > "$TMP/again.out" 2>&1; rc=$?
ok "…and refuses while that release PR's branch is on origin" test "$rc" = 1
ok "…saying why" has "$(cat "$TMP/again.out")" "already on origin"

# a main with no fragments waiting
git -C "$W" checkout -q -f -B clean-main origin/main && git -C "$W" clean -fdq
git -C "$W" rm -q changelog.d/71-second.md changelog.d/72-third.md changelog.d/70-pending.md
commit_all drained && git -C "$W" push -q origin HEAD:main 2>/dev/null && git -C "$W" fetch -q origin
out=$(cd "$W" && bash scripts/release.sh 2>&1); rc=$?
ok "no fragments on main: nothing to release, exit 0" test "$rc" = 0
ok "…saying so" has "$out" "Nothing to release"

section "main released while a branch was in flight"
git -C "$W" checkout -q -f -B behind origin/main && git -C "$W" clean -fdq
echo "y" >> "$W/plugins/bk/skills/s.md"; frag 80-behind.md "level: patch"; commit_all behind
git -C "$W" checkout -q -f -B main-released origin/main && git -C "$W" clean -fdq
release_files 0.99.0; commit_all release
git -C "$W" push -q origin HEAD:main 2>/dev/null && git -C "$W" fetch -q origin
git -C "$W" checkout -q -f behind
out=$(chk); rc=$?
ok "a branch cut before main released: its fragment is enough, no bump seen" test "$rc" = 0
ok "…even though its version is lower than origin/main's now" has "$(git -C "$W" show origin/main:plugins/bk/.claude-plugin/plugin.json)" '"0\.99\.0"'
branch behind-nofrag
git -C "$W" checkout -q -f -B behind2 main-released~1 && git -C "$W" clean -fdq
echo "z" >> "$W/plugins/bk/skills/s.md"; commit_all behind2
out=$(chk); rc=$?
ok "…and with no fragment it still fails, naming the fragment, not a bump" test "$rc" = 1 && has "$out" "adds no fragment"

# =============================================================================
echo ""
echo "# passed $PASS · failed $FAIL · total $N"
[[ "$HOME" != "$REAL_HOME" ]] || { echo "# BUG: HOME was not isolated"; exit 1; }
(( FAIL == 0 ))
