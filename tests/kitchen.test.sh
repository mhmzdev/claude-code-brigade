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
