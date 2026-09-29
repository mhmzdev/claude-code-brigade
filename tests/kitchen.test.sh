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
  printf -- '---\nid: BKLG-001\ntitle: Open ticket\nlane: B\nstatus: backlog\ncook: null\n---\n' > "$dir/docs/backlog/BKLG-001-open.md"
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

out=$("$K" open --terminal print -m "o s")
ok "open names cooks <repo>-cook-N" has "$out" "--name app-cook-2"
ok "open uses one model per station" has "$out" "app-cook-1 --model opus"
ok "open defaults to auto permission mode" has "$out" "--permission-mode auto"
ok "open starts each session as a line cook" has "$out" '"/bk:line-cook"'
ok "open without CLAUDE_CONFIG_DIR prints plain claude" bash -c "! printf '%s' \"\$1\" | grep -q CLAUDE_CONFIG_DIR" _ "$out"
out=$(CLAUDE_CONFIG_DIR=/x/profile "$K" open --terminal print)
ok "open passes CLAUDE_CONFIG_DIR through when set" has "$out" "CLAUDE_CONFIG_DIR=/x/profile claude"
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
out=$(BRIGADE_OS=linux DISPLAY=:0 PATH="$FAKE:$PATH" "$K" open --no-launch)
ok "no Warp: open falls back to the Linux desktop's terminal" has "$out" "would run: gnome-terminal --working-directory=.*station-1"
ok "…running the cook's claude command" has "$out" "app-cook-1"
stub warp-terminal
out=$(BRIGADE_OS=linux DISPLAY=:0 PATH="$FAKE:$PATH" "$K" open --no-launch)
ok "Warp installed: open prefers it over the native terminal" has "$out" "Warp config written"
rm "$FAKE/warp-terminal"
out=$(env -u DISPLAY -u WAYLAND_DISPLAY BRIGADE_OS=linux PATH="$FAKE:$PATH" "$K" open --no-launch)
ok "no Warp and no desktop: open prints the commands" has "$out" "cd .*station-1.* && claude"
out=$(BRIGADE_OS=mac PATH="$FAKE:$PATH" "$K" open --terminal native --no-launch)
ok "macOS native terminal is Terminal.app" has "$out" 'would run: osascript .*Terminal'
out=$(BRIGADE_OS=wsl PATH="$FAKE:$PATH" "$K" open --terminal native --no-launch)
ok "WSL native terminal is Windows Terminal running wsl.exe" has "$out" "would run: wt.exe .*wsl.exe"
out=$(BRIGADE_OS=windows PATH="$FAKE:$PATH" "$K" open --terminal native --no-launch)
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
