#!/usr/bin/env bash
# =============================================================================
# scripts/check.sh — THE gate for changes to the Brigade plugin.
#
# 1. manifests   claude plugin validate (skipped with a warning if no claude CLI)
# 2. script      bash -n + shellcheck on kitchen.sh, hooks/guard.sh and bin/bk (shellcheck required)
# 3. skills      frontmatter sanity: name matches folder, description present,
#                disable-model-invocation only on setup
# 4. behaviour   tests/kitchen.test.sh, tests/guard.test.sh, tests/bk.test.sh, tests/budget.test.sh and tests/window.test.sh
# 5. release     plugin.json's version is the top CHANGELOG.md entry, the one Formula/bk.rb
#                downloads, and, on a branch, higher than origin/main's (every merge to
#                main is a release)
#
# Exit 0 = safe to push to main (which is the release).
# =============================================================================

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
KITCHEN=plugins/bk/skills/kitchen/kitchen.sh
GUARD=plugins/bk/hooks/guard.sh
BK=bin/bk
FAILED=()

step() { echo ""; echo "== $1"; }
fail() { echo "   ✗ $1"; FAILED+=("$1"); }

step "1. manifests"
if command -v claude >/dev/null; then
  for target in . plugins/bk; do
    if out=$(claude plugin validate "$target" 2>&1); then echo "   ✓ $target"
    else echo "$out" | sed 's/^/     /'; fail "claude plugin validate $target"; fi
  done
else
  echo "   ! claude CLI not found: manifest validation skipped"
fi

step "2. kitchen.sh, hooks/guard.sh and bin/bk"
bash -n "$KITCHEN" && echo "   ✓ bash -n kitchen.sh" || fail "bash -n $KITCHEN"
bash -n "$GUARD" && echo "   ✓ bash -n guard.sh" || fail "bash -n $GUARD"
bash -n "$BK" && echo "   ✓ bash -n bk" || fail "bash -n $BK"
[[ -x "$BK" ]] && echo "   ✓ bin/bk is executable" || fail "$BK is not executable"
if command -v shellcheck >/dev/null; then
  if out=$(shellcheck -S warning "$KITCHEN" "$GUARD" "$BK" tests/kitchen.test.sh tests/guard.test.sh tests/bk.test.sh tests/budget.test.sh tests/window.test.sh scripts/check.sh 2>&1); then echo "   ✓ shellcheck"
  else echo "$out" | sed 's/^/     /'; fail "shellcheck"; fi
else
  fail "shellcheck not installed (brew install shellcheck)"
fi

step "3. skill frontmatter"
before=${#FAILED[@]}
for f in plugins/bk/skills/*/SKILL.md; do
  dir=$(basename "$(dirname "$f")")
  name=$(awk '/^---$/{n++; next} n==1 && /^name:/{print $2; exit}' "$f")
  [[ "$name" == "$dir" ]] || fail "$f: name '$name' doesn't match folder '$dir'"
  grep -q '^description: .\{40,\}' "$f" || fail "$f: missing or too-short description"
  if grep -q '^disable-model-invocation: true' "$f" && [[ "$dir" != setup ]]; then
    fail "$f: disable-model-invocation is only allowed on setup (cooks would stall)"
  fi
done
for f in plugins/bk/agents/*.md; do
  name=$(awk '/^---$/{n++; next} n==1 && /^name:/{print $2; exit}' "$f")
  grep -q "\"./agents/$name.md\"" plugins/bk/.claude-plugin/plugin.json || fail "$f: not listed in plugin.json agents"
done
python3 -c 'import json,sys; json.load(open("plugins/bk/hooks/hooks.json"))["hooks"]' 2>/dev/null || fail "plugins/bk/hooks/hooks.json: not valid JSON with a top-level \"hooks\" key"
(( ${#FAILED[@]} == before )) && echo "   ✓ $(ls plugins/bk/skills/*/SKILL.md | wc -l | tr -d ' ') skills, $(ls plugins/bk/agents/*.md | wc -l | tr -d ' ') agents"

step "4. behaviour (tests/kitchen.test.sh, tests/guard.test.sh, tests/bk.test.sh, tests/budget.test.sh, tests/window.test.sh)"
if out=$(bash tests/kitchen.test.sh 2>&1); then echo "   ✓ kitchen: $(printf '%s\n' "$out" | tail -1 | sed 's/^# //')"
else printf '%s\n' "$out" | grep -E '^not ok|^# passed' | sed 's/^/     /'; fail "kitchen tests"; fi
if out=$(bash tests/guard.test.sh 2>&1); then echo "   ✓ guard: $(printf '%s\n' "$out" | tail -1 | sed 's/^# //')"
else printf '%s\n' "$out" | grep -E '^not ok|^# passed' | sed 's/^/     /'; fail "guard tests"; fi
if out=$(bash tests/bk.test.sh 2>&1); then echo "   ✓ bk: $(printf '%s\n' "$out" | tail -1 | sed 's/^# //')"
else printf '%s\n' "$out" | grep -E '^not ok|^# passed' | sed 's/^/     /'; fail "bk tests"; fi
if out=$(bash tests/budget.test.sh 2>&1); then echo "   ✓ budget: $(printf '%s\n' "$out" | tail -1 | sed 's/^# //')"
else printf '%s\n' "$out" | grep -E '^not ok|^# passed|^Bail' | sed 's/^/     /'; fail "budget tests"; fi
if out=$(bash tests/window.test.sh 2>&1); then echo "   ✓ window: $(printf '%s\n' "$out" | tail -1 | sed 's/^# //')"
else printf '%s\n' "$out" | grep -E '^not ok|^# passed|^Bail' | sed 's/^/     /'; fail "window tests"; fi

step "5. release (version, CHANGELOG.md, Formula/bk.rb)"
before=${#FAILED[@]}
version_of() { sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' | head -1; }
newer() {  # newer A B: A > B, both X.Y.Z
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<<"$1"; IFS=. read -r b1 b2 b3 <<<"$2"
  (( a1 > b1 || (a1 == b1 && (a2 > b2 || (a2 == b2 && a3 > b3))) ))
}
MANIFEST=plugins/bk/.claude-plugin/plugin.json
version=$(version_of <"$MANIFEST")
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "$MANIFEST: version '$version' isn't X.Y.Z"
else
  top=$(grep -m1 '^## \[' CHANGELOG.md 2>/dev/null)
  [[ "$top" =~ ^"## [$version] - "[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
    || fail "CHANGELOG.md: top entry is '${top:-missing}', want '## [$version] - YYYY-MM-DD'"
  grep -q "/archive/refs/tags/v$version.tar.gz\"" Formula/bk.rb \
    || fail "Formula/bk.rb: url must download v$version (the release workflow fills in the sha256)"
  if ! git rev-parse -q --verify origin/main >/dev/null; then
    echo "   ! no origin/main: version bump not checked"
  elif git merge-base --is-ancestor HEAD origin/main && git diff --quiet HEAD; then
    :  # main itself, or a clean checkout behind it: nothing new to release
  else
    main_version=$(git show "origin/main:$MANIFEST" | version_of)
    newer "$version" "$main_version" \
      || fail "$MANIFEST: version $version must be higher than origin/main's $main_version (every merge is a release)"
  fi
fi
(( ${#FAILED[@]} == before )) && echo "   ✓ v$version"

echo ""
if (( ${#FAILED[@]} == 0 )); then echo "ALL CHECKS PASSED"; else echo "FAILED: ${#FAILED[@]} check(s)"; exit 1; fi
