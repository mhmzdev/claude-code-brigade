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
for t in git bash sh awk sed grep head tail cat mkdir rm cp mv ls ps lsof readlink chmod nohup sleep printf kill uname dirname basename sort uniq wc tr find date mktemp cut env touch xargs diff paste seq rev tee stat id gh curl python3 open; do p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$NB/$t"; done

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

push_all "$C" "brigade setup"
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

# =============================================================================
echo ""
echo "# passed $PASS · failed $FAIL · total $N"
[[ "$HOME" != "$REAL_HOME" ]] || { echo "# BUG: HOME was not isolated"; exit 1; }
(( FAIL == 0 ))
