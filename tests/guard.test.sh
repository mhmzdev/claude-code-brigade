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

# The Bash and file-tool rules. gbash <cwd> <command> sends a Bash call (the command is JSON-escaped
# here); gbash_raw takes one already escaped (a \n for a newline). gfile <cwd> <tool> <key> <path>
# sends an Edit/Write-style call. setgrant <main> <station> [action…] writes (or, with no action,
# removes) the sous's grant file, the way kitchen.sh grant does.
gbash_raw() {
  printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"x"}}' "$1" "$2" \
    | "$G" 2>"$TMP/err" >/dev/null; echo $?
}
gbash() { gbash_raw "$1" "$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }')"; }
gfile() {
  printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"%s":"%s","content":"x"}}' "$1" "$2" "$3" "$4" \
    | "$G" 2>"$TMP/err" >/dev/null; echo $?
}
setgrant() {
  local m="$1" st="$2"; shift 2; rm -f "$m/.claude/grants/$st"
  if [[ $# -gt 0 ]]; then mkdir -p "$m/.claude/grants"; printf '%s\n' "$@" > "$m/.claude/grants/$st"; fi
}

# --- a repo with a kitchen next to it, and a station --------------------------
A="$TMP/app"; git init -q "$A"; mkdir -p "$A/.claude"
printf -- '---\ntrunk: main\n---\n' > "$A/.claude/brigade.md"
git -C "$A" add -A; git -C "$A" commit -qm init
git -C "$A" worktree add -q --detach "$TMP/app-stations/station-1" HEAD 2>/dev/null
S="$TMP/app-stations/station-1"
# --- the same with the old kitchen_mode: worktree line, which is ignored ------
B="$TMP/wt/app"; mkdir -p "$TMP/wt"; git init -q "$B"; mkdir -p "$B/.claude"
printf -- '---\ntrunk: main\nkitchen_mode: worktree\n---\n' > "$B/.claude/brigade.md"
git -C "$B" add -A; git -C "$B" commit -qm init
git -C "$B" worktree add -q --detach "$TMP/wt/app-stations/station-1" HEAD 2>/dev/null
WS="$TMP/wt/app-stations/station-1"
# --- things under a Brigade checkout that are NOT stations --------------------
mkdir -p "$A/vendor"; git init -q "$A/vendor/lib"; echo x > "$A/vendor/lib/x"; git -C "$A/vendor/lib" add -A; git -C "$A/vendor/lib" commit -qm init
git -C "$A" worktree add -q --detach "$A/.claude/worktrees/feature" HEAD 2>/dev/null   # claude --worktree
git -C "$A" worktree add -q --detach "$TMP/app-stations/scratch" HEAD 2>/dev/null      # a worktree in the kitchen, not named station-*
mkdir -p "$TMP/elsewhere"; git -C "$A" worktree add -q --detach "$TMP/elsewhere/station-9" HEAD 2>/dev/null   # named station-*, but not in the kitchen
# --- a kitchen: key pointing somewhere else -----------------------------------
K2="$TMP/k2/app"; mkdir -p "$TMP/k2"; git init -q "$K2"; mkdir -p "$K2/.claude" "$K2/benches"
printf -- '---\ntrunk: main\nkitchen: benches\n---\n' > "$K2/.claude/brigade.md"; git -C "$K2" add -A; git -C "$K2" commit -qm init
git -C "$K2" worktree add -q --detach "$K2/benches/station-1" HEAD 2>/dev/null; git -C "$K2" worktree add -q --detach "$K2/stations/station-1" HEAD 2>/dev/null
# --- a plain repo with no Brigade ---------------------------------------------
P="$TMP/plain"; git init -q "$P"; echo x > "$P/x"; git -C "$P" add -A; git -C "$P" commit -qm init

section "outside the Brigade"
ok "a repo without .claude/brigade.md is left alone" test "$(guard "$P" AskUserQuestion)" = 0
ok "garbage on stdin is allowed, not blocked" test "$(printf 'not json' | "$G" >/dev/null 2>&1; echo $?)" = 0
ok "empty stdin is allowed" test "$(printf '' | "$G" >/dev/null 2>&1; echo $?)" = 0

section "the main checkout"
ok "the sous may open a dialog" test "$(guard "$A" AskUserQuestion)" = 0
ok "the sous may send any message" test "$(guard "$A" SendMessage '[gate] Q1 something')" = 0

section "a station"
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
ok "a worktree in the kitchen folder not named station-*" test "$(guard "$TMP/app-stations/scratch" AskUserQuestion)" = 0
ok "a worktree named station-* outside the kitchen" test "$(guard "$TMP/elsewhere/station-9" AskUserQuestion)" = 0
ok "with kitchen: benches, stations/station-1 is not a station" test "$(guard "$K2/stations/station-1" AskUserQuestion)" = 0
ok "…and benches/station-1 is" test "$(guard "$K2/benches/station-1" AskUserQuestion)" = 2

section "a stale grilling marker"
mkdir -p "$S/.claude"; touch -t 202001010000 "$S/.claude/grilling"
ok "a marker older than four hours no longer lets the dialog through" test "$(guard "$S" AskUserQuestion)" = 2
rm "$S/.claude/grilling"

section "a station of a config that still says kitchen_mode: worktree"
ok "a cook's AskUserQuestion is blocked there too" test "$(guard "$WS" AskUserQuestion)" = 2
ok "…and the gate rule applies" test "$(guard "$WS" SendMessage '[gate] #12 Q1 which helper?')" = 2
ok "the worktree repo's main checkout is left alone" test "$(guard "$B" AskUserQuestion)" = 0

# --- positive authorization (Contract 5): a station's outward actions need the sous's grant ------------
# One suite for both stations: $S of $A, and $WS of $B (a config that still says kitchen_mode: worktree).
# A second station on a branch named like trunk lets the "bare push from trunk" rule be tried.
git -C "$A" worktree add -q -b main "$TMP/app-stations/station-2" HEAD 2>/dev/null
git -C "$B" worktree add -q -b main "$TMP/wt/app-stations/station-2" HEAD 2>/dev/null
grant_suite() {
  local label="$1" S="$2" M="$3" T="$4" st c; st="$(basename "$S")"
  section "positive authorization ($label): no grant"
  setgrant "$M" "$st"
  ok "$label: git commit is refused with no grant file" test "$(gbash "$S" 'git commit -m x')" = 2
  ok "$label: …the reason names the missing action, the sous and kitchen.sh grant" bash -c 'for w in "grant for \`commit\`" "the sous grants" "kitchen.sh grant"; do printf "%s" "$1" | grep -qF "$w" || exit 1; done' _ "$(reason)"
  ok "$label: git push is refused" test "$(gbash "$S" 'git push origin feature')" = 2
  ok "$label: …naming push" bash -c 'printf "%s" "$1" | grep -qF "grant for \`push\`"' _ "$(reason)"
  ok "$label: gh pr create is refused" test "$(gbash "$S" 'gh pr create --title x --body y')" = 2
  ok "$label: …naming open-pr" bash -c 'printf "%s" "$1" | grep -qF "grant for \`open-pr\`"' _ "$(reason)"
  while IFS= read -r c; do
    ok "$label: a commit by another route is refused with no grant: $c" test "$(gbash "$S" "$c")" = 2
  done <<'EOT'
git merge origin/main
git pull
git pull --rebase
git rebase origin/main
git cherry-pick abc123
git revert abc123
git am x.patch
git commit --amend --no-edit
EOT
  section "positive authorization ($label): with a grant"
  setgrant "$M" "$st" commit
  ok "$label: commit granted: git commit passes" test "$(gbash "$S" 'git commit -m x')" = 0
  ok "$label: …and so does a merge, which makes a commit" test "$(gbash "$S" 'git merge origin/main')" = 0
  ok "$label: …but git push is still refused" test "$(gbash "$S" 'git push origin feature')" = 2
  ok "$label: …and gh pr create" test "$(gbash "$S" 'gh pr create --title x')" = 2
  setgrant "$M" "$st" push open-pr
  ok "$label: push and open-pr granted, commit not: git commit is refused" test "$(gbash "$S" 'git commit -m x')" = 2
  ok "$label: …git push passes" test "$(gbash "$S" 'git push -u origin feature')" = 0
  ok "$label: …gh pr create passes" test "$(gbash "$S" 'gh pr create --title x')" = 0
  setgrant "$M" "$st" commit push open-pr
  ok "$label: all three granted: git commit passes" test "$(gbash "$S" 'git commit -m x')" = 0
  ok "$label: …git push origin feature:feature passes" test "$(gbash "$S" 'git push origin feature:feature')" = 0
  ok "$label: …gh -R a/b pr create passes" test "$(gbash "$S" 'gh -R a/b pr create --title x')" = 0

  section "positive authorization ($label): refused whatever is granted"
  while IFS= read -r c; do
    ok "$label: refused with every grant: $c" test "$(gbash "$S" "$c")" = 2
  done <<'EOT'
git push origin main
git push origin HEAD:main
git push origin HEAD:refs/heads/main
git push origin feature:main
git push origin :main
git push --force origin feature
git push -f origin feature
git push -fu origin feature
git push --force-with-lease origin feature
git push origin +feature
git push --all
git push --mirror
git push --delete origin feature
git push -d origin feature
gh pr merge 12
gh pr merge --auto --squash 12
gh -R a/b pr merge 12
git reset --hard
git reset --hard origin/main
git clean -fdx
git clean -xfd
git clean -fdX
git clean -x
EOT
  ok "$label: …a push to trunk says the sous merges" bash -c 'git_out="$1"; printf "%s" "$git_out" | grep -q "the sous merges"' _ "$( gbash "$S" 'git push origin main' >/dev/null; reason)"
  ok "$label: …gh pr merge says nothing grants it" bash -c 'printf "%s" "$1" | grep -q "never granted"' _ "$( gbash "$S" 'gh pr merge 1' >/dev/null; reason)"
  setgrant "$M" "$(basename "$T")" push   # with push granted, only the trunk rule can refuse these
  ok "$label: a bare git push from a station that stands on trunk is refused" test "$(gbash "$T" 'git push')" = 2
  ok "$label: …and git push origin HEAD" test "$(gbash "$T" 'git push origin HEAD')" = 2
  ok "$label: …but a push of a named branch from it is judged by its target" test "$(gbash "$T" 'git push origin feature')" = 0
  setgrant "$M" "$(basename "$T")"

  section "positive authorization ($label): what passes"
  while IFS= read -r c; do
    ok "$label: passes with every grant: $c" test "$(gbash "$S" "$c")" = 0
  done <<'EOT'
git push -u origin feature
git merge --ff-only origin/main
git pull --ff-only
git merge --abort
git rebase --abort
git cherry-pick --abort
git reset --soft HEAD~1
git reset HEAD file.txt
git clean -fd
git clean -n
EOT
  setgrant "$M" "$st"
  while IFS= read -r c; do
    ok "$label: passes with no grant at all: $c" test "$(gbash "$S" "$c")" = 0
  done <<'EOT'
git status
git diff origin/main
git log --oneline -3
git log --grep "git push"
git add -A
git switch -c issue-1-x origin/main
git fetch origin
git merge --ff-only origin/main
git pull --ff-only
git merge --abort
git rebase --abort
git stash push -u -m "station-1: x"
gh pr view 1
gh pr checks 1
gh issue view 91
gh pr list --head x
echo hello
ls .claude
kitchen.sh grant --show
kitchen.sh rail claim '#91' todo
kitchen.sh check
EOT

  section "positive authorization ($label): the word that runs"
  while IFS= read -r c; do
    ok "$label: found and refused with no grant: $c" test "$(gbash "$S" "$c")" = 2
  done <<'EOT'
cd x && git commit -m y
ls; git push origin feature
git -C /tmp commit -m y
git -c user.name=a push origin feature
GIT_AUTHOR_NAME=a git commit -m y
env git commit -m y
sudo git commit -m y
nohup git push origin feature
bash -c "git commit -m y"
sh -c 'git push origin feature'
echo $(git push origin feature)
echo `git commit -m y`
true || git commit -m y
(git commit -m y)
{ git push origin feature; }
/usr/bin/git commit -m y
/opt/homebrew/bin/gh pr create --title x
gh --repo a/b pr create --title x
if true; then git commit -m y; fi
git commit -m "fix git push bug"
EOT
  while IFS= read -r c; do
    ok "$label: a quoted argument is not a command (no grant): $c" test "$(gbash "$S" "$c")" = 0
  done <<'EOT'
echo "git push origin feature"
git grep -n "git commit" origin/main -- plugins
grep -rn 'git push' docs
kitchen.sh here --note "git push done"
gh issue comment 91 --body "run git commit later"
EOT
  ok "$label: a command on a second line (a JSON \\n) is found" test "$(gbash_raw "$S" 'echo hi\ngit commit -m y')" = 2
  ok "$label: a quote inside the command (JSON-escaped) is read through" test "$(gbash "$S" 'git commit -m "a \"quoted\" word"')" = 2
  ok "$label: a heredoc commit message is a commit" test "$(gbash_raw "$S" 'git commit -F - <<EOF\nmsg\nEOF')" = 2
  ok "$label: a call whose text cannot be read passes" test "$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":' "$S" | "$G" >/dev/null 2>&1; echo $?)" = 0
  ok "$label: an unbalanced quote never crashes the hook" bash -c 'r="$1"; [ "$r" = 0 ] || [ "$r" = 2 ]' _ "$(gbash "$S" 'echo "git push')"

  section "positive authorization ($label): quoting, heredocs, continuations, wrappers"
  setgrant "$M" "$st"
  while IFS= read -r c; do
    ok "$label: quoted text is not a command (no grant): $c" test "$(gbash "$S" "$c")" = 0
  done <<'EOT'
grep -rn 'git commit\|git push' plugins
rg 'git commit|git push' .
git log --grep 'x; git push'
git log --grep "x && git commit"
kitchen.sh here --note 'done; git push next'
echo "a && git push && gh pr merge 1"
echo $((1<<2))
EOT
  setgrant "$M" "$st" commit
  ok "$label: a heredoc commit message that names commands passes with commit granted" test "$(gbash "$S" $'git commit -m "$(cat <<\'EOF\'\nfix it\n\nrefuses `gh pr merge` and git reset --hard, then git push\nEOF\n)"')" = 0
  ok "$label: …an unquoted heredoc body too" test "$(gbash "$S" $'git commit -F - <<\'EOF\'\ngit push is the next step\ngh pr merge 1\nEOF')" = 0
  ok "$label: …a command after the heredoc is still judged" test "$(gbash "$S" $'git commit -F - <<EOF\nmsg\nEOF\ngit push origin feature')" = 2
  ok "$label: …and a heredoc starting an arithmetic << does not hide the next line" test "$(gbash "$S" $'echo $((1<<2))\ngit push origin feature')" = 2
  setgrant "$M" "$st"
  while IFS= read -r c; do
    ok "$label: found and refused with no grant: $c" test "$(gbash "$S" "$c")" = 2
  done <<'EOT'
\git push origin feature
\env git push origin feature
\sudo git commit -m y
eval git push origin feature
eval "git push origin feature"
sudo -u deploy git push origin feature
sudo -E -g staff git commit -m y
env -u FOO git commit -m y
env -i PATH=x git push origin feature
timeout 5 git push origin feature
nice -n 5 git commit -m y
echo "$(git push origin feature)"
X="$(git commit -m y)"
echo "`git commit -m y`"
sh -c 'git push'
bash -c "echo hi; git commit -m y"
bash -c "git commit -m 'a; b'"
/bin/sh -c "git push origin feature"
bash -lc 'git push origin feature'
EOT
  setgrant "$M" "$st" commit push open-pr
  ok "$label: a trunk push split by backslash-newline is refused" test "$(gbash "$S" $'git push \\\n origin main')" = 2
  ok "$label: …a force split by backslash-newline" test "$(gbash "$S" $'git push origin \\\n --force-with-lease')" = 2
  ok "$label: …a continued push of a feature branch passes" test "$(gbash "$S" $'git push \\\n origin feature')" = 0
  ok "$label: …a continuation with the grant missing is refused" test "$(setgrant "$M" "$st" commit; gbash "$S" $'git push \\\n origin feature')" = 2
  ok "$label: a push to trunk inside \$( ) in double quotes is refused" test "$(setgrant "$M" "$st" commit push open-pr; gbash "$S" 'echo "$(git push origin main)"')" = 2
  ok "$label: the refusal says to reword quoted text" bash -c 'printf "%s" "$1" | grep -q "reword it"' _ "$(setgrant "$M" "$st"; gbash "$S" 'git push origin feature' >/dev/null; reason)"
  setgrant "$M" "$st"

  section "positive authorization ($label): the grants folder and the receipts"
  setgrant "$M" "$st" commit push open-pr
  ok "$label: a Bash command that names the grants folder is refused, granted or not" test "$(gbash "$S" "cat $M/.claude/grants/$st")" = 2
  ok "$label: …a write to it" test "$(gbash "$S" "echo push > $M/.claude/grants/$st")" = 2
  ok "$label: …even with no git or gh in the command" test "$(gbash "$S" 'rm -f ../app/.claude/grants/station-1')" = 2
  ok "$label: Write to the sous's grant file is refused" test "$(gfile "$S" Write file_path "$M/.claude/grants/$st")" = 2
  ok "$label: …Edit of another station's grant too" test "$(gfile "$S" Edit file_path "$M/.claude/grants/station-9")" = 2
  for c in check.log procs served; do
    ok "$label: Write to <station>/.claude/$c is refused" test "$(gfile "$S" Write file_path "$S/.claude/$c")" = 2
    ok "$label: …Edit" test "$(gfile "$S" Edit file_path "$S/.claude/$c")" = 2
    ok "$label: …MultiEdit" test "$(gfile "$S" MultiEdit file_path "$S/.claude/$c")" = 2
  done
  ok "$label: …the reason names who writes it" bash -c 'printf "%s" "$1" | grep -q "kitchen.sh"' _ "$(gfile "$S" Write file_path "$S/.claude/check.log" >/dev/null; reason)"
  ok "$label: NotebookEdit of .claude/procs through notebook_path is refused" test "$(gfile "$S" NotebookEdit notebook_path "$S/.claude/procs")" = 2
  mkdir -p "$S/src"
  ok "$label: a relative path from a subfolder that lands on check.log is refused" test "$(gfile "$S/src" Write file_path "../.claude/check.log")" = 2
  ok "$label: a path through ./ and .. is resolved first" test "$(gfile "$S" Write file_path "$S/src/../.claude/./procs")" = 2
  ok "$label: Write to a file in the station passes" test "$(gfile "$S" Write file_path "$S/src/x.txt")" = 0
  ok "$label: …to the station's own .claude/grilling" test "$(gfile "$S" Write file_path "$S/.claude/grilling")" = 0
  ok "$label: …to its .claude/here" test "$(gfile "$S" Write file_path "$S/.claude/here")" = 0
  ok "$label: …to a file named check.log in a subfolder" test "$(gfile "$S" Write file_path "$S/src/check.log")" = 0
  ok "$label: …to another station's check.log is not this rule's business" test "$(gfile "$S" Write file_path "$T/.claude/check.log")" = 0
  ok "$label: an Edit whose path cannot be read passes" test "$(printf '{"cwd":"%s","tool_name":"Edit","tool_input":{}}' "$S" | "$G" >/dev/null 2>&1; echo $?)" = 0
  setgrant "$M" "$st"
}
grant_suite "station" "$S" "$A" "$TMP/app-stations/station-2"
grant_suite "legacy-config station" "$WS" "$B" "$TMP/wt/app-stations/station-2"

section "positive authorization: left alone outside a station"
setgrant "$A" station-1
for c in 'git commit -m x' 'git push origin main' 'git push --force' 'gh pr merge 1' 'git reset --hard' 'git clean -fdx' 'git merge origin/main'; do
  ok "the main checkout: $c" test "$(gbash "$A" "$c")" = 0
  ok "a repo without the Brigade: $c" test "$(gbash "$P" "$c")" = 0
  ok "a nested repo under the checkout: $c" test "$(gbash "$A/vendor/lib" "$c")" = 0
  ok "Claude Code's own --worktree session: $c" test "$(gbash "$A/.claude/worktrees/feature" "$c")" = 0
  ok "a worktree in the kitchen not named station-*: $c" test "$(gbash "$TMP/app-stations/scratch" "$c")" = 0
  ok "a worktree named station-* outside the kitchen: $c" test "$(gbash "$TMP/elsewhere/station-9" "$c")" = 0
done
ok "the sous may write the grant file from the main checkout" test "$(gfile "$A" Write file_path "$A/.claude/grants/station-1")" = 0
ok "the main checkout's own .claude/check.log is not a station's" test "$(gfile "$A" Write file_path "$A/.claude/check.log")" = 0
ok "the main checkout may name the grants folder in a command" test "$(gbash "$A" "cat $A/.claude/grants/station-1")" = 0
ok "a repo without the Brigade may write a check.log" test "$(gfile "$P" Write file_path "$P/.claude/check.log")" = 0

echo ""
echo "# passed $PASS · failed $FAIL · total $N"
(( FAIL == 0 ))
