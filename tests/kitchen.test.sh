#!/usr/bin/env bash
# =============================================================================
# tests/kitchen.test.sh — behaviour tests for plugins/bk/skills/kitchen/kitchen.sh
#
# Builds throwaway repos in a temp dir (a bare "origin", a workspace repo that
# gitignores an app repo inside it) and drives kitchen.sh in both kitchen
# modes. Nothing touches the real machine:
#   - git runs with GIT_CONFIG_GLOBAL=/dev/null, so your own config can't hide a bug;
#   - HOME points into the temp dir, so Warp configs land there;
#   - `open` only ever runs with --terminal print or --no-launch, and the native
#     launchers it looks for are stubs on a fake PATH, so no window ever opens.
#
# Usage:   tests/kitchen.test.sh            (exit 0 = all passed)
#          KEEP=1 tests/kitchen.test.sh     (keep the temp dir for poking at)
# =============================================================================

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K="$REPO/plugins/bk/skills/kitchen/kitchen.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/brigade-test.XXXXXX")"
REAL_HOME="$HOME"

export HOME="$TMP/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
  GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
  GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset CLAUDE_CONFIG_DIR BRIGADE_TRUNK BRIGADE_KITCHEN BRIGADE_KITCHEN_MODE BRIGADE_STATIONS \
  BRIGADE_MODEL BRIGADE_PERMISSION_MODE BRIGADE_TERMINAL BRIGADE_OS
mkdir -p "$HOME"

cleanup() { [[ -n "${KEEP:-}" ]] && echo "kept: $TMP" || rm -rf "$TMP"; }
trap cleanup EXIT

# A sealed PATH: every tool kitchen.sh uses, and nothing it must not find on this machine
# (tmux, brew, Warp, node), so the terminal it picks depends on the test, not the laptop.
NB="$TMP/sealedbin"; mkdir -p "$NB"; export BRIGADE_TMUX_DIRS=""
for t in git bash sh awk sed grep head tail cat mkdir rm cp mv ls ps lsof readlink chmod nohup sleep printf kill uname dirname basename sort uniq wc tr find date mktemp cut env touch tar xargs diff paste seq rev tee stat id gh curl python3 open; do p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$NB/$t"; done

PASS=0; FAIL=0; N=0
ok() {  # ok <description> <command…>: passes when the command exits 0
  local desc="$1"; shift; N=$((N+1))
  if ( "$@" ) >/dev/null 2>&1; then PASS=$((PASS+1)); echo "ok $N - $desc"
  else FAIL=$((FAIL+1)); echo "not ok $N - $desc"; fi
}
has() { printf '%s' "$1" | grep -qE -- "$2"; }   # has <text> <regex>
section() { echo "# $1"; }

# new_repo <dir> <config-body>: a clone of a fresh bare origin on trunk main, with a
# config and two tickets written but NOT committed, so setup's push guard can be tested.
new_repo() {
  local dir="$1" body="$2"
  git init -q --bare "$dir.git"
  git clone -q "$dir.git" "$dir" 2>/dev/null
  git -C "$dir" checkout -q -b main
  mkdir -p "$dir/.claude" "$dir/docs/backlog"
  printf -- '---\n%s\n---\n' "$body" > "$dir/.claude/brigade.md"
  printf -- '---\nid: BKLG-001\ntitle: Open ticket\nlane: B\nkind: bug\nstatus: backlog\ncook: null\n---\n' > "$dir/docs/backlog/BKLG-001-open.md"
  printf -- '---\nid: BKLG-002\ntitle: Done ticket\nlane: B\nstatus: done\ncook: null\n---\n' > "$dir/docs/backlog/BKLG-002-done.md"
}
push_all() { git -C "$1" add -A && git -C "$1" commit -qm "$2" && git -C "$1" push -q -u origin main 2>/dev/null; }

# =============================================================================
section "clone mode (the default)"
# =============================================================================
C="$TMP/clone/app"; mkdir -p "$TMP/clone"
new_repo "$C" 'trunk: main
install: "true"
copy_into_stations: ".env"
stations: 2
migrations: db/migrations'
echo "SECRET=1" > "$C/.env"; echo ".env" > "$C/.gitignore"
cd "$C" || exit 1

out=$("$K" setup 2>&1); rc=$?
ok "setup refuses while the config isn't pushed" test "$rc" -ne 0
ok "…and says why" has "$out" "no \.claude/brigade\.md"
ok "…and creates no station" test ! -e "$C/stations"
out=$("$K" open --terminal print 2>&1); rc=$?
ok "open with no stations tries to create them, and refuses for the same reason" bash -c 'test "$1" -ne 0 && printf "%s" "$2" | grep -q "No stations yet: creating 2" && printf "%s" "$2" | grep -q "no \.claude/brigade\.md"' _ "$rc" "$out"
ok "…creating none" test ! -e "$C/stations"

push_all "$C" "brigade setup"
out=$("$K" open --terminal print 2>&1)
ok "a first open creates the stations itself (nobody has to know setup exists)" has "$out" "No stations yet: creating 2"
ok "…and opens them in the same run" has "$out" "--name app-cook-2"
ok "…without setup's own Next: line" bash -c '! printf "%s" "$1" | grep -q "Next: kitchen.sh open"' _ "$out"
out=$("$K" setup 2>&1)
ok "setup creates station-1 and station-2" test -d "$C/stations/station-1/.git" -a -d "$C/stations/station-2/.git"
ok "stations are full clones (.git is a directory)" test -d "$C/stations/station-2/.git"
ok "setup gitignores /stations/ in the repo" grep -qx "/stations/" "$C/.gitignore"
ok "setup copies copy_into_stations files" test -f "$C/stations/station-1/.env"
ok "setup seeds settings.local.json" test -f "$C/stations/station-1/.claude/settings.local.json"
ok "setup keeps the grilling marker out of the station's status" grep -qx ".claude/grilling" "$C/stations/station-1/.git/info/exclude"
ok "fresh stations are clean (seeded files excluded)" test -z "$(git -C "$C/stations/station-1" status --porcelain)"
ok "setup prints the git clean -fdx warning" has "$out" "git clean -fdx"
ok "setup says cooks start already running /bk:line-cook" has "$out" "cooks start already running"
out=$("$K" setup 2>&1)
ok "setup is idempotent (existing stations left alone)" has "$out" "station-1: exists"
out=$("$K" setup -n 3 2>&1)
ok "setup -n grows the kitchen, keeping existing stations" has "$out" "station-2: exists"
ok "…and adding the new one" test -d "$C/stations/station-3/.git"
out=$("$K" open --terminal print)
ok "open without -n takes every station, not just the configured count" has "$out" "--name app-cook-3"
out=$("$K" open --terminal print -n 2)
ok "open -n N takes only the first N" bash -c "! printf '%s' \"\$1\" | grep -q app-cook-3" _ "$out"
rm -rf "$C/stations/station-3"

# A cook already at work: a stub claude sleeping in station-1 (killed right after).
CB="$TMP/cookbin"; mkdir -p "$CB"; printf '#!/bin/sh\nsleep 30\n' > "$CB/claude"; chmod +x "$CB/claude"
(cd "$C/stations/station-1" && exec "$CB/claude") & COOK=$!
sleep 1
out=$("$K" open --terminal print -m "o s")
ok "open leaves a station with a running cook alone" has "$out" "left alone: station-1"
ok "…opening only the free ones" bash -c "! printf '%s' \"\$1\" | grep -q 'name app-cook-1'" _ "$out"
ok "…and each keeps its own model" has "$out" "app-cook-2 --model sonnet"
(cd "$C/stations/station-2" && exec "$CB/claude") & COOK2=$!
sleep 1
out=$("$K" open --terminal print)
ok "open with every station busy opens nothing" has "$out" "Every station has a cook"
pkill -P "$COOK" 2>/dev/null; pkill -P "$COOK2" 2>/dev/null; kill "$COOK" "$COOK2" 2>/dev/null; wait "$COOK" "$COOK2" 2>/dev/null

ok "role is main in the main checkout" test "$("$K" role | cut -d' ' -f1)" = main
mkdir -p "$C/stations/station-2/lib/deep"
ok "role is cook from a station subfolder" test "$(cd "$C/stations/station-2/lib/deep" && "$K" role | cut -d' ' -f1-2)" = "cook station-2"
ok "role from a station names the main checkout" has "$(cd "$C/stations/station-1" && "$K" role)" "$(cd "$C" && pwd -P)\$"

out=$("$K" rail)
ok "rail lists open tickets" has "$out" "BKLG-001"
ok "rail hides done tickets" bash -c "! printf '%s' \"\$1\" | grep -q BKLG-002" _ "$out"
ok "rail shows a ticket with no priority as normal (-)" has "$out" "BKLG-001 +B +backlog +- +yes +- +Open ticket"
printf -- '---\nid: BKLG-003\ntitle: Urgent one\nlane: B\nkind: bug\nstatus: backlog\npriority: high   # jumps the queue\ncook: null\n---\n' > "$C/docs/backlog/BKLG-003-urgent.md"
printf -- '---\nid: BKLG-004\ntitle: Someday\nlane: B\nkind: bug\nstatus: backlog\npriority: low\ncook: null\n---\n' > "$C/docs/backlog/BKLG-004-someday.md"
out=$("$K" rail)
ok "rail shows high priority" has "$out" "BKLG-003 +B +backlog +high +yes +- +Urgent one"
ok "rail shows low priority" has "$out" "BKLG-004 +B +backlog +low +yes +- +Someday"
printf -- '---\nid: BKLG-005\ntitle: Plain\nlane: B\nkind: bug\nstatus: blocked\npriority: normal\ncook: null\nblocked_by: [BKLG-001, BKLG-003]\n---\n' > "$C/docs/backlog/BKLG-005-plain.md"
printf -- '---\nid: BKLG-006\ntitle: Odd\nlane: B\nkind: bug\nstatus: backlog\npriority: urgent\ncook: null\nblocked_by: []\n---\n' > "$C/docs/backlog/BKLG-006-odd.md"
out=$("$K" rail)
ok "an explicit normal priority reads as -" has "$out" "BKLG-005 +B +blocked +- +no +- +Plain"
ok "an unknown priority reads as normal, not as itself" has "$out" "BKLG-006 +B +backlog +- +yes +- +Odd"
ok "rail prints a ticket's blockers after its title" has "$out" "Plain  \(blocked by: BKLG-001, BKLG-003\)"
ok "…and nothing for an empty blocked_by" bash -c '! printf "%s" "$1" | grep -q "Odd.*blocked by"' _ "$out"
ok "no footnote when every blocker is a ticket on the rail" bash -c '! printf "%s" "$1" | grep -q "not a ticket on this rail"' _ "$out"
printf -- '---\nid: BKLG-007\ntitle: After done\nlane: B\nkind: bug\nstatus: blocked\ncook: null\nblocked_by: [BKLG-002]\n---\n' > "$C/docs/backlog/BKLG-007-after.md"
printf -- '---\nid: BKLG-008\ntitle: Mixed\nlane: B\nkind: bug\nstatus: backlog\ncook: null\nblocked_by: ["BKLG-002", T-007, BKLG-001]\n---\n' > "$C/docs/backlog/BKLG-008-mixed.md"
printf -- '---\nid: BKLG-009\ntitle: Claimed\nlane: B\nstatus: todo\ncook: station-2\nblocked_by: []\n---\n' > "$C/docs/backlog/BKLG-009-claimed.md"
out=$("$K" rail)
ok "a ticket whose only blocker is done is ready, with no blocker shown" has "$out" "BKLG-007 +B +blocked +- +yes +- +After done$"
ok "a done blocker is dropped; an open one and an unknown one hold the ticket" has "$out" "BKLG-008 +B +backlog +- +no +- +Mixed  \(blocked by: T-007\?, BKLG-001\)"
ok "an unknown blocker gets the footnote" has "$out" "\? = not a ticket on this rail"
ok "a claimed ticket is neither ready nor not" has "$out" "BKLG-009 +B +todo +- +- +station-2 +Claimed"
ok "done tickets stay hidden" bash -c '! printf "%s" "$1" | grep -q "^BKLG-002"' _ "$out"
rm "$C/docs/backlog/BKLG-007-after.md" "$C/docs/backlog/BKLG-008-mixed.md" "$C/docs/backlog/BKLG-009-claimed.md"
printf -- '---\nid: BKLG-010\ntitle: A capability\nlane: B\nstatus: backlog\ncook: null\n---\n' > "$C/docs/backlog/BKLG-010-cap.md"
printf -- '---\nid: BKLG-011\ntitle: Also an item\nlane: B\nkind: item\nstatus: backlog\ncook: null\n---\n' > "$C/docs/backlog/BKLG-011-item.md"
mkdir -p "$C/docs/specs/001-demo"
printf -- '---\nid: S001-01\ntitle: A spec ticket\nlane: A\nstatus: backlog\ncook: null\n---\n' > "$C/docs/specs/001-demo/01-first.md"
out=$("$K" rail)
ok "a backlog item with no kind still needs a spec" has "$out" "BKLG-010 +B +backlog +- +spec +- +A capability"
ok "a backlog item of kind item still needs a spec" has "$out" "BKLG-011 +B +backlog +- +spec +- +Also an item"
ok "a spec ticket is ready without any kind" has "$out" "S001-01 +A +backlog +- +yes +- +A spec ticket"
ok "the last ticket read is listed once, not once per pass" test "$(printf '%s\n' "$out" | grep -c '^S001-01')" = 1
rm -r "$C/docs/backlog/BKLG-010-cap.md" "$C/docs/backlog/BKLG-011-item.md" "$C/docs/specs/001-demo"
rm "$C/docs/backlog/BKLG-005-plain.md" "$C/docs/backlog/BKLG-006-odd.md"
rm "$C/docs/backlog/BKLG-003-urgent.md" "$C/docs/backlog/BKLG-004-someday.md"

out=$("$K" open --terminal print -m "o s")
ok "open names cooks <repo>-cook-N" has "$out" "--name app-cook-2"
ok "open uses one model per station" has "$out" "app-cook-1 --model opus"
ok "open defaults to auto permission mode" has "$out" "--permission-mode auto"
ok "open starts each session as a line cook" has "$out" '"/bk:line-cook"'
ok "open without CLAUDE_CONFIG_DIR prints plain claude" bash -c "! printf '%s' \"\$1\" | grep -q CLAUDE_CONFIG_DIR" _ "$out"
out=$(CLAUDE_CONFIG_DIR=/x/profile "$K" open --terminal print)
ok "open passes CLAUDE_CONFIG_DIR through when set" has "$out" "CLAUDE_CONFIG_DIR=/x/profile claude"
# .claude/cook, the hand restart: a stub claude prints the profile and args it got.
EB="$TMP/echobin"; mkdir -p "$EB"
printf '#!/bin/sh\necho "pwd=$(pwd -P) profile=${CLAUDE_CONFIG_DIR-unset} args=$*"\n' > "$EB/claude"; chmod +x "$EB/claude"
S2="$C/stations/station-2"
before=$(git -C "$S2" status --porcelain)
CLAUDE_CONFIG_DIR="/x/my profile" "$K" open --terminal print -m "o s" >/dev/null
ok "open writes an executable .claude/cook in each station" test -x "$C/stations/station-1/.claude/cook" -a -x "$S2/.claude/cook"
ok "…kept out of git" test "$before" = "$(git -C "$S2" status --porcelain)"
out=$(cd /tmp && PATH="$EB:$PATH" CLAUDE_CONFIG_DIR=/wrong "$S2/.claude/cook")
ok ".claude/cook runs in its station, from anywhere" has "$out" "pwd=$(cd "$S2" && pwd -P) "
ok "…under open's profile, not the caller's" has "$out" "profile=/x/my profile args"
ok "…resuming by default, with the cook's name and model" has "$out" "args=--name app-cook-2 --model sonnet --permission-mode auto --continue$"
out=$(PATH="$EB:$PATH" "$S2/.claude/cook" "/bk:line-cook")
ok ".claude/cook with a prompt starts fresh instead" has "$out" "--permission-mode auto /bk:line-cook$"
"$K" open --terminal print -m "o s" >/dev/null
out=$(PATH="$EB:$PATH" CLAUDE_CONFIG_DIR=/wrong "$S2/.claude/cook")
ok "opened with no profile, .claude/cook drops a stray one" has "$out" "profile=unset "
ok "a second open adds no second exclude line" test "$(grep -c '^\.claude/cook$' "$(git -C "$S2" rev-parse --path-format=absolute --git-path info/exclude)")" = 1

out=$("$K" open --terminal print --bare)
ok "open --bare starts plain sessions" bash -c "! printf '%s' \"\$1\" | grep -q 'bk:line-cook\"'" _ "$out"
out=$(BRIGADE_OS=mac "$K" open --terminal warp --no-launch)
ok "open --no-launch writes the Warp config and launches nothing" has "$out" "not launched"
ok "…into HOME's launch_configurations, titled by cook" grep -q 'title: "app-cook-1' "$HOME/.warp/launch_configurations/app-brigade.yaml"
BRIGADE_OS=linux "$K" open --terminal warp --no-launch >/dev/null
ok "on Linux the Warp config goes to warp-terminal's data dir" test -f "$HOME/.local/share/warp-terminal/launch_configurations/app-brigade.yaml"

# Terminal choice: stub launchers on a fake PATH; --no-launch shows what would run.
FAKE="$TMP/fakebin"; mkdir -p "$FAKE"
stub() { printf '#!/bin/sh\nexit 0\n' > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
stub gnome-terminal; stub osascript; stub wt.exe
out=$(BRIGADE_OS=linux DISPLAY=:0 PATH="$FAKE:$NB" "$K" open --no-launch)
ok "no Warp: open falls back to the Linux desktop's terminal" has "$out" "would run: gnome-terminal --working-directory=.*station-1"
ok "…running the cook's claude command" has "$out" "app-cook-1"
stub warp-terminal
out=$(BRIGADE_OS=linux DISPLAY=:0 PATH="$FAKE:$NB" "$K" open --no-launch)
ok "Warp installed: open prefers it over the native terminal" has "$out" "Warp config written"
rm "$FAKE/warp-terminal"
out=$(env -u DISPLAY -u WAYLAND_DISPLAY BRIGADE_OS=linux PATH="$FAKE:$NB" "$K" open --no-launch)
ok "no Warp and no desktop: open prints the commands" has "$out" "cd .*station-1.* && claude"
out=$(BRIGADE_OS=mac PATH="$FAKE:$NB" "$K" open --terminal native --no-launch)
ok "macOS native terminal is Terminal.app" has "$out" 'would run: osascript .*Terminal'
out=$(BRIGADE_OS=wsl PATH="$FAKE:$NB" "$K" open --terminal native --no-launch)
ok "WSL native terminal is Windows Terminal running wsl.exe" has "$out" "would run: wt.exe .*wsl.exe"
out=$(BRIGADE_OS=windows PATH="$FAKE:$NB" "$K" open --terminal native --no-launch)
ok "Git Bash native terminal is Windows Terminal" has "$out" "would run: wt.exe -w 0 new-tab"
out=$(env -u DISPLAY -u WAYLAND_DISPLAY BRIGADE_OS=linux "$K" open --terminal native --no-launch)
ok "--terminal native with no terminal found prints the commands" has "$out" "No terminal found"
out=$("$K" open --terminal bogus)
ok "an unknown --terminal is named" has "$out" "Unknown terminal 'bogus'"
ok "…and the commands are printed" has "$out" "claude --name app-cook-1"
out=$("$K" open --terminal print -m zz 2>&1); rc=$?
ok "open rejects an unknown model" test "$rc" -ne 0
out=$(BRIGADE_KITCHEN_MODE=bogus "$K" status 2>&1); rc=$?
ok "an invalid kitchen_mode is refused" test "$rc" -ne 0

S1="$C/stations/station-1"
git -C "$S1" switch -q -c bklg-001-open origin/main
mkdir -p "$S1/db/migrations" "$S1/docs/plans" "$S1/docs/journal"
touch "$S1/db/migrations/001_add.sql" "$S1/docs/plans/BKLG-001-open.md"
out=$("$K" files)
ok "files flags an unmerged migration" has "$out" "db/migrations/001_add.sql  \(UNMERGED MIGRATION\)"
ok "files marks a plan" has "$out" "docs/plans/BKLG-001-open.md  \(plan\)"
out=$("$K" status)
ok "status shows the cook's branch" has "$out" "station-1 +bklg-001-open"
out=$("$K" sync)
ok "sync skips a dirty station" has "$out" "station-1: dirty"
ok "sync resets a clean station" has "$out" "station-2: synced to origin/main"

section "questions"
ok "no open questions before any journal" has "$("$K" questions)" "No open questions"
cat > "$S1/docs/journal/BKLG-001-open.md" <<'EOF'
- 2026-09-29 10:00 · app-cook-1 · Q1: reuse the helper? — recommend: yes
- 2026-09-29 10:05 · app-cook-1 · A1 (sous): yes
- 2026-09-29 10:10 · app-cook-1 · Q2: new column or reuse? — recommend: reuse
- 2026-09-29 10:20 · app-cook-1 · Q12: rename the flag? — recommend: no
EOF
out=$("$K" questions)
ok "an answered question isn't listed" bash -c "! printf '%s' \"\$1\" | grep -q 'Q1: reuse'" _ "$out"
ok "an unanswered question is listed" has "$out" "Q2: new column"
ok "Q12 isn't mistaken for answered Q1" has "$out" "Q12: rename"

section "board"
before=$(git -C "$C" status --porcelain)
out=$("$K" board)
ok "board shows stations, files, the rail and open questions" bash -c 'has() { printf "%s" "$1" | grep -qE -- "$2"; }; has "$1" "station-1 +bklg-001-open" && has "$1" "UNMERGED MIGRATION" && has "$1" "BKLG-001 +B +backlog" && has "$1" "Q2: new column"' _ "$out"
ok "board writes the same snapshot to .claude/board.md" test "$out" = "$(cat "$C/.claude/board.md")"
ok "board.md stays out of git without touching a tracked file" test "$before" = "$(git -C "$C" status --porcelain)"
"$K" board >/dev/null
ok "a second board doesn't add a second exclude line" test "$(grep -c 'board.md' "$C/.git/info/exclude")" = 1
printf 'keep-me' > "$C/.git/info/exclude"; rm "$C/.claude/board.md"; "$K" board >/dev/null
ok "an exclude file with no final newline keeps its last line intact" bash -c 'grep -qx keep-me "$1" && grep -qx .claude/board.md "$1"' _ "$C/.git/info/exclude"
rm "$C/.claude/board.md"
out=$(cd "$S1" && "$K" board)
ok "board from a station prints the same board" has "$out" "Q2: new column"
ok "…but writes nothing into the main checkout or the station" bash -c '! test -e "$1/.claude/board.md" && ! test -e "$2/.claude/board.md"' _ "$C" "$S1"

section "sous"
out=$(cd "$S1" && "$K" sous 2>&1); rc=$?
ok "sous with nothing recorded fails" test "$rc" -ne 0
ok "…and says to wait for the [hello]" has "$out" "wait for its \[hello\]"
out=$(cd "$S1" && "$K" sous --set app-cook-1 2>&1); rc=$?
ok "sous --set is refused from a station" test "$rc" -ne 0 -a ! -e "$C/.claude/sous"
ok "sous --set refuses a missing name" bash -c '! "$1" sous --set' _ "$K"
ok "sous --set doesn't take a flag for a name" bash -c '! "$1" sous --set -x' _ "$K"
ok "sous --set refuses a name with a space" bash -c '! "$1" sous --set "two words"' _ "$K"
before=$(git -C "$C" status --porcelain)
ok "sous --set from the main checkout prints the name" test "$("$K" sous --set app-f6)" = app-f6
ok "a station reads the sous's name" test "$(cd "$S1" && "$K" sous)" = app-f6
ok ".claude/sous stays out of git without touching a tracked file" test "$before" = "$(git -C "$C" status --porcelain)"
"$K" sous --set app-sous-2 >/dev/null
ok "a new sous overwrites the old name" test "$(cd "$S1" && "$K" sous)" = app-sous-2
ok "…without a second exclude line" test "$(grep -c '^\.claude/sous$' "$C/.git/info/exclude")" = 1

section "open --terminal tmux"
TB="$TMP/tmuxbin"; mkdir -p "$TB"; : > "$TB/tmux.log"
printf '#!/bin/sh\n[ "$1" = has-session ] && exit 1\necho "tmux $*" >> "%s"\n' "$TB/tmux.log" > "$TB/tmux"; chmod +x "$TB/tmux"
out=$(PATH="$TB:$NB" "$K" open --terminal tmux)
ok "tmux: the session starts with a 'sous' window in the main checkout" has "$(cat "$TB/tmux.log")" "new-session -d -s app-brigade -n sous -c $(cd "$C" && pwd -P)"
ok "…running /bk:sous-chef on opus, with no cook name" has "$(cat "$TB/tmux.log")" "send-keys -t app-brigade:sous claude --model opus \"/bk:sous-chef\" Enter"
ok "…and one window per station running /bk:line-cook" bash -c 'grep -q "new-window -t app-brigade -n station-1" "$1" && grep -q "station-2 .*line-cook" "$1"' _ "$TB/tmux.log"
ok "…and says how to attach to the sous" has "$out" "tmux attach -t app-brigade:sous"
ok "tmux is the default terminal when it is on the PATH" has "$(PATH="$TB:$NB" "$K" open)" "runs in tmux session 'app-brigade'"
cp "$C/.claude/brigade.md" "$TMP/brigade.md.bak"; printf -- '---\nsous_model: haiku\n---\n' > "$C/.claude/brigade.md"; : > "$TB/tmux.log"
PATH="$TB:$NB" "$K" open >/dev/null
ok "sous_model in the config picks the sous's model" has "$(cat "$TB/tmux.log")" "sous claude --model haiku"
cp "$TMP/brigade.md.bak" "$C/.claude/brigade.md"
# BRIGADE_CLAUDE_ARGS (what bk sets to --plugin-dir) reaches every session and the launcher
: > "$TB/tmux.log"; PATH="$TB:$NB" BRIGADE_CLAUDE_ARGS="--plugin-dir /p/bk" "$K" open >/dev/null
ok "BRIGADE_CLAUDE_ARGS is added to the sous's command" has "$(cat "$TB/tmux.log")" 'sous claude --model opus --plugin-dir /p/bk "/bk:sous-chef"'
ok "…and to each cook's" has "$(cat "$TB/tmux.log")" 'station-1 claude --name app-cook-1 --model sonnet --permission-mode auto --plugin-dir /p/bk "/bk:line-cook"'
ok "…and is baked into .claude/cook" has "$(cat "$C/stations/station-1/.claude/cook")" 'permission-mode auto --plugin-dir /p/bk "\$@"'
# a paused kitchen (bk stop) left session ids: open resumes them, once
echo sid-sous > "$C/.claude/sous-session"; echo sid-one > "$C/stations/station-1/.claude/cook-session"
: > "$TB/tmux.log"; PATH="$TB:$NB" "$K" open >/dev/null
ok "a saved sous session is resumed" has "$(cat "$TB/tmux.log")" 'sous claude --model opus --resume sid-sous "/bk:sous-chef"'
ok "a saved cook session is resumed" has "$(cat "$TB/tmux.log")" 'app-cook-1 --model sonnet --permission-mode auto --resume sid-one "/bk:line-cook"'
ok "…a station without one starts fresh" bash -c '! grep "station-2 claude" "$1" | grep -q resume' _ "$TB/tmux.log"
ok "…and the ids are used once" test ! -e "$C/.claude/sous-session" -a ! -e "$C/stations/station-1/.claude/cook-session"
ok "the bk hints replace the tmux ones when bk opened the kitchen" has "$(PATH="$TB:$NB" BRIGADE_VIA_BK=1 "$K" open)" "bk attach .*bk peek 1 .*bk stop"
# a session that already exists gains windows instead of being refused
printf '#!/bin/sh\n[ "$1" = has-session ] && exit 0\n[ "$1" = list-windows ] && { echo sous; echo station-1; exit 0; }\n[ "$1" = display-message ] && { echo node; exit 0; }\necho "tmux $*" >> "%s"\n' "$TB/tmux.log" > "$TB/tmux"
: > "$TB/tmux.log"
out=$(PATH="$TB:$NB" "$K" open --terminal tmux)
ok "an existing session keeps its sous window" bash -c '! grep -q "new-window -t app-brigade -n sous" "$1" && ! grep -q "new-session" "$1"' _ "$TB/tmux.log"
ok "…and a sous still running there is left alone" bash -c '! grep -q "send-keys -t app-brigade:sous" "$1"' _ "$TB/tmux.log"
ok "…reuses a dead cook's window and adds the missing one" bash -c 'grep -q "kill-window -t app-brigade:station-1" "$1" && grep -q "new-window -t app-brigade -n station-2" "$1"' _ "$TB/tmux.log"
# the sous window is there but holds a bare shell (the sous was exited by hand): the sous restarts in it
printf '#!/bin/sh\n[ "$1" = has-session ] && exit 0\n[ "$1" = list-windows ] && { echo sous; echo station-1; exit 0; }\n[ "$1" = display-message ] && { echo zsh; exit 0; }\necho "tmux $*" >> "%s"\n' "$TB/tmux.log" > "$TB/tmux"
: > "$TB/tmux.log"
out=$(PATH="$TB:$NB" "$K" open --terminal tmux)
ok "a sous window left as a bare shell gets the sous started again in place" has "$(cat "$TB/tmux.log")" 'send-keys -t app-brigade:sous claude --model opus "/bk:sous-chef" Enter'
ok "…without a second sous window" bash -c '! grep -q "new-window -t app-brigade -n sous" "$1"' _ "$TB/tmux.log"
ok "…and says so" has "$out" "the sous started in window 'sous'"
printf '#!/bin/sh\n[ "$1" = has-session ] && exit 1\necho "tmux $*" >> "%s"\n' "$TB/tmux.log" > "$TB/tmux"
# no tmux, a Mac with Homebrew: brew installs it (the stub drops a tmux onto the PATH)
BB="$TMP/brewbin"; mkdir -p "$BB"; : > "$BB/brew.log"
printf '#!/bin/sh\necho "brew $*" >> "%s"\ncp "%s" "%s/tmux"\n' "$BB/brew.log" "$TB/tmux" "$BB" > "$BB/brew"; chmod +x "$BB/brew"
: > "$TB/tmux.log"
out=$(PATH="$BB:$NB" BRIGADE_OS=mac "$K" open --terminal tmux 2>&1)
ok "tmux missing on a Mac: brew install tmux runs" has "$(cat "$BB/brew.log")" "brew install tmux"
ok "…and the kitchen then opens in tmux" has "$out" "runs in tmux session 'app-brigade'"
rm -f "$BB/tmux"
out=$(PATH="$NB" BRIGADE_OS=linux "$K" open --terminal tmux 2>&1)
ok "tmux missing on Linux: says the apt command and falls back to printed commands" bash -c 'printf "%s" "$1" | grep -q "sudo apt-get install -y tmux" && printf "%s" "$1" | grep -q "claude --name"' _ "$out"

section "live (the Window)"
ok "live status with nothing running says closed" has "$("$K" live status)" "closed"
ok "live stop with nothing running is quiet and fine" has "$("$K" live stop)" "closed"
if command -v node >/dev/null 2>&1; then
  before=$(git -C "$C" status --porcelain)
  out=$("$K" live --demo --port 47471 --no-launch 2>&1); rc=$?
  ok "live --demo opens the Window" test "$rc" -eq 0
  ok "…and prints its URL" has "$out" "http://localhost:47471"
  read -r wpid wport < "$C/.claude/window.pid"
  ok "…and records a live pid and the port" bash -c 'kill -0 "$1" && test "$2" = 47471' _ "$wpid" "$wport"
  # a cold runner can take a few seconds to bind the port: wait for it, up to 15s
  for _ in $(seq 1 30); do curl -sf "http://localhost:47471/api/state" >/dev/null 2>&1 && break; sleep 0.5; done
  ok "…and it serves the kitchen's state" bash -c 'curl -sf "http://localhost:47471/api/state" | grep -q "\"stations\""'
  ok "live status says open" has "$("$K" live status)" "open: http://localhost:47471"
  ok ".claude/window.pid and .log stay out of git" test "$before" = "$(git -C "$C" status --porcelain)"
  ok "live from a station finds the same Window" has "$(cd "$S1" && "$K" live status)" "open"
  out=$("$K" live 2>&1)
  ok "live again closes it" has "$out" "closed"
  sleep 0.5
  ok "…and the process is gone" bash -c '! kill -0 "$1" 2>/dev/null' _ "$wpid"
  ok "…and the pid file too" test ! -e "$C/.claude/window.pid"
  echo "99999999 47471" > "$C/.claude/window.pid"
  ok "a stale pid file reads as closed" has "$("$K" live status)" "closed"
  ok "…and is removed" test ! -e "$C/.claude/window.pid"
else
  echo "# node not installed: skipping the Window's start/stop tests"
fi
ok "live without node says what to install" has "$(PATH="$NB" "$K" live --no-launch 2>&1)" "needs node"

section "leaks"
ok "leaks with no local file has nothing to check" has "$("$K" leaks)" "nothing to check"
cat > "$C/.claude/brigade.local.md" <<'LOCAL'
## Test accounts
<!-- - password: <or how to get the code> -->
### local
- **local-builder** — a builder
  - login: builder@example.test
  - password: `hunter2-local`
### stage
- **stage-builder** — a builder
  - token: "tok_STAGE_9f3"
  - code: 1234
### production
LOCAL
out=$(cd "$S1" && "$K" leaks); rc=$?
ok "a clean station passes the leak check" test "$rc" -eq 0
ok "…and a value too short to search for is said, not skipped silently" has "$out" "1 value\(s\) shorter than 6"
echo "builder@example.test" > "$S1/notes.txt"
ok "a login isn't treated as a secret" bash -c 'cd "$1" && "$2" leaks' _ "$S1" "$K"
printf 'line one\nwalked as local-builder with hunter2-local\n' > "$S1/leak.txt"
out=$(cd "$S1" && "$K" leaks); rc=$?
ok "a secret in an untracked file fails the check" test "$rc" -eq 1
ok "…naming the file and line" has "$out" "leak.txt:2"
ok "…and never printing the value" bash -c '! printf "%s" "$1" | grep -q hunter2' _ "$out"
rm "$S1/leak.txt" "$S1/notes.txt"
echo 'body: tok_STAGE_9f3' > "$TMP/pr-body.md"
out=$(cd "$S1" && "$K" leaks --also "$TMP/pr-body.md"); rc=$?
ok "--also checks one extra file, such as a PR body" bash -c 'test "$1" -eq 1 && printf "%s" "$2" | grep -q "pr-body.md:1"' _ "$rc" "$out"
git -C "$S1" stash -q -u; git -C "$S1" commit -q --allow-empty -m "use hunter2-local to log in"
out=$(cd "$S1" && "$K" leaks); rc=$?
ok "a secret in a commit message on the branch fails the check" bash -c 'test "$1" -eq 1 && printf "%s" "$2" | grep -q "commit message"' _ "$rc" "$out"
git -C "$S1" reset -q --hard HEAD~1 >/dev/null 2>&1; git -C "$S1" stash pop -q >/dev/null 2>&1
out=$("$K" leaks --dir "$S1"); rc=$?
ok "leaks --dir checks a station from the main checkout" test "$rc" -eq 0
rm "$C/.claude/brigade.local.md"

section "lessons"
mkdir -p "$C/docs/journal"
printf -- '- lesson(repo): flaky-test | re-run once | BKLG-010\n- lesson(repo): flaky-test | re-run once | BKLG-010\n- lesson(plugin): wrong-gate | asked the human a routine question | BKLG-010\n' > "$C/docs/journal/BKLG-010-a.md"
printf -- '- lesson(repo): slow-install | pods take 6 min | BKLG-011\n' > "$C/docs/journal/BKLG-011-b.md"
printf -- '- lesson(repo): slow-install | pods again | BKLG-001\n' >> "$S1/docs/journal/BKLG-001-open.md"
out=$("$K" lessons)
ok "a repo lesson repeated in ONE ticket counts once (watch)" has "$out" "repo +flaky-test +1 +watch"
ok "a repo lesson in 2 tickets (one unmerged, in a station) is DUE" has "$out" "repo +slow-install +2 +DUE"
ok "a plugin lesson is DUE at 1 ticket" has "$out" "plugin +wrong-gate +1 +DUE"
printf '| `slow-install` | repo | BKLG-020 |\n' > "$C/docs/lessons.md"
ok "a key listed in docs/lessons.md is promoted" has "$("$K" lessons)" "slow-install +2 +promoted"
mkdir -p "$C/docs/journal/completed"
printf -- '- lesson(repo): flaky-test | flaked again | BKLG-012\n' > "$C/docs/journal/completed/BKLG-012-done.md"
ok "a journal moved to a subfolder of docs.journal still counts" has "$("$K" lessons)" "flaky-test +2 +DUE"
printf -- '- lesson(repo): flaky-test | not a journal | BKLG-013\n' > "$C/docs/journal/completed/INDEX.md"
ok "…but an INDEX.md there doesn't" has "$("$K" lessons)" "flaky-test +2 +DUE"
rm -r "$C/docs/journal/completed"

# A repo whose journal is the plans folder, with its own lessons register.
cp "$C/.claude/brigade.md" "$TMP/brigade.md.bak"
awk 'NR>1 && $0=="---" && !d { print "docs:\n  journal: docs/plans\n  lessons: docs/notes/lessons.md"; d=1 } { print }' "$TMP/brigade.md.bak" > "$C/.claude/brigade.md"
mkdir -p "$C/docs/plans/completed" "$C/docs/notes"
printf -- '# plan\n## Journal\n- lesson(repo): plan-lesson | x | BKLG-030\n' > "$C/docs/plans/BKLG-030-live.md"
printf -- '# plan\n## Journal\n- lesson(repo): plan-lesson | y | BKLG-031\n' > "$C/docs/plans/completed/BKLG-031-done.md"
out=$("$K" lessons)
ok "docs.journal set to plans: lessons in live and completed plans both count" has "$out" "plan-lesson +2 +DUE"
ok "…and the default journal folder is no longer read" bash -c '! printf "%s" "$1" | grep -q slow-install' _ "$out"
printf '| `plan-lesson` | repo | BKLG-031 |\n' > "$C/docs/notes/lessons.md"
ok "docs.lessons sets the register that marks a key promoted" has "$("$K" lessons)" "plan-lesson +2 +promoted"
cp "$TMP/brigade.md.bak" "$C/.claude/brigade.md"; rm -r "$C/docs/plans/completed" "$C/docs/notes" "$C/docs/plans/BKLG-030-live.md"
ok "with no docs.lessons the register is docs/lessons.md again" has "$("$K" lessons)" "slow-install +2 +promoted"

section "rail: chores are ready, items still need a spec"
printf -- '---\nid: BKLG-003\ntitle: A chore\nlane: B\nkind: chore\nstatus: backlog\ncook: null\n---\n' > "$C/docs/backlog/BKLG-003-chore.md"
printf -- '---\nid: BKLG-004\ntitle: An item\nlane: B\nkind: item\nstatus: backlog\ncook: null\n---\n' > "$C/docs/backlog/BKLG-004-item.md"
out=$("$K" rail)
ok "a kind: chore backlog item is ready" has "$out" "BKLG-003 +B +backlog +- +yes"
ok "a kind: item backlog item still says spec" has "$out" "BKLG-004 +B +backlog +- +spec"
printf -- '---\nid: BKLG-007\ntitle: A third provider\nlane: B\nkind: precedent\nprecedent: [src/providers/a.ts, src/providers/b.ts]\nprecedent_why: docs/specs/002-providers.md\nstatus: backlog\ncook: null\n---\n' > "$C/docs/backlog/BKLG-007-precedent.md"
ok "a kind: precedent backlog item is ready (Contract 4)" has "$("$K" rail)" "BKLG-007 +B +backlog +- +yes"

section "questions: open question files"
ok "no docs.questions folder: only journal questions are listed" bash -c '! "$1" questions | grep -q "(record)"' _ "$K"
mkdir -p "$C/docs/questions"
cat > "$C/docs/questions/2026-10-01-refund-window.md" <<'EOF2'
---
type: question
title: How long is the refund window?
status: open
asked: 2026-10-01
blocks: [BKLG-001]
---
EOF2
cat > "$C/docs/questions/2026-09-01-old.md" <<'EOF2'
---
type: question
title: Already answered
status: answered
---
EOF2
printf '# Questions\n' > "$C/docs/questions/INDEX.md"
out=$("$K" questions)
ok "an open question file is listed as (record), with what it blocks" has "$out" "\(record\) +2026-10-01-refund-window.md +How long is the refund window\?  \(blocks: BKLG-001\)"
ok "…and before the journals' questions: the head chef's debt comes first" test "$(printf '%s' "$out" | sed -n 2p | cut -d' ' -f1)" = "(record)"
ok "an answered question file isn't" bash -c '! printf "%s" "$1" | grep -q "Already answered"' _ "$out"
ok "…and the journals' open questions still are" has "$out" "station-1 +BKLG-001-open.md +.*Q2: new column"
mkdir -p "$S1/docs/journal/completed"
printf -- '- 2026-09-29 12:00 · app-cook-1 · Q7: deeper? — recommend: yes\n' > "$S1/docs/journal/completed/BKLG-009-deep.md"
printf -- '- 2026-09-29 12:00 · app-sous · Q1: trunk question? — recommend: yes\n' > "$C/docs/journal/BKLG-011-b.md.q"
mv "$C/docs/journal/BKLG-011-b.md.q" "$C/docs/journal/BKLG-012-trunk.md"
out=$("$K" questions)
ok "a journal in a subfolder of docs.journal is read, with the right station" has "$out" "station-1 +BKLG-009-deep.md +.*Q7: deeper"
ok "a trunk journal's open question is listed as (trunk)" has "$out" "\(trunk\) +BKLG-012-trunk.md +.*Q1: trunk question"
rm -r "$S1/docs/journal/completed" "$C/docs/journal/BKLG-012-trunk.md"

section "decisions"
rm -f "$C/docs/lessons.md"
ok "no head-chef answers yet" has "$("$K" decisions)" "No head-chef answers"
cat >> "$S1/docs/journal/BKLG-001-open.md" <<'EOF2'
- 2026-09-29 11:00 · app-cook-1 · Q3: show refunds to agents? — options: yes / no — recommend: no
- 2026-09-29 11:30 · app-cook-1 · A3 (head chef): yes, agents see refunds, because support asked for it
- 2026-09-29 11:40 · app-cook-1 · Q4: rename the flag? — recommend: no
- 2026-09-29 11:45 · app-cook-1 · A4 (sous): no
EOF2
printf -- '---\nticket: BKLG-011\n---\n- 2026-09-30 09:00 · app-cook-2 · A1 (head chef): keep the old endpoint until March\n' > "$C/docs/journal/BKLG-011-b.md"
out=$("$K" decisions)
ok "a (head chef) answer in a station journal is DUE" has "$out" "BKLG-001 A3 +DUE +- +yes, agents see refunds"
ok "a (head chef) answer in a trunk journal is DUE too (id from its frontmatter)" has "$out" "BKLG-011 A1 +DUE"
ok "a (sous) answer isn't listed" bash -c '! printf "%s" "$1" | grep -q "A4"' _ "$out"
mkdir -p "$C/docs/decisions"
printf -- '---\ntype: adr\ntitle: Agents see refunds\nstatus: accepted\nsource: BKLG-001 A3\n---\n' > "$C/docs/decisions/001-agents-see-refunds.md"
out=$("$K" decisions)
ok "an answer a decision file cites is filed, naming the file" has "$out" "BKLG-001 A3 +filed +docs/decisions/001-agents-see-refunds.md"
printf -- '- 2026-09-30 09:05 · app-cook-2 · A12 (head chef): twelve\n' >> "$C/docs/journal/BKLG-011-b.md"
printf -- '---\ntype: adr\nsource: BKLG-011 A12\n---\n' > "$C/docs/decisions/002-twelve.md"
out=$("$K" decisions)
ok "citing A12 files A12…" has "$out" "BKLG-011 A12 +filed"
ok "…and does not file A1 by substring" has "$out" "BKLG-011 A1 +DUE"
printf -- '# plan\nmentions BKLG-011 A1 in passing\n' > "$C/docs/plans/other.md"
ok "a plan that merely mentions the answer doesn't count as filing it" has "$("$K" decisions)" "BKLG-011 A1 +DUE"
rm "$C/docs/plans/other.md" "$C/docs/decisions/002-twelve.md"
printf '| `BKLG-011 A1` | kept | — |\n' > "$C/docs/lessons.md"
ok "an answer listed in the register is kept" has "$("$K" decisions)" "BKLG-011 A1 +kept +register"
rm "$C/docs/lessons.md" "$C/docs/decisions/001-agents-see-refunds.md"

section "inbox"
before=$(git -C "$C" status --porcelain)
ok "an empty inbox says so" has "$("$K" inbox)" "Inbox empty"
ok "inbox --add refuses an empty line" bash -c '! "$1" inbox --add' _ "$K"
ok "inbox --add is refused from a station" bash -c '! (cd "$1" && "$2" inbox --add "from a cook")' _ "$S1" "$K"
ok "…and says a cook's gotcha is a lesson" has "$(cd "$S1" && "$K" inbox --add "from a cook" 2>&1)" "lesson\(repo\)"
out=$("$K" inbox --add "the fare cache invalidates on every rule-engine deploy")
ok "inbox --add appends a dated line and lists it" has "$out" "Inbox: 1 unfiled.*
- 20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} · the fare cache invalidates"
"$K" inbox --add "bus is not sold on web" >/dev/null
ok "a second line makes two" has "$("$K" inbox)" "Inbox: 2 unfiled"
ok ".claude/inbox.md stays out of git without touching a tracked file" test "$before" = "$(git -C "$C" status --porcelain)"
ok "…with one exclude line" test "$(grep -c '^\.claude/inbox\.md$' "$C/.git/info/exclude")" = 1
out=$("$K" board)
ok "the board shows the record's counts" has "$out" "Decisions to file: 3 · Inbox: 2 unfiled"
rm "$C/.claude/inbox.md"

section "asks and gaps"
before=$(git -C "$C" status --porcelain)
# the answered question file from the questions section carries a fix, so it is not a gap
cat > "$C/docs/questions/2026-09-01-old.md" <<'EOF2'
---
type: question
title: Already answered
status: answered
gap: ruling
fix: docs/decisions/001-agents-see-refunds.md
---
EOF2
ok "no asks says so" has "$("$K" asks)" "No asks waiting"
ok "no gaps says so" has "$("$K" gaps)" "No gaps to fix"
ok "asks --add is refused from a station" bash -c '! (cd "$1" && "$2" asks --add "from a cook" 2>/dev/null)' _ "$S1" "$K"
ok "…and says a cook's question is a [gate]" has "$(cd "$S1" && "$K" asks --add "from a cook" 2>&1)" "\[gate\]"
ok "asks --add refuses an unknown gap kind" bash -c '! "$1" asks --add "x" --gap vibes 2>/dev/null' _ "$K"
ok "asks --add refuses an empty question" bash -c '! "$1" asks --add 2>/dev/null' _ "$K"
id=$("$K" asks --add "Which currency do refunds show in?" --ticket BKLG-001 --gap ruling)
ok "asks --add prints the new id" test "$id" = A1
ok "…a second one counts up" test "$("$K" asks --add "Can I get a staging DB login?" --gap access)" = A2
ok "…and one without a ticket or kind is allowed" test "$("$K" asks --add "Do we support bus operators?")" = A3
out=$("$K" asks)
ok "asks lists the open ones with ticket, gap and question" has "$out" "A1 +20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} +BKLG-001 +ruling +open +Which currency do refunds show in\?"
ok "…a missing ticket is - and a missing kind is ?" has "$out" "A3 +.* +- +\? +open +Do we support bus"
ok "…with the counts" has "$out" "Asks: 3 open .* · 0 answered"
ok "asks --filed before --answer is refused" bash -c '! "$1" asks --filed A1 "docs/decisions/002.md" 2>/dev/null' _ "$K"
ok "…unless it is parked as an open question file" "$K" asks --filed A3 "docs/questions/2026-10-03-bus-operators.md"
ok "…which takes the ask off the list: the file carries it now" bash -c '! "$1" asks | grep -q "^A3 "' _ "$K"
"$K" asks --add "Do we support bus operators?" >/dev/null   # A4: stands in for A3 below
ok "asks --answer of an unknown id is refused" bash -c '! "$1" asks --answer A9 "x" 2>/dev/null' _ "$K"
ok "asks --answer with no words is refused" bash -c '! "$1" asks --answer A1 2>/dev/null' _ "$K"
"$K" asks --answer A1 "PKR only; we never show a foreign currency"
out=$("$K" asks)
ok "an answered ask shows its answer and stays listed: its gap is not fixed yet" has "$out" "A1 +.* +BKLG-001 +ruling +answered +Which currency do refunds show in\?  → PKR only"
ok "…and the counts move" has "$out" "Asks: 2 open .* · 1 answered"
out=$("$K" gaps)
ok "gaps groups the answered ask under its kind, with the fix that kind takes" has "$out" "^ruling → a decision in docs.decisions"
ok "…naming the ask, its ticket and the question" has "$out" "^  A1 +BKLG-001 +Which currency do refunds show in\?"
ok "…an open ask is not a gap yet" bash -c '! printf "%s" "$1" | grep -q "A2"' _ "$out"
ok "…a question file with a fix: is not one either" bash -c '! printf "%s" "$1" | grep -q "2026-09-01-old.md"' _ "$out"
cat > "$C/docs/questions/2026-10-02-cache.md" <<'EOF2'
---
type: question
title: Does the fare cache survive a deploy?
status: answered
gap: context
fix: null
---
EOF2
out=$("$K" gaps)
ok "an answered question file with no fix: is a gap, under its kind" has "$out" "^context → the record"
ok "…listed by file name" has "$out" "^  2026-10-02-cache.md +- +Does the fare cache survive a deploy\?"
out=$("$K" board)
ok "the board counts open asks and gaps to fix" has "$out" "Asks open: 2 · Gaps to fix: 2"
"$K" asks --filed A1 "docs/decisions/002-pkr-only.md"
ok "a filed ask leaves the asks list" bash -c '! "$1" asks | grep -q "^A1 "' _ "$K"
ok "…and the gaps list" bash -c '! "$1" gaps | grep -q "A1"' _ "$K"
ok ".claude/asks.md stays out of git without touching a tracked file" test "$before" = "$(git -C "$C" status --porcelain)"
ok "…with one exclude line" test "$(grep -c '^\.claude/asks\.md$' "$C/.git/info/exclude")" = 1
rm "$C/.claude/asks.md" "$C/docs/questions/2026-10-02-cache.md"

section "record-pr: the record on a protected trunk"
R="$TMP/rec/app"; mkdir -p "$TMP/rec"
new_repo "$R" 'trunk: main
rail:
  adapter: markdown
  commit: direct
docs:
  journal: docs/journal
  lessons: docs/lessons.md
  decisions: docs/decisions
  questions: docs/questions'
mkdir -p "$R/docs/journal"
printf -- '- lesson(plugin): record-key | the record stays unfiled | BKLG-001\n' > "$R/docs/journal/BKLG-001-open.md"
push_all "$R" "init"
GHSTUB="$TMP/rec/stub"; mkdir -p "$GHSTUB"
cat > "$GHSTUB/gh" <<EOF3
#!/usr/bin/env bash
echo "\$*" >> "$TMP/rec/gh.log"
[[ "\$GH_FAIL" == 1 ]] && exit 1
[[ "\$1 \$2" == "pr create" ]] && echo "https://example.test/pull/7"
exit 0
EOF3
chmod +x "$GHSTUB/gh"
file_record() {  # a decision, the register row and an unrelated rail edit, all uncommitted
  mkdir -p "$R/docs/decisions"
  printf -- '---\ntype: adr\ntitle: Kept\nstatus: accepted\nsource: BKLG-001 A1\n---\n' > "$R/docs/decisions/001-kept.md"
  printf '| Key | Scope | Outcome |\n|---|---|---|\n| `record-key` | plugin | filed #99 |\n' > "$R/docs/lessons.md"
  printf 'edited\n' >> "$R/docs/backlog/BKLG-001-open.md"
}
rec() { (cd "$R" && PATH="$GHSTUB:$PATH" "$K" record-pr 2>&1); }
ok "nothing dirty: nothing to file" has "$(rec)" "Nothing to file"
file_record
ok "uncommitted in the working tree, the register already counts" has "$(cd "$R" && "$K" lessons)" "plugin +record-key +1 +promoted"
# protect main on origin
cat > "$R.git/hooks/pre-receive" <<'EOF3'
#!/bin/sh
while read old new ref; do [ "$ref" = refs/heads/main ] && { echo "protected branch" >&2; exit 1; }; done
exit 0
EOF3
chmod +x "$R.git/hooks/pre-receive"
: > "$TMP/rec/gh.log"
out=$(rec); today=$(date +%Y-%m-%d)
ok "a protected trunk: the record goes to a PR" has "$out" "Record PR: https://example.test/pull/7"
ok "…from a record/<date> branch on origin" test -n "$(git -C "$R" ls-remote --heads origin "record/$today")"
ok "…opened against main" grep -q "pr create --base main --head record/$today" "$TMP/rec/gh.log"
ok "…and the PR body says the push was refused" grep -q "because main refused a direct push" "$TMP/rec/gh.log"
ok "…the main checkout is back on main" test "$(git -C "$R" branch --show-current)" = main
ok "…and its record paths are clean" test -z "$(git -C "$R" status --porcelain -- docs/decisions docs/lessons.md)"
ok "…the commit holds the decision and the register" bash -c "git -C '$R' show --name-only --format= origin/record/$today | sort | tr '\n' ' ' | grep -q '^docs/decisions/001-kept.md docs/lessons.md \$'"
ok "…and not the unrelated rail edit, which stays dirty" test "$(git -C "$R" status --porcelain)" = " M docs/backlog/BKLG-001-open.md"
ok "…main on origin has none of it" test -z "$(git -C "$R.git" ls-tree -r --name-only main | grep -E 'decisions|lessons')"
git -C "$R" checkout -q -- docs/backlog
drop_branches() { git -C "$R" push -q origin --delete "$@" 2>/dev/null; git -C "$R" branch -q -D "$@" 2>/dev/null; git -C "$R" update-ref -d "refs/remotes/origin/$1" 2>/dev/null; true; }
newdec() { mkdir -p "$R/docs/decisions"; printf -- '---\ntype: adr\ntitle: %s\nstatus: accepted\nsource: BKLG-001 %s\n---\n' "$1" "$1" > "$R/docs/decisions/$1.md"; }
newdec 002-second
out=$(rec)
ok "a second run the same day: its own branch, record/<date>-2" test -n "$(git -C "$R" ls-remote --heads origin "record/$today-2")"
drop_branches "record/$today" "record/$today-2"
newdec 003-third
out=$(cd "$R" && GH_FAIL=1 PATH="$GHSTUB:$PATH" "$K" record-pr 2>&1); rc=$?
ok "gh failing: the branch is pushed and the exit is 1" test "$rc" = 1 -a -n "$(git -C "$R" ls-remote --heads origin "record/$today")"
ok "…and the message carries the gh pr create line" has "$out" "gh pr create --base main --head record/$today"
ok "…the checkout is still on a clean main" test "$(git -C "$R" branch --show-current)" = main -a -z "$(git -C "$R" status --porcelain -- docs/decisions)"
drop_branches "record/$today"
# an unprotected trunk
rm "$R.git/hooks/pre-receive"
newdec 004-direct
: > "$TMP/rec/gh.log"
out=$(rec)
ok "an unprotected trunk with rail.commit direct: filed on main" has "$out" "Filed on main"
ok "…it is on origin/main" bash -c "git -C '$R.git' show main:docs/decisions/004-direct.md"
ok "…no record branch is left, and gh was not called" test -z "$(git -C "$R" branch --list 'record/*')" -a ! -s "$TMP/rec/gh.log"
sed -i.bak 's/commit: direct/commit: daily-pr/' "$R/.claude/brigade.md"; rm "$R/.claude/brigade.md.bak"
newdec 005-viapr
out=$(rec)
ok "rail.commit daily-pr: a PR even though trunk would take the push" has "$out" "Record PR:"
ok "…and the PR body gives daily-pr as the reason, not a refusal" bash -c 'grep -q "because rail.commit is daily-pr" "$1" && ! grep -q "refused a direct push" "$1"' _ "$TMP/rec/gh.log"
ok "…and main on origin did not move" bash -c "! git -C '$R.git' show main:docs/decisions/005-viapr.md"
drop_branches "record/$today"
printf '#!/bin/sh\nexit 1\n' > "$R/.git/hooks/pre-commit"; chmod +x "$R/.git/hooks/pre-commit"
newdec 006-hook
out=$(rec); rc=$?
rm "$R/.git/hooks/pre-commit"
ok "a commit that fails: the message says so" has "$out" "Could not commit the record"
ok "…it does not claim the record was filed" bash -c '! printf "%s" "$1" | grep -qE "Filed on|Record PR"' _ "$out"
ok "…the checkout is on main, the file is still there, nothing is staged, no record branch is left" test "$(git -C "$R" branch --show-current)" = main -a -f "$R/docs/decisions/006-hook.md" -a -z "$(git -C "$R" diff --cached --name-only)" -a -z "$(git -C "$R" branch --list 'record/*')"
rm "$R/docs/decisions/006-hook.md"
out=$(cd "$S1" && "$K" record-pr 2>&1); rc=$?
ok "from a station: refused" test "$rc" = 1
ok "…saying the sous files the record" has "$out" "Only the sous files the record"

section "the record on a branch: the readers see it"
R2="$TMP/rec2/app"; mkdir -p "$TMP/rec2"
new_repo "$R2" 'trunk: main
rail:
  adapter: markdown
  commit: direct
docs:
  journal: docs/journal
  lessons: docs/lessons.md
  decisions: docs/decisions
  questions: docs/questions'
mkdir -p "$R2/docs/journal" "$R2/docs/questions"
printf -- '- lesson(plugin): rec-key | one | BKLG-001\n- lesson(plugin): rec-key-2 | two | BKLG-001\n- 2026-11-03 10:00 · c · Q1: fork? — recommend: a\n- 2026-11-03 10:05 · c · A1 (head chef): yes\n- 2026-11-03 10:06 · c · A2 (head chef): ship it on Friday\n' > "$R2/docs/journal/BKLG-001-open.md"
mkdir -p "$R2/docs/specs"
printf -- '# Spec 001\n\nShipping day was decided in BKLG-001 A2.\n' > "$R2/docs/specs/001-ship.md"
printf -- '---\ntitle: Old fork\nstatus: answered\ngap: context\nfix: null\n---\n' > "$R2/docs/questions/q1.md"
push_all "$R2" "init"
cat > "$R2.git/hooks/pre-receive" <<'EOF3'
#!/bin/sh
while read old new ref; do [ "$ref" = refs/heads/main ] && { echo "protected branch" >&2; exit 1; }; done
exit 0
EOF3
chmod +x "$R2.git/hooks/pre-receive"
NODESTUB="$TMP/rec2/nodestub"; mkdir -p "$NODESTUB"
cat > "$NODESTUB/node" <<'EOF3'
#!/usr/bin/env bash
# node stub: print the file --register names, which is what the real reader would count
while [[ $# -gt 0 ]]; do [[ "$1" == --register ]] && { echo "REGISTER=$2"; cat "$2"; exit 0; }; shift; done
exit 0
EOF3
chmod +x "$NODESTUB/node"
VIEWTMP="$TMP/rec2/viewtmp"; mkdir -p "$VIEWTMP"
k2() { (cd "$R2" && TMPDIR="$VIEWTMP" PATH="$NODESTUB:$GHSTUB:$PATH" "$K" "$@" 2>&1); }
ok "before any record: the lesson is DUE" has "$(k2 lessons)" "plugin +rec-key +1 +DUE"
ok "…and the head-chef answer is DUE" has "$(k2 decisions)" "BKLG-001 A1 +DUE"
ok "…and the answered question file has no fix: it is listed as a gap" has "$(k2 gaps)" "q1.md"
mkdir -p "$R2/docs/decisions"
printf '| Key | Scope | Outcome |\n|---|---|---|\n| `rec-key` | plugin | filed #1 |\n' > "$R2/docs/lessons.md"
printf -- '---\ntype: adr\ntitle: Yes\nstatus: accepted\nsource: BKLG-001 A1\n---\n' > "$R2/docs/decisions/001-yes.md"
printf -- '---\ntitle: Old fork\nstatus: answered\ngap: context\nfix: docs/decisions/001-yes.md\n---\n' > "$R2/docs/questions/q1.md"
printf -- '---\ntitle: New fork\nstatus: open\nblocks: [BKLG-001]\n---\n' > "$R2/docs/questions/q2.md"
out=$(k2 record-pr); today=$(date +%Y-%m-%d)
ok "the record went to a PR" has "$out" "Record PR:"
ok "…and is not in the working tree any more" test ! -e "$R2/docs/lessons.md"
ok "lessons: the key the record branch lists is promoted" has "$(k2 lessons)" "plugin +rec-key +1 +promoted"
ok "…while a key it does not list is still DUE" has "$(k2 lessons)" "plugin +rec-key-2 +1 +DUE"
ok "decisions: an answer a decision file on the branch cites is filed" has "$(k2 decisions)" "BKLG-001 A1 +filed +docs/decisions/001-yes.md"
ok "decisions: an answer only a spec cites is still filed while a record branch is open" has "$(k2 decisions)" "BKLG-001 A2 +filed +docs/specs/001-ship.md"
ok "gaps: the branch's copy of the question file (fix: set) replaces trunk's" bash -c '! printf "%s" "$1" | grep -q q1.md' _ "$(k2 gaps)"
ok "questions: an open question file only on the branch is listed" has "$(k2 questions)" "\(record\) +q2.md"
ok "debrief reads the register with the branch's row" has "$(k2 debrief)" "rec-key"
ok "the temp view is removed afterwards" test -z "$(ls -A "$VIEWTMP")"
# a second record branch: the register is the union
printf '| Key | Scope | Outcome |\n|---|---|---|\n| `rec-key-2` | plugin | filed #2 |\n' > "$R2/docs/lessons.md"
out=$(k2 record-pr ; true)
ok "a second record branch exists" test -n "$(git -C "$R2" ls-remote --heads origin "record/$today-2")"
out=$(k2 lessons)
ok "the register is the union of the open branches: both keys promoted" bash -c 'printf "%s" "$1" | grep -qE "rec-key +1 +promoted" && printf "%s" "$1" | grep -qE "rec-key-2 +1 +promoted"' _ "$out"
# the branches are gone: the record is nowhere
git -C "$R2" push -q origin --delete "record/$today" "record/$today-2" 2>/dev/null
git -C "$R2" branch -q -D "record/$today" "record/$today-2" 2>/dev/null
git -C "$R2" update-ref -d "refs/remotes/origin/record/$today"; git -C "$R2" update-ref -d "refs/remotes/origin/record/$today-2"
ok "branches deleted: the lesson is DUE again (the branch was the only source)" has "$(k2 lessons)" "plugin +rec-key +1 +DUE"
ok "…and the gap is listed again" has "$(k2 gaps)" "q1.md"
ok "…and no temp view was made (nothing to lay over trunk)" test -z "$(ls -A "$VIEWTMP")"
# a record branch that reached trunk is not read as a branch
mkdir -p "$R2/docs/decisions"; printf '| Key | Scope | Outcome |\n|---|---|---|\n| `rec-key` | plugin | filed #1 |\n' > "$R2/docs/lessons.md"
k2 record-pr >/dev/null
rm "$R2.git/hooks/pre-receive"
git -C "$R2" push -q origin "refs/remotes/origin/record/$today:refs/heads/main" 2>/dev/null
git -C "$R2" fetch -q origin && git -C "$R2" merge -q --ff-only origin/main
ok "a record branch merged into trunk: lesson promoted from trunk itself" has "$(k2 lessons)" "plugin +rec-key +1 +promoted"
ok "…and the debrief reads the checkout's own register, not a temp view" bash -c '! printf "%s" "$1" | grep -q "REGISTER=.*brigade-record"' _ "$(k2 debrief)"

section "doctor"
rm -rf "$C/docs/questions" "$C/docs/decisions"
out=$("$K" doctor 2>&1); rc=$?
ok "doctor fails on a ticket without kind" bash -c 'test "$1" -ne 0 && printf "%s" "$2" | grep -q "BKLG-002-done.md: BKLG item without kind"' _ "$rc" "$out"
ok "…and warns on a mapped folder with no INDEX.md" has "$out" "warn: docs.backlog: docs/backlog/ has no INDEX.md"
printf -- '---\nid: BKLG-005\ntitle: Bad\nlane: B\nkind: bug\nstatus: cooking\ncook: null\nblocked_by: [BKLG-999]\n---\n' > "$C/docs/backlog/BKLG-005-bad.md"
printf -- '---\nid: BKLG-001\ntitle: Duplicate id\nlane: B\nkind: bug\nstatus: backlog\ncook: null\n---\n' > "$C/docs/backlog/BKLG-006-dup.md"
out=$("$K" doctor 2>&1)
ok "doctor reports an unknown status" has "$out" 'BKLG-005-bad.md: unknown status "cooking"'
ok "doctor reports a blocker that is no ticket" has "$out" "BKLG-005-bad.md is blocked by BKLG-999, which is no ticket here"
ok "doctor reports a duplicate id" has "$out" "BKLG-006-dup.md: id BKLG-001 is also docs/backlog/BKLG-001-open.md"
ok "doctor accepts kind: precedent with its instances" bash -c '! printf "%s" "$1" | grep -q "BKLG-007-precedent.md"' _ "$out"
printf -- '---\nid: BKLG-008\ntitle: Says precedent, names one\nlane: B\nkind: precedent\nprecedent: [src/providers/a.ts]\nprecedent_why: null\nstatus: backlog\ncook: null\n---\n' > "$C/docs/backlog/BKLG-008-bare.md"
out=$("$K" doctor 2>&1)
ok "doctor fails on kind: precedent with one instance" has "$out" "BKLG-008-bare.md: kind: precedent needs two instances or more under precedent: \(has 1\)"
ok "doctor fails on kind: precedent without precedent_why" has "$out" "BKLG-008-bare.md: kind: precedent without precedent_why:"
rm "$C/docs/backlog/BKLG-005-bad.md" "$C/docs/backlog/BKLG-006-dup.md" "$C/docs/backlog/BKLG-003-chore.md" "$C/docs/backlog/BKLG-004-item.md" "$C/docs/backlog/BKLG-007-precedent.md" "$C/docs/backlog/BKLG-008-bare.md"
sed -i.bak 's/^status: done$/kind: chore\nstatus: done/' "$C/docs/backlog/BKLG-002-done.md" 2>/dev/null || true
printf -- '---\nid: BKLG-002\ntitle: Done ticket\nlane: B\nkind: chore\nstatus: done\ncook: null\n---\n' > "$C/docs/backlog/BKLG-002-done.md"; rm -f "$C/docs/backlog/BKLG-002-done.md.bak"
for d in backlog journal specs plans checklists research brainstorm decisions conventions domains questions; do mkdir -p "$C/docs/$d"; printf '# index\n' > "$C/docs/$d/INDEX.md"; done
# a spec document from the template, with one ticket inside its folder
mkdir -p "$C/docs/specs/001-refunds"
printf -- '---\nid: S001\ntitle: Refunds\nstatus: approved\nbrainstorm: null\nbacklog: []\ncreated: 2026-10-01\n---\n' > "$C/docs/specs/001-refunds.md"
printf -- '---\nid: S001-01\ntitle: Refund window\nlane: A\nstatus: backlog\ncook: null\nspec: S001\n---\n' > "$C/docs/specs/001-refunds/01-refund-window.md"
out=$("$K" doctor 2>&1); rc=$?
ok "doctor passes a well-formed rail and a complete map" bash -c 'test "$1" -eq 0 && printf "%s" "$2" | grep -q "3 ticket file(s), all well-formed" && printf "%s" "$2" | grep -q "nothing under docs/ is unmapped"' _ "$rc" "$out"
ok "…a spec document is not checked as a ticket" bash -c '! printf "%s" "$1" | grep -q "001-refunds.md"' _ "$out"
printf -- '---\nid: S001-02\ntitle: Broken\nlane: A\nstatus: nope\ncook: null\n---\n' > "$C/docs/specs/001-refunds/02-broken.md"
ok "…but a ticket inside a spec folder is" has "$("$K" doctor 2>&1)" 'docs/specs/001-refunds/02-broken.md: unknown status "nope"'
rm "$C/docs/specs/001-refunds/02-broken.md"
mkdir -p "$C/docs/runbooks" "$C/docs/assets"
out=$("$K" doctor 2>&1); rc=$?
ok "doctor warns on a folder nobody mapped" has "$out" "warn: docs/runbooks/ is under docs/ but no docs: key names it"
ok "…and a warning doesn't fail doctor" test "$rc" -eq 0
awk 'NR>1 && $0=="---" && !d { print "docs:\n  runbooks: docs/runbooks"; d=1 } { print }' "$TMP/brigade.md.bak" > "$C/.claude/brigade.md"
out=$("$K" doctor 2>&1)
ok "a key the sous added under docs: maps it" bash -c '! printf "%s" "$1" | grep -q "runbooks/ is under"' _ "$out"
ok "…but it still warns about the missing INDEX.md" has "$out" "warn: docs.runbooks: docs/runbooks/ has no INDEX.md"
rmdir "$C/docs/assets"
printf 'x' > "$C/docs/notafolder"
awk 'NR>1 && $0=="---" && !d { print "docs:\n  runbooks: docs/notafolder"; d=1 } { print }' "$TMP/brigade.md.bak" > "$C/.claude/brigade.md"
out=$("$K" doctor 2>&1); rc=$?
ok "a mapped path that is a file is an error" bash -c 'test "$1" -ne 0 && printf "%s" "$2" | grep -q "docs.runbooks: docs/notafolder is a file, not a folder"' _ "$rc" "$out"
rm "$C/docs/notafolder"
cp "$TMP/brigade.md.bak" "$C/.claude/brigade.md"; rm -r "$C/docs/runbooks"

section "index"
X="$TMP/idx"; new_repo "$X" "trunk: main"
mkdir -p "$X/docs/plans" "$X/docs/journal/completed" "$X/docs/checklists"
ki() { ( cd "$X" && "$K" "$@" 2>&1 ); }
xcommit() { git -C "$X" add -A && git -C "$X" commit -qm "$1"; }
plan() {  # plan <file> <ticket> <title>
  printf -- '---\nticket: "%s"\ntitle: %s\n---\n\n# body\n' "$2" "$3" > "$X/docs/plans/$1"
}
plan 20-a.md '#1' 'Alpha'
out=$(ki index)
ok "index writes the plans table" has "$out" 'docs/plans/INDEX.md: regenerated \(1 row'
ok "…one row per plan: file, summary, ticket" grep -qF '| [20-a.md](20-a.md) | Alpha | #1 |' "$X/docs/plans/INDEX.md"
ok "…under a marker that says it is generated" grep -qF 'Generated by kitchen.sh index' "$X/docs/plans/INDEX.md"
ok "…and an empty folder still gets its table" grep -qF '| File | Summary | Ticket |' "$X/docs/journal/INDEX.md"
sum1=$(cksum < "$X/docs/plans/INDEX.md")
out=$(ki index)
ok "a second run says up to date" has "$out" 'docs/plans/INDEX.md: up to date'
ok "…and leaves the bytes alone" test "$sum1" = "$(cksum < "$X/docs/plans/INDEX.md")"
plan gh-5-c.md '#5' 'Gamma'
plan 13-z.md '#13' 'Pipe | in title'
printf -- '---\nticket: "#20"\nplan: docs/plans/20-a.md\n---\n# Acceptance\n' > "$X/docs/checklists/20-a.md"
printf '# A journal with no frontmatter\n' > "$X/docs/journal/completed/9-old.md"
ki index >/dev/null
ok "rows sort by path, byte order" bash -c 'grep -o "^| \[[^]]*\.md\]" "$1" | tr -d "|[] " | paste -sd, - | grep -qx "13-z.md,20-a.md,gh-5-c.md"' _ "$X/docs/plans/INDEX.md"
ok "a pipe in a title is escaped" grep -qF '| Pipe \| in title | #13 |' "$X/docs/plans/INDEX.md"
ok "a checklist with no title takes its plan's" grep -qF '| [20-a.md](20-a.md) | Alpha | #20 |' "$X/docs/checklists/INDEX.md"
ok "a file with no frontmatter takes its first heading, and a journal in a subfolder keeps its row" grep -qF '| [completed/9-old.md](completed/9-old.md) | A journal with no frontmatter | — |' "$X/docs/journal/INDEX.md"
xcommit base
git -C "$X" checkout -q -b branch-a; plan 21-a.md '#21' 'Branch a'; ki index >/dev/null; xcommit a
git -C "$X" checkout -q main; git -C "$X" checkout -q -b branch-b; plan 22-b.md '#22' 'Branch b'; ki index >/dev/null; xcommit b
git -C "$X" checkout -q branch-a
git -C "$X" merge -q branch-b >/dev/null 2>&1; rc=$?
ok "two branches that each add a plan do conflict on the INDEX" bash -c 'test "$1" -ne 0 && grep -q "^<<<<<<<" "$2"' _ "$rc" "$X/docs/plans/INDEX.md"
ki index >/dev/null
ok "index leaves no conflict marker in the conflicted INDEX" bash -c '! grep -qE "^(<<<<<<<|=======|>>>>>>>)" "$1"' _ "$X/docs/plans/INDEX.md"
ok "…keeps both branches' rows" bash -c 'grep -qF "| [21-a.md](21-a.md) | Branch a | #21 |" "$1" && grep -qF "| [22-b.md](22-b.md) | Branch b | #22 |" "$1"' _ "$X/docs/plans/INDEX.md"
ok "…as one table in order" bash -c 'grep -o "^| \[[^]]*\.md\]" "$1" | tr -d "|[] " | paste -sd, - | grep -qx "13-z.md,20-a.md,21-a.md,22-b.md,gh-5-c.md"' _ "$X/docs/plans/INDEX.md"
ok "…so the merge completes" bash -c 'cd "$1" && git add -A && git commit -q --no-edit' _ "$X"
plan 23-c.md '#23' 'Not indexed yet'
out=$(ki index --check); rc=$?
ok "index --check exits 1 when a plan has no row" bash -c 'test "$1" -eq 1' _ "$rc"
ok "…says which INDEX is out of date" has "$out" 'docs/plans/INDEX.md: out of date'
ok "…and writes nothing" bash -c '! grep -q 23-c "$1"' _ "$X/docs/plans/INDEX.md"
out=$(ki doctor)
ok "doctor warns about an out-of-date generated INDEX" has "$out" 'warn: docs.plans: docs/plans/INDEX.md is out of date \(run kitchen.sh index\)'
ki index >/dev/null
out=$(ki index --check); rc=$?
ok "after index, --check passes" bash -c 'test "$1" -eq 0' _ "$rc"
ok "…and doctor stops warning" bash -c '! printf "%s" "$1" | grep -q "INDEX.md is out of date"' _ "$(ki doctor)"
printf '# Plans I keep by hand\n\n| [gone.md](gone.md) | an old plan |\n' > "$X/docs/plans/INDEX.md"
cp "$X/docs/plans/INDEX.md" "$TMP/hand-index"
out=$(ki index)
ok "a hand-written INDEX is left alone and says so" has "$out" 'docs/plans/INDEX.md: hand-written, left alone'
ok "…byte for byte" cmp -s "$TMP/hand-index" "$X/docs/plans/INDEX.md"
ok "…and --check does not call it out of date" bash -c 'cd "$1" && "$2" index --check >/dev/null' _ "$X" "$K"
out=$(ki index --adopt)
ok "--adopt takes it over" bash -c 'grep -qF "Generated by kitchen.sh index" "$1" && grep -qF "[21-a.md](21-a.md)" "$1"' _ "$X/docs/plans/INDEX.md"
ok "…and lists the row it drops" has "$out" 'dropped row for gone.md \(no such file\)'
xcommit adopted
git -C "$X" worktree add -q -b station-branch "$TMP/idx-station-1"
printf -- '---\nticket: "#30"\ntitle: Station plan\n---\n' > "$TMP/idx-station-1/docs/plans/30-s.md"
( cd "$TMP/idx-station-1" && "$K" index >/dev/null 2>&1 )
ok "run in a station, index writes the station's INDEX" grep -qF '[30-s.md](30-s.md) | Station plan | #30 |' "$TMP/idx-station-1/docs/plans/INDEX.md"
ok "…and leaves the main checkout's alone" bash -c '! grep -q 30-s "$1"' _ "$X/docs/plans/INDEX.md"
git -C "$X" worktree remove --force "$TMP/idx-station-1"
Y="$TMP/idx2"; new_repo "$Y" $'trunk: main\ndocs:\n  plans: none'
mkdir -p "$Y/docs/plans"; plan_y() { printf -- '---\nticket: "#1"\ntitle: Skipped\n---\n' > "$Y/docs/plans/1-a.md"; }; plan_y
out=$(cd "$Y" && "$K" index 2>&1); rc=$?
ok "a folder the map sets to none is skipped without error" bash -c 'test "$1" -eq 0 && test ! -e "$2/docs/plans/INDEX.md"' _ "$rc" "$Y"

section "sessions"
slug() { (cd "$1" && pwd -P) | sed 's/[^A-Za-z0-9]/-/g'; }
CFG="$TMP/claude-config"
mkdir -p "$CFG/projects/$(slug "$C")" "$CFG/projects/$(slug "$S1")" "$HOME/.claude/projects/$(slug "$C")"
touch "$CFG/projects/$(slug "$C")/old-session.jsonl"
touch "$HOME/.claude/projects/$(slug "$C")/home-session.jsonl"
touch "$CFG/projects/$(slug "$S1")/cook-session.jsonl"
sleep 1; touch "$CFG/projects/$(slug "$C")/new-session.jsonl"
out=$(CLAUDE_CONFIG_DIR="$CFG" "$K" sessions)
ok "sessions reads CLAUDE_CONFIG_DIR, newest first" test "$(printf '%s\n' "$out" | xargs -n1 basename | tr '\n' ' ')" = "new-session.jsonl old-session.jsonl "
ok "…and ignores ~/.claude when CLAUDE_CONFIG_DIR is set" bash -c "! printf '%s' \"\$1\" | grep -q home-session" _ "$out"
ok "sessions falls back to ~/.claude without CLAUDE_CONFIG_DIR" has "$("$K" sessions)" "home-session\.jsonl"
ok "sessions --dir lists a station's sessions" has "$(CLAUDE_CONFIG_DIR="$CFG" "$K" sessions --dir "$S1")" "cook-session\.jsonl"
ok "sessions from inside a station lists that station's" has "$(cd "$S1" && CLAUDE_CONFIG_DIR="$CFG" "$K" sessions)" "cook-session\.jsonl"
ok "sessions says when there are none" has "$(CLAUDE_CONFIG_DIR="$TMP/empty" "$K" sessions)" "No saved sessions"

section "clear: the sous clears a session"
# A fake registry under ~/.claude/sessions (sleepers stand in for claude), handmade transcripts
# under ~/.claude/projects, and the tmux stub that logs what gets typed into which pane.
if command -v node >/dev/null 2>&1; then
  REG="$HOME/.claude/sessions"; mkdir -p "$REG"
  reg() {  # reg <cwd> <sid> <status> <pane> <name> → pid (a sleeper standing in for claude; killed from the registry at the end)
    sleep 300 >/dev/null 2>&1 & local p=$!
    printf '{"pid":%s,"sessionId":"%s","cwd":"%s","status":"%s","tmux":"%s","name":"%s","updatedAt":1}\n' "$p" "$2" "$1" "$3" "$4" "$5" > "$REG/$p.json"; printf '%s' "$p"
  }
  # One cook transcript: a turn at 10:00 (the brief), [plan] sent, [approved] back at 10:02; the last turn starts at 10:02.
  tline() { printf '{"type":"%s","timestamp":"%s","message":{"role":"%s","id":"%s","model":"claude-sonnet-5-5","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":%s},"content":[%s]}}\n' "$1" "$2" "$3" "$4" "$5" "$6"; }
  txt() { printf '{"type":"text","text":"%s"}' "$1"; }
  snd() { printf '{"type":"tool_use","id":"%s","name":"SendMessage","input":{"to":"sous","message":"%s"}}' "$1" "$2"; }
  PJ="$HOME/.claude/projects/$(slug "$S1")"; mkdir -p "$PJ"
  { tline user 2026-01-01T10:00:00Z user u1 0 "$(txt '[brief] BKLG-001 go')"
    tline assistant 2026-01-01T10:01:00Z assistant m1 1000 "$(snd t1 '[plan] BKLG-001 ready: /x')"
    tline user 2026-01-01T10:02:00Z user u2 0 "$(txt 'Another Claude session sent a message:\n<cross-session-message from-name=\"app-sous\">\n[approved] BKLG-001: /x · sous')"
  } > "$PJ/sid-c1.jsonl"
  mkdir -p "$S1/docs/journal"
  : > "$TB/tmux.log"
  p1=$(reg "$S1" sid-c1 busy %7 app-cook-1)
  out=$(PATH="$TB:$PATH" "$K" clear station-1 2>&1); rc=$?
  ok "clear refuses a busy cook" bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "is busy"' _ "$rc" "$out"
  sed -i.bak 's/"busy"/"idle"/' "$REG/$p1.json"
  out=$(PATH="$TB:$PATH" "$K" clear station-1 2>&1); rc=$?
  ok "clear refuses a cook with no handoff on disk" bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "no handoff"' _ "$rc" "$out"
  printf '# journal\n\n## Handoff — 2026-01-01 09:00 · app-cook-1\n- Stage: served\n' > "$S1/docs/journal/BKLG-001-open.md"
  touch -t 202512310000 "$S1/docs/journal/BKLG-001-open.md"   # older than the last turn (2026-01-01 10:02)
  out=$(PATH="$TB:$PATH" "$K" clear station-1 2>&1); rc=$?
  ok "clear refuses a handoff older than the cook's last turn" bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "older than its last turn"' _ "$rc" "$out"
  touch "$S1/docs/journal/BKLG-001-open.md"   # now: newer than the last turn
  { tline assistant 2026-01-01T10:03:00Z assistant m2 1000 "$(snd t2 '[gate] BKLG-001 Q1, see journal. commis: nothing')"; } >> "$PJ/sid-c1.jsonl"
  out=$(PATH="$TB:$PATH" "$K" clear station-1 2>&1); rc=$?
  ok "clear refuses a cook still waiting on an answer" bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "waiting on an answer to its \[gate\]"' _ "$rc" "$out"
  ok "…and typed nothing into tmux" test ! -s "$TB/tmux.log"
  { tline user 2026-01-01T10:04:00Z user u3 0 "$(txt '<cross-session-message from-name=\"app-sous\">\n[heard] Q1: three')"; } >> "$PJ/sid-c1.jsonl"
  touch "$S1/docs/journal/BKLG-001-open.md"
  out=$(PATH="$TB:$PATH" "$K" clear station-1 2>&1); rc=$?
  ok "clear clears an idle, handed-off, answered cook" bash -c '[ "$1" -eq 0 ] && printf "%s" "$2" | grep -q "^Cleared station-1 (app-cook-1)"' _ "$rc" "$out"
  ok "…typing /clear into its pane, then /bk:line-cook" bash -c 'grep -q "send-keys -t %7 -l /clear" "$1" && grep -q "send-keys -t %7 -l /bk:line-cook" "$1" && [ "$(grep -c "send-keys -t %7 Enter" "$1")" = 2 ]' _ "$TB/tmux.log"
  # The sous: named in .claude/sous, its handoff is .claude/sous-handoff.md, its "open" is an open ask.
  PS="$HOME/.claude/projects/$(slug "$C")"; mkdir -p "$PS"
  { tline user 2026-01-01T11:00:00Z user s1 0 "$(txt 'run the kitchen')"
    tline assistant 2026-01-01T11:01:00Z assistant sm1 400000 "$(txt 'the board')"
  } > "$PS/sid-s1.jsonl"
  pS=$(reg "$C" sid-s1 idle %0 app-7d); "$K" sous --set app-7d >/dev/null
  mv "$C/.claude/asks.md" "$C/.claude/asks.md.keep" 2>/dev/null   # earlier sections' asks stay out of this one
  : > "$TB/tmux.log"
  out=$(PATH="$TB:$PATH" "$K" clear sous 2>&1); rc=$?
  ok "clear refuses the sous with no handoff note" bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "no handoff"' _ "$rc" "$out"
  printf '# Sous handoff\n' > "$C/.claude/sous-handoff.md"
  aid=$("$K" asks --add "which queue?" --gap ruling)
  out=$(PATH="$TB:$PATH" "$K" clear sous 2>&1); rc=$?
  ok "clear refuses the sous while an ask to the head chef is open" bash -c '[ "$1" -ne 0 ] && printf "%s" "$2" | grep -q "open ask"' _ "$rc" "$out"
  "$K" asks --answer "$aid" "the fare queue" >/dev/null
  ok "board warns when the sous's turns are over the context line" has "$("$K" board)" "Context: the sous is at 400k cache-read tokens a turn .* kitchen.sh clear sous"
  out=$(PATH="$TB:$PATH" "$K" clear sous 2>&1); rc=$?
  ok "clear clears an idle sous once its note is written and nothing is open" bash -c '[ "$1" -eq 0 ] && printf "%s" "$2" | grep -q "^Cleared the sous (app-7d)"' _ "$rc" "$out"
  ok "…typing /clear, then /bk:sous-chef, into its pane" bash -c 'grep -q "send-keys -t %0 -l /clear" "$1" && grep -q "send-keys -t %0 -l /bk:sous-chef" "$1" && ! grep -q "line-cook" "$1"' _ "$TB/tmux.log"
  # The sous clearing itself: its own tool call is the busy turn, so the typing waits for idle.
  sed -i.bak 's/"idle"/"busy"/' "$REG/$pS.json"; : > "$TB/tmux.log"
  out=$(PATH="$TB:$PATH" "$K" clear sous 2>&1); rc=$?
  ok "a busy sous clearing itself is deferred, not refused" bash -c '[ "$1" -eq 0 ] && printf "%s" "$2" | grep -q "^Clearing the sous (app-7d) when this turn ends"' _ "$rc" "$out"
  ok "…and nothing is typed while it is busy" test ! -s "$TB/tmux.log"
  sleep 2; sed -i.bak 's/"busy"/"idle"/' "$REG/$pS.json"
  ok "…then /clear and /bk:sous-chef are typed once it is idle" bash -c 'for i in $(seq 1 30); do grep -q "send-keys -t %0 -l /bk:sous-chef" "$1" 2>/dev/null && grep -q "send-keys -t %0 -l /clear" "$1" && exit 0; sleep 1; done; exit 1' _ "$TB/tmux.log"
  sed -i.bak 's/400000/1000/' "$PS/sid-s1.jsonl"
  ok "…and the board is quiet when the sous is under the line" bash -c '! printf "%s" "$("$1" board)" | grep -q "^Context:"' _ "$K"
  ok "clear without a tmux pane refuses" bash -c 'sed -i.bak "s/\"tmux\":\"%0\"/\"tmux\":\"\"/" "$1"; ! "$2" clear sous >/dev/null 2>&1' _ "$REG/$pS.json" "$K"
  ok "clear of an unknown station refuses" bash -c '! "$1" clear station-9 >/dev/null 2>&1' _ "$K"
  for f in "$REG"/*.json; do kill "$(sed -n 's/.*"pid":\([0-9]*\).*/\1/p' "$f")" 2>/dev/null; done
  rm -rf "$REG" "$C/.claude/sous-handoff.md" "$C/.claude/asks.md"; rm -f "$S1/docs/journal/BKLG-001-open.md"
  mv "$C/.claude/asks.md.keep" "$C/.claude/asks.md" 2>/dev/null
else
  echo "# node not installed: skipping the clear tests"
fi

section "ship: the sous merges a green PR"
# A stub gh: `pr view` answers with $GH_VIEW (state|draft|base|head|mergeable|mergeState|checks),
# `pr merge` is logged. The config has no gates: block, so gates.merge is the default, sous-chef.
GB="$TMP/ghbin"; mkdir -p "$GB"; : > "$GB/gh.log"
printf '#!/bin/sh\necho "gh $*" >> "$GH_LOG"\ncase "$1 $2" in\n  "pr view") printf "%%s\\n" "$GH_VIEW" ;;\n  "pr merge") exit 0 ;;\n  *) exit 1 ;;\nesac\n' > "$GB/gh"; chmod +x "$GB/gh"
ship() { GH_LOG="$GB/gh.log" GH_VIEW="$1" PATH="$GB:$PATH" "$K" ship "$2" 2>&1; }
GOOD="OPEN|false|main|bklg-001-open|MERGEABLE|CLEAN|SUCCESS,SUCCESS"
ok "ship without a PR number is a usage error" bash -c '! "$1" ship >/dev/null 2>&1' _ "$K"
out=$(ship "MERGED|false|main|b|UNKNOWN|UNKNOWN|SUCCESS" 12); ok "ship refuses a PR that isn't open" has "$out" "Not merged: #12 is MERGED"
out=$(ship "OPEN|true|main|b|MERGEABLE|CLEAN|SUCCESS" 12); ok "ship refuses a draft" has "$out" "is a draft"
out=$(ship "OPEN|false|develop|b|MERGEABLE|CLEAN|SUCCESS" 12); ok "ship refuses a PR against another branch" has "$out" "targets develop, not main"
out=$(ship "OPEN|false|main|b|MERGEABLE|BLOCKED|SUCCESS,IN_PROGRESS" 12); ok "ship refuses while a check is still running, and says how to wait" has "$out" "1 check\(s\) still running. Wait: gh pr checks 12 --watch"
out=$(ship "OPEN|false|main|b|MERGEABLE|BLOCKED|FAILURE,SUCCESS" 12); ok "ship refuses a red check" has "$out" "1 red check\(s\)"
out=$(ship "OPEN|false|main|b|CONFLICTING|DIRTY|SUCCESS" 12); ok "ship refuses a conflict" has "$out" "is CONFLICTING"
out=$(ship "OPEN|false|main|b|MERGEABLE|BEHIND|SUCCESS" 12); ok "ship refuses a branch behind trunk" has "$out" "is behind main"
out=$(ship "OPEN|false|main|b|MERGEABLE|BLOCKED|SUCCESS" 12); ok "ship refuses a blocked PR and doesn't override" has "$out" "is blocked"
ok "…and none of those called gh pr merge" bash -c '! grep -q "pr merge" "$1"' _ "$GB/gh.log"
out=$(ship "$GOOD" 12); rc=$?
ok "ship merges an open, green, up-to-date PR against trunk" bash -c '[ "$1" = 0 ] && printf "%s" "$2" | grep -q "^Merged #12 (bklg-001-open) into main by merge"' _ "$rc" "$out"
ok "…with a merge commit" has "$(cat "$GB/gh.log")" "gh pr merge 12 --merge"
ok "…and #N is accepted too" has "$(ship "$GOOD" '#13')" "^Merged #13"
cp "$C/.claude/brigade.md" "$TMP/brigade.ship.bak"
printf -- '---\ntrunk: main\nkitchen_mode: clone\ngates:\n  merge: sous-chef\n  merge_method: squash\n---\n' > "$C/.claude/brigade.md"
: > "$GB/gh.log"; out=$(ship "$GOOD" 14)
ok "gates.merge_method: squash is passed to gh" has "$(cat "$GB/gh.log")" "gh pr merge 14 --squash"
printf -- '---\ntrunk: main\nkitchen_mode: clone\ngates:\n  merge: head-chef\n---\n' > "$C/.claude/brigade.md"
: > "$GB/gh.log"; out=$(ship "$GOOD" 15); rc=$?
ok "gates.merge: head-chef makes ship refuse: the merge is the head chef's" bash -c '[ "$1" != 0 ] && printf "%s" "$2" | grep -q "gates.merge is head-chef .* the head chef'"'"'s"' _ "$rc" "$out"
ok "…without calling gh at all" test ! -s "$GB/gh.log"
rm -f "$C/.claude/settings.local.json"
out=$(PATH="$GB:$NB" "$K" open --terminal print --bare 2>&1 || true)
ok "open with the head-chef gate seeds no sous permissions" test ! -e "$C/.claude/settings.local.json"
cp "$TMP/brigade.ship.bak" "$C/.claude/brigade.md"
out=$(PATH="$GB:$NB" "$K" open --terminal print --bare 2>&1 || true)
ok "open with the default gate seeds the sous's gh permissions in the main checkout" bash -c 'grep -q "Bash(gh pr merge:\*)" "$1/.claude/settings.local.json" && printf "%s" "$2" | grep -q "sous: permissions seeded"' _ "$C" "$out"
ok "…kept out of git" test "$(git -C "$C" status --porcelain | grep -c settings.local)" = 0
rm -f "$C/.claude/settings.local.json"

section "remove (clone)"
out=$(echo nope | "$K" remove 2>&1)
ok "remove aborts without 'delete'" test -d "$C/stations/station-1"
out=$(echo delete | "$K" remove 2>&1)
ok "remove deletes the stations folder" test ! -e "$C/stations"

# =============================================================================
section "worktree mode, inside a workspace repo"
# =============================================================================
W="$TMP/ws"; git init -q "$W"; git -C "$W" checkout -q -b deploy
echo "app" > "$W/.gitignore"; git -C "$W" add -A; git -C "$W" commit -qm workspace
A="$W/app"
new_repo "$A" 'trunk: main
install: "true"
kitchen_mode: worktree
stations: 2'
push_all "$A" "brigade setup"
cd "$A" || exit 1

out=$("$K" setup 2>&1)
ok "worktree setup creates ../app-stations/station-N" test -e "$W/app-stations/station-1/.git" -a -e "$W/app-stations/station-2/.git"
ok "stations are worktrees (.git is a file)" test -f "$W/app-stations/station-1/.git"
ok "git lists both worktrees" test "$(git -C "$A" worktree list | wc -l | tr -d ' ')" = 3
ok "idle stations are detached at origin/main" test -z "$(git -C "$W/app-stations/station-1" branch --show-current)"
ok "the ignore line goes to the ENCLOSING workspace repo" grep -qx "/app-stations/" "$W/.gitignore"
ok "…and not to the app repo" bash -c "! grep -q app-stations '$A/.gitignore' 2>/dev/null"
ok "worktree setup prints the shared-stash warning" has "$out" "Stashes are shared"
ok "worktree setup skips the git clean -fdx warning" bash -c "! printf '%s' \"\$1\" | grep -q 'git clean -fdx'" _ "$out"
ok "fresh worktree stations are clean" test -z "$(git -C "$W/app-stations/station-2" status --porcelain)"

WS1="$W/app-stations/station-1"
ok "role is cook inside a worktree station" test "$(cd "$WS1" && "$K" role | cut -d' ' -f1-2)" = "cook station-1"
ok "status labels a detached station" has "$("$K" status)" "station-2 +detached @"
before=$(git -C "$A" status --porcelain)
out=$("$K" board)
ok "board in worktree mode writes .claude/board.md and leaves the tree as it was" bash -c 'test "$1" = "$(cat "$2/.claude/board.md")" && test "$3" = "$(git -C "$2" status --porcelain)"' _ "$out" "$A" "$before"
rm "$A/.claude/board.md"; (cd "$WS1" && "$K" board >/dev/null)
before=$(git -C "$WS1" status --porcelain)
"$K" open --terminal print >/dev/null
ok "a worktree station gets .claude/cook, kept out of git" bash -c 'test -x "$1/.claude/cook" && test "$2" = "$(git -C "$1" status --porcelain)"' _ "$WS1" "$before"
ok "…and it runs in that worktree" has "$(PATH="$EB:$PATH" "$WS1/.claude/cook")" "pwd=$(cd "$WS1" && pwd -P) "
ok "board from a worktree station writes nothing" bash -c '! test -e "$1/.claude/board.md" && ! test -e "$2/.claude/board.md"' _ "$A" "$WS1"
before=$(git -C "$A" status --porcelain)
"$K" sous --set app-f6 >/dev/null
ok "a worktree station reads the sous's name from the main checkout" test "$(cd "$WS1" && "$K" sous)" = app-f6
ok "…and .claude/sous leaves the tree as it was" test "$before" = "$(git -C "$A" status --porcelain)"
git -C "$WS1" switch -q -c bklg-001-open origin/main; echo x > "$WS1/wip.txt"
ok "status run from inside a station still sees every station" has "$(cd "$WS1" && "$K" status)" "station-2"
out=$("$K" sync)
ok "worktree sync skips a dirty station" has "$out" "station-1: dirty"
ok "worktree sync re-detaches a clean station" has "$out" "station-2: synced, detached at origin/main"
out=$(echo delete | "$K" remove 2>&1)
ok "remove refuses a dirty worktree" has "$out" "station-1: NOT removed"
ok "…and keeps its work" test -f "$WS1/wip.txt"
rm "$WS1/wip.txt"
out=$(echo delete | "$K" remove 2>&1)
ok "remove clears clean worktrees" test ! -e "$W/app-stations"
ok "the cook's branch survives removal" git -C "$A" rev-parse --verify -q bklg-001-open
ok "git has no stale worktree records" test "$(git -C "$A" worktree list | wc -l | tr -d ' ')" = 1

# ---------------------------------------------------------------------------
section "check: the config's check runs once per tree"
CK="$TMP/ck"; RUNS="$TMP/ck-runs"; REDFILE="$TMP/ck-fail"; MUT="$TMP/ck-mutate"; : > "$RUNS"
# one command for the whole section: it counts its runs outside the tree, and the files that
# make it fail or rewrite a tracked file live outside the tree too, so the config never moves it
new_repo "$CK" "trunk: main
check: \"echo ran >> $RUNS; test ! -f $REDFILE; r=\$?; test -f $MUT && echo x\$RANDOM >> a.txt; exit \$r\""
echo one > "$CK/a.txt"; push_all "$CK" init
runs() { wc -l < "$RUNS" | tr -d ' '; }
loglines() { wc -l < "$1/.claude/check.log" | tr -d ' '; }
out=$(cd "$CK" && "$K" check); rc=$?
ok "the first call runs the command, green" bash -c 'test "$1" = 0 && test "$2" = 1' _ "$rc" "$(runs)"
ok "…says it ran" has "$out" "^check: green \\(ran, [0-9]+s\\)"
ok "…and logs the tree, the exit code and the command" has "$(cat "$CK/.claude/check.log")" "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z tree=[0-9a-f]{40} rc=0 secs=[0-9]+ cmd=[0-9a-f]{12}$"
ok "…keeping the log and the output out of git" test -z "$(git -C "$CK" status --porcelain | grep 'check\.')"
out=$(cd "$CK" && "$K" check); rc=$?
ok "a second call on the unchanged tree runs nothing" bash -c 'test "$1" = 0 && test "$2" = 1' _ "$rc" "$(runs)"
ok "…and says it trusted the record" has "$out" "^check: green on this tree, not re-run \\(recorded [0-9T:Z-]+, [0-9]+s\\)"
ok "…and writes no log line" test "$(loglines "$CK")" = 1
(cd "$CK" && "$K" check --force) >/dev/null
ok "--force runs it again" test "$(runs)" = 2
echo two > "$CK/a.txt"; (cd "$CK" && "$K" check) >/dev/null
ok "a changed tracked file runs it again" test "$(runs)" = 3
(cd "$CK" && "$K" check) >/dev/null
ok "…and that tree is then trusted" test "$(runs)" = 3
echo new > "$CK/b.txt"; (cd "$CK" && "$K" check) >/dev/null
ok "a new untracked file runs it again" test "$(runs)" = 4
rm "$CK/b.txt"; (cd "$CK" && "$K" check) >/dev/null
ok "going back to a tree that already passed is trusted" test "$(runs)" = 4
rm "$CK/a.txt"; (cd "$CK" && "$K" check) >/dev/null
ok "a deleted tracked file runs it again" test "$(runs)" = 5
echo two > "$CK/a.txt"
# a green line for another command is not this command's green
cp "$CK/.claude/check.log" "$TMP/ck-log.keep"
sed -i.bak 's/ cmd=[0-9a-f]*/ cmd=000000000000/' "$CK/.claude/check.log"; rm -f "$CK/.claude/check.log.bak"
(cd "$CK" && "$K" check) >/dev/null
ok "a green recorded for another command is not trusted" test "$(runs)" = 6
cp "$TMP/ck-log.keep" "$CK/.claude/check.log"
# a red check is logged, and never trusted
touch "$REDFILE"; echo three > "$CK/a.txt"
out=$(cd "$CK" && "$K" check); rc=$?
ok "a red check exits with its own code" test "$rc" = 1
ok "…says RED and shows the output file" has "$out" "^check: RED \\(rc 1, [0-9]+s\\)\\. Last lines of .*check\\.out"
ok "…and logs rc=1" has "$(tail -1 "$CK/.claude/check.log")" " rc=1 "
(cd "$CK" && "$K" check) >/dev/null
ok "a red result is run again, not trusted" test "$(runs)" = 8
rm "$REDFILE"
# a check that rewrites a tracked file is not trusted
touch "$MUT"
out=$(cd "$CK" && "$K" check)
ok "a run that moves the tree is logged as moved" has "$(tail -1 "$CK/.claude/check.log")" " moved$"
ok "…and says its green is not trusted" has "$out" "not trusted"
(cd "$CK" && "$K" check) >/dev/null
ok "…so the next call runs it again" test "$(runs)" = 10
rm "$MUT"
# a worktree station keeps its own log
git -C "$CK" worktree add -q --detach "$TMP/ck-st1" main 2>/dev/null
out=$(cd "$TMP/ck-st1" && "$K" check)
ok "a station run reads the main checkout's config and runs" has "$out" "^check: green \\(ran"
ok "…writes its log in the station" test "$(loglines "$TMP/ck-st1")" = 1
ok "…leaving the station's git status clean" test -z "$(git -C "$TMP/ck-st1" status --porcelain)"
ok "…and its own log is not the main checkout's" test "$(loglines "$CK")" != 1
# no check: command
new_repo "$TMP/ck2" "trunk: main"
out=$(cd "$TMP/ck2" && "$K" check 2>&1); rc=$?
ok "no check: in the config is an error" test "$rc" != 0
ok "…that says so" has "$out" "No check: command"

# =============================================================================
echo ""
echo "# passed $PASS · failed $FAIL · total $N"
[[ "$HOME" != "$REAL_HOME" ]] || { echo "# BUG: HOME was not isolated"; exit 1; }
(( FAIL == 0 ))
