#!/usr/bin/env bash
# =============================================================================
# hooks/guard.sh — the Brigade's PreToolUse guard (Contract 5 and 12, mechanical).
#
# Two rules that used to rest on a cook remembering them:
#   1. In a station, AskUserQuestion is refused unless a grilling is under way
#      (<station>/.claude/grilling exists: grill-me and brainstorm write it when
#      they start in a station, and remove it when they finish). Nobody watches
#      a cook's terminal, so a dialog there only stalls the station.
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

# Which checkout is this, and is it a station? A clone-mode station is a full
# clone (it carries .claude/brigade.md itself) inside a parent checkout that has
# one: walk up from the checkout's parent and the first repo with the config is
# the main checkout. A worktree station shares git's common dir with the main
# checkout, so that dir's parent is it. Neither found → not a station.
top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
top="$(cd "$top" && pwd -P)"
main=""
d="$(dirname "$top")"
while [[ "$d" != / && -n "$d" ]]; do
  if [[ -f "$d/.claude/brigade.md" ]] && [[ "$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" == "$d" ]]; then main="$d"; break; fi
  d="$(dirname "$d")"
done
if [[ -z "$main" ]] && common="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  c="$(cd "$(dirname "$common")" 2>/dev/null && pwd -P)"
  [[ "$c" != "$top" && -f "$c/.claude/brigade.md" ]] && main="$c"
fi
[[ -n "$main" ]] || exit 0   # the main checkout itself, a solo repo, or no Brigade at all

case "$tool" in
  AskUserQuestion)
    [[ -e "$top/.claude/grilling" ]] && exit 0
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
