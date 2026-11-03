#!/usr/bin/env bash
# =============================================================================
# scripts/check.sh — THE gate for changes to the Brigade plugin.
#
# 1. manifests   claude plugin validate (skipped with a warning if no claude CLI)
# 2. script      bash -n + shellcheck on kitchen.sh, hooks/guard.sh and bin/bk (shellcheck required)
# 3. skills      frontmatter sanity: name matches folder, description present,
#                disable-model-invocation only on setup
# 4. behaviour   tests/kitchen.test.sh, tests/guard.test.sh, tests/bk.test.sh, tests/budget.test.sh, tests/window.test.sh and tests/release.test.sh
# 5. release     scripts/release-check.sh: plugin.json's version is the top CHANGELOG.md entry
#                and the one Formula/bk.rb downloads; and, on a branch, a PR that changes
#                only docs/ carries nothing, a release PR raises the version, and any other
#                PR adds a changelog.d/ fragment and leaves the version alone (the release PR,
#                scripts/release.sh, assigns it)
#
# Exit 0 = safe to merge.
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
  if out=$(shellcheck -S warning "$KITCHEN" "$GUARD" "$BK" tests/kitchen.test.sh tests/guard.test.sh tests/bk.test.sh tests/budget.test.sh tests/window.test.sh tests/release.test.sh scripts/check.sh scripts/release-check.sh scripts/release.sh 2>&1); then echo "   ✓ shellcheck"
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

step "4. behaviour (tests/kitchen.test.sh, tests/guard.test.sh, tests/bk.test.sh, tests/budget.test.sh, tests/window.test.sh, tests/release.test.sh)"
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
if out=$(bash tests/release.test.sh 2>&1); then echo "   ✓ release: $(printf '%s\n' "$out" | tail -1 | sed 's/^# //')"
else printf '%s\n' "$out" | grep -E '^not ok|^# passed|^Bail' | sed 's/^/     /'; fail "release tests"; fi

step "5. release (version, CHANGELOG.md, Formula/bk.rb, changelog.d/)"
if out=$(bash scripts/release-check.sh 2>&1); then printf '%s\n' "$out"
else printf '%s\n' "$out"; fail "release check"; fi

echo ""
if (( ${#FAILED[@]} == 0 )); then echo "ALL CHECKS PASSED"; else echo "FAILED: ${#FAILED[@]} check(s)"; exit 1; fi
