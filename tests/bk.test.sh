#!/usr/bin/env bash
# =============================================================================
# tests/bk.test.sh — behaviour tests for bin/bk, the Brigade's command on the machine
#
# A throwaway repo with two clone stations, a sealed PATH, and stubs for the three things
# bk drives: `claude` (only looked for), `tmux` (logs every call; keeps the session,
# windows and panes it is told about in files; on `/exit` it ends the pane's process the
# way a real session would), and the session registry (JSON files under the profile's
# sessions/ folder, pointing at sleeping processes). Nothing touches the real machine:
# HOME is in the temp dir, git ignores your config, BRIGADE_TMUX_DIRS is empty.
#
# Usage:   tests/bk.test.sh            (exit 0 = all passed)
#          KEEP=1 tests/bk.test.sh     (keep the temp dir for poking at)
# =============================================================================

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BK="$REPO/bin/bk"
K="$REPO/plugins/bk/skills/kitchen/kitchen.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/bk-test.XXXXXX")"
REAL_HOME="$HOME"

export HOME="$TMP/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
  GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
  GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com BRIGADE_TMUX_DIRS=""
unset CLAUDE_CONFIG_DIR BRIGADE_TRUNK BRIGADE_KITCHEN BRIGADE_KITCHEN_MODE BRIGADE_STATIONS \
  BRIGADE_MODEL BRIGADE_PERMISSION_MODE BRIGADE_TERMINAL BRIGADE_OS BRIGADE_CLAUDE_ARGS TMUX BK_PLUGIN_DIR
mkdir -p "$HOME"

SLEEPERS=()
cleanup() {
  for p in "${SLEEPERS[@]+"${SLEEPERS[@]}"}"; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
  [[ -n "${KEEP:-}" ]] && echo "kept: $TMP" || rm -rf "$TMP"
}
trap cleanup EXIT

NB="$TMP/bin"; mkdir -p "$NB"
for t in git bash sh awk sed grep head tail cat mkdir rm cp mv ls ps kill readlink chmod sleep printf uname dirname basename sort uniq wc tr find date mktemp cut env touch xargs tee stat id lsof nohup seq ln diff paste rev python3; do p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$NB/$t"; done
printf '#!/bin/sh\necho "claude $* (profile=${CLAUDE_CONFIG_DIR-unset})"\n' > "$NB/claude"; chmod +x "$NB/claude"
ST="$TMP/tmux-state"; mkdir -p "$ST"; : > "$ST/log"
cat > "$NB/tmux" <<EOF
#!/bin/sh
S="$ST"
echo "tmux \$*" >> "\$S/log"
case "\$1" in
  has-session) [ -f "\$S/up" ]; exit \$? ;;
  list-windows) cat "\$S/windows" 2>/dev/null ;;
  list-panes) cat "\$S/panes" 2>/dev/null ;;
  new-session) touch "\$S/up"; echo sous >> "\$S/windows" ;;
  new-window) while [ \$# -gt 0 ] && [ "\$1" != -n ]; do shift; done; echo "\$2" >> "\$S/windows" ;;
  kill-window) : ;;
  kill-session) rm -f "\$S/up" "\$S/windows" "\$S/panes" ;;
  send-keys) # send-keys -t <pane> -l <text>: "/exit" ends the process behind that pane
    if [ "\$5" = /exit ]; then pid=\$(awk -v p="\$3" '\$2==p {print \$1}' "\$S/panes" 2>/dev/null); [ -n "\$pid" ] && kill "\$pid" 2>/dev/null; fi ;;
esac
exit 0
EOF
chmod +x "$NB/tmux"
export PATH="$NB"
tlog() { cat "$ST/log"; }

PASS=0; FAIL=0; N=0
ok() { local desc="$1"; shift; N=$((N+1)); if ( "$@" ) >/dev/null 2>&1; then PASS=$((PASS+1)); echo "ok $N - $desc"; else FAIL=$((FAIL+1)); echo "not ok $N - $desc"; fi; }
has() { printf '%s' "$1" | grep -qE -- "$2"; }
section() { echo "# $1"; }

# the repo: a clone of a bare origin, Brigade config pushed, two clone stations
C="$TMP/app"
git init -q --bare "$C.git"; git clone -q "$C.git" "$C" 2>/dev/null; git -C "$C" checkout -q -b main
mkdir -p "$C/.claude" "$C/docs/backlog"
printf -- '---\ntrunk: main\ninstall: "true"\nstations: 2\n---\n' > "$C/.claude/brigade.md"
git -C "$C" add -A && git -C "$C" commit -qm setup && git -C "$C" push -q -u origin main 2>/dev/null
cd "$C" || exit 1
"$K" setup >"$TMP/setup.log" 2>&1 || { echo "setup failed:"; cat "$TMP/setup.log"; exit 1; }
S1="$C/stations/station-1"

# =============================================================================
section "version, help, where the plugin is"
# =============================================================================
version=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$REPO/plugins/bk/.claude-plugin/plugin.json")
ok "bk version prints the plugin's version" has "$("$BK" version)" "^bk $version \(plugin at $REPO/plugins/bk\)"
ok "bk help prints the usage" has "$("$BK" help)" "bk open"
ok "bk with no command prints the usage" has "$("$BK")" "bk stop"
ok "bk through a symlink (Homebrew's bin/bk) still finds the plugin" bash -c 'mkdir -p "$1/sym" && ln -sf "$2" "$1/sym/bk" && "$1/sym/bk" version | grep -q "plugin at"' _ "$TMP" "$BK"
ok "BK_PLUGIN_DIR pointing nowhere is refused" bash -c '! BK_PLUGIN_DIR=/nope "$1" version 2>&1 | grep -q "^bk "' _ "$BK"
ok "outside a git repo bk says so" bash -c 'cd / && ! "$1" status 2>&1' _ "$BK"

# =============================================================================
section "profiles"
# =============================================================================
mkdir -p "$HOME/.claude"
out=$("$BK" open --no-attach 2>&1); rc=$?
ok "one profile on the machine: open takes it without asking" test "$rc" -eq 0
ok "…says which" has "$out" "Profile: default \($HOME/.claude, from the only profile\)"
ok "…records it in .claude/bk-profile" test "$(cat "$C/.claude/bk-profile")" = "$HOME/.claude"
ok "…kept out of git" git -C "$C" check-ignore -q .claude/bk-profile
ok "…and the sous runs under it with the bundled plugin" has "$(tlog)" "sous CLAUDE_CONFIG_DIR=$HOME/.claude claude --model opus --plugin-dir $REPO/plugins/bk \"/bk:sous-chef\""
ok "…and so does each cook" has "$(tlog)" "station-2 CLAUDE_CONFIG_DIR=$HOME/.claude claude --name app-cook-2 --model sonnet --permission-mode auto --plugin-dir $REPO/plugins/bk \"/bk:line-cook\""
ok "…and the launcher .claude/cook loads it too" has "$(cat "$S1/.claude/cook")" "--plugin-dir $REPO/plugins/bk"
ok "open prints the bk hints" has "$out" "bk attach .*bk peek 1 .*bk stop"
ok "open outside a terminal does not attach" has "$("$BK" open 2>&1 </dev/null)" "Not a terminal: not attaching. bk attach"
mkdir -p "$HOME/.claude-work" "$HOME/.claude-system"; touch "$HOME/.claude.json"
ok "status reads the recorded profile" has "$("$BK" status 2>&1)" "Profile:  default \($HOME/.claude, from .claude/bk-profile\)"
ok "CLAUDE_CONFIG_DIR in the shell wins over the recorded one" has "$(CLAUDE_CONFIG_DIR="$HOME/.claude-work" "$BK" status 2>&1)" "Profile:  work \($HOME/.claude-work, from the shell"
rm "$C/.claude/bk-profile"; "$NB/tmux" kill-session; : > "$ST/log"
out=$("$BK" open --no-attach 2>&1); rc=$?
ok "several profiles, none recorded, no terminal: open refuses" test "$rc" -ne 0
ok "…listing them as --profile flags, dirs only" bash -c 'printf "%s" "$1" | grep -q -- "--profile work" && printf "%s" "$1" | grep -q -- "--profile system" && printf "%s" "$1" | grep -q -- "--profile default" && ! printf "%s" "$1" | grep -q json' _ "$out"
ok "…and opens nothing" test ! -s "$ST/log"
ok "status without a recorded profile says so and still runs" has "$("$BK" status 2>&1)" "Profile:  none recorded"
ok "live needs a profile when several exist" bash -c '! "$1" live status 2>&1' _ "$BK"
ok "a kitchen.sh pass-through does not" has "$("$BK" rail 2>&1)" "BKLG|rail|Rail|ready|tickets"
out=$("$BK" open --profile work --no-attach 2>&1)
ok "--profile NAME picks ~/.claude-NAME" has "$out" "Profile: work \($HOME/.claude-work, from --profile\)"
ok "…records it" test "$(cat "$C/.claude/bk-profile")" = "$HOME/.claude-work"
ok "…and the sessions run under it" has "$(tlog)" "sous CLAUDE_CONFIG_DIR=$HOME/.claude-work claude"
ok "--profile=default is ~/.claude" has "$("$BK" --profile=default status 2>&1)" "Profile:  default \($HOME/.claude, from --profile\)"
ok "--profile with a path is taken as is" has "$("$BK" status --profile "$HOME/.claude-system" 2>&1)" "Profile:  system \($HOME/.claude-system"
ok "an unknown profile is refused, naming the known ones" has "$("$BK" open --profile nope --no-attach 2>&1)" "no profile 'nope'.*default.*system.*work"
ok "a recorded profile that is gone is dropped, not used" bash -c 'echo /gone > "$1/.claude/bk-profile"; "$2" status 2>&1 | grep -q "is gone"' _ "$C" "$BK"
printf '%s\n' "$HOME/.claude-work" > "$C/.claude/bk-profile"

# =============================================================================
section "run: one session already running a skill"
# =============================================================================
out=$("$BK" run grill-me poke holes in this 2>&1)
ok "run starts claude here with the bundled plugin and the skill as its prompt" has "$out" "claude --plugin-dir $REPO/plugins/bk /bk:grill-me poke holes in this"
ok "…under the kitchen's profile" has "$out" "profile=$HOME/.claude-work"
ok "…and says so first" has "$out" "Profile: work · /bk:grill-me poke holes in this"
ok "run with no words sends the bare skill" has "$("$BK" run brainstorm 2>&1)" "/bk:brainstorm \(profile"
ok "run with an unknown skill lists the real ones" has "$("$BK" run nope 2>&1)" "no skill 'nope'.*grill-me.*sous-chef"
ok "run with no skill prints the usage" has "$("$BK" run 2>&1)" "bk run SKILL"
ok "bk setup is the repo setup skill" has "$("$BK" setup 2>&1)" "/bk:setup \(profile"
ok "bk feedback carries the words" has "$("$BK" feedback the sous asked me twice 2>&1)" "/bk:feedback the sous asked me twice"
ok "bk stations creates the stations (kitchen.sh setup)" has "$("$BK" stations -n 2 2>&1)" "station"
mv "$NB/claude" "$TMP/claude.bak"; out=$("$BK" run spec 2>&1); mv "$TMP/claude.bak" "$NB/claude"
ok "run without claude says what to install" has "$out" "claude isn't installed"

# =============================================================================
section "attach and peek"
# =============================================================================
"$NB/tmux" kill-session
ok "attach with no kitchen says to open it" has "$("$BK" attach 2>&1)" "isn't open.*bk open"
ok "peek with no kitchen says the same" has "$("$BK" peek 1 2>&1)" "isn't open"
"$BK" open --no-attach >/dev/null 2>&1; : > "$ST/log"
"$BK" attach; ok "attach goes to the sous window" has "$(tlog)" "attach-session -t app-brigade:sous"
"$BK" peek 2; ok "peek N goes to station-N" has "$(tlog)" "attach-session -t app-brigade:station-2"
"$BK" peek sous; ok "peek sous is the sous" test "$(grep -c 'attach-session -t app-brigade:sous' "$ST/log")" = 2
"$BK" peek station-1; ok "peek station-N works too" has "$(tlog)" "attach-session -t app-brigade:station-1"
ok "peek of a window that isn't there says which are" has "$("$BK" peek 7 2>&1)" "no window 'station-7'.*sous station-1 station-2"
ok "peek with a bad word prints the usage" has "$("$BK" peek two 2>&1)" "bk peek N"
ok "peek with no word prints the usage" has "$("$BK" peek 2>&1)" "bk peek N"
: > "$ST/log"; TMUX=/tmp/tmux-1/default,1,0 "$BK" attach
ok "from inside tmux, attach switches the client instead" has "$(tlog)" "switch-client -t app-brigade:sous"
ok "status says the kitchen is open and lists the windows" has "$("$BK" status 2>&1)" "Kitchen:  open in tmux 'app-brigade', windows: sous station-1 station-2"

# =============================================================================
section "stop (a pause) and the resume"
# =============================================================================
REG="$HOME/.claude-work/sessions"; mkdir -p "$REG"
future=$(( $(date +%s) * 1000 + 3600000 ))
start_session() {  # start_session <cwd> <session id> <status> → the pid of a sleeper standing in for claude
  sleep 300 >/dev/null 2>&1 & local p=$!; SLEEPERS+=("$p")   # quiet, or the $(…) around us waits for it
  printf '{"pid":%s,"sessionId":"%s","cwd":"%s","status":"%s","statusUpdatedAt":%s,"name":"x"}\n' "$p" "$2" "$1" "$3" "$future" > "$REG/$p.json"
  printf '%s' "$p"
}
pS=$(start_session "$C" sid-sous idle); p1=$(start_session "$S1" sid-one busy)
printf '%s %%0 sous\n%s %%1 station-1\n' "$pS" "$p1" > "$ST/panes"   # station-2 has a window but no session
sleep 300 >/dev/null 2>&1 & SLEEPERS+=("$!"); printf '{"pid":%s,"sessionId":"sid-other","cwd":"/elsewhere","status":"idle"}\n' "$!" > "$REG/$!.json"   # another kitchen's session
( sleep 3; sed -i.bak 's/"busy"/"idle"/' "$REG/$p1.json" ) &
: > "$ST/log"
out=$("$BK" stop --timeout 30 2>&1); rc=$?
ok "stop exits 0" test "$rc" -eq 0
ok "stop types /bk:handoff into the sous and every cook" bash -c 'grep -q "send-keys -t %0 -l /bk:handoff" "$1" && grep -q "send-keys -t %1 -l /bk:handoff" "$1"' _ "$ST/log"
ok "…not into a session outside this kitchen" bash -c '! grep -q "elsewhere" "$1"' _ "$ST/log"
ok "…waits for the busy cook to go idle" has "$out" "Waiting for each session"
ok "…then types /exit into each" bash -c 'grep -q "send-keys -t %0 -l /exit" "$1" && grep -q "send-keys -t %1 -l /exit" "$1"' _ "$ST/log"
ok "…handoff before exit" bash -c 'test "$(grep -n "/bk:handoff" "$1" | tail -1 | cut -d: -f1)" -lt "$(grep -n "/exit" "$1" | head -1 | cut -d: -f1)"' _ "$ST/log"
ok "…saves the sous's session id in .claude/sous-session" test "$(cat "$C/.claude/sous-session")" = sid-sous
ok "…and the cook's in its station's .claude/cook-session" test "$(cat "$S1/.claude/cook-session")" = sid-one
ok "…both kept out of git" bash -c 'git -C "$1" check-ignore -q .claude/sous-session && git -C "$2" check-ignore -q .claude/cook-session' _ "$C" "$S1"
ok "…kills the tmux session" has "$(tlog)" "kill-session -t app-brigade"
ok "…and says what it saved" has "$out" "Paused: sous station-1 saved"
ok "…the sessions are gone" bash -c '! kill -0 "$1" 2>/dev/null && ! kill -0 "$2" 2>/dev/null' _ "$pS" "$p1"
ok "status says paused" has "$("$BK" status 2>&1)" "Kitchen:  paused"
ok "stop with no kitchen is quiet and fine" has "$("$BK" stop 2>&1)" "nothing to stop"
# resume: the next open picks each session up, once
: > "$ST/log"
out=$("$BK" open --no-attach 2>&1)
ok "open after a stop says it resumes" has "$out" "Resuming the paused kitchen"
ok "…resumes the sous by id" has "$(tlog)" "sous CLAUDE_CONFIG_DIR=$HOME/.claude-work claude --model opus --plugin-dir $REPO/plugins/bk --resume sid-sous \"/bk:sous-chef\""
ok "…and the cook by id" has "$(tlog)" "station-1 .*--plugin-dir $REPO/plugins/bk --resume sid-one \"/bk:line-cook\""
ok "…a station that had no session starts fresh" bash -c '! grep "station-2 " "$1" | grep -q resume' _ "$ST/log"
ok "…and forgets the ids" test ! -e "$C/.claude/sous-session" -a ! -e "$S1/.claude/cook-session"
# a stop that runs out of patience still saves and stops
"$NB/tmux" kill-session; rm -f "$REG"/*.json
pS=$(start_session "$C" sid-sous2 busy)
"$BK" open --no-attach >/dev/null 2>&1; printf '%s %%0 sous\n' "$pS" > "$ST/panes"; : > "$ST/log"
out=$("$BK" stop --timeout 4 2>&1)
ok "a session that never goes idle: stop says so after the timeout" has "$out" "Still busy after 4s: sous"
ok "…still saves its id" test "$(cat "$C/.claude/sous-session")" = sid-sous2
ok "…and still closes the kitchen" has "$(tlog)" "kill-session"
ok "stop --timeout wants a number" has "$("$BK" stop --timeout soon 2>&1)" "needs seconds"
# --fresh ignores what a stop saved
echo sid-x > "$S1/.claude/cook-session"; : > "$ST/log"
"$BK" open --fresh --no-attach >/dev/null 2>&1
ok "open --fresh starts new sessions" bash -c '! grep -q resume "$1"' _ "$ST/log"
ok "…and drops the saved ids" test ! -e "$C/.claude/sous-session" -a ! -e "$S1/.claude/cook-session"
# flags after open reach kitchen.sh
"$NB/tmux" kill-session; : > "$ST/log"; "$BK" open --no-attach -m "h o" >/dev/null 2>&1
ok "open passes kitchen flags through (-m)" has "$(tlog)" "app-cook-1 --model haiku"

# =============================================================================
echo ""
echo "# passed $PASS · failed $FAIL · total $N"
[[ "$HOME" != "$REAL_HOME" ]] || { echo "# BUG: HOME was not isolated"; exit 1; }
(( FAIL == 0 ))
