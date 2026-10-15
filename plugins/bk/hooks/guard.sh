#!/usr/bin/env bash
# =============================================================================
# hooks/guard.sh — the Brigade's PreToolUse guard (Contract 5 and 12, mechanical).
#
# Two rules that used to rest on a cook remembering them:
#   1. In a station, AskUserQuestion is refused unless a grilling is under way
#      (<station>/.claude/grilling exists and is under four hours old: grill-me
#      and brainstorm write it when they start in a station, and remove it when
#      they finish; a stale one from a cleared session doesn't count). Nobody
#      watches a cook's terminal, so a dialog there only stalls the station.
#   2. A [gate] message that carries a numbered question (Q3) is refused when it
#      names no commis result ("commis:"): look it up before you ask.
#
# Everything else passes. The hook exits 0 at once outside a Brigade repo (no
# .claude/brigade.md up the tree) and in the main checkout, so it never touches a
# solo session or another project. Blocking is exit 2 with the reason on stderr.
# No jq: the fields are pulled out of the stdin JSON with sed, defensively; when
# a field can't be read, the call is allowed.
# =============================================================================
set -u

input="$(cat 2>/dev/null)" || exit 0
tool="$(printf '%s' "$input" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[[ -n "$tool" ]] || exit 0
cwd="$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
cwd="${cwd:-${BRIGADE_HOOK_CWD:-$PWD}}"
[[ -d "$cwd" ]] || exit 0

# Which checkout is this, and is it a station? The same test kitchen.sh uses: the
# folder is named station-*, and it sits in the kitchen of a main checkout that has
# .claude/brigade.md. The kitchen is the config's `kitchen:` key, else stations/
# under the main checkout (clone mode) or ../<repo>-stations next to it (worktree
# mode). A nested repo, a submodule, or Claude Code's own --worktree session is
# none of those, and the human is at that terminal: leave them alone.
top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
top="$(cd "$top" && pwd -P)"
case "$(basename "$top")" in station-*) ;; *) exit 0 ;; esac
kitchen="$(cd "$(dirname "$top")" && pwd -P)"
main=""
# clone mode: the kitchen folder is inside the main checkout
d="$(dirname "$kitchen")"
while [[ "$d" != / && -n "$d" ]]; do
  if [[ -f "$d/.claude/brigade.md" ]] && [[ "$(cd "$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || echo /nonexistent)" 2>/dev/null && pwd -P)" == "$d" ]]; then main="$d"; break; fi
  d="$(dirname "$d")"
done
# worktree mode: the station shares git's common dir with the main checkout
if [[ -z "$main" ]] && common="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  c="$(cd "$(dirname "$common")" 2>/dev/null && pwd -P)"
  [[ -n "$c" && "$c" != "$top" && -f "$c/.claude/brigade.md" ]] && main="$c"
fi
[[ -n "$main" ]] || exit 0
# and the kitchen must be the one the config names (or the mode's default)
cfg_kitchen="$(sed -n '2,/^---$/{s/^kitchen:[[:space:]]*//p;}' "$main/.claude/brigade.md" | head -1 | sed 's/[[:space:]]*#.*$//; s/^"//; s/"$//')"
want=""
if [[ -n "$cfg_kitchen" ]]; then
  case "$cfg_kitchen" in /*) want="$cfg_kitchen" ;; *) want="$main/$cfg_kitchen" ;; esac
  want="$(cd "$want" 2>/dev/null && pwd -P)"
  [[ "$kitchen" == "$want" ]] || exit 0
else
  sibling="$(cd "$(dirname "$main")/$(basename "$main")-stations" 2>/dev/null && pwd -P)"
  [[ "$kitchen" == "$main/stations" || ( -n "$sibling" && "$kitchen" == "$sibling" ) ]] || exit 0
fi

case "$tool" in
  AskUserQuestion)
    # a grilling marker younger than four hours lets the dialog through; an older one
    # was left behind by a cleared or crashed grilling and no longer counts
    if [[ -e "$top/.claude/grilling" ]] && [[ -n "$(find "$top/.claude/grilling" -mmin -240 2>/dev/null)" ]]; then exit 0; fi
    echo "Brigade: you are a line cook in $(basename "$top"); nobody watches this terminal. Don't open a dialog: send the sous a [gate] (Contract 5). A grilling the sous briefed you for writes .claude/grilling first." >&2
    exit 2 ;;
  SendMessage)
    msg="$(printf '%s' "$input" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -1)"
    [[ -n "$msg" ]] || exit 0
    case "$msg" in
      '[gate]'*|'\[gate\]'*) ;;
      *) exit 0 ;;
    esac
    printf '%s' "$msg" | grep -qE '(^|[^A-Za-z])Q[0-9]+' || exit 0
    printf '%s' "$msg" | grep -qi 'commis:' && exit 0
    echo "Brigade: a [gate] with a question goes up with the commis's result in it (\"commis: nothing recorded in <places>\", or the decision it found). Spawn bk:commis first, then send the gate (Contract 5)." >&2
    exit 2 ;;
esac
exit 0
