#!/usr/bin/env bash
# =============================================================================
# kitchen.sh — the Brigade's station manager
#
# Two kinds of station, picked by `kitchen_mode:` in .claude/brigade.md:
#   clone    (default) full git clones inside the repo, <repo>/stations/station-N,
#            gitignored. Simplest; right for one standalone repo.
#   worktree git worktrees of the main checkout, by default in a sibling folder
#            ../<repo>-stations/station-N. Shares one object store, so it suits
#            big repos and repos that live inside a workspace repo.
# One Claude Code line cook works in each. Assignment happens through the sous chef over SendMessage, never
# through this script: each session starts as a line cook and waits for a brief.
#
# Run from anywhere inside the main checkout. Settings come from the flat keys
# in .claude/brigade.md (trunk, install, copy_into_stations, kitchen_mode,
# kitchen, stations, migrations); env vars override them.
#
# Usage:
#   kitchen.sh setup  [-n N]              create stations 1..N, keeping existing ones, so
#                                         it also grows a kitchen (clone, gitignore,
#                                         copy files, seed permissions, install)
#   kitchen.sh open   [-n N] [-m "O S"] [--terminal tmux|warp|native|print] [--bare]
#                                         open the kitchen: one claude session per station
#                                         (every one, or the first N with -n) that has no
#                                         cook running yet, already running /bk:line-cook.
#                                         Default terminal: tmux, one session <repo>-brigade
#                                         with a 'sous' window in the main checkout already
#                                         running /bk:sous-chef (model: sous_model in the
#                                         config, BRIGADE_SOUS_MODEL, else opus) and one
#                                         window per station; a Mac without tmux gets it
#                                         from Homebrew. Attach to the sous to talk to it.
#                                         Else Warp if installed, else the OS's own terminal
#                                         (Terminal.app, Windows Terminal/mintty, or the
#                                         Linux desktop's), else printed commands (--bare:
#                                         plain sessions; --no-launch: write the Warp config
#                                         or show the native launch, open nothing). Each
#                                         station it opens gets .claude/cook, which
#                                         restarts that cook with the same profile
#                                         (CLAUDE_CONFIG_DIR), name and model
#   kitchen.sh sync   [-n N]              reset CLEAN stations to origin/<trunk>
#                                         (dirty ones are skipped)
#   kitchen.sh status                     branch / dirty / ahead per station + open PRs
#   kitchen.sh files                      files in flight per station vs origin/<trunk>,
#                                         plans, and unmerged migrations
#   kitchen.sh rail                       the board, computed from ticket frontmatter
#                                         (markdown rail only): priority, whether each
#                                         free ticket is ready (or still needs a spec),
#                                         and its open blockers
#   kitchen.sh board                      status, files, rail, open questions and the
#                                         record's counts (decisions, inbox, asks, gaps) in one
#                                         go; from the main checkout it also writes them
#                                         to .claude/board.md (kept out of git)
#   kitchen.sh leaks [--dir D] [--also F] search a checkout's changed files and branch
#                                         commit messages (D, default: here; plus file F,
#                                         e.g. a PR body) for any test-account secret in
#                                         .claude/brigade.local.md. Prints file:line only,
#                                         never the value; exits 1 on a hit
#   kitchen.sh remove                     delete every station (asks first)
#   kitchen.sh role                       "cook <station> <main checkout>" when run inside
#                                         a station, else "main <main checkout>"
#   kitchen.sh sous [--set NAME]          print the sous chef's session name, from the
#                                         main checkout or any station (exits 1 if none
#                                         is recorded). --set, from the main checkout:
#                                         record it in .claude/sous (kept out of git)
#   kitchen.sh lessons                    count lesson(...) lines across ticket journals
#   kitchen.sh decisions                  every "(head chef)" answer in a journal that no doc
#                                         under the docs map cites and the register doesn't
#                                         list: what the sous's handoff still has to file
#   kitchen.sh inbox [--add "<text>"]     the inbox, .claude/inbox.md: things the head chef
#                                         said that the record doesn't hold yet. --add
#                                         appends one dated line; without it, list them
#   kitchen.sh asks [--add "<question>" [--ticket ID] [--gap KIND]]
#                   [--answer A3 "<the head chef's words>"] [--filed A3 "<where the fix went>"]
#                                         the ask log, .claude/asks.md: every question the
#                                         sous put to the head chef, written the moment it
#                                         is asked. Without options: the open ones, then
#                                         the answered ones whose gap is not fixed yet.
#                                         KIND: context | ruling | harness | access
#   kitchen.sh gaps                       what the handoff still has to fix: every answered
#                                         ask not yet filed, and every answered question
#                                         file with no fix:, grouped by gap kind with the
#                                         fix each kind takes
#   kitchen.sh doctor                     check ticket files (fields, statuses, blockers,
#                                         ids) and the docs map (folders exist, have an
#                                         INDEX.md, nothing under docs/ is unmapped)
#                                         (any depth under docs.journal, so finished
#                                         ones moved to a subfolder still count) and
#                                         say which are due for promotion
#   kitchen.sh questions                  every open question file under docs.questions,
#                                         then every unanswered question (Qn with no An)
#                                         in the stations' ticket journals
#   kitchen.sh sessions [--dir D]         the Claude Code session transcripts saved for
#                                         this checkout (or D, e.g. a station), newest
#                                         first, from $CLAUDE_CONFIG_DIR (else ~/.claude)
#   kitchen.sh debrief [--json]           the kitchen's own friction over the last week,
#                                         read from the budget: the check red three times
#                                         on a ticket, rework over a third of its spend,
#                                         ten CI minutes or more, a gate the record had
#                                         after the commis said nothing, a session carrying
#                                         too much context. One row per rule tripped, DUE
#                                         at two tickets, promoted once the register
#                                         (docs.lessons) lists its key; each with its fix
#   kitchen.sh budget [--ticket ID] [--since today|7d] [--ci] [--json]
#                                         what the kitchen spends: tokens (input, output,
#                                         cache read, cache write), money at Anthropic's
#                                         list prices (a prices: block in the config
#                                         overrides), time (per session: working time;
#                                         per ticket: brief→served and each phase), and
#                                         sub-agents, per session and per ticket, read
#                                         from the session transcripts Claude Code keeps
#                                         (needs node 20+; a week back at most). --ci asks gh for the CI
#                                         minutes of each ticket's PR branch. Served
#                                         tickets and CI results are kept in
#                                         .claude/budget.jsonl (out of git) so they
#                                         outlive transcript cleanup.
#                                         --ticket ID --journal-line [--session NAME]
#                                         prints the one line open-pr adds to the journal
#   kitchen.sh live [stop|status] [--port P] [--demo [-n N]] [--no-launch]
#                                         the Window: a live view of this kitchen on
#                                         localhost (needs node 20+). With no word it
#                                         toggles: opens it (and your browser) if closed,
#                                         closes it if open. --demo runs a scripted
#                                         service with N stations instead of the live
#                                         kitchen. Pid and log in .claude/, out of git
#
# Env overrides:
#   BRIGADE_TRUNK, BRIGADE_KITCHEN_MODE, BRIGADE_KITCHEN, BRIGADE_STATIONS, BRIGADE_MODEL (default sonnet),
#   BRIGADE_PERMISSION_MODE (default: auto — cooks run unattended, so a mode that
#   stops on every permission would stall them), BRIGADE_TERMINAL,
#   BRIGADE_CLAUDE_ARGS (extra flags for every claude session open starts, baked into
#   .claude/cook too; the bk command sets it to --plugin-dir <its bundled plugin>)
#
# Pause and resume (what `bk stop` leaves behind): when .claude/sous-session in the main
# checkout, or .claude/cook-session in a station, holds a Claude Code session id, open
# starts that session with `claude --resume <id>` instead of a fresh one, then removes
# the file. Both files are kept out of git.
#
# Requires: git, claude. Optional: tmux (open; installed by Homebrew on a Mac), gh (status, budget --ci), node 20+ (live, budget).
# BRIGADE_OS (mac|linux|wsl|windows) overrides OS detection; the tests use it.
# =============================================================================

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not inside a git repo." >&2; exit 1; }
HERE="$ROOT"   # the checkout this was run from, before ROOT climbs to the main one
# Run from inside a station? Find the main checkout that owns it.
# A worktree station knows its owner: its common git dir is the main repo's .git.
COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
GIT_DIR_ABS="$(git rev-parse --absolute-git-dir 2>/dev/null || true)"
if [[ -n "$COMMON_DIR" && "$COMMON_DIR" != "$GIT_DIR_ABS" && "$(basename "$COMMON_DIR")" == .git ]]; then
  ROOT="$(dirname "$COMMON_DIR")"
# A clone station sits two levels below its owner: <owner>/stations/station-N.
elif [[ "$(basename "$ROOT")" == station-* ]]; then
  OWNER="$(git -C "$(dirname "$(dirname "$ROOT")")" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$OWNER" && -f "$OWNER/.claude/brigade.md" ]] && ROOT="$OWNER"
fi
CONFIG="$ROOT/.claude/brigade.md"
REPO_NAME="$(basename "$ROOT")"

# cfg <key> → value of a flat frontmatter key in .claude/brigade.md ("" if absent)
cfg() {
  [[ -f "$CONFIG" ]] || return 0
  awk -v k="$1" '
    NR==1 && $0=="---" { inside=1; next }
    inside && $0=="---" { exit }
    inside && $0 ~ "^" k ":" {
      sub("^" k ":[ ]*", ""); sub(/[ ]+#.*$/, "")
      gsub(/^"|"$/, ""); print; exit
    }' "$CONFIG"
}

# cfg_docs <name> → docs.<name> from the nested docs: block, with a default
cfg_docs() {  # cfg_docs <key> [default] → docs.<key>, else the default, else docs/<key>
  local v=""
  [[ -f "$CONFIG" ]] && v=$(awk -v k="$1" '
    NR==1 && $0=="---" { inside=1; next }
    inside && $0=="---" { exit }
    inside && /^docs:/ { indocs=1; next }
    indocs && /^[^ ]/ { indocs=0 }
    indocs && $0 ~ "^  " k ":" { sub("^  " k ":[ ]*", ""); sub(/[ ]+#.*$/, ""); print; exit }' "$CONFIG")
  printf '%s' "${v:-${2:-docs/$1}}"
}

TRUNK="${BRIGADE_TRUNK:-$(cfg trunk)}"
TRUNK="${TRUNK:-$(git -C "$ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')}"
TRUNK="${TRUNK:-main}"
MODE="${BRIGADE_KITCHEN_MODE:-$(cfg kitchen_mode)}"; MODE="${MODE:-clone}"
case "$MODE" in clone|worktree) ;; *) echo "kitchen_mode must be clone or worktree (got: $MODE)" >&2; exit 1 ;; esac
KITCHEN_REL="${BRIGADE_KITCHEN:-$(cfg kitchen)}"
if [[ -z "$KITCHEN_REL" ]]; then
  [[ "$MODE" == worktree ]] && KITCHEN_REL="../${REPO_NAME}-stations" || KITCHEN_REL="stations"
fi
[[ "$KITCHEN_REL" == /* ]] && KITCHEN="$KITCHEN_REL" || KITCHEN="$ROOT/$KITCHEN_REL"
# Normalise ../ so paths print cleanly and compare reliably.
if [[ -d "$(dirname "$KITCHEN")" ]]; then
  KITCHEN="$(cd "$(dirname "$KITCHEN")" && pwd -P)/$(basename "$KITCHEN")"
fi
ROOT_REAL="$(cd "$ROOT" && pwd -P)"
N="${BRIGADE_STATIONS:-$(cfg stations)}"; N="${N:-2}"
N_GIVEN=false   # -n on the command line; without it, open takes every station there is
INSTALL="$(cfg install)"
COPY_FILES="$(cfg copy_into_stations)"
MIGRATIONS="$(cfg migrations)"; [[ "$MIGRATIONS" == "none" ]] && MIGRATIONS=""
MODEL="${BRIGADE_MODEL:-sonnet}"
SOUS_MODEL="${BRIGADE_SOUS_MODEL:-$(cfg sous_model)}"; SOUS_MODEL="${SOUS_MODEL:-opus}"
PERMISSION_MODE="${BRIGADE_PERMISSION_MODE:-$(cfg permission_mode)}"; PERMISSION_MODE="${PERMISSION_MODE:-auto}"
TERMINAL="${BRIGADE_TERMINAL:-}"
BARE=false
NO_LAUNCH=false
SESSIONS_DIR=""   # --dir, for sessions and leaks
ALSO=""           # --also, one extra file for leaks
SET_SOUS=false    # --set, for sous
SOUS_NAME=""
ADD_GIVEN=false   # --add, for inbox and asks
ADD_TEXT=""
GAP=""            # --gap, for asks --add
ANSWER_ID=""      # --answer, for asks
ANSWER_TEXT=""
FILED_ID=""       # --filed, for asks
FILED_TEXT=""
MODELS=()
LIVE_WORD=""    # stop | status, for live
LIVE_PORT="${BRIGADE_WINDOW_PORT:-4747}"
DEMO=false        # --demo, for live
TICKET=""         # --ticket, for budget
SINCE="today"     # --since, for budget
CI=false          # --ci, for budget
JSON=false        # --json, for budget
JOURNAL_LINE=false # --journal-line, for budget
SESSION_NAME=""   # --session, for budget --journal-line
ARGV=()   # set by native_argv

usage() { awk 'NR>2 { if (/^# =+$/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; exit 1; }

CMD="${1:-}"; shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) N="$2"; N_GIVEN=true; shift 2 ;;
    --terminal) TERMINAL="$2"; shift 2 ;;
    --bare) BARE=true; shift ;;
    --no-launch) NO_LAUNCH=true; shift ;;
    --port) LIVE_PORT="$2"; shift 2 ;;
    --demo) DEMO=true; shift ;;
    stop|status) LIVE_WORD="$1"; shift ;;
    --dir) SESSIONS_DIR="$2"; shift 2 ;;
    --also) ALSO="$2"; shift 2 ;;
    --set) SET_SOUS=true; SOUS_NAME="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
    --add) ADD_TEXT="${2:-}"; ADD_GIVEN=true; shift; [[ $# -gt 0 ]] && shift ;;
    --gap) GAP="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
    --answer) ANSWER_ID="${2:-}"; ANSWER_TEXT="${3:-}"; shift; [[ $# -gt 0 ]] && shift; [[ $# -gt 0 ]] && shift ;;
    --filed) FILED_ID="${2:-}"; FILED_TEXT="${3:-}"; shift; [[ $# -gt 0 ]] && shift; [[ $# -gt 0 ]] && shift ;;
    --ticket) TICKET="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --ci) CI=true; shift ;;
    --json) JSON=true; shift ;;
    --journal-line) JOURNAL_LINE=true; shift ;;
    --session) SESSION_NAME="$2"; shift 2 ;;
    -m|--model) shift
      while [[ $# -gt 0 && "$1" != -* ]]; do
        for tok in ${1//,/ }; do MODELS+=("$tok"); done; shift
      done ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
stations() {
  local d
  for d in "$KITCHEN"/station-*; do [[ -e "$d/.git" ]] && echo "$d"; done
  return 0
}

normalize_model() {
  local raw="$1" ctx="" base
  case "$raw" in *'[1m]') ctx='[1m]'; raw="${raw%\[1m\]}" ;; esac
  base=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
  case "$base" in
    o|opus) printf 'opus%s' "$ctx" ;;   s|sonnet) printf 'sonnet%s' "$ctx" ;;
    h|haiku) printf 'haiku%s' "$ctx" ;; f|fable) printf 'fable%s' "$ctx" ;;
    claude-*) printf '%s%s' "$base" "$ctx" ;;
    *) return 1 ;;
  esac
}

model_for() {  # model_for <index>
  if   (( ${#MODELS[@]} == 1 )); then printf '%s' "${MODELS[0]}"
  elif (( ${#MODELS[@]} > $1 )); then printf '%s' "${MODELS[$1]}"
  else printf '%s' "$MODEL"; fi
}

# session_name <station dir> → the display name the cook's session gets:
# <repo>-cook-N for station-N. The station is the place, the cook is who works
# there. The repo prefix keeps it unique when several kitchens run on one
# machine, since every session shares one ListAgents list.
session_name() { printf '%s-cook-%s' "$REPO_NAME" "$(basename "$1" | sed 's/^station-//')"; }

# CLAUDE_CONFIG_DIR is passed through only when the launching shell has it set
# (someone running several Claude profiles). Sessions only see each other
# within one profile, so cooks must inherit the sous's. Unset → plain `claude`.

# saved_session <checkout> → the session id a pause (bk stop) left there, if any:
# .claude/sous-session in the main checkout, .claude/cook-session in a station.
saved_session() {
  local f="$1/.claude/cook-session"
  [[ "$(cd "$1" && pwd -P)" == "$ROOT_REAL" ]] && f="$1/.claude/sous-session"
  head -1 "$f" 2>/dev/null | tr -d '[:space:]'
}
# resume_flag <checkout> → " --resume <id>" when a paused session is saved there.
resume_flag() {
  local id; id="$(saved_session "$1")"
  [[ -n "$id" ]] && printf ' --resume %s' "$(printf '%q' "$id")"
  return 0
}
extra_args() { [[ -n "${BRIGADE_CLAUDE_ARGS:-}" ]] && printf ' %s' "$BRIGADE_CLAUDE_ARGS"; return 0; }

claude_cmd() {  # claude_cmd <model> <station dir>
  local prefix=""
  [[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && prefix="CLAUDE_CONFIG_DIR=$(printf '%q' "$CLAUDE_CONFIG_DIR") "
  printf '%sclaude --name %s --model %s --permission-mode %s%s%s' "$prefix" \
    "$(printf '%q' "$(session_name "$2")")" "$1" "$PERMISSION_MODE" "$(extra_args)" "$(resume_flag "$2")"
  # Start as a line cook: it checks in with the sous, or waits for the sous's [hello].
  $BARE || printf ' "/bk:line-cook"'
}
sous_cmd() {  # the sous in the main checkout, already running /bk:sous-chef (--bare: plain)
  local prefix=""
  [[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && prefix="CLAUDE_CONFIG_DIR=$(printf '%q' "$CLAUDE_CONFIG_DIR") "
  printf '%sclaude --model %s%s%s' "$prefix" "$SOUS_MODEL" "$(extra_args)" "$(resume_flag "$ROOT")"
  $BARE || printf ' "/bk:sous-chef"'
}
# forget_session <checkout>: a saved session id is used once; the next open starts fresh.
forget_session() { rm -f "$1/.claude/cook-session" "$1/.claude/sous-session"; }

# write_launcher <station dir> <model> → <station>/.claude/cook, the way to restart
# that cook by hand (after /exit, say, to load a new agent or MCP server) without
# retyping anything. It pins the profile open ran under: a cook started under
# another CLAUDE_CONFIG_DIR can't see the sous in ListAgents. Profile unset at
# open → the launcher unsets it too, so a stray export in that terminal can't win.
write_launcher() {
  local st="$1" file="$1/.claude/cook" profile excl
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then profile="export CLAUDE_CONFIG_DIR=$(printf '%q' "$CLAUDE_CONFIG_DIR")"
  else profile="unset CLAUDE_CONFIG_DIR"; fi
  mkdir -p "$st/.claude"
  cat > "$file" <<EOF
#!/usr/bin/env bash
# Written by kitchen.sh open; rewritten each time. Restarts this station's cook
# under the kitchen's Claude Code profile, so it can still reach the sous:
#   .claude/cook                  resume the last session here (claude --continue)
#   .claude/cook "/bk:line-cook"  start a fresh session as a line cook
cd "\$(dirname "\$0")/.." || exit 1
$profile
[ \$# -eq 0 ] && set -- --continue
exec claude --name $(printf '%q' "$(session_name "$st")") --model $(printf '%q' "$2") --permission-mode $(printf '%q' "$PERMISSION_MODE")$(extra_args) "\$@"
EOF
  chmod +x "$file"
  excl="$(git -C "$st" rev-parse --path-format=absolute --git-path info/exclude)"
  mkdir -p "$(dirname "$excl")"
  grep -qxF ".claude/cook" "$excl" 2>/dev/null && return 0
  [[ -s "$excl" && -n "$(tail -c1 "$excl")" ]] && echo "" >> "$excl"
  echo ".claude/cook" >> "$excl"
}

# ensure_tmux → 0 when tmux is on the PATH, installing it on a Mac with Homebrew (no sudo
# needed there). Elsewhere it prints the one command to run and returns 1: those package
# managers want sudo, which can't be answered from a session.
# Homebrew's folder is looked in too, since a tmux installed mid-session isn't on a PATH
# that was built before it. The tests clear BRIGADE_TMUX_DIRS so the laptop's tmux stays out.
tmux_on_path() {
  local d
  for d in ${BRIGADE_TMUX_DIRS-/opt/homebrew/bin /usr/local/bin /home/linuxbrew/.linuxbrew/bin}; do
    [[ -x "$d/tmux" ]] && [[ ":$PATH:" != *":$d:"* ]] && PATH="$PATH:$d"   # after, so a tmux already on the PATH wins
  done
  command -v tmux >/dev/null 2>&1
}
# tmux_usable → 0 when tmux is here, or can be put here without a password (a Mac with Homebrew).
tmux_usable() {
  tmux_on_path && return 0
  [[ "$(os_kind)" == mac ]] && command -v brew >/dev/null 2>&1
}
ensure_tmux() {
  tmux_on_path && return 0
  case "$(os_kind)" in
    mac)
      if command -v brew >/dev/null 2>&1; then
        echo "tmux isn't installed; installing it with Homebrew (brew install tmux)…"
        if brew install tmux >/dev/null 2>&1 && tmux_on_path; then echo "  tmux installed."; return 0; fi
        echo "  brew install tmux failed: run it yourself, then open again." >&2; return 1
      fi
      echo "tmux isn't installed and neither is Homebrew. Install one: https://brew.sh then 'brew install tmux'." >&2; return 1 ;;
    linux|wsl)
      local pm="sudo apt-get install -y tmux"
      command -v dnf >/dev/null 2>&1 && pm="sudo dnf install -y tmux"
      command -v pacman >/dev/null 2>&1 && pm="sudo pacman -S --noconfirm tmux"
      echo "tmux isn't installed. Run: $pm   (then open again)" >&2; return 1 ;;
    windows) echo "tmux isn't available in Git Bash or MSYS. Use WSL, or stay with Warp / Windows Terminal (the Window then shows commands to paste)." >&2; return 1 ;;
    *) echo "tmux isn't installed; install it, then open again." >&2; return 1 ;;
  esac
}

# os_kind → mac | linux | wsl | windows (Git Bash, MSYS, Cygwin) | other.
# BRIGADE_OS overrides it, so the tests can drive every branch from one machine.
os_kind() {
  if [[ -n "${BRIGADE_OS:-}" ]]; then printf '%s' "$BRIGADE_OS"; return 0; fi
  case "$(uname -s)" in
    Darwin) printf mac ;;
    Linux)
      if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then printf wsl
      else printf linux; fi ;;
    MINGW*|MSYS*|CYGWIN*) printf windows ;;
    *) printf other ;;
  esac
}

warp_installed() {
  case "$(os_kind)" in
    mac) [[ -d /Applications/Warp.app || -d "$HOME/Applications/Warp.app" ]] ;;
    linux) command -v warp-terminal >/dev/null ;;
    *) return 1 ;;
  esac
}

# native_terminal → the launcher for this machine's own terminal, or fail when
# there is none we can drive (e.g. a Linux box with no desktop).
native_terminal() {
  local os t; os=$(os_kind)
  if [[ "$os" == mac ]]; then
    command -v osascript >/dev/null && { printf osascript; return 0; }
    return 1
  fi
  if [[ "$os" == wsl || "$os" == windows ]] && command -v wt.exe >/dev/null; then printf wt.exe; return 0; fi
  if [[ "$os" == windows ]] && command -v mintty >/dev/null; then printf mintty; return 0; fi
  if [[ "$os" == linux || "$os" == wsl ]] && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    for t in x-terminal-emulator gnome-terminal konsole xfce4-terminal xterm; do
      command -v "$t" >/dev/null && { printf '%s' "$t"; return 0; }
    done
  fi
  return 1
}

# native_argv <launcher> <station dir> <command> <title> → sets ARGV to the
# command that opens one window (or tab) running <command> in <station dir>.
# The shell stays open after claude exits, as it does in Warp.
native_argv() {
  local term="$1" dir="$2" cmd="$3" title="$4" qdir sh
  qdir=$(printf '%q' "$dir")
  case "$term" in
    osascript)  # Terminal.app runs the script in the user's own shell, which stays open.
      ARGV=(osascript -e 'on run argv' -e 'tell application "Terminal"'
        -e 'set t to do script (item 1 of argv)' -e 'set custom title of t to (item 2 of argv)'
        -e 'activate' -e 'end tell' -e 'end run' "cd $qdir && $cmd" "$title") ;;
    wt.exe)  # wt splits its arguments on ';' unless escaped as '\;'.
      if [[ "$(os_kind)" == wsl ]]; then
        ARGV=(wt.exe -w 0 new-tab --title "$title" wsl.exe)
        [[ -n "${WSL_DISTRO_NAME:-}" ]] && ARGV+=(-d "$WSL_DISTRO_NAME")
        ARGV+=(--cd "$dir" -- bash -lc "$cmd\\; exec bash -l")
      else
        sh=$(command -v bash)
        if command -v cygpath >/dev/null; then dir=$(cygpath -w "$dir"); sh=$(cygpath -w "$sh"); fi
        ARGV=(wt.exe -w 0 new-tab --title "$title" -d "$dir" "$sh" -lc "$cmd\\; exec bash -l")
      fi ;;
    mintty)          ARGV=(mintty --dir "$dir" -t "$title" -e bash -lc "$cmd; exec bash -l") ;;
    gnome-terminal)  ARGV=(gnome-terminal --working-directory="$dir" -- bash -lc "$cmd; exec bash -l") ;;
    konsole)         ARGV=(konsole --workdir "$dir" -e bash -lc "$cmd; exec bash -l") ;;
    xfce4-terminal)  ARGV=(xfce4-terminal --working-directory="$dir" -x bash -lc "$cmd; exec bash -l") ;;
    *)               ARGV=("$term" -e bash -lc "cd $qdir && $cmd; exec bash -l") ;;
  esac
}

# claude_cwds → the working directory of every running claude process, one per
# line. A process counts when its program, or the script its interpreter runs
# (node /…/claude), is named claude. cwd comes from /proc on Linux, lsof elsewhere.
claude_cwds() {
  local pid a1 a2 _
  ps -Ao pid=,args= 2>/dev/null | while read -r pid a1 a2 _; do
    [[ "${a1##*/}" == claude || "${a2##*/}" == claude ]] || continue
    if [[ -e "/proc/$pid/cwd" ]]; then readlink "/proc/$pid/cwd" 2>/dev/null
    else lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'; fi
  done
}

# busy <station dir> <cwds> → true when a claude session is working in it.
busy() {
  local st cwd; st="$(cd "$1" && pwd -P)"
  while IFS= read -r cwd; do
    [[ -n "$cwd" ]] && [[ "$cwd" == "$st" || "$cwd" == "$st"/* ]] && return 0
  done <<< "$2"
  return 1
}

# exclude_locally <path in the main checkout>: keep a machine-local file out of git
# through .git/info/exclude, so no tracked file (like .gitignore) changes.
exclude_locally() {
  local exclude
  git -C "$ROOT" check-ignore -q "$ROOT/$1" && return 0
  exclude="$(git -C "$ROOT" rev-parse --path-format=absolute --git-path info/exclude)"
  mkdir -p "$(dirname "$exclude")"
  # a file that doesn't end in a newline would fuse our line onto its last one
  [[ -s "$exclude" && -n "$(tail -c1 "$exclude")" ]] && echo "" >> "$exclude"
  echo "$1" >> "$exclude"
}

ensure_ignored() {  # ensure_ignored <file> <line>
  local file="$1" line="$2"
  [[ -f "$file" ]] && grep -qxF "$line" "$file" && return 1
  printf '\n# The Brigade: line-cook stations (never committed)\n%s\n' "$line" >> "$file"
  return 0
}

where() {  # where <station> → branch name, or "detached @ <sha>"
  local b; b=$(git -C "$1" branch --show-current)
  [[ -n "$b" ]] && printf '%s' "$b" || printf 'detached @ %s' "$(git -C "$1" rev-parse --short HEAD)"
}

# ignore_kitchen → add the kitchen folder to the .gitignore of whichever repo
# contains it: this repo (clone mode) or an enclosing workspace repo (a sibling
# worktree folder inside e.g. a docker/workspace checkout). Outside any repo:
# nothing to ignore.
ignore_kitchen() {
  local parent owner rel
  parent="$(dirname "$KITCHEN")"
  owner="$(git -C "$parent" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -z "$owner" ]] && return 0
  owner="$(cd "$owner" && pwd -P)"
  rel="${KITCHEN#"$owner"/}"
  if ensure_ignored "$owner/.gitignore" "/$rel/"; then
    if [[ "$owner" == "$ROOT_REAL" ]]; then echo "  .gitignore: added /$rel/ (commit this)"
    else echo "  $owner/.gitignore: added /$rel/ (the enclosing repo — commit it there)"; fi
  fi
  if [[ "$owner" == "$ROOT_REAL" && -f "$ROOT/.dockerignore" ]] && ensure_ignored "$ROOT/.dockerignore" "$rel/"; then
    echo "  .dockerignore: added $rel/"
  fi
}

changed_files() {  # committed-but-unmerged ∪ working tree, deduped
  { git -C "$1" diff --name-only "origin/$TRUNK...HEAD" 2>/dev/null
    git -C "$1" status --porcelain -uall 2>/dev/null | cut -c4- | sed 's/.* -> //'; } | sort -u
}

# ---------------------------------------------------------------------------
# setup
# ---------------------------------------------------------------------------
cmd_setup() {
  local remote; remote=$(git -C "$ROOT" remote get-url origin 2>/dev/null) \
    || { echo "No 'origin' remote: stations clone from it."; exit 1; }

  # Stations clone origin/<trunk>, not this working tree. If the Brigade setup
  # isn't pushed yet, every cook would start without its config and CLAUDE.md.
  git -C "$ROOT" fetch --quiet origin "$TRUNK" 2>/dev/null || true
  if ! git -C "$ROOT" cat-file -e "origin/$TRUNK:.claude/brigade.md" 2>/dev/null; then
    cat <<EOF2

  Not yet: origin/$TRUNK has no .claude/brigade.md.

  Stations start from origin/$TRUNK (a fresh clone, or a worktree detached
  there), so they'd start without the
  Brigade setup (config, CLAUDE.md section, docs/ folders). Get the setup onto
  origin/$TRUNK first (push it, or merge its PR), then run this again:

    git add -A && git commit -m "chore: set up The Brigade" && git push origin $TRUNK
EOF2
    exit 1
  fi

  ignore_kitchen

  echo ""
  if [[ "$MODE" == worktree ]]; then
    echo "  Creating $N worktree station(s) in $KITCHEN (detached at origin/$TRUNK)"
  else
    echo "  Creating $N station(s) of $remote in $KITCHEN_REL/ (trunk: $TRUNK)"
  fi
  mkdir -p "$KITCHEN"
  local i st f
  for i in $(seq 1 "$N"); do
    st="$KITCHEN/station-$i"
    if [[ -e "$st/.git" ]]; then
      echo "  station-$i: exists ($(where "$st")) — left alone"
      continue
    fi
    if [[ "$MODE" == worktree ]]; then
      # Detached, because trunk is already checked out in the main checkout and
      # git allows one worktree per branch. The cook branches off origin/<trunk>.
      echo "  station-$i: adding worktree ..."
      git -C "$ROOT" worktree add --quiet --detach "$st" "origin/$TRUNK" \
        || { echo "  station-$i: 'git worktree add' failed — skipped"; continue; }
    else
      echo "  station-$i: cloning ..."
      git clone --quiet "$remote" "$st" && git -C "$st" checkout --quiet "$TRUNK" 2>/dev/null || true
    fi

    for f in $COPY_FILES; do
      [[ -f "$ROOT/$f" && ! -f "$st/$f" ]] && cp "$ROOT/$f" "$st/$f" && echo "  station-$i: copied $f"
    done

    mkdir -p "$st/.claude"
    if [[ ! -f "$st/.claude/settings.local.json" ]]; then
      cat > "$st/.claude/settings.local.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git fetch:*)",
      "Bash(git checkout:*)", "Bash(git switch:*)", "Bash(git add:*)", "Bash(git merge:*)",
      "Bash(gh pr view:*)", "Bash(gh pr create:*)", "Bash(gh issue view:*)",
      "Bash(ls:*)", "Bash(find:*)", "Bash(mkdir:*)"
    ]
  }
}
EOF
      echo "  station-$i: permissions seeded (.claude/settings.local.json)"
    fi
    # Keep that file (and the copied env files) out of the station's own status.
    # For a worktree this resolves to the shared info/exclude, which also hides
    # them in the main checkout; both are machine-local files, so that's fine.
    local excl; excl="$(git -C "$st" rev-parse --path-format=absolute --git-path info/exclude)"
    mkdir -p "$(dirname "$excl")"
    grep -qxF ".claude/settings.local.json" "$excl" 2>/dev/null || echo ".claude/settings.local.json" >> "$excl"
    # the grilling marker (Contract 12): written by grill-me in a station, read by the hook
    grep -qxF ".claude/grilling" "$excl" 2>/dev/null || echo ".claude/grilling" >> "$excl"
    for f in $COPY_FILES; do
      grep -qxF "$f" "$excl" 2>/dev/null || echo "$f" >> "$excl"
    done

    if [[ -n "$INSTALL" ]]; then
      ( cd "$st" && eval "$INSTALL" >/dev/null 2>&1 ) \
        && echo "  station-$i: installed ($INSTALL)" \
        || echo "  station-$i: '$INSTALL' failed — run it by hand in $KITCHEN_REL/station-$i"
    fi

    # A fresh station must be clean. If cloning + install changed tracked files,
    # say so now: otherwise the cook's first check-in reports someone else's diff.
    local dirty; dirty=$(git -C "$st" status --porcelain)
    if [[ -n "$dirty" ]]; then
      echo "  station-$i: ⚠️  DIRTY right after setup — the install step changed tracked files:"
      printf '%s\n' "$dirty" | sed 's/^/        /'
      echo "        Inspect before briefing a cook: git -C $KITCHEN_REL/station-$i diff"
    fi
  done

  echo ""
  echo "  Done: $N station(s) in $KITCHEN_REL/."
  echo ""
  if [[ "$KITCHEN" == "$ROOT_REAL"/* ]]; then
    cat <<EOF
  ⚠️  Never run 'git clean -fdx' in this repo: -x deletes ignored files,
      which means every station and its uncommitted work.
  ⚠️  Tools that don't read .gitignore will see $KITCHEN_REL/. Exclude it where
      it applies: tsconfig "exclude", test-runner excludes, linter ignores,
      file watchers, pytest norecursedirs.
EOF
  fi
  if [[ "$MODE" == worktree ]]; then
    cat <<EOF
  ⚠️  Worktrees share one repo. Stashes are shared too: a cook stashes with
      'git stash push -m "<station>: …"' and applies only its own, by name.
  ⚠️  Remove stations with 'kitchen.sh remove', never rm -rf: git keeps a
      record of every worktree and would be left with stale ones.
EOF
  fi
  [[ "${AUTO_SETUP:-}" == true ]] && return 0
  cat <<EOF

  Next: kitchen.sh open   (then /bk:sous-chef here; cooks start already running /bk:line-cook)
EOF
}

# ---------------------------------------------------------------------------
# open
# ---------------------------------------------------------------------------
cmd_open() {
  local list=() s i norm bad=()
  while IFS= read -r s; do list+=("$s"); done < <(stations)
  if (( ${#list[@]} == 0 )); then
    # A first open creates the stations itself: nobody should have to know setup exists.
    # cmd_setup still refuses (and says why) when origin/<trunk> lacks the config.
    echo "No stations yet: creating $N (stations: in .claude/brigade.md; kitchen.sh setup -n N adds more)."
    AUTO_SETUP=true cmd_setup || exit 1
    while IFS= read -r s; do list+=("$s"); done < <(stations)
    (( ${#list[@]} == 0 )) && { echo "No station could be created; see above."; exit 1; }
  fi
  # Stations added later with `setup -n` open too; `stations:` only sizes a fresh setup.
  $N_GIVEN && (( ${#list[@]} > N )) && list=("${list[@]:0:$N}")

  for i in "${!MODELS[@]}"; do
    if norm=$(normalize_model "${MODELS[$i]}"); then MODELS[$i]="$norm"; else bad+=("${MODELS[$i]}"); fi
  done
  (( ${#bad[@]} > 0 )) && { echo "Unknown model(s): ${bad[*]} (use O/S/H/F, full names, or claude-*)"; exit 1; }

  # Skip stations where a cook is already running: open fills the empty ones.
  local cwds keep=() models=() skipped=()
  cwds="$(claude_cwds)"
  for i in "${!list[@]}"; do
    if busy "${list[$i]}" "$cwds"; then skipped+=("$(basename "${list[$i]}")")
    else keep+=("${list[$i]}"); models+=("$(model_for "$i")"); fi
  done
  (( ${#skipped[@]} > 0 )) && echo "Already running a cook, left alone: ${skipped[*]}"
  (( ${#keep[@]} == 0 )) && { echo "Every station has a cook; nothing to open."; return 0; }
  list=("${keep[@]}")
  for i in "${!list[@]}"; do write_launcher "${list[$i]}" "${models[$i]}"; done

  if [[ -z "$TERMINAL" ]]; then
    # tmux by default: the sessions run unattended, attachable when you want to look, and the
    # Window can type into them. A Mac without it gets it from Homebrew; otherwise Warp, else
    # the OS's terminal, else printed commands.
    if tmux_usable; then TERMINAL=tmux
    elif warp_installed; then TERMINAL=warp
    elif native_terminal >/dev/null; then TERMINAL=native
    else TERMINAL=print; fi
  fi

  case "$TERMINAL" in
    warp)
      local dir file opener=open
      if [[ "$(os_kind)" == mac ]]; then dir="$HOME/.warp/launch_configurations"
      else dir="${XDG_DATA_HOME:-$HOME/.local/share}/warp-terminal/launch_configurations"; opener=xdg-open; fi
      file="$dir/${REPO_NAME}-brigade.yaml"; mkdir -p "$dir"
      {
        echo "---"; echo "name: ${REPO_NAME}-brigade"; echo "windows:"; echo "  - tabs:"
        for i in "${!list[@]}"; do
          echo "      - title: \"$(session_name "${list[$i]}") · ${models[$i]}\""
          echo "        layout:"
          echo "          cwd: \"${list[$i]}\""
          echo "          commands:"
          echo "            - exec: '$(claude_cmd "${models[$i]}" "${list[$i]}")'"
        done
      } > "$file"
      if $NO_LAUNCH; then echo "Warp config written, not launched: $file"; return 0; fi
      "$opener" "warp://launch/$(basename "$file")" >/dev/null 2>&1 \
        && echo "Warp window opened with ${#list[@]} $($BARE && echo bare || echo line-cook) session(s)." \
        || { echo "Warp launch failed; commands:"; TERMINAL=print; }
      ;;
    native)
      local term
      if ! term=$(native_terminal); then
        echo "No terminal found to open ($(os_kind)); commands:"; TERMINAL=print
      else
        for i in "${!list[@]}"; do
          native_argv "$term" "${list[$i]}" "$(claude_cmd "${models[$i]}" "${list[$i]}")" \
            "$(session_name "${list[$i]}") · ${models[$i]}"
          if $NO_LAUNCH; then
            printf 'would run:'; printf ' %q' "${ARGV[@]}"; echo
          elif [[ "$term" == osascript || "$term" == wt.exe ]]; then
            # These hand the window to the OS and return, so a failure is a real one.
            "${ARGV[@]}" >/dev/null 2>&1 || { echo "$term launch failed; commands:"; TERMINAL=print; break; }
          else
            # Linux terminals stay in the foreground until closed: detach them.
            nohup "${ARGV[@]}" >/dev/null 2>&1 &
          fi
        done
        $NO_LAUNCH && return 0
        [[ "$TERMINAL" == native ]] && echo "$term opened ${#list[@]} $($BARE && echo bare || echo line-cook) session(s)."
      fi
      ;;
    tmux)
      if ! ensure_tmux; then echo "commands:"; TERMINAL=print; else
      # One tmux session per kitchen, <repo>-brigade: a 'sous' window in the main checkout that
      # starts /bk:sous-chef by itself, and one window per station. Nothing to type: attach to
      # the sous to talk to it; peek at a cook's window when you want to see it work.
      local sess="${REPO_NAME}-brigade" win opened=0 sous_started=false
      # A pane's shell inherits the tmux server's environment, not this one's. With the
      # profile unset here (the default login), a CLAUDE_CONFIG_DIR the server kept from an
      # earlier shell would silently pick another login: drop it before any window opens.
      [[ -z "${CLAUDE_CONFIG_DIR:-}" ]] && tmux set-environment -g -u CLAUDE_CONFIG_DIR 2>/dev/null
      if ! tmux has-session -t "$sess" 2>/dev/null; then
        tmux new-session -d -s "$sess" -n sous -c "$ROOT"
        tmux send-keys -t "$sess:sous" "$(sous_cmd)" Enter; sous_started=true
      elif ! tmux list-windows -t "$sess" -F '#W' 2>/dev/null | grep -qx sous; then
        tmux new-window -t "$sess" -n sous -c "$ROOT"
        tmux send-keys -t "$sess:sous" "$(sous_cmd)" Enter; sous_started=true
      elif [[ "$(tmux display-message -p -t "$sess:sous" '#{pane_current_command}' 2>/dev/null)" =~ ^-?(zsh|bash|sh|fish|dash|ksh)$ ]]; then
        # the sous window is there but the sous has left it (an /exit by hand): start it again in place
        tmux send-keys -t "$sess:sous" "$(sous_cmd)" Enter; sous_started=true
      fi
      for i in "${!list[@]}"; do
        win="$(basename "${list[$i]}")"
        if tmux list-windows -t "$sess" -F '#W' 2>/dev/null | grep -qx "$win"; then
          tmux kill-window -t "$sess:$win" 2>/dev/null   # the cook that lived there is gone; reuse its window
        fi
        tmux new-window -t "$sess" -n "$win" -c "${list[$i]}"
        tmux send-keys -t "$sess:$win" "$(claude_cmd "${models[$i]}" "${list[$i]}")" Enter
        opened=$((opened+1))
      done
      $sous_started && forget_session "$ROOT"
      echo "The kitchen runs in tmux session '$sess': $opened cook window(s) opened$($sous_started && echo ", the sous started in window 'sous'")."
      if [[ -n "${BRIGADE_VIA_BK:-}" ]]; then echo "  Talk to the sous:  bk attach      peek at a cook:  bk peek 1      pause it all:  bk stop"
      elif [[ -n "${TMUX:-}" ]]; then echo "  You're inside tmux: tmux switch-client -t $sess:sous   (then prefix+w to pick a window)"
      else echo "  Talk to the sous:  tmux attach -t $sess:sous      peek at a cook:  tmux attach -t $sess:station-1"; fi
      echo "  Watch it all:      $([[ -n "${BRIGADE_VIA_BK:-}" ]] && echo "bk live" || echo "/bk:live")"
      if ! grep -qs 'mouse on' "$HOME/.tmux.conf" 2>/dev/null; then echo "  (mouse scrolling in tmux: echo 'set -g mouse on' >> ~/.tmux.conf)"; fi
      fi
      ;;
    print) ;;
    *) echo "Unknown terminal '$TERMINAL' (use warp, native, tmux or print); commands:"; TERMINAL=print ;;
  esac

  if [[ "$TERMINAL" == print ]]; then
    for i in "${!list[@]}"; do
      echo "  $(basename "${list[$i]}"):  cd $(printf '%q' "${list[$i]}") && $(claude_cmd "${models[$i]}" "${list[$i]}")"
    done
  fi
  for i in "${!list[@]}"; do forget_session "${list[$i]}"; done   # a paused session resumes once
  if $BARE; then
    echo "Sessions open bare. In each one run /bk:line-cook, or let the sous brief them."
  else
    echo "Each session starts as a line cook and checks in with the sous (or waits for it)."
  fi
  echo "To restart a cook by hand (after /exit), run .claude/cook in its station: same profile, name and model."
}

# ---------------------------------------------------------------------------
# sync / status / files
# ---------------------------------------------------------------------------
cmd_sync() {
  local s name found=false
  while IFS= read -r s; do
    found=true; name=$(basename "$s")
    if [[ -n "$(git -C "$s" status --porcelain)" ]]; then
      echo "  $name: dirty — skipped (a cook may be mid-ticket; ask the sous)"; continue
    fi
    if [[ "$MODE" == worktree ]]; then
      # Trunk is checked out in the main checkout, so an idle worktree sits
      # detached at origin/<trunk> instead.
      git -C "$s" fetch --quiet origin "$TRUNK" \
        && git -C "$s" switch --quiet --detach "origin/$TRUNK" \
        && echo "  $name: synced, detached at origin/$TRUNK ($(git -C "$s" rev-parse --short HEAD))"
    else
      git -C "$s" fetch --quiet origin "$TRUNK" \
        && git -C "$s" checkout --quiet "$TRUNK" \
        && git -C "$s" reset --quiet --hard "origin/$TRUNK" \
        && echo "  $name: synced to origin/$TRUNK ($(git -C "$s" rev-parse --short HEAD))"
    fi
  done < <(stations)
  $found || echo "No stations in $KITCHEN_REL/."
}

cmd_status() {
  local s found=false
  echo ""; echo "Stations ($MODE, $KITCHEN_REL/, trunk $TRUNK):"
  while IFS= read -r s; do
    found=true
    printf '  %-11s %-44s %-6s +%s\n' "$(basename "$s")" "$(where "$s")" \
      "$([[ -n "$(git -C "$s" status --porcelain)" ]] && echo dirty || echo clean)" \
      "$(git -C "$s" rev-list --count "origin/$TRUNK..HEAD" 2>/dev/null || echo '?')"
  done < <(stations)
  $found || echo "  (none — run setup)"
  if command -v gh >/dev/null; then
    echo ""; echo "Open PRs against $TRUNK:"
    ( cd "$ROOT" && gh pr list --base "$TRUNK" --state open --json number,title,headRefName \
      --template '{{range .}}  #{{.number}} {{.title}}  ({{.headRefName}}){{"\n"}}{{end}}' 2>/dev/null ) \
      || echo "  (gh unavailable for this remote)"
  fi
}

cmd_files() {
  local s f found=false plans; plans="$(cfg_docs plans)"
  echo ""; echo "Files in flight (vs origin/$TRUNK as last fetched):"
  while IFS= read -r s; do
    found=true
    local files=()
    while IFS= read -r f; do [[ -n "$f" ]] && files+=("$f"); done < <(changed_files "$s")
    printf '  %-11s %-36s %d file(s)\n' "$(basename "$s")" "$(where "$s")" "${#files[@]}"
    for f in "${files[@]+"${files[@]}"}"; do
      if [[ -n "$MIGRATIONS" && "$f" == "$MIGRATIONS"/* ]]; then echo "      ⚠️  $f  (UNMERGED MIGRATION)"
      elif [[ "$f" == "$plans"/* && "$(basename "$f")" != INDEX.md ]]; then echo "      $f  (plan)"
      else echo "      $f"; fi
    done
  done < <(stations)
  $found || echo "  (none — run setup)"
}

# ---------------------------------------------------------------------------
# rail — the board, computed from ticket frontmatter
# ---------------------------------------------------------------------------
cmd_rail() {
  local specs backlog
  specs="$ROOT/$(cfg_docs specs)"; backlog="$ROOT/$(cfg_docs backlog)"
  if [[ -f "$CONFIG" ]] && ! awk '/^rail:/{r=1;next} r&&/^[^ ]/{exit} r&&/adapter:[ ]*(markdown|mixed)/{f=1} END{exit !f}' "$CONFIG"; then
    grep -q '^rail:' "$CONFIG" && { echo "This repo's rail isn't markdown — use the tracker's board (or /bk:rail list)."; return 0; }
  fi
  local files=()
  while IFS= read -r f; do files+=("$f"); done < <(
    { find "$specs" -mindepth 2 -maxdepth 2 -name '[0-9][0-9]-*.md' 2>/dev/null
      find "$backlog" -maxdepth 1 \( -name 'BKLG-*.md' -o -name 'HYG-*.md' \) 2>/dev/null; } | sort)
  (( ${#files[@]} == 0 )) && { echo "The rail is empty."; return 0; }
  printf '%-10s %-4s %-12s %-5s %-4s %-11s %s\n' ID LANE STATUS PRI RDY COOK TITLE
  # Two passes over the same files: the first learns every ticket's status (done
  # ones included), the second prints. So a blocker is resolved here, not guessed:
  # done → dropped; open → listed; an id that is no ticket on this rail → listed
  # with "?", and it holds the ticket like an open one.
  awk '
    function flush(   n, i, x, b, held, rdy) {
      if (id == "") return
      if (cur == 1) { st[id] = status; id = ""; return }
      if (status != "done") {
        if (cook == "null" || cook == "") cook = "-"
        if (pri != "high" && pri != "low") pri = "-"   # normal, absent or anything else reads as normal
        held = ""; n = split(blk, b, ",")
        for (i = 1; i <= n; i++) {
          x = b[i]; if (x == "") continue
          if (!(x in st)) { x = x "?"; unknown = 1 } else if (st[x] == "done") continue
          held = held (held == "" ? "" : ", ") x
        }
        rdy = "-"
        if (status == "backlog" || status == "blocked") {
          rdy = (held == "" ? "yes" : "no")
          # a backlog item is built directly only when it is a bug; anything else
          # still has to become a spec and tickets (Contract 4)
          if (id ~ /^BKLG-/ && kind != "bug" && kind != "chore" && kind != "precedent") rdy = "spec"
        }
        printf "%-10s %-4s %-12s %-5s %-4s %-11s %s%s\n", id, lane, status, pri, rdy, cook, title, (held == "" ? "" : "  (blocked by: " held ")")
      }
      id = ""
    }
    FNR==1 { flush(); cur = pass; lane=status=cook=title=pri=blk=kind=""; fm=0 }
    FNR==1 && $0=="---" { fm=1; next }
    fm && $0=="---" { fm=0; next }
    fm {
      line=$0; key=line; sub(/:.*/, "", key); val=line; sub(/^[^:]*:[ ]*/, "", val); sub(/[ ]+#.*$/, "", val); gsub(/^"|"$/, "", val)
      if (key=="id") id=val; else if (key=="lane") lane=val; else if (key=="status") status=val
      else if (key=="cook") cook=val; else if (key=="title") title=val; else if (key=="priority") pri=val; else if (key=="kind") kind=val
      else if (key=="blocked_by") { blk=val; gsub(/[]["\047 ]/, "", blk) }
    }
    END {
      flush()
      if (unknown) print "\n? = not a ticket on this rail (an id from elsewhere, or a typo). It holds the ticket until the blocker is removed."
    }' pass=1 "${files[@]}" pass=2 "${files[@]}"
}

# ---------------------------------------------------------------------------
# board — everything the sous reads, in one snapshot. Run from the main checkout
# it is also written to .claude/board.md, for a human to keep open. The file is
# generated, never edited, and never committed: it goes in .git/info/exclude so
# no tracked file changes.
# ---------------------------------------------------------------------------
cmd_board() {
  local here_real text
  text="$(echo "# The board: $REPO_NAME"
    echo ""
    echo "Generated $(date '+%Y-%m-%d %H:%M') by \`kitchen.sh board\`. Rewritten each time; don't edit it."
    echo ""; echo '```'
    cmd_status; cmd_files
    echo ""; echo "The rail:"; cmd_rail
    echo ""; echo "Open questions:"; cmd_questions
    echo ""; echo "Decisions to file: $(cmd_decisions | grep -c ' DUE ' || true) · Inbox: $(inbox_count) unfiled · Asks open: $(asks_count open) · Gaps to fix: $(cmd_gaps | grep -c '^  ' || true)"
    echo '```')"
  printf '%s\n' "$text"
  here_real="$(cd "$HERE" && pwd -P)"
  [[ "$here_real" == "$ROOT_REAL" && -d "$ROOT/.claude" ]] || return 0
  exclude_locally .claude/board.md
  printf '%s\n' "$text" > "$ROOT/.claude/board.md"
}

# ---------------------------------------------------------------------------
# leaks — has a test-account secret been copied out of .claude/brigade.local.md?
# Secrets are the values of `password:`, `code:`, `token:` and `secret:` lines in
# that file. They are matched as fixed strings from a temp pattern file, so no
# value ever appears on a command line or in the output: a hit prints file:line.
# A literal search: it can't see a value that was encoded, split or reworded.
# ---------------------------------------------------------------------------
cmd_leaks() {
  local file="$ROOT/.claude/brigade.local.md" dir="${SESSIONS_DIR:-$HERE}" pat short f n hits=0 checked=0
  [[ -f "$file" ]] || { echo "No .claude/brigade.local.md in the main checkout: nothing to check."; return 0; }
  pat="$(mktemp "${TMPDIR:-/tmp}/brigade-leaks.XXXXXX")"
  short=$(awk -v out="$pat" -v q="'" '
    /^[ \t]*(-[ \t]*)?(password|code|token|secret)[ \t]*:/ {
      v=$0; sub(/^[^:]*:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      gsub("^[`\"" q "]|[`\"" q "]$", "", v)
      if (v == "" || v ~ /^</) next
      if (length(v) < 6) { s++; next }
      print v > out
    } END { print s+0 }' "$file")
  if [[ ! -s "$pat" ]]; then
    rm -f "$pat"; echo "No test-account secrets on file: nothing to check."
    (( short > 0 )) && echo "  ($short value(s) shorter than 6 characters can't be searched for)"
    return 0
  fi
  while IFS= read -r f; do
    [[ -f "$dir/$f" ]] || continue
    checked=$((checked+1))
    while IFS= read -r n; do echo "  $f:$n"; hits=$((hits+1)); done < <(grep -anF -f "$pat" -- "$dir/$f" | cut -d: -f1)
  done < <(changed_files "$dir")
  if git -C "$dir" log "origin/$TRUNK..HEAD" --format=%B 2>/dev/null | grep -qaF -f "$pat"; then
    echo "  (a commit message on this branch)"; hits=$((hits+1))
  fi
  if [[ -n "$ALSO" && -f "$ALSO" ]]; then
    while IFS= read -r n; do echo "  $ALSO:$n"; hits=$((hits+1)); done < <(grep -anF -f "$pat" -- "$ALSO" | cut -d: -f1)
  fi
  rm -f "$pat"
  (( short > 0 )) && echo "  ($short value(s) shorter than 6 characters weren't searched for)"
  if (( hits > 0 )); then
    echo "LEAK: $hits place(s) hold a test-account secret. Remove it; name the account instead."
    return 1
  fi
  echo "No test-account secrets in $checked changed file(s) or this branch's commit messages."
}

# ---------------------------------------------------------------------------
# role — am I a cook? Skills call this first: a session inside a station is a
# line cook whether or not /bk:line-cook was typed (e.g. after /clear).
# ---------------------------------------------------------------------------
cmd_role() {
  local here_real; here_real="$(cd "$HERE" && pwd -P)"
  if [[ "$here_real" != "$ROOT_REAL" ]]; then
    echo "cook $(basename "$here_real") $ROOT_REAL"
  else
    echo "main $ROOT_REAL"
  fi
}

# ---------------------------------------------------------------------------
# sous — the sous chef's session name, so a cook can find it without waiting for
# a [hello] (after a restart or a /clear). /bk:sous-chef records the name that
# ListAgents gives it; a cook reads it from its station. The file can outlive the
# session: a cook checks the name is still listed before it messages it.
# ---------------------------------------------------------------------------
cmd_sous() {
  local file="$ROOT/.claude/sous" name here_real
  if $SET_SOUS; then
    name="$SOUS_NAME"
    if [[ -z "$name" || "$name" == -* || "$name" =~ [[:space:]] ]]; then
      echo "Usage: kitchen.sh sous --set <session name>  (one word, as ListAgents shows it)" >&2; return 1
    fi
    here_real="$(cd "$HERE" && pwd -P)"
    if [[ "$here_real" != "$ROOT_REAL" ]]; then
      echo "Only the sous records its name, from the main checkout ($ROOT_REAL)." >&2; return 1
    fi
    mkdir -p "$ROOT/.claude"
    exclude_locally .claude/sous
    printf '%s\n' "$name" > "$file"
  fi
  name="$(head -1 "$file" 2>/dev/null)"
  if [[ -z "$name" ]]; then
    echo "No sous chef recorded for $REPO_NAME: wait for its [hello]." >&2; return 1
  fi
  echo "$name"
}

# ---------------------------------------------------------------------------
# lessons — the mechanical half of lesson promotion. A lesson is one line in a
# ticket journal:  - lesson(repo|plugin): <key> | <text> | <TICKET-ID>
# Due: a repo lesson seen in >= 2 different tickets, a plugin lesson seen once,
# and the key not yet listed in the register (docs.lessons, default docs/lessons.md).
# Journals are read at any depth under docs.journal: a repo whose journal lives in
# its plans moves them to e.g. plans/completed/ when done, and those still count.
# ---------------------------------------------------------------------------
cmd_lessons() {
  local lessons_file f files=()
  lessons_file="$ROOT/$(cfg_docs lessons docs/lessons.md)"
  while IFS= read -r f; do files+=("$f"); done < <(journal_files)
  (( ${#files[@]} == 0 )) && { echo "No ticket journals yet."; return 0; }
  printf '%-7s %-28s %-8s %-9s %s\n' SCOPE KEY TICKETS STATUS "FIRST SEEN AS"
  grep -h -E '^- lesson\((repo|plugin)\): ' "${files[@]}" 2>/dev/null | awk -F' \\| ' -v lf="$lessons_file" '
    BEGIN { while ((getline line < lf) > 0) promoted[line]=1 }
    {
      head=$1; sub(/^- lesson\(/, "", head); scope=head; sub(/\).*/, "", scope)
      key=head; sub(/^[a-z]+\): /, "", key); gsub(/ +$/, "", key)
      id=$NF; gsub(/^ +| +$/, "", id)
      k=scope SUBSEP key
      if (!(k in text)) { text[k]=$2; order[++n]=k }
      if (!((k, id) in seen)) { seen[k, id]=1; count[k]++ }
    }
    END {
      for (i=1; i<=n; i++) {
        k=order[i]; split(k, parts, SUBSEP); scope=parts[1]; key=parts[2]
        done=0; for (l in promoted) if (index(l, "`" key "`")) done=1
        need=(scope=="plugin") ? 1 : 2
        st = done ? "promoted" : (count[k] >= need ? "DUE" : "watch")
        printf "%-7s %-28s %-8s %-9s %s\n", scope, key, count[k], st, text[k]
      }
    }'
}

# ---------------------------------------------------------------------------
# questions — what the kitchen is waiting on, open question files first. Two sources: a cook's journal line
# "- <when> · <session> · Qn: …" with no "An" line after it in the same journal,
# and an open question file under docs.questions (frontmatter status: open), which
# is where the sous parks a question the head chef hasn't answered by a handoff.
# ---------------------------------------------------------------------------
journal_files() {  # every journal, trunk and stations, any depth, INDEX.md excluded
  local journal dir
  journal="$(cfg_docs journal)"
  for dir in "$ROOT/$journal" "$KITCHEN"/station-*/"$journal"; do
    [[ -d "$dir" ]] || continue
    find "$dir" -name '*.md' ! -name INDEX.md -type f 2>/dev/null
  done
}

cmd_questions() {
  local qdir f st any=false kitchen_real
  qdir="$(docs_path questions)"
  kitchen_real="$(cd "$KITCHEN" 2>/dev/null && pwd -P || printf '%s' "$KITCHEN")"
  {
    # open question files first: those are the head chef's, and the oldest debt
    if [[ "$qdir" != none && -d "$ROOT/$qdir" ]]; then
      for f in "$ROOT/$qdir"/*.md; do
        [[ -f "$f" && "$(basename "$f")" != INDEX.md ]] || continue
        awk -v fn="$(basename "$f")" '
          NR==1 && $0=="---" { fm=1; next }
          fm && $0=="---" { exit }
          fm && /^status:/ { s=$0; sub(/^status:[ ]*/, "", s); sub(/[ ]+#.*$/, "", s); status=s }
          fm && /^title:/ { t=$0; sub(/^title:[ ]*/, "", t); gsub(/^"|"$/, "", t); title=t }
          fm && /^blocks:/ { b=$0; sub(/^blocks:[ ]*/, "", b); gsub(/[]["\047]/, "", b); blocks=b }
          END { if (status == "open") printf "%-11s %-28s %s%s\n", "(record)", fn, title, (blocks == "" ? "" : "  (blocks: " blocks ")") }' "$f"
      done
    fi
    while IFS= read -r f; do
      # the station is the first path segment under the kitchen; a trunk journal says so
      case "$f" in
        "$KITCHEN"/*) st="${f#"$KITCHEN"/}"; st="${st%%/*}" ;;
        "$kitchen_real"/*) st="${f#"$kitchen_real"/}"; st="${st%%/*}" ;;
        *) st="(trunk)" ;;
      esac
      awk -v st="$st" -v fn="$(basename "$f")" '
        /^- .* · Q[0-9]+:/ { match($0, /Q[0-9]+:/); q=substr($0, RSTART+1, RLENGTH-2); ask[q]=$0; order[++n]=q }
        /^- .* · A[0-9]+/  { match($0, /A[0-9]+/);  a=substr($0, RSTART+1, RLENGTH-1); answered[a]=1 }
        END { for (i=1; i<=n; i++) if (!(order[i] in answered)) { line=ask[order[i]]; sub(/^- /, "", line); printf "%-11s %-28s %s\n", st, fn, line } }' "$f"
    done < <(journal_files)
  } | { if read -r first; then any=true; printf '%-11s %-28s %s\n' STATION JOURNAL QUESTION; echo "$first"; cat; fi; $any || echo "No open questions."; }
}

# ---------------------------------------------------------------------------
# decisions — the mechanical half of recording (Contract 12). A head-chef answer
# is a journal line "- <when> · <session> · An (head chef): …" in the journal of
# ticket <ID>. It is handled once a file under any docs map folder cites "<ID> An"
# (a decision's source: line, say) or the register (docs.lessons) lists it as
# kept. Everything else is DUE for the sous's handoff.
# ---------------------------------------------------------------------------
# docs_keys → every key of the docs map: the ones the contract names (with their
# defaults) and any extra key the sous added to the config, each once.
DOCS_DEFAULT_KEYS="specs backlog plans checklists journal lessons research brainstorm decisions conventions knowledge questions"
docs_keys() {
  local k seen=" "
  for k in $DOCS_DEFAULT_KEYS; do echo "$k"; seen="$seen$k "; done
  [[ -f "$CONFIG" ]] || return 0
  while IFS= read -r k; do
    [[ "$seen" == *" $k "* ]] && continue; seen="$seen$k "; echo "$k"
  done < <(awk '
    NR==1 && $0=="---" { inside=1; next }
    inside && $0=="---" { exit }
    inside && /^docs:/ { indocs=1; next }
    indocs && /^[^ ]/ { indocs=0 }
    indocs && /^  [a-z_]+:/ { k=$0; sub(/^  /, "", k); sub(/:.*/, "", k); print k }' "$CONFIG")
}
docs_path() {  # docs_path <key> → its path from the config, else the contract's default
  case "$1" in
    knowledge) cfg_docs knowledge docs/domains ;;
    lessons) cfg_docs lessons docs/lessons.md ;;
    *) cfg_docs "$1" ;;
  esac
}
# record_dirs → the places a decision can be *filed*: the record's own stores
# (decisions, conventions, knowledge, questions, specs) and any key the sous added.
# Not journals, plans, checklists, backlog, research or brainstorms: those mention
# answers without recording them, and a mention must not count as filed.
record_dirs() {
  local key path seen=" "
  while IFS= read -r key; do
    case "$key" in journal|plans|checklists|backlog|research|brainstorm|lessons) continue ;; esac
    path="$(docs_path "$key")"
    [[ "$path" == none || -z "$path" ]] && continue
    path="${path%/}"
    [[ "$seen" == *" $path "* ]] && continue; seen="$seen$path "
    [[ -e "$ROOT/$path" ]] && echo "$ROOT/$path"
  done < <(docs_keys)
  [[ -f "$ROOT/CLAUDE.md" ]] && echo "$ROOT/CLAUDE.md"
}

cmd_decisions() {
  local register f files=() dirs=() d hits id n key status where any=false
  register="$ROOT/$(cfg_docs lessons docs/lessons.md)"
  while IFS= read -r f; do files+=("$f"); done < <(journal_files)
  (( ${#files[@]} == 0 )) && { echo "No ticket journals yet."; return 0; }
  while IFS= read -r d; do dirs+=("$d"); done < <(record_dirs)
  {
    for f in "${files[@]}"; do
      id="$(awk 'NR==1 && $0=="---" {fm=1; next} fm && $0=="---" {exit} fm && /^ticket:/ {sub(/^ticket:[ ]*/, ""); print; exit}' "$f")"
      [[ -z "$id" ]] && id="$(basename "$f" | sed -E 's/^([A-Za-z]+-[0-9]+(-[0-9]+)?|S[0-9]+-[0-9]+).*/\1/')"
      grep -E '^- .* · A[0-9]+ \(head chef\)' "$f" 2>/dev/null | while IFS= read -r line; do
        n="$(printf '%s' "$line" | sed -E 's/^- .* · (A[0-9]+) \(head chef\).*/\1/')"
        key="$id $n"
        status=DUE; where="-"
        if [[ -f "$register" ]] && grep -qF -- "\`$key\`" "$register"; then
          status=kept; where="register"
        elif (( ${#dirs[@]} > 0 )) && hits="$(grep -rlE -- "${key}([^0-9]|\$)" "${dirs[@]}" 2>/dev/null | grep -v -F -e "$f" -e "$register" | head -1)" && [[ -n "$hits" ]]; then
          status=filed; where="${hits#"$ROOT"/}"
        fi
        printf '%-14s %-6s %-36s %s\n' "$key" "$status" "$where" "$(printf '%s' "$line" | sed -E 's/^- .* · A[0-9]+ \(head chef\):? *//')"
      done
    done
  } | { if read -r first; then any=true; printf '%-14s %-6s %-36s %s\n' ANSWER STATUS WHERE "HEAD CHEF SAID"; echo "$first"; cat; fi; $any || echo "No head-chef answers in any journal."; }
}

# ---------------------------------------------------------------------------
# inbox — capture at utterance, file at handoff (Contract 12). One dated line per
# thing the head chef said that the record doesn't hold. Local to this machine
# (.git/info/exclude), so it survives a /clear and never reaches a PR.
# ---------------------------------------------------------------------------
inbox_count() { local f="$ROOT/.claude/inbox.md"; [[ -f "$f" ]] || { echo 0; return 0; }; grep -c '^- ' "$f" || true; }

cmd_inbox() {
  local file="$ROOT/.claude/inbox.md" here_real n
  if $ADD_GIVEN; then
    if [[ -z "$ADD_TEXT" || "$ADD_TEXT" == -* ]]; then
      echo "Usage: kitchen.sh inbox --add \"<what the head chef said>\"" >&2; return 1
    fi
    here_real="$(cd "$HERE" && pwd -P)"
    if [[ "$here_real" != "$ROOT_REAL" ]]; then
      echo "Only the sous feeds the inbox, from the main checkout ($ROOT_REAL). A cook's gotcha is a lesson(repo) in its journal." >&2; return 1
    fi
    mkdir -p "$ROOT/.claude"
    exclude_locally .claude/inbox.md
    if [[ ! -f "$file" ]]; then
      printf '# Inbox\n\nThings the head chef said that the record does not hold yet. Written by `kitchen.sh inbox --add`;\nfiled into the docs map at the sous'"'"'s handoff, then removed. Local to this machine.\n\n' > "$file"
    fi
    printf -- '- %s · %s\n' "$(date '+%Y-%m-%d %H:%M')" "$ADD_TEXT" >> "$file"
  fi
  n="$(inbox_count)"
  if (( n == 0 )); then echo "Inbox empty."; return 0; fi
  echo "Inbox: $n unfiled line(s) in .claude/inbox.md"
  grep '^- ' "$file"
}

# ---------------------------------------------------------------------------
# asks — the ask log (Contract 12). Every question the sous puts to the head chef
# is one line in .claude/asks.md, written the moment it is asked, so a question the
# head chef never got round to is still there after a /clear. Its answer and its
# fix are appended as lines of their own, like Qn/An in a journal, so the file is
# append-only and the status is derived:
#   - A3 · <when> · <ticket or -> · <gap kind or ?> · Q: <the question>
#   - A3 answered · <when> · <the head chef's words>
#   - A3 filed · <when> · <where the fix went>
# A question that reached the head chef is a gap: something the kitchen lacked.
#   context  the record didn't hold it      → knowledge, convention or decision doc
#   ruling   no rule covered it             → a decision (ADR) in docs.decisions
#   harness  a tool, hook, skill or script  → a chore ticket here, or lesson(plugin) → /bk:feedback
#   access   a credential, CLI or permission → brigade.local.md, and a note in the config
# Local to this machine (.git/info/exclude), like the inbox.
# ---------------------------------------------------------------------------
GAP_KINDS="context ruling harness access"
gap_fix() {
  case "$1" in
    context) echo "the record: a knowledge, convention or decision doc (handoff step 3 or 6)" ;;
    ruling) echo "a decision in docs.decisions, citing the ask" ;;
    harness) echo "a chore ticket in this repo, or lesson(plugin) → /bk:feedback" ;;
    access) echo "brigade.local.md, plus a one-line note in the config so the next session knows" ;;
    *) echo "decide the gap kind first (context | ruling | harness | access)" ;;
  esac
}
# asks_rows → one row per ask: "<id>\t<when>\t<ticket>\t<gap>\t<status>\t<question>\t<answer>\t<where filed>"
asks_rows() {
  local f="$ROOT/.claude/asks.md"
  [[ -f "$f" ]] || return 0
  awk -F' · ' '
    /^- A[0-9]+ · / { id=$1; sub(/^- /, "", id); q=""; for (i=5; i<=NF; i++) q = q (i>5 ? " · " : "") $i; sub(/^Q: /, "", q)
                      if (!(id in seen)) { seen[id]=1; order[++n]=id }; when[id]=$2; tk[id]=$3; gap[id]=$4; text[id]=q; next }
    /^- A[0-9]+ answered · / { id=$1; sub(/^- /, "", id); sub(/ answered$/, "", id); a=""; for (i=3; i<=NF; i++) a = a (i>3 ? " · " : "") $i; ans[id]=a; next }
    /^- A[0-9]+ filed · /    { id=$1; sub(/^- /, "", id); sub(/ filed$/, "", id); w=""; for (i=3; i<=NF; i++) w = w (i>3 ? " · " : "") $i; filed[id]=w; next }
    END { for (i=1; i<=n; i++) { id=order[i]; st = (id in filed) ? "filed" : (id in ans) ? "answered" : "open"
          printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", id, when[id], tk[id], gap[id], st, text[id], ans[id], filed[id] } }' "$f"
}
asks_count() { asks_rows | awk -F'\t' -v st="$1" '$5==st { n++ } END { print n+0 }'; }

cmd_asks() {
  local file="$ROOT/.claude/asks.md" here_real id n writing=false
  if $ADD_GIVEN || [[ -n "$ANSWER_ID" || -n "$FILED_ID" ]]; then
    writing=true
    here_real="$(cd "$HERE" && pwd -P)"
    if [[ "$here_real" != "$ROOT_REAL" ]]; then
      echo "Only the sous keeps the ask log, from the main checkout ($ROOT_REAL). A cook's question is a [gate] to the sous." >&2; return 1
    fi
  fi
  if $ADD_GIVEN; then
    if [[ -z "$ADD_TEXT" || "$ADD_TEXT" == -* ]]; then
      echo "Usage: kitchen.sh asks --add \"<the question, as put to the head chef>\" [--ticket ID] [--gap context|ruling|harness|access]" >&2; return 1
    fi
    if [[ -n "$GAP" && " $GAP_KINDS " != *" $GAP "* ]]; then
      echo "Unknown gap kind \"$GAP\": one of $GAP_KINDS (or leave it out until you know)." >&2; return 1
    fi
    mkdir -p "$ROOT/.claude"
    exclude_locally .claude/asks.md
    if [[ ! -f "$file" ]]; then
      printf '# Asks\n\nEvery question the sous put to the head chef, written the moment it was asked (`kitchen.sh asks --add`).\nAn answer and a fix are appended as lines of their own (`--answer`, `--filed`). A question that reached the\nhead chef is a gap; the handoff files its fix. Local to this machine.\n\n' > "$file"
    fi
    n="$(grep -c '^- A[0-9]* · ' "$file" || true)"; id="A$((n+1))"
    printf -- '- %s · %s · %s · %s · Q: %s\n' "$id" "$(date '+%Y-%m-%d %H:%M')" "${TICKET:--}" "${GAP:-?}" "$ADD_TEXT" >> "$file"
    echo "$id"
  fi
  if [[ -n "$ANSWER_ID" ]]; then
    [[ -n "$ANSWER_TEXT" && "$ANSWER_TEXT" != -* ]] || { echo "Usage: kitchen.sh asks --answer A3 \"<the head chef's words>\"" >&2; return 1; }
    [[ -f "$file" ]] && grep -q "^- $ANSWER_ID · " "$file" || { echo "No ask $ANSWER_ID in .claude/asks.md." >&2; return 1; }
    printf -- '- %s answered · %s · %s\n' "$ANSWER_ID" "$(date '+%Y-%m-%d %H:%M')" "$ANSWER_TEXT" >> "$file"
  fi
  if [[ -n "$FILED_ID" ]]; then
    [[ -n "$FILED_TEXT" && "$FILED_TEXT" != -* ]] || { echo "Usage: kitchen.sh asks --filed A3 \"<where the fix went: a path, a ticket, an issue>\"" >&2; return 1; }
    [[ -f "$file" ]] && grep -q "^- $FILED_ID · " "$file" || { echo "No ask $FILED_ID in .claude/asks.md." >&2; return 1; }
    # an unanswered ask may only be "filed" into a question file (parked at the handoff); a fix needs the answer first
    if ! grep -q "^- $FILED_ID answered · " "$file"; then
      local qdir; qdir="$(docs_path questions)"
      case "$FILED_TEXT" in *"$qdir"/*) ;; *) echo "$FILED_ID has no answer yet: --answer first, then --filed (or file it into $qdir/ as an open question)." >&2; return 1 ;; esac
    fi
    printf -- '- %s filed · %s · %s\n' "$FILED_ID" "$(date '+%Y-%m-%d %H:%M')" "$FILED_TEXT" >> "$file"
  fi
  $writing && return 0
  local open answered
  open="$(asks_count open)"; answered="$(asks_count answered)"
  if (( open + answered == 0 )); then echo "No asks waiting: nothing open, nothing answered and unfiled."; return 0; fi
  echo "Asks: $open open (the head chef still owes an answer) · $answered answered, gap not fixed yet"
  printf '%-4s %-16s %-9s %-8s %-9s %s\n' ASK WHEN TICKET GAP STATUS QUESTION
  asks_rows | awk -F'\t' '$5!="filed" { printf "%-4s %-16s %-9s %-8s %-9s %s%s\n", $1, $2, $3, $4, $5, $6, ($7=="" ? "" : "  → " $7) }'
}

# gaps — the handoff's fourth list: every answered ask not yet filed, and every
# answered question file under docs.questions with no fix:, grouped by gap kind.
cmd_gaps() {
  local qdir any=false
  qdir="$(docs_path questions)"
  {
    asks_rows | awk -F'\t' '$5=="answered" { printf "%s\t%s\t%s\t%s\n", $4, $1, $3, $6 }'
    if [[ "$qdir" != none && -d "$ROOT/$qdir" ]]; then
      for f in "$ROOT/$qdir"/*.md; do
        [[ -f "$f" && "$(basename "$f")" != INDEX.md ]] || continue
        awk -v fn="$(basename "$f")" '
          NR==1 && $0=="---" { fm=1; next }
          fm && $0=="---" { exit }
          fm && /^status:/ { s=$0; sub(/^status:[ ]*/, "", s); sub(/[ ]+#.*$/, "", s); status=s }
          fm && /^title:/ { t=$0; sub(/^title:[ ]*/, "", t); gsub(/^"|"$/, "", t); title=t }
          fm && /^gap:/ { g=$0; sub(/^gap:[ ]*/, "", g); sub(/[ ]+#.*$/, "", g); gap=g }
          fm && /^fix:/ { x=$0; sub(/^fix:[ ]*/, "", x); sub(/[ ]+#.*$/, "", x); fix=x }
          END { if (status == "answered" && (fix == "" || fix == "null")) printf "%s\t%s\t%s\t%s\n", (gap == "" || gap == "null" ? "?" : gap), fn, "-", title }' "$f"
      done
    fi
  } | sort -t$'\t' -k1,1 -s | {
    local kind item ticket text last=""
    while IFS=$'\t' read -r kind item ticket text; do
      any=true
      if [[ "$kind" != "$last" ]]; then
        [[ -n "$last" ]] && echo ""
        echo "$kind → $(gap_fix "$kind")"; last="$kind"
      fi
      printf '  %-28s %-9s %s\n' "$item" "$ticket" "$text"
    done
    $any || echo "No gaps to fix: every answered ask is filed, every answered question has its fix."
  }
}

# ---------------------------------------------------------------------------
# doctor — are the ticket files and the docs map well-formed? Two tiers:
#   errors   (exit 1): a ticket with a missing or unknown field, a BKLG item with
#            no kind, a duplicate id, a blocker that is no ticket; a mapped path
#            that is a file where a folder should be.
#   warnings (exit 0): a mapped folder with no INDEX.md, a folder under docs/ that
#            no docs: key names. Real repos have docs/assets/ and an adr/ folder
#            from another tool; those are worth a look, not a red gate.
# Tickets are the files in docs.backlog and one level inside a spec's folder
# (docs.specs/NNN-<slug>/NN-<slug>.md); the spec documents themselves are not
# tickets and have their own statuses.
# ---------------------------------------------------------------------------
cmd_doctor() {
  local backlog specs key path problems=0 warnings=0 f d sub mapped=" "
  backlog="$(cfg_docs backlog)"; specs="$(cfg_docs specs)"
  say() { echo "  $1"; problems=$((problems+1)); }
  warn() { echo "  warn: $1"; warnings=$((warnings+1)); }
  echo "Tickets:"
  local files=()
  if [[ "$backlog" != none && -d "$ROOT/$backlog" ]]; then
    while IFS= read -r f; do files+=("$f"); done < <(find "$ROOT/$backlog" -name '*.md' ! -name INDEX.md -type f 2>/dev/null | sort)
  fi
  if [[ "$specs" != none && -d "$ROOT/$specs" ]]; then
    while IFS= read -r f; do files+=("$f"); done < <(find "$ROOT/$specs" -mindepth 2 -maxdepth 2 -name '*.md' ! -name INDEX.md -type f 2>/dev/null | sort)
  fi
  if (( ${#files[@]} > 0 )); then
    while IFS= read -r line; do say "$line"; done < <(awk '
      function flush() {
        if (file == "") return
        if (!fm_seen) { print rel ": no frontmatter"; file=""; return }
        if (id == "") print rel ": missing id"
        else { if (id in seen) print rel ": id " id " is also " seen[id]; else seen[id]=rel }
        if (title == "") print rel ": missing title"
        if (lane == "") print rel ": missing lane"
        if (status == "") print rel ": missing status"
        else if (status !~ /^(backlog|todo|in-progress|rfr|done|blocked)$/) print rel ": unknown status \"" status "\""
        if (id ~ /^BKLG-/ && kind == "") print rel ": BKLG item without kind (item | bug | chore | precedent)"
        if (kind != "" && kind !~ /^(item|bug|chore|precedent)$/) print rel ": unknown kind \"" kind "\""
        if (kind == "precedent") { n = split(prec, pi, ","); c = 0; for (i = 1; i <= n; i++) if (pi[i] != "") c++
          if (c < 2) print rel ": kind: precedent needs two instances or more under precedent: (has " c ")"
          if (why == "" || why == "null") print rel ": kind: precedent without precedent_why: (where the record says why)" }
        n = split(blk, b, ","); for (i = 1; i <= n; i++) if (b[i] != "") pend[++np] = rel " blocked_by " b[i]
        file=""
      }
      FNR==1 { flush(); file=FILENAME; rel=substr(FILENAME, length(root)+2); id=title=lane=status=kind=blk=prec=why=""; fm=0; fm_seen=0 }
      FNR==1 && $0=="---" { fm=1; fm_seen=1; next }
      fm && $0=="---" { fm=0; next }
      fm { key=$0; sub(/:.*/, "", key); val=$0; sub(/^[^:]*:[ ]*/, "", val); sub(/[ ]+#.*$/, "", val); gsub(/^"|"$/, "", val)
           if (key=="id") id=val; else if (key=="title") title=val; else if (key=="lane") lane=val; else if (key=="status") status=val
           else if (key=="kind") kind=val; else if (key=="precedent") { prec=val; gsub(/[]["\047 ]/, "", prec) } else if (key=="precedent_why") why=val; else if (key=="blocked_by") { blk=val; gsub(/[]["\047 ]/, "", blk) } }
      END { flush(); for (i = 1; i <= np; i++) { split(pend[i], p, " blocked_by "); if (!(p[2] in seen)) print p[1] " is blocked by " p[2] ", which is no ticket here" } }
    ' root="$ROOT" "${files[@]}")
    (( problems == 0 )) && echo "  ${#files[@]} ticket file(s), all well-formed."
  else
    echo "  no ticket files under $backlog or $specs."
  fi
  echo "Docs map:"
  local before=$problems before_w=$warnings
  while IFS= read -r key; do
    path="$(docs_path "$key")"
    [[ "$path" == none || -z "$path" ]] && continue
    path="${path%/}"; mapped="$mapped$path "
    [[ "$path" == *.md ]] && continue   # a file, such as the register: created on first use
    [[ -f "$ROOT/$path" ]] && { say "docs.$key: $path is a file, not a folder"; continue; }
    [[ -d "$ROOT/$path" ]] || continue   # a store this repo hasn't needed yet is fine
    [[ -f "$ROOT/$path/INDEX.md" ]] || warn "docs.$key: $path/ has no INDEX.md (Contract 4: one row per file)"
  done < <(docs_keys)
  if [[ -d "$ROOT/docs" ]]; then
    for d in "$ROOT"/docs/*/; do
      [[ -d "$d" ]] || continue
      sub="${d#"$ROOT"/}"; sub="${sub%/}"
      [[ "$mapped" == *" $sub "* ]] && continue
      # a folder that holds a mapped folder (docs/exec-plans holding docs/exec-plans/active) is fine
      [[ "$mapped" == *" $sub/"* ]] && continue
      warn "$sub/ is under docs/ but no docs: key names it (add one, or it stays invisible to the commis)"
    done
  fi
  (( problems == before && warnings == before_w )) && echo "  every mapped folder exists with an INDEX.md; nothing under docs/ is unmapped."
  (( warnings == 0 )) || echo "$warnings warning(s): worth a look, not a failure."
  (( problems == 0 )) || { echo "$problems problem(s)."; return 1; }
}

# ---------------------------------------------------------------------------
# sessions — where Claude Code saved this checkout's session transcripts, for
# /bk:feedback. Claude Code keeps them in <config dir>/projects/<slug>/<id>.jsonl,
# where the slug is the session's working directory with every character that
# isn't a letter or digit turned into "-". CLAUDE_CONFIG_DIR wins over ~/.claude.
# ---------------------------------------------------------------------------
cmd_sessions() {
  local base dir d slug seen=" " found=false
  base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
  dir="${SESSIONS_DIR:-$HERE}"
  [[ -d "$dir" ]] || { echo "No such directory: $dir" >&2; return 1; }
  # A session may have recorded the path as typed or with symlinks resolved.
  for d in "$(cd "$dir" && pwd -L)" "$(cd "$dir" && pwd -P)"; do
    slug="$(printf '%s' "$d" | sed 's/[^A-Za-z0-9]/-/g')"
    [[ "$seen" == *" $slug "* ]] && continue; seen="$seen$slug "
    [[ -d "$base/$slug" ]] || continue
    # shellcheck disable=SC2012  # names are <uuid>.jsonl; ls -t is the portable mtime sort
    ls -1t "$base/$slug"/*.jsonl 2>/dev/null && found=true
  done
  $found || echo "No saved sessions for $dir under $base."
}

# ---------------------------------------------------------------------------
# budget — what the kitchen spends. The reading lives in the Window's server
# (window/server/live/budget.js) so the terminal and the Window sum the same way; this
# only finds node and runs it from the main checkout.
# ---------------------------------------------------------------------------
cmd_budget() {
  local dir args=()
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../window" 2>/dev/null && pwd -P)"
  [[ -f "$dir/server/live/budget.js" ]] || { echo "The budget reader isn't in this plugin install ($dir)." >&2; return 1; }
  command -v node >/dev/null 2>&1 || { echo "The budget needs node 20 or newer on your PATH (brew install node, or nodejs.org)." >&2; return 1; }
  mkdir -p "$ROOT/.claude"; exclude_locally .claude/budget.jsonl
  args=(--root "$ROOT" --since "$SINCE")
  [[ -n "$TICKET" ]] && args+=(--ticket "$TICKET")
  [[ -n "$SESSION_NAME" ]] && args+=(--session "$SESSION_NAME")
  $CI && args+=(--ci); $JSON && args+=(--json); $JOURNAL_LINE && args+=(--journal-line)
  node "$dir/server/live/budget.js" "${args[@]}"
}

# debrief — the budget's rules over the week (Contract 11): the mechanical half of the
# kitchen fixing its own friction. The sous runs it at handoff next to lessons and fires a
# chore per DUE row.
cmd_debrief() {
  local dir args=()
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../window" 2>/dev/null && pwd -P)"
  [[ -f "$dir/server/live/budget.js" ]] || { echo "The budget reader isn't in this plugin install ($dir)." >&2; return 1; }
  command -v node >/dev/null 2>&1 || { echo "The debrief needs node 20 or newer on your PATH (brew install node, or nodejs.org)." >&2; return 1; }
  args=(--root "$ROOT" --since 7d --debrief --register "$ROOT/$(cfg_docs lessons docs/lessons.md)")
  $JSON && args+=(--json)
  node "$dir/server/live/budget.js" "${args[@]}"
}

# ---------------------------------------------------------------------------
# live — the Window. One node process (plugins/bk/window/server) serving the kitchen on
# localhost; pid and port in .claude/window.pid, output in .claude/window.log, both kept
# out of git. `live` toggles, `live stop` closes, `live status` only looks.
# ---------------------------------------------------------------------------
open_url() {
  case "$(os_kind)" in
    mac) open "$1" >/dev/null 2>&1 ;;
    linux) command -v xdg-open >/dev/null 2>&1 && xdg-open "$1" >/dev/null 2>&1 ;;
    wsl) cmd.exe /c start "$1" >/dev/null 2>&1 ;;
    windows) start "$1" >/dev/null 2>&1 ;;
  esac
  return 0
}

cmd_live() {
  local pidfile="$ROOT/.claude/window.pid" logfile="$ROOT/.claude/window.log" dir pid port url
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../window" 2>/dev/null && pwd -P)"
  pid=""; port=""; [[ -f "$pidfile" ]] && read -r pid port < "$pidfile"
  if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then rm -f "$pidfile"; pid=""; fi   # a stale pid file
  url="http://localhost:${port:-$LIVE_PORT}"
  case "$LIVE_WORD" in
    status)
      if [[ -n "$pid" ]]; then echo "The Window is open: $url (pid $pid)"; else echo "The Window is closed."; fi
      return 0 ;;
    stop)
      [[ -n "$pid" ]] || { echo "The Window is closed."; return 0; } ;;
  esac
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null; rm -f "$pidfile"
    echo "The Window is closed (was $url)."
    return 0
  fi
  [[ -f "$dir/server/index.js" ]] || { echo "The Window isn't in this plugin install ($dir)." >&2; return 1; }
  command -v node >/dev/null 2>&1 || { echo "The Window needs node 20 or newer on your PATH (brew install node, or nodejs.org)." >&2; return 1; }
  mkdir -p "$ROOT/.claude"
  exclude_locally .claude/window.pid; exclude_locally .claude/window.log
  local args=(--root "$ROOT" --port "$LIVE_PORT")
  $DEMO && args+=(--demo --stations "$N")
  nohup node "$dir/server/index.js" "${args[@]}" > "$logfile" 2>&1 &
  pid=$!
  printf '%s %s\n' "$pid" "$LIVE_PORT" > "$pidfile"
  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$pidfile"
    echo "The Window didn't start. Its log, $logfile:" >&2; tail -5 "$logfile" >&2
    return 1
  fi
  url="http://localhost:$LIVE_PORT"
  if $DEMO; then echo "The Window is open on a demo service: $url"; else echo "The Window is open: $url"; fi
  echo "  run again to close it; log: $logfile"
  $NO_LAUNCH || open_url "$url"
}

# ---------------------------------------------------------------------------
# remove
# ---------------------------------------------------------------------------

cmd_remove() {
  [[ -d "$KITCHEN" ]] || { echo "No $KITCHEN_REL/ to remove."; exit 0; }
  cmd_status || true
  echo ""
  if [[ "$MODE" == worktree ]]; then
    echo "This removes every worktree in $KITCHEN_REL/. Branches and commits stay in the repo;"
    echo "a station with uncommitted work is refused, not deleted."
  else
    echo "This deletes $KITCHEN_REL/ — every station, including unpushed branches and uncommitted work."
  fi
  read -r -p "Type 'delete' to confirm: " answer
  [[ "$answer" == delete ]] || { echo "Aborted."; exit 1; }
  if [[ "$MODE" == worktree ]]; then
    # git worktree remove refuses a dirty worktree, which is the point: it
    # would otherwise delete a cook's uncommitted work. Stash or commit first.
    local s failed=false
    while IFS= read -r s; do
      git -C "$ROOT" worktree remove "$s" && echo "  $(basename "$s"): removed" \
        || { echo "  $(basename "$s"): NOT removed (dirty? commit or stash it first)"; failed=true; }
    done < <(stations)
    git -C "$ROOT" worktree prune
    $failed || { rmdir "$KITCHEN" 2>/dev/null; echo "Removed."; }
  else
    rm -rf "$KITCHEN"; echo "Removed."
  fi
}

case "$CMD" in
  setup) cmd_setup ;; open) cmd_open ;; sync) cmd_sync ;; status) cmd_status ;;
  files) cmd_files ;; rail) cmd_rail ;; board) cmd_board ;; leaks) cmd_leaks ;; remove) cmd_remove ;;
  role) cmd_role ;; sous) cmd_sous ;; lessons) cmd_lessons ;; questions) cmd_questions ;;
  decisions) cmd_decisions ;; inbox) cmd_inbox ;; asks) cmd_asks ;; gaps) cmd_gaps ;; doctor) cmd_doctor ;;
  sessions) cmd_sessions ;; live) cmd_live ;; budget) cmd_budget ;; debrief) cmd_debrief ;; *) usage ;;
esac
