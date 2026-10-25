#!/usr/bin/env bash
# =============================================================================
# tests/guard.test.sh — behaviour tests for plugins/bk/hooks/guard.sh, the
# PreToolUse guard. Feeds it the JSON Claude Code sends and checks the exit code:
# 0 lets the tool call through, 2 blocks it with the reason on stderr.
# Throwaway repos only; nothing touches the real machine.
# =============================================================================
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
G="$REPO/plugins/bk/hooks/guard.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/brigade-guard.XXXXXX")"
export HOME="$TMP/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
  GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
  GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
mkdir -p "$HOME"
cleanup() { [[ -n "${KEEP:-}" ]] && echo "kept: $TMP" || rm -rf "$TMP"; }
trap cleanup EXIT

PASS=0; FAIL=0; N=0
ok() { local desc="$1"; shift; N=$((N+1)); if ( "$@" ) >/dev/null 2>&1; then PASS=$((PASS+1)); echo "ok $N - $desc"; else FAIL=$((FAIL+1)); echo "not ok $N - $desc"; fi; }
section() { echo "# $1"; }

# guard <cwd> <tool> <message> → runs the hook as Claude Code would; prints the exit
# code, and leaves the reason (stderr) in $TMP/err for the next assertion to read.
guard() {
  local cwd="$1" tool="$2" msg="${3:-}"
  printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"to":"app-sous","message":"%s"}}' "$cwd" "$tool" "$msg" \
    | "$G" 2>"$TMP/err" >/dev/null; echo $?
}
reason() { cat "$TMP/err"; }

# --- a repo with a kitchen in clone mode, and a station -----------------------
A="$TMP/app"; git init -q "$A"; mkdir -p "$A/.claude" "$A/stations"
printf -- '---\ntrunk: main\n---\n' > "$A/.claude/brigade.md"
git -C "$A" add -A; git -C "$A" commit -qm init
git clone -q "$A" "$A/stations/station-1" 2>/dev/null
S="$A/stations/station-1"
# --- a worktree station next to a repo ----------------------------------------
B="$TMP/wt/app"; mkdir -p "$TMP/wt"; git init -q "$B"; mkdir -p "$B/.claude"
printf -- '---\ntrunk: main\nkitchen_mode: worktree\n---\n' > "$B/.claude/brigade.md"
git -C "$B" add -A; git -C "$B" commit -qm init
git -C "$B" worktree add -q --detach "$TMP/wt/app-stations/station-1" HEAD 2>/dev/null
WS="$TMP/wt/app-stations/station-1"
# --- things under a Brigade checkout that are NOT stations --------------------
mkdir -p "$A/vendor"; git init -q "$A/vendor/lib"; echo x > "$A/vendor/lib/x"; git -C "$A/vendor/lib" add -A; git -C "$A/vendor/lib" commit -qm init
git -C "$A" worktree add -q --detach "$A/.claude/worktrees/feature" HEAD 2>/dev/null   # claude --worktree
mkdir -p "$A/stations"; git clone -q "$A" "$A/stations/scratch" 2>/dev/null            # a clone in the kitchen, not named station-*
mkdir -p "$TMP/elsewhere"; git clone -q "$A" "$TMP/elsewhere/station-9" 2>/dev/null     # named station-*, but not in the kitchen
# --- a kitchen: key pointing somewhere else -----------------------------------
K2="$TMP/k2/app"; mkdir -p "$TMP/k2"; git init -q "$K2"; mkdir -p "$K2/.claude" "$K2/benches"
printf -- '---\ntrunk: main\nkitchen: benches\n---\n' > "$K2/.claude/brigade.md"; git -C "$K2" add -A; git -C "$K2" commit -qm init
git clone -q "$K2" "$K2/benches/station-1" 2>/dev/null; mkdir -p "$K2/stations"; git clone -q "$K2" "$K2/stations/station-1" 2>/dev/null
# --- a plain repo with no Brigade ---------------------------------------------
P="$TMP/plain"; git init -q "$P"; echo x > "$P/x"; git -C "$P" add -A; git -C "$P" commit -qm init

section "outside the Brigade"
ok "a repo without .claude/brigade.md is left alone" test "$(guard "$P" AskUserQuestion)" = 0
ok "garbage on stdin is allowed, not blocked" test "$(printf 'not json' | "$G" >/dev/null 2>&1; echo $?)" = 0
ok "empty stdin is allowed" test "$(printf '' | "$G" >/dev/null 2>&1; echo $?)" = 0

section "the main checkout"
ok "the sous may open a dialog" test "$(guard "$A" AskUserQuestion)" = 0
ok "the sous may send any message" test "$(guard "$A" SendMessage '[gate] Q1 something')" = 0

section "a clone-mode station"
ok "a cook's AskUserQuestion is blocked" test "$(guard "$S" AskUserQuestion)" = 2
ok "…with the reason naming the station and the gate" bash -c 'printf "%s" "$1" | grep -q "line cook in station-1" && printf "%s" "$1" | grep -q "\[gate\]"' _ "$(reason)"
ok "…from a subfolder of the station too" test "$(mkdir -p "$S/src" && guard "$S/src" AskUserQuestion)" = 2
mkdir -p "$S/.claude"; touch "$S/.claude/grilling"
ok "during a grilling (.claude/grilling exists) the dialog is allowed" test "$(guard "$S" AskUserQuestion)" = 0
rm "$S/.claude/grilling"
ok "a [gate] with a question and no commis result is blocked" test "$(guard "$S" SendMessage '[gate] BKLG-004 Q3, see journal')" = 2
ok "…and the reason says to spawn the commis" bash -c 'printf "%s" "$1" | grep -q "bk:commis"' _ "$(reason)"
ok "a [gate] carrying the commis result passes" test "$(guard "$S" SendMessage '[gate] BKLG-004 Q3, see journal. commis: nothing recorded in decisions, specs, journals')" = 0
ok "a [gate] carrying a precedent the commis found passes (Contract 6)" test "$(guard "$S" SendMessage '[gate] BKLG-004 Q3, see journal. commis: precedent in src/providers/a.ts, src/providers/b.ts, but they differ on refunds')" = 0
ok "a [gate] with no numbered question passes (needs grilling, test account)" test "$(guard "$S" SendMessage '[gate] BKLG-004 needs grilling: scope')" = 0
ok "a [gate] about a test account passes" test "$(guard "$S" SendMessage '[gate] BKLG-004 need a test account: stage, builder')" = 0
ok "any other message kind passes" test "$(guard "$S" SendMessage '[check-in] station-1 sonnet clean no ticket fresh waiting: nothing')" = 0
ok "an unrelated tool passes" test "$(guard "$S" Edit)" = 0

section "not a station: left alone"
ok "a nested repo or submodule under the checkout" test "$(guard "$A/vendor/lib" AskUserQuestion)" = 0
ok "Claude Code's own --worktree session" test "$(guard "$A/.claude/worktrees/feature" AskUserQuestion)" = 0
ok "a clone in the kitchen folder not named station-*" test "$(guard "$A/stations/scratch" AskUserQuestion)" = 0
ok "a clone named station-* outside the kitchen" test "$(guard "$TMP/elsewhere/station-9" AskUserQuestion)" = 0
ok "with kitchen: benches, stations/station-1 is not a station" test "$(guard "$K2/stations/station-1" AskUserQuestion)" = 0
ok "…and benches/station-1 is" test "$(guard "$K2/benches/station-1" AskUserQuestion)" = 2

section "a stale grilling marker"
mkdir -p "$S/.claude"; touch -t 202001010000 "$S/.claude/grilling"
ok "a marker older than four hours no longer lets the dialog through" test "$(guard "$S" AskUserQuestion)" = 2
rm "$S/.claude/grilling"

section "a worktree station"
ok "a cook's AskUserQuestion is blocked there too" test "$(guard "$WS" AskUserQuestion)" = 2
ok "…and the gate rule applies" test "$(guard "$WS" SendMessage '[gate] #12 Q1 which helper?')" = 2
ok "the worktree repo's main checkout is left alone" test "$(guard "$B" AskUserQuestion)" = 0

echo ""
echo "# passed $PASS · failed $FAIL · total $N"
(( FAIL == 0 ))
