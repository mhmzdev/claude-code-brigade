#!/usr/bin/env bash
# =============================================================================
# scripts/check.sh — THE gate for changes to the Brigade plugin.
#
# 1. manifests   claude plugin validate (skipped with a warning if no claude CLI)
# 2. script      bash -n + shellcheck on kitchen.sh (shellcheck required)
# 3. skills      frontmatter sanity: name matches folder, description present,
#                disable-model-invocation only on implement and setup
# 4. behaviour   tests/kitchen.test.sh
#
# Exit 0 = safe to push to main (which is the release).
# =============================================================================

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
KITCHEN=plugins/bk/skills/kitchen/kitchen.sh
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

step "2. kitchen.sh"
bash -n "$KITCHEN" && echo "   ✓ bash -n" || fail "bash -n $KITCHEN"
if command -v shellcheck >/dev/null; then
  if out=$(shellcheck -S warning "$KITCHEN" tests/kitchen.test.sh scripts/check.sh 2>&1); then echo "   ✓ shellcheck"
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
  if grep -q '^disable-model-invocation: true' "$f" && [[ "$dir" != implement && "$dir" != setup ]]; then
    fail "$f: disable-model-invocation is only allowed on implement and setup (cooks would stall)"
  fi
done
for f in plugins/bk/agents/*.md; do
  name=$(awk '/^---$/{n++; next} n==1 && /^name:/{print $2; exit}' "$f")
  grep -q "\"./agents/$name.md\"" plugins/bk/.claude-plugin/plugin.json || fail "$f: not listed in plugin.json agents"
done
(( ${#FAILED[@]} == before )) && echo "   ✓ $(ls plugins/bk/skills/*/SKILL.md | wc -l | tr -d ' ') skills, $(ls plugins/bk/agents/*.md | wc -l | tr -d ' ') agents"

step "4. behaviour (tests/kitchen.test.sh)"
if out=$(bash tests/kitchen.test.sh 2>&1); then echo "   ✓ $(printf '%s\n' "$out" | tail -1 | sed 's/^# //')"
else printf '%s\n' "$out" | grep -E '^not ok|^# passed' | sed 's/^/     /'; fail "kitchen tests"; fi

echo ""
if (( ${#FAILED[@]} == 0 )); then echo "ALL CHECKS PASSED"; else echo "FAILED: ${#FAILED[@]} check(s)"; exit 1; fi
