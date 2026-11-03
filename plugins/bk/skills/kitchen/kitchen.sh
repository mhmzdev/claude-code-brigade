#!/usr/bin/env bash
# =============================================================================
# kitchen.sh — the Brigade's station manager
#
# A station is a git worktree of the main checkout, by default in a sibling folder
# ../<repo>-stations/station-N (or the config's `kitchen:`). It shares one object store,
# so it suits big repos and repos that live inside a workspace repo. Its work is
# ephemeral: when the ticket is merged, `done` deletes the branch and resets the station.
# One Claude Code line cook works in each. Assignment happens through the sous chef over SendMessage, never
# through this script: each session starts as a line cook and waits for a brief.
#
# Run from anywhere inside the main checkout. Settings come from the flat keys
# in .claude/brigade.md (trunk, install, copy_into_stations,
# kitchen, stations, migrations); env vars override them.
#
# Usage:
#   kitchen.sh setup  [-n N]              create stations 1..N, keeping existing ones, so
#                                         it also grows a kitchen (worktree, gitignore,
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
#   kitchen.sh sync   [-n N]              detach CLEAN stations at origin/<trunk>
#                                         (dirty ones are skipped)
#   kitchen.sh status                     branch / dirty / ahead per station + open PRs
#   kitchen.sh files                      files in flight per station vs origin/<trunk>,
#                                         plans, and unmerged migrations
#   kitchen.sh rail                       the board, computed from ticket frontmatter
#                                         (markdown rail only): priority, whether each
#                                         free ticket is ready (or still needs a spec),
#                                         and its open blockers
#   kitchen.sh rail brief <ID> station-N  the sous, as it sends a [brief]: record that the station is
#                                         briefed on the ticket (.claude/briefs, out of git). Refuses
#                                         a ticket somebody else holds
#   kitchen.sh rail claim <ID> <todo|in-progress>
#   kitchen.sh rail move <ID> <in-progress|rfr>
#                                         a cook claims, then moves, the ticket briefed to it: todo →
#                                         in-progress → rfr (and rfr → in-progress). Free tickets only;
#                                         a claim is never overwritten (Contract 3). A markdown rail is
#                                         written as a commit built on origin/<trunk>, never touching
#                                         the main checkout; a github rail through gh project
#                                         item-edit. Every refusal exits 1, writes nothing and says
#                                         to send the sous [rail]. (From the main checkout the sous
#                                         names the station: rail claim <ID> <status> station-N)
#   kitchen.sh here [--fresh|--spent] [--waiting "<what>"] [--note "<text>"] [-m <model>]
#                                         a cook's state, by script, in place of a [check-in] or
#                                         [status] message: <station>/.claude/here (out of git), read
#                                         by board. A free cook still sends one [check-in] message
#   kitchen.sh board                      status, files, rail, open questions and the
#                                         record's counts (decisions, inbox, asks, gaps) in one
#                                         go; from the main checkout it also writes them
#                                         to .claude/board.md (kept out of git)
#   kitchen.sh leaks [--dir D] [--also F] search a checkout's changed files and branch
#                                         commit messages (D, default: here; plus file F,
#                                         e.g. a PR body) for any test-account secret in
#                                         .claude/brigade.local.md. Prints file:line only,
#                                         never the value; exits 1 on a hit
#   kitchen.sh scope [station-N]          the plan's files: is the ticket's write scope (Contract 4):
#                                         the station's changed files against it, printed inside and
#                                         outside; exits 1 when anything is outside, or no plan names
#                                         the ticket. The record (plan, journal, checklist, INDEX files,
#                                         the config's scope: always_inside: globs) is always inside
#   kitchen.sh scope --overlap [--ticket ID[,ID…]]
#                                         every collision between two scopes (each station's plan files
#                                         and diff, each ready ticket's plan or files:) as ticket (station,
#                                         stage) × ticket, with the paths; exits 1 on any
#   kitchen.sh check [--force]            the config's check command, run once per tree. It
#                                         hashes this checkout's working state (tracked,
#                                         deleted and untracked files, minus what git
#                                         ignores) and looks in .claude/check.log for a
#                                         green receipt of the same command on that tree:
#                                         found, it says so and runs nothing; else it runs the
#                                         command, appends a receipt to the log (the tree, start
#                                         and end, the command, exit, sha256 of the output, the
#                                         station) and prints green or red (the last 40 lines on
#                                         red; the full output is in .claude/check.out). --force
#                                         runs it anyway. Exits with the check's own code. Both
#                                         files are kept out of git
#   kitchen.sh check --receipt [TREE]     print the newest receipt for this checkout's tree (or
#                                         TREE, a full 40-hex id; anything else exits 64). Exit
#                                         0: it is green and the config's check: line is the
#                                         one it ran; 1: there is none ("no receipt for this
#                                         tree"); 2: there is one that cannot be relied on,
#                                         red or stale (the reason on stderr). A run that
#                                         moved its own tree is not a receipt
#   kitchen.sh remove                     delete every station (asks first)
#   kitchen.sh role                       "cook <station> <main checkout>" when run inside
#                                         a station, else "main <main checkout>"
#   kitchen.sh sous [--set NAME]          print the sous chef's session name, from the
#                                         main checkout or any station (exits 1 if none
#                                         is recorded). --set, from the main checkout:
#                                         record it in .claude/sous (kept out of git)
#   kitchen.sh clear <station-N|sous>     clear that session, the sous's job (Contract 5):
#                                         types /clear into its tmux pane, then the role skill
#                                         (/bk:line-cook, or /bk:sous-chef: the sous's own call
#                                         waits for its turn to end), once it is idle, its handoff is newer
#                                         than its last turn and nothing it sent still waits
#                                         for an answer. Refuses otherwise, saying why.
#                                         Needs node (reads the session's transcript)
#   kitchen.sh ship <PR number>           merge that PR, the sous's job when gates.merge is
#                                         sous-chef (the default): open, not a draft, against
#                                         trunk, mergeable, up to date, every check green
#                                         (refuses otherwise, naming the condition), then
#                                         `gh pr merge --merge` (gates.merge_method: merge |
#                                         squash | rebase). With gates.merge: head-chef it
#                                         refuses: the merge is the head chef's there
#   kitchen.sh done <station-N>           after the merge, the sous's job (End of shift: ship, done,
#                                         reap, clear): detach the station at origin/<trunk>, delete
#                                         the ticket branch locally and on origin, drop the ticket's
#                                         per-ticket files; the folder and the session stay. Only a
#                                         branch whose PR gh says is MERGED, and whose tip is that
#                                         PR's head (and the PR went into trunk); refuses a dirty station
#                                         or a busy session. Never force-pushes; one summary line says
#                                         what was and wasn't deleted
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
#   kitchen.sh record-pr                  file the record: the dirty files under the docs map's
#                                         decisions, conventions, knowledge and questions and
#                                         the lessons register. With rail.commit direct it
#                                         pushes them to trunk; if trunk refuses (protected),
#                                         or with daily-pr, it pushes a record/<date> branch
#                                         and opens a PR. Back on a clean trunk either way.
#                                         The sous's, from the main checkout only
#   kitchen.sh doctor                     check ticket files (fields, statuses, blockers,
#                                         ids) and the docs map (folders exist, have an
#                                         INDEX.md, nothing under docs/ is unmapped)
#                                         (any depth under docs.journal, so finished
#                                         ones moved to a subfolder still count) and
#                                         say which are due for promotion
#   kitchen.sh index [--check] [--adopt]  the INDEX.md of plans, journals and checklists,
#                                         generated from the files' frontmatter (Contract
#                                         12), in the checkout it is run from. --check
#                                         writes nothing and exits 1 if one is out of
#                                         date. A hand-written INDEX is left alone until
#                                         --adopt takes it over
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
#   kitchen.sh procs [--add <pid> "<what>" [--ticket ID]] [--prune] [--station N]
#                    [--reap <station-N|all>] [--scan]
#                                         the processes the kitchen started, and only those
#                                         (Contract 7). --add registers a pid the moment a cook
#                                         starts it (a dev server, a watcher, a tunnel, a poll):
#                                         its start time and command line go into
#                                         <station>/.claude/procs (out of git), from a station,
#                                         or --station N from the main checkout. A system process,
#                                         claude, tmux, a pane's shell, someone else's process,
#                                         the caller's own session and a process whose working
#                                         directory is not inside the station are refused. A cook
#                                         can use only its own station (--reap, and --station for
#                                         another, are the sous's). With no
#                                         option: the register of the station it runs in, or of
#                                         every station from the main checkout (--station N picks
#                                         one), each line alive, dead or reused (the pid now
#                                         belongs to another process). --prune drops the dead and
#                                         the reused lines. --reap is
#                                         the sous's, after ship and before clear (bk stop runs it
#                                         for every station): each registered process that still
#                                         has its recorded start time and command line gets TERM,
#                                         then KILL after 5 s, and is logged in
#                                         <station>/.claude/procs.log; anything else is left alone
#                                         and printed. --scan lists processes standing in a station
#                                         that are not registered and are not a kitchen session.
#                                         It only reports; nothing it finds is ever signalled
#   kitchen.sh live [stop|status] [--port P] [--demo [-n N]] [--no-launch]
#                                         the Window: a live view of this kitchen on
#                                         localhost (needs node 20+). With no word it
#                                         toggles: opens it (and your browser) if closed,
#                                         closes it if open. --demo runs a scripted
#                                         service with N stations instead of the live
#                                         kitchen. Pid and log in .claude/, out of git
#
# Env overrides:
#   BRIGADE_TRUNK, BRIGADE_KITCHEN, BRIGADE_STATIONS, BRIGADE_MODEL (default sonnet),
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

# cfg_gate <key> [default] → gates.<key> from the nested gates: block ("" or the default if absent)
cfg_gate() {
  local v=""
  [[ -f "$CONFIG" ]] && v="$(awk -v k="$1" '
    NR==1 && $0=="---" { inside=1; next }
    inside && $0=="---" { exit }
    inside && /^gates:/ { ing=1; next }
    ing && /^[^ ]/ { ing=0 }
    ing && $0 ~ "^  " k ":" { sub("^  " k ":[ ]*", ""); sub(/[ ]+#.*$/, ""); gsub(/^"|"$/, ""); print; exit }' "$CONFIG")"
  printf '%s' "${v:-${2:-}}"
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
# Clone stations are gone (#85). A config that still says clone may only run `remove`, which
# deletes the old <repo>/stations/; every other command stops below, before the dispatcher.
LEGACY_CLONE=false
[[ "${BRIGADE_KITCHEN_MODE:-$(cfg kitchen_mode)}" == clone ]] && LEGACY_CLONE=true
KITCHEN_REL="${BRIGADE_KITCHEN:-$(cfg kitchen)}"
$LEGACY_CLONE && KITCHEN_REL="stations"
KITCHEN_REL="${KITCHEN_REL:-../${REPO_NAME}-stations}"
[[ "$KITCHEN_REL" == /* ]] && KITCHEN="$KITCHEN_REL" || KITCHEN="$ROOT/$KITCHEN_REL"
# Normalise ../ so paths print cleanly and compare reliably.
if [[ -d "$(dirname "$KITCHEN")" ]]; then
  KITCHEN="$(cd "$(dirname "$KITCHEN")" && pwd -P)/$(basename "$KITCHEN")"
fi
ROOT_REAL="$(cd "$ROOT" && pwd -P)"
REC="$ROOT"   # where the record is read from: $ROOT, or the temp view that lays the open record branches over it (record_view)
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
FORCE=false       # --force, for check
RECEIPT=false; RECEIPT_TREE=""   # --receipt [<tree>], for check
POS=()            # the words after rail brief|claim|move
HERE_SESSION=""   # --fresh | --spent, for here
HERE_WAITING=""   # --waiting, for here
HERE_NOTE=""      # --note, for here
PROCS_ARGS=()     # everything after `procs`: it reads its own arguments (--add takes a pid and a text there)
SESSION_NAME=""   # --session, for budget --journal-line
CLEAR_WHO=""      # station-N | sous, for clear
SHIP_PR=""        # a PR number, for ship
CHECK_INDEX=false # --check, for index
ADOPT=false       # --adopt, for index
ARGV=()   # set by native_argv

usage() { awk 'NR>2 { if (/^# =+$/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; exit 1; }

CMD="${1:-}"; shift || true
# rail brief|claim|move take bare words (ids, statuses, station names) the flag parser below would read as other commands's
if [[ "$CMD" == rail && "${1:-}" =~ ^(brief|claim|move)$ ]]; then POS=("$@"); set --; fi
# procs reads its own arguments: its --add takes a pid and a text, unlike inbox's and asks'
if [[ "$CMD" == procs ]]; then PROCS_ARGS=("$@"); set --; fi
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
    --force) FORCE=true; shift ;;
    --receipt) RECEIPT=true; shift
      if [[ $# -gt 0 && "$1" != -* ]]; then
        [[ "$1" =~ ^[0-9a-f]{40}$ ]] || { echo "--receipt takes a full 40-hex tree id." >&2; exit 64; }
        RECEIPT_TREE="$1"; shift
      fi ;;
    --fresh) HERE_SESSION=fresh; shift ;;
    --spent) HERE_SESSION=spent; shift ;;
    --waiting) HERE_WAITING="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
    --note) HERE_NOTE="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
    --session) SESSION_NAME="$2"; shift 2 ;;
    sous|station-*) CLEAR_WHO="$1"; shift ;;
    [0-9]*|'#'[0-9]*) SHIP_PR="${1#\#}"; shift ;;
    --check) CHECK_INDEX=true; shift ;;
    --adopt) ADOPT=true; shift ;;
    --overlap) OVERLAP=true; shift ;;
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

# exclude_locally <path> [checkout]: keep a machine-local file out of git (in the main
# checkout, or in the checkout given) through .git/info/exclude, so no tracked file (like
# .gitignore) changes.
exclude_locally() {
  local exclude repo="${2:-$ROOT}"
  git -C "$repo" check-ignore -q "$repo/$1" && return 0
  exclude="$(git -C "$repo" rev-parse --path-format=absolute --git-path info/exclude)"
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
# contains it: this repo (a `kitchen:` inside it) or an enclosing workspace repo (the
# sibling folder inside e.g. a docker/workspace checkout). Outside any repo:
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
  git -C "$ROOT" remote get-url origin >/dev/null 2>&1 \
    || { echo "No 'origin' remote: stations start from origin/$TRUNK."; exit 1; }

  # Stations start at origin/<trunk>, not this working tree. If the Brigade setup
  # isn't pushed yet, every cook would start without its config and CLAUDE.md.
  git -C "$ROOT" fetch --quiet origin "$TRUNK" 2>/dev/null || true
  if ! git -C "$ROOT" cat-file -e "origin/$TRUNK:.claude/brigade.md" 2>/dev/null; then
    cat <<EOF2

  Not yet: origin/$TRUNK has no .claude/brigade.md.

  Stations start from origin/$TRUNK (a worktree detached there), so they'd start
  without the Brigade setup (config, CLAUDE.md section, docs/ folders). Get the setup onto
  origin/$TRUNK first (push it, or merge its PR), then run this again:

    git add -A && git commit -m "chore: set up The Brigade" && git push origin $TRUNK
EOF2
    exit 1
  fi

  ignore_kitchen

  echo ""
  echo "  Creating $N worktree station(s) in $KITCHEN (detached at origin/$TRUNK)"
  mkdir -p "$KITCHEN"
  local i st f
  for i in $(seq 1 "$N"); do
    st="$KITCHEN/station-$i"
    if [[ -e "$st/.git" ]]; then
      echo "  station-$i: exists ($(where "$st")) — left alone"
      continue
    fi
    # Detached, because trunk is already checked out in the main checkout and
    # git allows one worktree per branch. The cook branches off origin/<trunk>.
    echo "  station-$i: adding worktree ..."
    git -C "$ROOT" worktree add --quiet --detach "$st" "origin/$TRUNK" \
      || { echo "  station-$i: 'git worktree add' failed — skipped"; continue; }

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
  cat <<EOF
  ⚠️  Worktrees share one repo. Stashes are shared too: a cook stashes with
      'git stash push -m "<station>: …"' and applies only its own, by name.
  ⚠️  Remove stations with 'kitchen.sh remove', never rm -rf: git keeps a
      record of every worktree and would be left with stale ones.
EOF
  [[ "${AUTO_SETUP:-}" == true ]] && return 0
  cat <<EOF

  Next: kitchen.sh open   (then /bk:sous-chef here; cooks start already running /bk:line-cook)
EOF
}

# ---------------------------------------------------------------------------
# open
# ---------------------------------------------------------------------------
cmd_open() {
  seed_sous_permissions
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
    # Trunk is checked out in the main checkout, so an idle worktree sits
    # detached at origin/<trunk> instead.
    git -C "$s" fetch --quiet origin "$TRUNK" \
      && git -C "$s" switch --quiet --detach "origin/$TRUNK" \
      && echo "  $name: synced, detached at origin/$TRUNK ($(git -C "$s" rev-parse --short HEAD))"
  done < <(stations)
  $found || echo "No stations in $KITCHEN_REL/."
}

cmd_status() {
  local s found=false
  echo ""; echo "Stations ($KITCHEN_REL/, trunk $TRUNK):"
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
# scope — the plan's files: is the ticket's write scope (Contract 4 and 8)
#
#   kitchen.sh scope [station-N]   the station's changed files (changed_files) against its plan's
#                                  files: (the plan whose ticket: is the branch's id, in the
#                                  station's docs.plans): prints inside and outside, exits 1 when
#                                  anything is outside, or when no plan names the ticket (a HYG
#                                  ticket has none and is skipped). A pattern is an exact path,
#                                  a glob (* also crosses /) or a folder ending in /.
#                                  Always inside: the plan, the ticket's journal and checklist, the
#                                  INDEX files kitchen.sh index writes, and the globs under scope:
#                                  always_inside: in the config (<id> is the ticket's key).
#   kitchen.sh scope --overlap [--ticket ID[,ID…]]   see scope_overlap below.
# ---------------------------------------------------------------------------
cfg_scope_always() {  # the globs of scope: → always_inside: in the config (inline [a, b] or a block list), one per line
  [[ -f "$CONFIG" ]] || return 0
  awk '
    function emit(g) { sub(/[ ]+#.*$/, "", g); gsub(/^[ ]*["\047]?|["\047]?[ ]*$/, "", g); if (g != "") print g }
    NR==1 && $0=="---" { inside=1; next }
    inside && $0=="---" { exit }
    inside && /^scope:/ { ing=1; next }
    ing && /^[^ ]/ { ing=0 }
    ing && blk && /^[ ]+-[ ]/ { l=$0; sub(/^[ ]+-[ ]+/, "", l); emit(l); next }
    ing && blk { exit }
    ing && /^  always_inside:/ {
      v=$0; sub(/^  always_inside:[ ]*/, "", v); sub(/[ ]+#.*$/, "", v)
      if (v == "") { blk=1; next }
      gsub(/^\[|\]$/, "", v); n=split(v, a, ",")
      for (i=1; i<=n; i++) emit(a[i])
      exit
    }' "$CONFIG"
}

scope_plan_files() {  # a plan's (or a ticket's) frontmatter on stdin → its files: entries, one per line
  awk '
    function emit(s) { sub(/[ \t]+#.*$/, "", s); gsub(/^[ \t`"\047]+|[ \t`"\047]+$/, "", s); sub(/[ \t]+\(.*\)$/, "", s)
                       if (s != "" && s !~ /^</) print s }
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    /^files:/ { v = $0; sub(/^files:[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v)
                if (v ~ /^\[/) { gsub(/^\[|\]$/, "", v); n = split(v, a, ","); for (i = 1; i <= n; i++) emit(a[i]) }
                list = 1; next }
    list && /^[ \t]*-[ \t]/ { l = $0; sub(/^[ \t]*-[ \t]+/, "", l); emit(l); next }
    list && /^[^ \t-]/ { list = 0 }'
}

scope_covers() {  # scope_covers <path> <pattern…> → 0 when a pattern covers the path
  local p="$1" pat; shift
  for pat in "$@"; do
    # shellcheck disable=SC2053  # the pattern is meant to glob
    case "$pat" in */) [[ "$p" == "$pat"* ]] && return 0 ;; *) [[ "$p" == $pat ]] && return 0 ;; esac
  done
  return 1
}

scope_record() {  # scope_record <ticket> <path> → 0 when the path is the record that travels with the PR
  local key="${1#\#}" d p="$2" base g restore=false
  [[ -n "${SCOPE_RECORD_DIRS+x}" ]] || { SCOPE_RECORD_DIRS="$(cfg_docs plans) $(cfg_docs journal) $(cfg_docs checklists)"; SCOPE_RECORD_GLOBS="$(cfg_scope_always)"; }
  shopt -q nocasematch || { shopt -s nocasematch; restore=true; }   # ids and file names compare without case
  base="${p##*/}"
  for d in $SCOPE_RECORD_DIRS; do
    d="${d%/}"; [[ -z "$d" || "$d" == none ]] && continue
    if [[ "$p" == "$d/INDEX.md" ]] || [[ "$p" == "$d/"* && "${p#"$d"/}" != */* && ( "$base" == "$key-"* || "$base" == "gh-$key-"* ) ]]; then
      $restore && shopt -u nocasematch; return 0
    fi
  done
  while IFS= read -r g; do
    [[ -n "$g" ]] || continue
    if scope_covers "$p" "${g//<id>/$key}"; then $restore && shopt -u nocasematch; return 0; fi
  done <<< "$SCOPE_RECORD_GLOBS"
  $restore && shopt -u nocasematch
  return 1
}

scope_plan_of() {  # scope_plan_of <ticket> <checkout> → the path of the plan in its docs.plans whose ticket: is the id
  local id="$1" dir="$2" f
  for f in "$dir/$(cfg_docs plans)"/*.md; do
    [[ -f "$f" && "${f##*/}" != INDEX.md ]] || continue
    [[ "$(fm_text_get ticket < "$f")" == "$id" ]] && { printf '%s\n' "$f"; return 0; }
  done
  return 1
}

cmd_scope() {
  if ${OVERLAP:-false}; then scope_overlap; return; fi
  local st="${CLEAR_WHO:-}" dir branch id plan planrel f pats=() inside=() outside=()
  if [[ -n "$st" ]]; then
    [[ "$st" == station-* && -e "$KITCHEN/$st/.git" ]] || { echo "kitchen.sh scope: no station named $st." >&2; return 2; }
    dir="$KITCHEN/$st"
  else
    st="$(rail_actor)"
    [[ -n "$st" ]] || { echo "kitchen.sh scope: name a station (scope station-N), or run it inside one." >&2; return 2; }
    dir="$HERE"
  fi
  branch="$(git -C "$dir" branch --show-current 2>/dev/null)"
  id="-"; [[ -n "$branch" ]] && id="$(branch_ticket "$branch")"
  [[ "$id" == - ]] && { echo "Scope of $st: no ticket on the branch (${branch:-detached}); nothing to check."; return 0; }
  case "$id" in HYG-*) echo "Scope of $st ($id): a hygiene ticket has no plan, so no scope to check."; return 0 ;; esac
  plan="$(scope_plan_of "$id" "$dir")" || {
    echo "Scope of $st ($id): no plan in $(cfg_docs plans) names this ticket, so the diff has no scope to be checked against."
    echo "Write the plan (ticket: $id), or say why there is none."
    return 1; }
  planrel="${plan#"$dir"/}"
  while IFS= read -r f; do [[ -n "$f" ]] && pats+=("$f"); done < <(scope_plan_files < "$plan")
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if [[ "$f" == "$planrel" ]] || scope_record "$id" "$f"; then inside+=("$f  (record)")
    elif (( ${#pats[@]} > 0 )) && scope_covers "$f" "${pats[@]}"; then inside+=("$f")
    else outside+=("$f"); fi
  done < <(changed_files "$dir")
  echo "Scope of $st ($id): plan $planrel, ${#pats[@]} entr$([[ ${#pats[@]} == 1 ]] && echo y || echo ies) in files:"
  echo "inside (${#inside[@]}):"
  for f in "${inside[@]+"${inside[@]}"}"; do echo "  $f"; done
  echo "outside (${#outside[@]}):"
  for f in "${outside[@]+"${outside[@]}"}"; do echo "  $f"; done
  if (( ${#outside[@]} > 0 )); then
    echo "${#outside[@]} path(s) outside the plan's files: add each to the plan's files: with a line of why in Decisions → How, or revert it."
    return 1
  fi
  return 0
}

# scope --overlap: two scopes that share a path do not run at once (Contract 8). The parties are
# every station on a ticket (its plan's files: and what it has changed so far, so a plan written
# but not yet built counts, stage planned, and so does a build, stage building) and the candidates
# (the --ticket ids, else every ready ticket of a markdown rail; scope = its plan on origin/<trunk>,
# else the ticket's own files:). A scope is expanded to concrete paths (an exact path as written, a
# glob or folder against the files on origin/<trunk> and the station's changes); two scopes collide
# on the paths they share. Two globs that share no existing file do not collide. Output: one block
# per collision, ticket (station, stage) × ticket, then the paths. Exit 1 on any.
scope_expand() {  # scope_expand <ticket> <patterns-file> <changes-file> <tree-file> → concrete paths, sorted, record files left out
  local id="$1" pfile="$2" chg="$3" tree="$4" pat pre p
  {
    while IFS= read -r pat; do
      [[ -n "$pat" ]] || continue
      case "$pat" in
        *'*'*|*'?'*|*'['*|*/)
          pre="${pat%%[*?[]*}"; [[ "$pat" == */ ]] && pre="$pat"
          while IFS= read -r p; do scope_covers "$p" "$pat" && ! scope_record "$id" "$p" && echo "$p"; done < <(awk -v p="$pre" 'index($0, p) == 1' "$tree") ;;
        *) scope_record "$id" "$pat" || echo "$pat" ;;
      esac
    done < "$pfile"
    cat "$chg"
  } | LC_ALL=C sort -u
}

scope_plan_at_origin() {  # scope_plan_at_origin <ticket> → the plan for it as origin/<trunk> has it, on stdout
  local id="$1" f
  while IFS= read -r f; do
    [[ "$f" == *.md && "${f##*/}" != INDEX.md ]] || continue
    [[ "$(git -C "$ROOT" show "origin/$TRUNK:$f" 2>/dev/null | fm_text_get ticket)" == "$id" ]] && { git -C "$ROOT" show "origin/$TRUNK:$f"; return 0; }
  done < <(git -C "$ROOT" ls-tree --name-only "origin/$TRUNK" "$(cfg_docs plans)/" 2>/dev/null)
  return 1
}

scope_ticket_file() {  # scope_ticket_file <ticket> → the markdown rail's file for it, or nothing
  grep -rlE "^id:[ ]*[\"']?$1[\"']?[ ]*$" "$ROOT/$(cfg_docs specs)" "$ROOT/$(cfg_docs backlog)" 2>/dev/null | head -n 1
}

scope_overlap() (
  export LC_ALL=C
  local T s branch id plan planrel f stage n=0 i j k common ids adapter tf header=false hits=0 unknown="" ids_held=" "
  local -a sc_label sc_kind
  sc_label=(); sc_kind=()
  T="$(mktemp -d "${TMPDIR:-/tmp}/brigade-scope.XXXXXX")" || return 2
  trap 'rm -rf "$T"' EXIT
  git -C "$ROOT" ls-tree -r --name-only "origin/$TRUNK" > "$T/tree" 2>/dev/null || : > "$T/tree"
  while IFS= read -r s; do
    branch="$(git -C "$s" branch --show-current 2>/dev/null)"
    id="-"; [[ -n "$branch" ]] && id="$(branch_ticket "$branch")"
    [[ "$id" == - ]] && continue
    ids_held="$ids_held$id "
    : > "$T/p"; planrel=""
    if [[ "$id" != HYG-* ]] && plan="$(scope_plan_of "$id" "$s")"; then planrel="${plan#"$s"/}"; scope_plan_files < "$plan" > "$T/p"; fi
    : > "$T/c"
    while IFS= read -r f; do
      [[ -n "$f" && "$f" != "$planrel" ]] && ! scope_record "$id" "$f" && echo "$f" >> "$T/c"
    done < <(changed_files "$s")
    [[ -s "$T/p" || -s "$T/c" ]] || continue   # a cook with no plan and no change yet holds nothing
    stage=building; [[ -s "$T/c" ]] || stage=planned
    n=$((n+1)); sc_label[n]="$id (${s##*/}, $stage)"; sc_kind[n]=station
    scope_expand "$id" "$T/p" "$T/c" "$T/tree" > "$T/$n"
  done < <(stations)
  ids="${TICKET:-}"
  if [[ -z "$ids" ]]; then
    adapter="$(cfg_rail adapter)"
    case "${adapter:-markdown}" in markdown|mixed) ids="$(cmd_rail 2>/dev/null | awk 'NR>1 && $5=="yes" { print $1 }' | paste -sd, -)" ;; esac
  fi
  for id in ${ids//,/ }; do
    [[ "$ids_held" == *" $id "* ]] && continue
    : > "$T/p"; : > "$T/c"
    if plan="$(scope_plan_at_origin "$id")"; then printf '%s\n' "$plan" | scope_plan_files > "$T/p"
    else tf="$(scope_ticket_file "$id")"; [[ -n "$tf" ]] && scope_plan_files < "$tf" > "$T/p"; fi
    [[ -s "$T/p" ]] || { unknown="$unknown $id"; continue; }
    n=$((n+1)); sc_label[n]="$id (ready)"; sc_kind[n]=candidate
    scope_expand "$id" "$T/p" "$T/c" "$T/tree" > "$T/$n"
  done
  for ((i=1; i<=n; i++)); do
    for ((j=i+1; j<=n; j++)); do
      [[ "${sc_kind[i]}" == candidate && "${sc_kind[j]}" == candidate ]] && continue
      common="$(comm -12 "$T/$i" "$T/$j")"
      [[ -n "$common" ]] || continue
      $header || { echo "Scope collisions (vs origin/$TRUNK as last fetched):"; header=true; }
      hits=$((hits+1)); k="$(printf '%s\n' "$common" | wc -l | tr -d ' ')"
      echo "  ${sc_label[i]} × ${sc_label[j]}   $k path(s)"
      printf '%s\n' "$common" | sed 's/^/      /'
    done
  done
  (( n == 0 )) && echo "Nothing in flight and no ready ticket with a scope: nothing to compare."
  (( n > 0 && hits == 0 )) && echo "No collisions among $n scope(s)."
  [[ -z "$unknown" ]] || echo "No scope known (no plan, no files:):$unknown"
  if (( hits > 0 )); then
    echo "Two scopes that collide do not run at once (Contract 8): the second waits for the first to merge, or goes to the same cook."
    exit 1
  fi
  exit 0
)

# ---------------------------------------------------------------------------
# rail — the board, computed from ticket frontmatter
# ---------------------------------------------------------------------------
# The board reads the tickets as origin/<trunk> has them: a cook's claim (kitchen.sh rail claim) is a commit
# on origin that the sous's checkout has not pulled yet, so the working tree would show that ticket still
# free. A quiet fetch, then the ticket folders exported to a temp dir. Not on a daily-pr rail (its changes
# live on a rail/ branch, in the working tree), and not without a remote or a trunk on it.
rail_origin_tree() {  # → the temp dir with docs/specs and docs/backlog as origin/<trunk> has them, or exit 1
  local tmp spec
  [[ "$(cfg_rail commit)" == daily-pr ]] && return 1
  git -C "$ROOT" fetch --quiet origin "$TRUNK" 2>/dev/null
  git -C "$ROOT" rev-parse -q --verify "origin/$TRUNK" >/dev/null 2>&1 || return 1
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/brigade-rail.XXXXXX")" || return 1
  for spec in "$(cfg_docs specs)" "$(cfg_docs backlog)"; do
    git -C "$ROOT" cat-file -e "origin/$TRUNK:$spec" 2>/dev/null && git -C "$ROOT" archive "origin/$TRUNK" "$spec" 2>/dev/null | tar -x -C "$tmp" 2>/dev/null
  done
  echo "$tmp"
}

cmd_rail() {
  local specs backlog base="${RAIL_BASE:-$ROOT}"   # RAIL_BASE: set by board, to the tickets as origin has them
  specs="$base/$(cfg_docs specs)"; backlog="$base/$(cfg_docs backlog)"
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
# rail brief | claim | move — the routine rail writes by script (Contract 3 and 6).
#
#   rail brief <ID> station-N     the sous, in the main checkout, in the turn it sends the
#                                 [brief]: records that station-N is briefed on <ID>
#                                 (.claude/briefs, out of git). Refuses a ticket somebody
#                                 else holds.
#   rail claim <ID> <todo|in-progress>   a cook, in its station: claims the ticket briefed
#                                 to it. Only a free ticket (backlog, blocked) or its own.
#   rail move <ID> <in-progress|rfr>     a cook: todo → in-progress → rfr, and rfr →
#                                 in-progress for the pass's [findings]. Its own ticket only.
#   From the main checkout: rail claim <ID> <status> station-N and rail move <ID> <status>
#   skip the brief check (the sous is the rail's writer).
# A markdown rail is written without touching the main checkout: a commit built with git
# plumbing on origin/<trunk> (read the ticket there, edit status: and cook:, push). A github
# rail goes through gh, as /bk:rail does. Every refusal names the status and whose claim it
# is, exits 1 and writes nothing; the cook then sends the sous a [rail] message instead.
# ---------------------------------------------------------------------------
cfg_rail() {  # cfg_rail <key> → rail.<key> (adapter, commit, github.owner …) from the config, "" if absent
  local blk key="$1" v=""
  [[ -f "$CONFIG" ]] || return 0
  blk="$(awk 'NR==1 && $0=="---" { inside=1; next } inside && $0=="---" { exit } inside && /^rail:/ { r=1; next } inside && r && /^[^ ]/ { r=0 } inside && r { print }' "$CONFIG")"
  case "$key" in
    github.*)
      key="${key#github.}"
      v="$(printf '%s\n' "$blk" | sed -n 's/^  github:[ ]*{\(.*\)}.*/\1/p' | tr ',' '\n' | sed -n "s/^[ ]*$key:[ ]*//p" | head -1)"
      [[ -n "$v" ]] || v="$(printf '%s\n' "$blk" | sed -n "s/^    $key:[ ]*//p" | head -1)" ;;
    *) v="$(printf '%s\n' "$blk" | sed -n "s/^  $key:[ ]*//p" | head -1)" ;;
  esac
  v="$(printf '%s' "$v" | sed 's/[ ]*#.*$//; s/[ ]*$//; s/^"//; s/"$//')"
  printf '%s' "$v"
}

rail_backend() {  # markdown | github | none (jira, or a config this can't write)
  case "$(cfg_rail adapter)" in
    ""|markdown) echo markdown ;;
    github) echo github ;;
    mixed) [[ -n "$(cfg_rail github.project)" ]] && echo github || echo none ;;
    *) echo none ;;
  esac
}

rail_id() {  # rail_id <as typed> → the canonical id: 65 and #65 are #65 on a github rail, the rest upper-case
  local v="${1#\#}"
  if [[ "$(rail_backend)" == github && "$v" =~ ^[0-9]+$ ]]; then printf '#%s' "$v"; else printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; fi
}

rail_actor() {  # the station this runs in (station-N), or "" in the main checkout
  local here_real; here_real="$(cd "$HERE" && pwd -P)"
  [[ "$here_real" == "$ROOT_REAL" ]] && return 0
  basename "$here_real"
}

rail_free() { [[ "$1" == backlog || "$1" == blocked ]]; }

rail_fail() { echo "$*" >&2; return 1; }

briefs_file() { echo "$ROOT/.claude/briefs"; }
brief_of() { awk -F'\t' -v id="$1" '$1==id { s=$2 } END { if (s != "") print s }' "$(briefs_file)" 2>/dev/null; }

# ---- the markdown adapter: read and write origin/<trunk>, never the main checkout ----
md_fetch() { git -C "$HERE" fetch --quiet origin "$TRUNK" 2>/dev/null || rail_fail "Could not fetch origin/$TRUNK."; }

md_path() {  # md_path <ID> → the ticket's path at origin/<trunk>, or nothing
  local id="$1" backlog specs n t
  backlog="$(cfg_docs backlog)"; specs="$(cfg_docs specs)"
  if [[ "$id" =~ ^S([0-9]{3})-([0-9]{2})$ ]]; then
    n="${BASH_REMATCH[1]}"; t="${BASH_REMATCH[2]}"
    git -C "$HERE" ls-tree -r --name-only "origin/$TRUNK" -- "$specs" 2>/dev/null | grep -E "^$specs/$n-[^/]*/$t-[^/]*\.md$" | head -1
  else
    git -C "$HERE" ls-tree -r --name-only "origin/$TRUNK" -- "$backlog" 2>/dev/null | grep -E "^$backlog/$id(-[^/]*)?\.md$" | head -1
  fi
}

fm_text_get() {  # fm_text_get <key> < a ticket's text → its frontmatter value
  awk -v k="$1" 'NR==1 && $0=="---" { fm=1; next } fm && $0=="---" { exit } fm && $0 ~ "^" k ":" { sub("^" k ":[ ]*", ""); sub(/[ ]+#.*$/, ""); gsub(/^"|"$/, ""); print; exit }'
}

md_edit() {  # md_edit <status> <cook or ""> < a ticket's text → the text with status: (and cook:) set
  awk -v st="$1" -v ck="$2" '
    NR==1 && $0=="---" { fm=1; print; next }
    fm && $0=="---" { if (!ds) print "status: " st; if (!dc && ck != "") print "cook: " ck; fm=0; print; next }
    fm && /^status:/ { print "status: " st; ds=1; next }
    fm && /^cook:/ { if (ck != "") print "cook: " ck; else print; dc=1; next }
    { print }'
}

md_write() {  # md_write <ID> <status> <cook> <who> <claim|move> → 0 written/no-op, 1 refused
  local id="$1" to="$2" cook="$3" who="$4" kind="$5" path text cur holder blob idx tree commit
  [[ "$(cfg_rail commit)" == daily-pr ]] && { rail_fail "This rail commits through a daily PR: send the sous [rail] $kind $id $to."; return 1; }
  for _ in 1 2; do
    md_fetch || return 1
    path="$(md_path "$id")"
    [[ -n "$path" ]] || { rail_fail "No ticket $id at origin/$TRUNK (is it merged to $TRUNK?)."; return 1; }
    text="$(git -C "$HERE" show "origin/$TRUNK:$path")"
    cur="$(printf '%s\n' "$text" | fm_text_get status)"; holder="$(printf '%s\n' "$text" | fm_text_get cook)"; [[ "$holder" == null ]] && holder=""
    rail_check "$id" "$kind" "$cur" "$to" "$who" "$holder" || { [[ $? == 2 ]] && return 0; return 1; }
    blob="$(printf '%s\n' "$text" | md_edit "$to" "$cook" | git -C "$HERE" hash-object -w --stdin)"
    idx="$(mktemp "${TMPDIR:-/tmp}/brigade-rail.XXXXXX")" || return 1; rm -f "$idx"
    if GIT_INDEX_FILE="$idx" git -C "$HERE" read-tree "origin/$TRUNK" \
       && GIT_INDEX_FILE="$idx" git -C "$HERE" update-index --cacheinfo "100644,$blob,$path" \
       && tree="$(GIT_INDEX_FILE="$idx" git -C "$HERE" write-tree)" \
       && commit="$(git -C "$HERE" commit-tree "$tree" -p "origin/$TRUNK" -m "rail: $id → $to")"; then
      rm -f "$idx"
      git -C "$HERE" push --quiet origin "$commit:refs/heads/$TRUNK" 2>/dev/null && return 0
    else rm -f "$idx"; rail_fail "Could not build the rail commit."; return 1; fi
  done
  rail_fail "Could not push the rail change for $id (trunk keeps moving, or the push is refused). Send the sous [rail] $kind $id $to."
}

# ---- the github adapter: gh project item-edit, as /bk:rail does ----
gh_col() {  # gh_col <status> → the board's column names to try, in order
  case "$1" in
    backlog) echo "Backlog" ;; todo) echo "Todo|To do" ;; in-progress) echo "In Progress|In progress" ;;
    rfr) echo "Ready for review|In review" ;; blocked) echo "Blocked" ;; done) echo "Done" ;;
  esac
}
gh_col_status() {  # gh_col_status <column name> → the status
  case "$1" in
    Backlog) echo backlog ;; Todo|"To do") echo todo ;; "In Progress"|"In progress") echo in-progress ;;
    "Ready for review"|"In review") echo rfr ;; Blocked) echo blocked ;; Done) echo "done" ;; *) echo "$1" ;;
  esac
}

gh_item() {  # gh_item <ID> → sets GH_ITEM (the project item id) and GH_COL (its Status column); 1 and a message if it can't
  local n="${1#\#}" owner proj fld low line count
  command -v gh >/dev/null 2>&1 || { rail_fail "The github rail needs the gh CLI on your PATH, logged in."; return 1; }
  owner="$(cfg_rail github.owner)"; proj="$(cfg_rail github.project)"; fld="$(cfg_rail github.status_field)"; fld="${fld:-Status}"
  [[ -n "$owner" && -n "$proj" ]] || { rail_fail "rail.github needs owner and project in .claude/brigade.md."; return 1; }
  low="$(printf '%s' "$fld" | tr '[:upper:]' '[:lower:]')"
  line="$(cd "$ROOT" && gh project item-list "$proj" --owner "$owner" --format json --limit 500 \
    --jq "(.items|length) as \$len | ([.items[]|select(.content.number==$n)]|first) as \$i | [\$len, (\$i.id // \"\"), (\$i[\"$low\"] // \"\")] | join(\"|\")" 2>&1)" \
    || { rail_fail "gh could not list project $proj: $line"; return 1; }
  IFS='|' read -r count GH_ITEM GH_COL <<<"$line"
  if [[ -z "$GH_ITEM" ]]; then
    if (( ${count:-0} >= 500 )); then rail_fail "Project $proj has 500 items or more: gh cannot list them all, so #$n may be on the rail but out of sight."
    else rail_fail "#$n is not an item of project $proj."; fi
    return 1
  fi
}

gh_write() {  # gh_write <ID> <status> <cook> <who> <kind> → 0 written/no-op, 1 refused
  local id="$1" to="$2" cook="$3" who="$4" kind="$5" n owner proj fld cur out err fid pid opt col_try login
  n="${id#\#}"; owner="$(cfg_rail github.owner)"; proj="$(cfg_rail github.project)"; fld="$(cfg_rail github.status_field)"; fld="${fld:-Status}"
  gh_item "$id" || { echo "Send the sous [rail] $kind $id $to." >&2; return 1; }
  cur="$(gh_col_status "$GH_COL")"
  rail_check "$id" "$kind" "$cur" "$to" "$who" "" || { [[ $? == 2 ]] && return 0; return 1; }
  out="$(cd "$ROOT" && gh project field-list "$proj" --owner "$owner" --format json \
    --jq ".fields[] | select(.name==\"$fld\") | (\"FIELD|\" + .id), (.options[]? | \"OPT|\" + .name + \"|\" + .id)" 2>&1)" \
    || { rail_fail "gh could not read project $proj's fields: $out. Send the sous [rail] $kind $id $to."; return 1; }
  fid="$(printf '%s\n' "$out" | sed -n 's/^FIELD|//p' | head -1)"
  [[ -n "$fid" ]] || { rail_fail "Project $proj has no field called $fld (rail.github.status_field). Send the sous [rail] $kind $id $to."; return 1; }
  opt=""
  while IFS= read -r col_try; do
    opt="$(printf '%s\n' "$out" | sed -n "s/^OPT|$col_try|//p" | head -1)"; [[ -n "$opt" ]] && break
  done < <(gh_col "$to" | tr '|' '\n')
  [[ -n "$opt" ]] || { rail_fail "Project $proj's $fld field has no column for $to (tried: $(gh_col "$to" | tr '|' ',')). Name it like one of those, or send the sous [rail] $kind $id $to."; return 1; }
  pid="$(cd "$ROOT" && gh project view "$proj" --owner "$owner" --format json --jq .id 2>&1)" || { rail_fail "gh could not read project $proj: $pid. Send the sous [rail] $kind $id $to."; return 1; }
  err="$(cd "$ROOT" && gh project item-edit --id "$GH_ITEM" --project-id "$pid" --field-id "$fid" --single-select-option-id "$opt" 2>&1 >/dev/null)" \
    || { rail_fail "gh could not set $id to $to: $err. Send the sous [rail] $kind $id $to."; return 1; }
  if [[ "$kind" == claim && -n "$cook" ]]; then
    login="$(cd "$ROOT" && gh api user --jq .login 2>/dev/null)"
    [[ -n "$login" ]] && (cd "$ROOT" && gh issue edit "$n" --add-assignee "$login" >/dev/null 2>&1)
    (cd "$ROOT" && gh issue comment "$n" --body "claimed by $cook (kitchen.sh rail claim)" >/dev/null 2>&1) || true
  fi
  return 0
}

# The legal moves (Contract 3), shared by both adapters. Returns 0 to go on, 1 refused (message
# printed), 2 nothing to write (already so).
rail_check() {  # rail_check <ID> <kind> <current> <to> <who: the station acting, "" for the sous> <holder: the ticket's cook, "" if unknown>
  local id="$1" kind="$2" cur="$3" to="$4" who="$5" holder="$6"
  if [[ "$kind" == claim ]]; then
    rail_free "$cur" && return 0
    # the claim's own station asking again, at this status or a later one (a resumed cook re-running pick-ticket): nothing to write
    if [[ "$cur" =~ ^(todo|in-progress|rfr)$ && -n "$who" && ( "$holder" == "$who" || ( -z "$holder" && "$(brief_of "$id")" == "$who" ) ) ]]; then echo "$id is already $cur."; return 2; fi
    rail_fail "Not claimed: $id is $cur, and that is ${holder:-somebody else}'s claim (Contract 3: a claim is never overwritten). Ask the sous."; return 1
  fi
  [[ -z "$holder" || -z "$who" || "$holder" == "$who" ]] || { rail_fail "Not moved: $id is $cur and belongs to $holder, not $who."; return 1; }
  if [[ "$cur" == "$to" ]]; then echo "$id is already $to."; return 2; fi
  case "$cur>$to" in
    todo\>in-progress|in-progress\>rfr|rfr\>in-progress) return 0 ;;
    *) rail_fail "Not moved: $id is $cur and a cook cannot move it to $to (cooks move todo → in-progress → rfr, and rfr → in-progress; the sous does the rest: send [rail])."; return 1 ;;
  esac
}

rail_write() {
  local op="${POS[0]:-}" raw="${POS[1]:-}" arg="${POS[2]:-}" id actor cook="" backend to
  id="$(rail_id "$raw")"; actor="$(rail_actor)"; backend="$(rail_backend)"
  [[ -n "$raw" ]] || { echo "Usage: kitchen.sh rail brief <ID> station-N | claim <ID> <todo|in-progress> | move <ID> <in-progress|rfr>" >&2; return 1; }
  [[ "$backend" != none ]] || { rail_fail "kitchen.sh rail $op writes a markdown or a github rail; this one is $(cfg_rail adapter). Send the sous [rail] instead."; return 1; }
  case "$op" in
    brief)
      [[ -z "$actor" ]] || { rail_fail "Only the sous briefs, from the main checkout ($ROOT_REAL)."; return 1; }
      [[ "$arg" =~ ^station-[0-9]+$ ]] || { rail_fail "Usage: kitchen.sh rail brief <ID> station-N"; return 1; }
      rail_brief "$id" "$arg" ;;
    claim|move)
      if [[ -n "$actor" ]]; then
        to="$arg"; cook="$actor"
        [[ "$(brief_of "$id")" == "$actor" ]] || { rail_fail "No brief for $actor on $id: the sous briefs a ticket (kitchen.sh rail brief) before a cook claims it. Send the sous [rail] $op $id $to."; return 1; }
      else
        if [[ "$op" == claim ]]; then to="$arg"; cook="${POS[3]:-}"; [[ "$cook" =~ ^station-[0-9]+$ ]] || { rail_fail "Usage: kitchen.sh rail claim <ID> <status> station-N (from the main checkout)"; return 1; }
        else to="$arg"; fi
      fi
      if [[ "$op" == claim ]]; then case "$to" in todo|in-progress) ;; *) rail_fail "A claim goes to todo or in-progress (lane C), not $to."; return 1 ;; esac
      else case "$to" in in-progress|rfr) ;; *) rail_fail "A cook moves a ticket to in-progress or rfr, not ${to:-nothing}; the sous does the rest: send [rail]."; return 1 ;; esac; fi
      if [[ "$backend" == markdown ]]; then md_write "$id" "$to" "$cook" "${actor:-$cook}" "$op" || return 1
      else gh_write "$id" "$to" "$cook" "${actor:-$cook}" "$op" || return 1; fi
      echo "$id → $to${cook:+ ($cook)}" ;;
  esac
}

rail_brief() {  # rail_brief <ID> <station-N>
  local id="$1" st="$2" cur holder text path out fresh
  if [[ "$(rail_backend)" == markdown ]]; then
    md_fetch || return 1
    path="$(md_path "$id")"; [[ -n "$path" ]] || { rail_fail "No ticket $id at origin/$TRUNK."; return 1; }
    text="$(git -C "$HERE" show "origin/$TRUNK:$path")"
    cur="$(printf '%s\n' "$text" | fm_text_get status)"; holder="$(printf '%s\n' "$text" | fm_text_get cook)"; [[ "$holder" == null ]] && holder=""
  else
    gh_item "$id" || return 1
    cur="$(gh_col_status "$GH_COL")"; holder="$(brief_of "$id")"
  fi
  if ! rail_free "$cur" && [[ "$holder" != "$st" ]]; then
    if [[ "$cur" == "done" ]]; then rail_fail "Not briefed: $id is done."; else rail_fail "Not briefed: $id is $cur, and that is ${holder:-somebody}'s claim (Contract 3). Pick another ticket."; fi
    return 1
  fi
  mkdir -p "$ROOT/.claude"; exclude_locally .claude/briefs
  fresh="$(awk -F'\t' -v id="$id" '$1!=id' "$(briefs_file)" 2>/dev/null)"
  { [[ -n "$fresh" ]] && printf '%s\n' "$fresh"; printf '%s\t%s\t%s\n' "$id" "$st" "$(date +%s)"; } > "$(briefs_file).tmp" && mv "$(briefs_file).tmp" "$(briefs_file)"
  echo "$id briefed to $st."
}

cmd_rail_dispatch() { case "${POS[0]:-}" in brief|claim|move) rail_write ;; *) cmd_rail ;; esac; }

# ---------------------------------------------------------------------------
# here — a cook's state, by script, in place of a [check-in] or [status] message
# (Contract 6). Written to <station>/.claude/here (the station's own folder, kept out of
# git); the sous reads it in `kitchen.sh board`. A free cook (no ticket, clean, fresh) still
# sends one [check-in] message: a file cannot wake an idle sous.
#   kitchen.sh here [--fresh|--spent] [--waiting "<what>"] [--note "<text>"] [--model <m>]
# ---------------------------------------------------------------------------
branch_ticket() {  # the ticket id a branch name carries (the shell twin of live/ticket-id.js), or -
  local b="$1" lb
  lb="$(printf '%s' "$b" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lb" =~ ^(s[0-9]{3}-[0-9]{2}|bklg-[0-9]{3}|hyg-[0-9]{3})($|[^0-9]) ]]; then printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]'
  elif [[ "$lb" =~ ^issue-([0-9]+)(-|$) ]]; then printf '#%s' "${BASH_REMATCH[1]}"
  elif [[ "$(cfg_rail adapter)" == jira && "$lb" =~ ^([a-z][a-z0-9]+-[0-9]+)(-|$) ]]; then printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]'
  else printf -- '-'; fi
}

cmd_here() {
  local st dir branch dirty now log
  st="$(rail_actor)"
  [[ -n "$st" ]] || { echo "kitchen.sh here is a cook's: run it in a station. The sous reads the cooks with kitchen.sh board." >&2; return 1; }
  dir="$HERE/.claude"; mkdir -p "$dir"; exclude_locally .claude/here "$HERE"; exclude_locally .claude/here.log "$HERE"
  branch="$(git -C "$HERE" branch --show-current 2>/dev/null)"; now="$(date +%s)"
  dirty=clean; [[ -n "$(git -C "$HERE" status --porcelain 2>/dev/null)" ]] && dirty=dirty
  {
    echo "at: $now"
    echo "station: $st"
    echo "branch: ${branch:-detached}"
    echo "dirty: $dirty"
    echo "ticket: $([[ -n "$branch" ]] && branch_ticket "$branch" || echo -)"
    echo "session: ${HERE_SESSION:--}"
    echo "waiting: ${HERE_WAITING:-nothing}"
    echo "model: ${MODELS[0]:--}"
  } > "$dir/here.tmp" && mv "$dir/here.tmp" "$dir/here"
  if [[ -n "$HERE_NOTE" ]]; then
    log="$dir/here.log"; printf '%s %s\n' "$now" "$HERE_NOTE" >> "$log"
    tail -n 20 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
  fi
  cat "$dir/here"
}

cmd_here_board_lines() {  # one line per station from its here file, then its last note
  local s name f now at age line found=false
  now="$(date +%s)"
  while IFS= read -r s; do
    found=true; name="$(basename "$s")"; f="$s/.claude/here"
    if [[ ! -f "$f" ]]; then printf '  %-11s no check-in yet\n' "$name"; continue; fi
    at="$(sed -n 's/^at: //p' "$f" | head -1)"; age=$(( (now - ${at:-$now}) / 60 ))
    printf '  %-11s %3sm ago  %s · %s · %s · %s · waiting: %s · %s\n' "$name" "$age" \
      "$(sed -n 's/^branch: //p' "$f")" "$(sed -n 's/^dirty: //p' "$f")" "$(sed -n 's/^ticket: //p' "$f")" \
      "$(sed -n 's/^session: //p' "$f")" "$(sed -n 's/^waiting: //p' "$f")" "$(sed -n 's/^model: //p' "$f")"
    line="$(tail -n 1 "$s/.claude/here.log" 2>/dev/null | sed 's/^[0-9]* //')"
    [[ -n "$line" ]] && printf '  %-11s note: %s\n' "" "$line"
  done < <(stations)
  $found || echo "  (no stations)"
}

# ---------------------------------------------------------------------------
# board — everything the sous reads, in one snapshot. Run from the main checkout
# it is also written to .claude/board.md, for a human to keep open. The file is
# generated, never edited, and never committed: it goes in .git/info/exclude so
# no tracked file changes.
# ---------------------------------------------------------------------------
cmd_board() {
  local here_real text rt=""
  rt="$(rail_origin_tree)" && export RAIL_BASE="$rt"
  text="$(echo "# The board: $REPO_NAME"
    echo ""
    echo "Generated $(date '+%Y-%m-%d %H:%M') by \`kitchen.sh board\`. Rewritten each time; don't edit it."
    echo ""; echo '```'
    cmd_status; cmd_files
    echo ""; echo "The cooks (kitchen.sh here):"; cmd_here_board_lines
    echo ""; echo "The rail:"; cmd_rail
    echo ""; echo "Open questions:"; cmd_questions
    echo ""; echo "Decisions to file: $(cmd_decisions | grep -c ' DUE ' || true) · Inbox: $(inbox_count) unfiled · Asks open: $(asks_count open) · Gaps to fix: $(cmd_gaps | grep -c '^  ' || true)"
    echo "Processes: $(procs_summary)"
    context_warning
    echo '```')"
  [[ -n "$rt" ]] && { rm -rf "$rt"; unset RAIL_BASE; }
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
  lessons_file="$REC/$(cfg_docs lessons docs/lessons.md)"
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
    if [[ "$qdir" != none && -d "$REC/$qdir" ]]; then
      for f in "$REC/$qdir"/*.md; do
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
    [[ -e "$REC/$path" ]] && echo "$REC/$path"
  done < <(docs_keys)
  [[ -f "$ROOT/CLAUDE.md" ]] && echo "$ROOT/CLAUDE.md"
}

# rail_commit → rail.commit from the config (direct | daily-pr), else direct.
rail_commit() {
  local v=""
  [[ -f "$CONFIG" ]] && v=$(awk '
    NR==1 && $0=="---" { inside=1; next }
    inside && $0=="---" { exit }
    inside && /^rail:/ { inrail=1; next }
    inrail && /^[^ ]/ { inrail=0 }
    inrail && /^  commit:/ { sub(/^  commit:[ ]*/, ""); sub(/[ ]+#.*$/, ""); print; exit }' "$CONFIG")
  printf '%s' "${v:-direct}"
}
# record_paths → the record's own paths, relative to the repo, as the config maps them: every docs
# key but the rail's and the cooks' (journal, plans, checklists, backlog, specs, research,
# brainstorm), the lessons register included. Whether they exist is the caller's question.
record_paths() {
  local key path seen=" "
  while IFS= read -r key; do
    case "$key" in journal|plans|checklists|backlog|specs|research|brainstorm) continue ;; esac
    path="$(docs_path "$key")"; path="${path%/}"
    [[ "$path" == none || -z "$path" ]] && continue
    [[ "$seen" == *" $path "* ]] && continue; seen="$seen$path "
    echo "$path"
  done < <(docs_keys)
}

# record_branches → the record branches not yet on trunk, oldest first: local and remote-tracking
# refs under record/, minus any already an ancestor of origin/<trunk>. As of the last fetch; no
# network, no gh. A record PR closed unmerged counts until its branch is deleted.
record_branches() {
  local ref
  git -C "$ROOT" rev-parse -q --verify "origin/$TRUNK" >/dev/null 2>&1 || return 0
  git -C "$ROOT" for-each-ref --sort=committerdate --format='%(refname)' refs/heads/record refs/remotes/origin/record |
    while IFS= read -r ref; do
      git -C "$ROOT" merge-base --is-ancestor "$ref" "origin/$TRUNK" 2>/dev/null || echo "$ref"
    done
}
# record_view → where the record is read from. With no record branch open: $ROOT itself. Else a
# temp dir holding this checkout's record paths with every unmerged record branch laid over
# them (a file takes the newest branch's version; the lessons register, which is only ever read
# as "which keys are listed", is the union of all of them). The dispatcher removes it on exit.
record_view() {
  local view ref p reg files=() branches=() paths=()
  while IFS= read -r ref; do branches+=("$ref"); done < <(record_branches)
  (( ${#branches[@]} )) || { printf '%s' "$ROOT"; return 0; }
  view="$(mktemp -d "${TMPDIR:-/tmp}/brigade-record.XXXXXX")"
  reg="$(cfg_docs lessons docs/lessons.md)"
  # what the view carries is what record_dirs searches: the record's paths and the specs
  while IFS= read -r p; do paths+=("$p"); done < <(record_paths; echo "$(docs_path specs)")
  for p in "${paths[@]}"; do
    [[ -z "$p" || "$p" == none ]] && continue
    [[ -e "$ROOT/$p" ]] && { mkdir -p "$view/$(dirname "$p")"; cp -R "$ROOT/$p" "$view/$p"; }
  done
  if [[ -f "$ROOT/$reg" ]]; then cp "$ROOT/$reg" "$view/.register"; else : > "$view/.register"; fi
  for ref in "${branches[@]}"; do
    files=()
    while IFS= read -r p; do files+=("$p"); done < <(git -C "$ROOT" ls-tree -r --name-only "$ref" -- "${paths[@]}")
    if (( ${#files[@]} )); then
      if ! git -C "$ROOT" archive -o "$view/.record.tar" "$ref" -- "${files[@]}" || ! tar -x -C "$view" -f "$view/.record.tar"; then
        echo "kitchen.sh: could not read the record branch ${ref#refs/}; its files are left out." >&2
      fi
      rm -f "$view/.record.tar"
    fi
    git -C "$ROOT" show "$ref:$reg" >> "$view/.register" 2>/dev/null || true
  done
  mkdir -p "$view/$(dirname "$reg")"; mv "$view/.register" "$view/$reg"
  printf '%s' "$view"
}

cmd_decisions() {
  local register f files=() dirs=() d hits id n key status where any=false
  register="$REC/$(cfg_docs lessons docs/lessons.md)"
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
          status=filed; where="${hits#"$REC"/}"; where="${where#"$ROOT"/}"
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
    if [[ "$qdir" != none && -d "$REC/$qdir" ]]; then
      for f in "$REC/$qdir"/*.md; do
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
# record-pr — file the record (Contract 12) when trunk may not take a direct push. The sous's
# handoff writes decisions, question files and the register into the main checkout's working
# tree; this commits exactly those files on a branch, tries trunk first when rail.commit is
# direct (a refusal, protected trunk or otherwise, is the signal: no probe), else pushes the
# branch and opens the PR, and leaves the checkout on a clean trunk. lessons, decisions,
# questions, gaps and debrief read an unmerged record/* branch like trunk (record_view).
# ---------------------------------------------------------------------------
cmd_record_pr() {
  local paths=() files=() p f branch day n=1 msg url has_origin=false why="rail.commit is daily-pr"
  if [[ "$(cd "$HERE" && pwd -P)" != "$ROOT_REAL" ]]; then
    echo "Only the sous files the record, from the main checkout ($ROOT_REAL)." >&2; return 1
  fi
  while IFS= read -r p; do paths+=("$p"); done < <(record_paths)
  while IFS= read -r f; do [[ -n "$f" ]] && files+=("$f"); done < <(git -C "$ROOT" status --porcelain -uall -- "${paths[@]}" | sed 's/^...//')
  (( ${#files[@]} )) || { echo "Nothing to file: the record paths are clean."; return 0; }
  if [[ "$(git -C "$ROOT" branch --show-current)" != "$TRUNK" ]]; then
    echo "The main checkout is not on $TRUNK: switch to it first." >&2; return 1
  fi
  git -C "$ROOT" remote get-url origin >/dev/null 2>&1 && has_origin=true
  if $has_origin; then
    git -C "$ROOT" fetch origin "$TRUNK" --quiet 2>/dev/null || true
    git -C "$ROOT" merge --ff-only "origin/$TRUNK" >/dev/null 2>&1 \
      || { echo "Could not fast-forward $TRUNK to origin/$TRUNK with the record files dirty: bring it up to date by hand." >&2; return 1; }
  fi
  day="$(date +%Y-%m-%d)"; branch="record/$day"
  while git -C "$ROOT" show-ref -q --verify "refs/heads/$branch" || git -C "$ROOT" show-ref -q --verify "refs/remotes/origin/$branch"; do
    n=$((n+1)); branch="record/$day-$n"
  done
  msg="docs(record): the sous's record, $day (${#files[@]} file(s))"
  git -C "$ROOT" switch -q -c "$branch" || { echo "Could not create $branch." >&2; return 1; }
  if ! git -C "$ROOT" add -- "${files[@]}" || ! git -C "$ROOT" commit -q -m "$msg"; then
    git -C "$ROOT" reset -q 2>/dev/null   # unstage; the files stay as they were
    git -C "$ROOT" switch -q "$TRUNK" && git -C "$ROOT" branch -q -D "$branch"
    echo "Could not commit the record (a hook? no git identity?): its files are still in the working tree." >&2; return 1
  fi
  if [[ "$(rail_commit)" == direct ]]; then why="$TRUNK refused a direct push"; fi
  if ! $has_origin || { [[ "$(rail_commit)" == direct ]] && git -C "$ROOT" push -q origin "HEAD:refs/heads/$TRUNK" 2>/dev/null; }; then
    if git -C "$ROOT" switch -q "$TRUNK" && git -C "$ROOT" merge -q --ff-only "$branch" && git -C "$ROOT" branch -q -d "$branch"; then
      echo "Filed on $TRUNK: $msg"; return 0
    fi
    echo "Pushed to $TRUNK, but this checkout could not fast-forward to $branch: run git merge --ff-only $branch on $TRUNK." >&2; return 1
  fi
  if ! git -C "$ROOT" push -q -u origin "$branch" 2>/dev/null; then
    git -C "$ROOT" switch -q "$TRUNK"
    echo "Could not push $branch; the record commit is on it locally." >&2; return 1
  fi
  git -C "$ROOT" switch -q "$TRUNK"
  if url="$(cd "$ROOT" && gh pr create --base "$TRUNK" --head "$branch" --title "$msg" \
      --body "The sous's record (Contract 12), filed on a branch because $why. Files: ${files[*]}" 2>/dev/null)"; then
    echo "Record PR: $(printf '%s\n' "$url" | tail -1)"; return 0
  fi
  echo "Pushed $branch, but the PR was not opened. Open it by hand: gh pr create --base $TRUNK --head $branch" >&2
  return 1
}

# ---------------------------------------------------------------------------
# index — the INDEX.md of plans, journals and checklists, generated from the files'
# frontmatter (Contract 12), so two branches that each add a file merge to the same
# table. A folder's INDEX that lacks the marker below is hand-written and is left alone
# until --adopt. It runs on the checkout it is run from (a station's own files), with the
# docs paths from the config at the main checkout. bash 3.2 safe: no mapfile, no
# associative arrays.
# ---------------------------------------------------------------------------
INDEX_MARK='Generated by kitchen.sh index'
INDEX_TYPES="plans:Plans journal:Journals checklists:Checklists"

fm_get() {  # fm_get <file> <key> → the frontmatter value, unquoted ("" if absent)
  awk -v k="$2" '
    NR==1 { if ($0 != "---") exit; fm=1; next }
    fm && $0=="---" { exit }
    fm && index($0, k ":")==1 { v=substr($0, length(k)+2); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v=substr(v, 2, length(v)-2); print v; exit }' "$1"
}
first_heading() {  # the first "# " line outside the frontmatter
  awk 'NR==1 && $0=="---" { fm=1; next } fm && $0=="---" { fm=0; next } !fm && /^# / { sub(/^# +/, ""); print; exit }' "$1"
}
index_summary() {  # index_summary <checkout> <file>
  local t p
  t="$(fm_get "$2" title)"
  if [[ -z "$t" ]]; then
    p="$(fm_get "$2" plan)"
    [[ -n "$p" && -f "$1/$p" ]] && t="$(fm_get "$1/$p" title)"
  fi
  [[ -n "$t" ]] || t="$(first_heading "$2")"
  [[ -n "$t" ]] || t="$(basename "$2")"
  printf '%s' "${t//|/\\|}"
}
index_render() {  # index_render <checkout> <folder> <heading> → the whole INDEX.md on stdout
  local base="$1" dir="$2" rel tk
  local note="<!-- $INDEX_MARK from the files' frontmatter (Contract 12). Do not edit by hand: run \`kitchen.sh index\`. -->"
  printf '# %s\n\n%s\n\n' "$3" "$note"
  printf '| File | Summary | Ticket |\n|---|---|---|\n'
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    tk="$(fm_get "$base/$dir/$rel" ticket)"; [[ -n "$tk" ]] || tk="—"
    printf '| [%s](%s) | %s | %s |\n' "$rel" "$rel" "$(index_summary "$base" "$base/$dir/$rel")" "$tk"
  done < <(cd "$base/$dir" && find . -type f -name '*.md' ! -name INDEX.md | sed 's#^\./##' | LC_ALL=C sort)
}
index_state() {  # index_state <checkout> <folder> <heading> → missing | hand | fresh | stale
  local dest="$1/$2/INDEX.md"
  [[ -f "$dest" ]] || { echo missing; return 0; }
  grep -qF "$INDEX_MARK" "$dest" || { echo hand; return 0; }
  if [[ "$(index_render "$1" "$2" "$3")" == "$(cat "$dest")" ]]; then echo fresh; else echo stale; fi
}
cmd_index() {
  local base="$HERE" pair key heading path state stale=0 n old gone
  for pair in $INDEX_TYPES; do
    key="${pair%%:*}"; heading="${pair#*:}"
    path="$(docs_path "$key")"; path="${path%/}"
    [[ -z "$path" || "$path" == none || "$path" == *.md || ! -d "$base/$path" ]] && continue
    state="$(index_state "$base" "$path" "$heading")"
    if [[ "$state" == hand ]] && ! $ADOPT; then
      echo "  $path/INDEX.md: hand-written, left alone (kitchen.sh index --adopt makes it generated)"; continue
    fi
    if $CHECK_INDEX; then
      case "$state" in
        fresh|hand) echo "  $path/INDEX.md: up to date" ;;
        *) echo "  $path/INDEX.md: out of date"; stale=$((stale+1)) ;;
      esac
      continue
    fi
    if [[ "$state" == fresh ]]; then echo "  $path/INDEX.md: up to date"; continue; fi
    if [[ "$state" == hand ]]; then   # --adopt: say which old rows name a file that isn't there
      old="$base/$path/INDEX.md"
      while IFS= read -r gone; do
        [[ -n "$gone" && ! -f "$base/$path/$gone" ]] && echo "  $path/INDEX.md: dropped row for $gone (no such file)"
      done < <(grep -oE '\]\([^)]+\)' "$old" | sed 's/^](//; s/)$//' | sort -u)
    fi
    index_render "$base" "$path" "$heading" > "$base/$path/INDEX.md"
    n=$(grep -c '^| \[' "$base/$path/INDEX.md" || true)
    echo "  $path/INDEX.md: regenerated ($n row(s))"
  done
  (( stale == 0 )) || { echo "$stale INDEX file(s) out of date: run kitchen.sh index."; return 1; }
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
  local pair ikey ipath
  for pair in $INDEX_TYPES; do
    ikey="${pair%%:*}"; ipath="$(docs_path "$ikey")"; ipath="${ipath%/}"
    [[ -z "$ipath" || "$ipath" == none || "$ipath" == *.md || ! -d "$ROOT/$ipath" ]] && continue
    [[ "$(index_state "$ROOT" "$ipath" "${pair#*:}")" == stale ]] && warn "docs.$ikey: $ipath/INDEX.md is out of date (run kitchen.sh index)"
  done
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
# clear — the sous clears a session (Contract 5). Clearing is deterministic, so it needs
# no human judgement: `clear <station-N|sous>` refuses unless the session is idle (the
# registry's word, <config>/sessions/<pid>.json), its handoff is newer than its last turn
# (a cook: the newest journal in the station with a "## Handoff" section; the sous:
# .claude/sous-handoff.md) and nothing it sent still waits for an answer (a cook: a
# [gate], [plan], [handoff] or [walk-in] with no reply since; the sous: an open ask).
# Then it types /clear into the session's tmux pane (the pane the registry names, the
# way bk stop types /bk:handoff), waits for the session to say idle, and for a cook types
# /bk:line-cook so it checks in fresh. Nothing is ever typed into a busy pane. The
# transcript is read by window/server/live/session-state.js, so this needs node.
# ---------------------------------------------------------------------------
json_str() { sed -n "s/.*\"$2\":\"\\([^\"]*\\)\".*/\\1/p" "$1" | head -1; }      # a string field of a flat JSON file
json_num() { sed -n "s/.*\"$2\":\\([0-9][0-9]*\\).*/\\1/p" "$1" | head -1; }     # a number field
mtime_ms() { local s; s="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)"; printf '%s000' "${s:-0}"; }   # GNU first: BSD stat -c fails, GNU stat -f %m is the mount point
# registry_of <checkout> [name] → the registry file of the live session running there: the one
# named <name> when given, else the most recently active. Nothing when none is running.
registry_of() {
  local real dir f cwd pid t best="" best_t=0
  real="$(cd "$1" && pwd -P)"; dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions"
  for f in "$dir"/*.json; do
    [[ -f "$f" ]] || continue
    cwd="$(json_str "$f" cwd)"; [[ -n "$cwd" && -d "$cwd" ]] || continue
    [[ "$(cd "$cwd" && pwd -P)" == "$real" ]] || continue
    pid="$(json_num "$f" pid)"; [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null || continue
    if [[ -n "${2:-}" ]]; then [[ "$(json_str "$f" name)" == "$2" ]] && { echo "$f"; return 0; }; continue; fi
    t="$(json_num "$f" updatedAt)"; t="${t:-0}"
    (( t >= best_t )) && { best="$f"; best_t=$t; }
  done
  [[ -n "$best" ]] && echo "$best"
  return 0
}
transcript_of() {  # transcript_of <registry file> → that session's transcript (as typed or resolved), or exit 1
  local cwd sid base d slug
  cwd="$(json_str "$1" cwd)"; sid="$(json_str "$1" sessionId)"; base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
  [[ -n "$cwd" && -n "$sid" ]] || return 1
  for d in "$cwd" "$(cd "$cwd" 2>/dev/null && pwd -P)"; do
    slug="$(printf '%s' "$d" | sed 's/[^A-Za-z0-9]/-/g')"
    [[ -f "$base/$slug/$sid.jsonl" ]] && { echo "$base/$slug/$sid.jsonl"; return 0; }
  done
  return 1
}
session_state() {  # session_state <transcript> → key=value lines from session-state.js, or exit 1
  local dir; dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../window" 2>/dev/null && pwd -P)"
  [[ -f "$dir/server/live/session-state.js" ]] || return 1
  command -v node >/dev/null 2>&1 || return 1
  node "$dir/server/live/session-state.js" "$1"
}
state_field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }
newest_handoff() {  # newest_handoff <station> → the station journal with a "## Handoff" section modified last
  local f best="" best_t=0 t
  for f in "$1/$(cfg_docs journal docs/journal)"/*.md; do
    [[ -f "$f" ]] && grep -q '^## Handoff' "$f" || continue
    t="$(mtime_ms "$f")"; (( t >= best_t )) && { best="$f"; best_t=$t; }
  done
  [[ -n "$best" ]] && echo "$best"
  return 0
}
# context_warning: one line for the board when the sous's own session carries too much
# (its last ten turns over the budget's context line). Silent without node or a sous.
context_warning() {
  local reg tr state read over line
  reg="$(registry_of "$ROOT" "$(head -1 "$ROOT/.claude/sous" 2>/dev/null)")"; [[ -n "$reg" ]] || return 0
  tr="$(transcript_of "$reg")" || return 0
  state="$(session_state "$tr" 2>/dev/null)" || return 0
  read="$(state_field "$state" lastRead)"; over="$(state_field "$state" over)"; line="$(state_field "$state" line)"
  [[ -n "$read" && -n "$line" ]] || return 0
  (( read > line )) || return 0
  echo ""
  echo "Context: the sous is at $(( read / 1000 ))k cache-read tokens a turn over its last 10 turns ($over turns over the $(( line / 1000 ))k line): run /bk:handoff, then kitchen.sh clear sous (Contract 5)."
}
cmd_clear() {
  local who="$CLEAR_WHO" dir reg name pane handoff tr state open last_turn hmtime n i defer
  case "$who" in
    sous) dir="$ROOT" ;;
    station-*) dir="$KITCHEN/$who"; [[ -e "$dir/.git" ]] || { echo "No such station: $who" >&2; return 1; } ;;
    *) echo "Usage: kitchen.sh clear <station-N|sous>" >&2; return 1 ;;
  esac
  command -v node >/dev/null 2>&1 || { echo "clear needs node 20 or newer on your PATH: it reads the session's transcript." >&2; return 1; }
  if [[ "$who" == sous ]]; then reg="$(registry_of "$dir" "$(head -1 "$ROOT/.claude/sous" 2>/dev/null)")"; else reg="$(registry_of "$dir")"; fi
  [[ -n "$reg" ]] || { echo "Not cleared: no live session in $who (none registered under ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions with that cwd)." >&2; return 1; }
  name="$(json_str "$reg" name)"; pane="$(json_str "$reg" tmux)"
  [[ -n "$pane" ]] || { echo "Not cleared: $who ($name) isn't in a tmux pane; clear it by hand." >&2; return 1; }
  # 1. idle: never type into a pane mid-turn. The sous clearing itself is the one case where
  # the caller is the busy session (its own tool call is the turn): the typing is deferred
  # to a waiter that fires when the registry says idle. A busy cook is refused.
  defer=false
  if [[ "$(json_str "$reg" status)" != idle ]]; then
    if [[ "$who" == sous ]]; then defer=true
    else echo "Not cleared: $who ($name) is busy. Wait for its turn to end." >&2; return 1; fi
  fi
  # 2. a handoff newer than its last turn
  tr="$(transcript_of "$reg")" || { echo "Not cleared: no transcript found for $who ($name)." >&2; return 1; }
  state="$(session_state "$tr")" || { echo "Not cleared: couldn't read $tr." >&2; return 1; }
  last_turn="$(state_field "$state" lastTurnStart)"; last_turn="${last_turn:-0}"
  if [[ "$who" == sous ]]; then handoff="$ROOT/.claude/sous-handoff.md"; else handoff="$(newest_handoff "$dir")"; fi
  [[ -n "$handoff" && -f "$handoff" ]] || { echo "Not cleared: $who ($name) has no handoff on disk. Ask it for /bk:handoff first." >&2; return 1; }
  hmtime="$(mtime_ms "$handoff")"
  (( hmtime >= last_turn )) || { echo "Not cleared: $who's handoff ($handoff) is older than its last turn. Ask it for /bk:handoff first." >&2; return 1; }
  # 3. nothing open
  if [[ "$who" == sous ]]; then
    n="$(asks_count open)"; (( n == 0 )) || { echo "Not cleared: the sous has $n open ask(s) to the head chef (kitchen.sh asks). Answer them first." >&2; return 1; }
  else
    open="$(state_field "$state" open)"
    [[ -z "$open" || "$open" == none ]] || { echo "Not cleared: $who ($name) is waiting on an answer to its [$open]. Answer it, or let it finish." >&2; return 1; }
  fi
  # act: /clear, wait for the session to say idle, then the role skill (/bk:line-cook for a
  # cook, /bk:sous-chef for the sous) so the pane is a cook or a sous again, not a solo session
  local role="/bk:line-cook"; [[ "$who" == sous ]] && role="/bk:sous-chef"
  if $defer; then
    # the sous asked to clear itself mid-turn: a detached waiter types once the turn has ended
    nohup bash -c '
      reg=$1; pane=$2; role=$3; i=0
      st() { sed -n "s/.*\"status\":\"\([^\"]*\)\".*/\1/p" "$reg" | head -1; }
      while [ "$i" -lt 180 ] && [ "$(st)" != idle ]; do sleep 1; i=$((i+1)); done
      [ "$(st)" = idle ] || exit 0
      sleep 1; tmux send-keys -t "$pane" -l "/clear" && tmux send-keys -t "$pane" Enter || exit 0
      sleep 3; tmux send-keys -t "$pane" -l "$role" && tmux send-keys -t "$pane" Enter
    ' _ "$reg" "$pane" "$role" >/dev/null 2>&1 &
    echo "Clearing the sous ($name) when this turn ends: /clear, then $role, will be typed into $pane (it waits up to three minutes for the turn to end). End your turn now; the fresh sous reads .claude/sous-handoff.md first."
    return 0
  fi
  { tmux send-keys -t "$pane" -l "/clear" && tmux send-keys -t "$pane" Enter; } || { echo "Not cleared: tmux refused pane $pane." >&2; return 1; }
  sleep 2
  for i in 1 2 3 4 5 6 7 8 9 10; do [[ "$(json_str "$reg" status)" == idle ]] && break; sleep 1; done
  { tmux send-keys -t "$pane" -l "$role" && tmux send-keys -t "$pane" Enter; } || { echo "Cleared $who ($name), but tmux refused $role; type it there." >&2; return 1; }
  if [[ "$who" == sous ]]; then echo "Cleared the sous ($name): /clear, then /bk:sous-chef typed into $pane. It reads .claude/sous-handoff.md first."
  else echo "Cleared $who ($name): /clear, then /bk:line-cook typed into $pane. It checks in fresh."; fi
}

# ---------------------------------------------------------------------------
# ship — the sous merges a PR (Contract 5). Once a PR has passed the pass, is green on CI,
# mergeable and up to date with trunk, merging it is no decision, so `gates.merge:
# sous-chef` (the default) makes it the sous's: `ship <PR>` checks every one of those through
# gh and refuses, naming the condition, when one fails (a check still running says so); when
# they all hold it runs `gh pr merge --merge` (gates.merge_method: merge | squash | rebase)
# and says which stations are now behind trunk. With `gates.merge: head-chef` it refuses:
# the merge stays the head chef's in that kitchen. Whether the pass happened is the sous's
# word, not checked here: the sous runs this only after its LGTM.
# ---------------------------------------------------------------------------
cmd_ship() {
  local n="$SHIP_PR" gate method line state draft base head mergeable mstate checks s pending=0 failed=0 ok=0
  [[ -n "$n" ]] || { echo "Usage: kitchen.sh ship <PR number>" >&2; return 1; }
  gate="$(cfg_gate merge sous-chef)"
  [[ "$gate" == sous-chef ]] || { echo "Not merged: gates.merge is $gate in .claude/brigade.md, so merging #$n is the head chef's." >&2; return 1; }
  command -v gh >/dev/null 2>&1 || { echo "ship needs the gh CLI on your PATH, logged in." >&2; return 1; }
  line="$(cd "$ROOT" && gh pr view "$n" --json state,isDraft,baseRefName,headRefName,mergeable,mergeStateStatus,statusCheckRollup \
    --jq '[.state, (.isDraft|tostring), .baseRefName, .headRefName, .mergeable, .mergeStateStatus, ([.statusCheckRollup[]? | (.conclusion // .status // "PENDING")] | join(","))] | join("|")' 2>/dev/null)" \
    || { echo "Not merged: gh could not read PR #$n (does it exist, and are you logged in?)." >&2; return 1; }
  IFS='|' read -r state draft base head mergeable mstate checks <<<"$line"
  [[ "$state" == OPEN ]] || { echo "Not merged: #$n is $state, not open." >&2; return 1; }
  [[ "$draft" == false ]] || { echo "Not merged: #$n is a draft." >&2; return 1; }
  [[ "$base" == "$TRUNK" ]] || { echo "Not merged: #$n targets $base, not $TRUNK." >&2; return 1; }
  for s in ${checks//,/ }; do
    case "$s" in SUCCESS|NEUTRAL|SKIPPED) ok=$((ok+1)) ;; FAILURE|CANCELLED|TIMED_OUT|ACTION_REQUIRED|STARTUP_FAILURE|STALE) failed=$((failed+1)) ;; *) pending=$((pending+1)) ;; esac
  done
  (( failed == 0 )) || { echo "Not merged: #$n has $failed red check(s) ($checks). Send the cook [findings]." >&2; return 1; }
  (( pending == 0 )) || { echo "Not merged: #$n has $pending check(s) still running. Wait: gh pr checks $n --watch" >&2; return 1; }
  [[ "$mergeable" == MERGEABLE ]] || { echo "Not merged: #$n is $mergeable (a conflict with $TRUNK, or GitHub is still computing: try again in a minute). The cook brings $TRUNK in." >&2; return 1; }
  case "$mstate" in
    CLEAN|HAS_HOOKS|UNSTABLE) ;;
    BEHIND) echo "Not merged: #$n ($head) is behind $TRUNK. The cook brings $TRUNK in and pushes." >&2; return 1 ;;
    BLOCKED) echo "Not merged: #$n is blocked (a required review, a protection rule, or a check GitHub still waits on: gh pr view $n). Not the sous's to override." >&2; return 1 ;;
    *) echo "Not merged: #$n merge state is $mstate." >&2; return 1 ;;
  esac
  method="$(cfg_gate merge_method merge)"
  case "$method" in merge|squash|rebase) ;; *) echo "Not merged: gates.merge_method is $method; use merge, squash or rebase." >&2; return 1 ;; esac
  (cd "$ROOT" && gh pr merge "$n" "--$method") || { echo "Not merged: gh pr merge #$n failed (see above)." >&2; return 1; }
  echo "Merged #$n ($head) into $TRUNK by $method (gates.merge: sous-chef). $TRUNK moved: stations on a branch bring it in before their PR; kitchen.sh status shows who is behind. Next: kitchen.sh done <station> for the cook's station."
}

# ---------------------------------------------------------------------------
# done — a served ticket's station goes back to trunk (#85). A station's work is ephemeral:
# once its PR is merged the ticket branch is deleted (here and on origin) and the station is
# detached at origin/<trunk>; the worktree folder stays, because the cook's session lives in it.
# The merge is proven through gh, never assumed: the branch's PR must be MERGED, and the
# station's tip must be that PR's head, so a commit made after the PR was opened is never lost
# (a squash or rebase merge passes: the tip is the PR's head, not a commit on trunk). Refuses a
# dirty station and a busy session. The one summary line says what was and wasn't deleted, so a
# refused `git push origin --delete` shows (and the exact command is printed). Never force-pushes;
# the local branch is deleted with -D, which a squash merge needs, only at the merged PR's head, and
# the origin branch only when it still is at that head. The PR must be merged into trunk.
# ---------------------------------------------------------------------------
cmd_done() {
  local who="$CLEAR_WHO" dir branch rows pr="" pretip="" other="" n st tip base reg f lstate rstate rsha rc=0
  [[ "$who" == station-* ]] || { echo "Usage: kitchen.sh done <station-N>" >&2; return 1; }
  dir="$KITCHEN/$who"; [[ -e "$dir/.git" ]] || { echo "No such station: $who" >&2; return 1; }
  command -v gh >/dev/null 2>&1 || { echo "done needs the gh CLI on your PATH, logged in." >&2; return 1; }
  branch="$(git -C "$dir" branch --show-current)"
  [[ -n "$branch" ]] || { echo "$who is already detached ($(git -C "$dir" rev-parse --short HEAD)): nothing to do."; return 0; }
  [[ "$branch" != "$TRUNK" ]] || { echo "Not done: $who is on $TRUNK itself, not a ticket branch." >&2; return 1; }
  [[ -z "$(git -C "$dir" status --porcelain)" ]] || { echo "Not done: $who has uncommitted work on $branch." >&2; return 1; }
  reg="$(registry_of "$dir")"
  if [[ -n "$reg" && "$(json_str "$reg" status)" != idle ]]; then
    echo "Not done: $who ($(json_str "$reg" name)) is busy. Wait for its turn to end." >&2; return 1
  fi
  rows="$(cd "$ROOT" && gh pr list --head "$branch" --state all --json number,state,headRefOid,baseRefName \
    --jq '.[] | "\(.number) \(.state) \(.headRefOid) \(.baseRefName)"' 2>/dev/null)" \
    || { echo "Not done: gh could not list the PRs of $branch." >&2; return 1; }
  while read -r n st tip base; do
    [[ "$st" == MERGED ]] || continue
    if [[ "$base" == "$TRUNK" ]]; then pr="$n"; pretip="$tip"; break; else other="#$n into $base"; fi
  done <<<"$rows"
  if [[ -z "$pr" && -n "$other" ]]; then
    echo "Not done: $branch's merged PR went into another branch ($other), not $TRUNK: its work has not reached $TRUNK." >&2; return 1
  fi
  [[ -n "$pr" ]] || { echo "Not done: $branch has no merged PR (${rows:-no PR found}). Only a merged ticket's branch is deleted." >&2; return 1; }
  [[ "$(git -C "$dir" rev-parse HEAD)" == "$pretip" ]] \
    || { echo "Not done: $branch is at $(git -C "$dir" rev-parse --short HEAD) but merged PR #$pr ended at ${pretip:0:7}: the station has commits the PR does not. Push or park them first." >&2; return 1; }
  if ! git -C "$dir" fetch --quiet origin "$TRUNK" || ! git -C "$dir" switch --quiet --detach "origin/$TRUNK"; then
    echo "Not done: could not detach $who at origin/$TRUNK." >&2; return 1
  fi
  lstate=deleted; rstate="already gone"
  git -C "$dir" branch -D "$branch" >/dev/null 2>&1 || { lstate="NOT deleted"; rc=1; }
  # the exact ref, and only at the PR's head: a push after the merge is unmerged work on origin
  rsha="$(git -C "$dir" ls-remote origin "refs/heads/$branch" 2>/dev/null | cut -f1)"
  if [[ -n "$rsha" && "$rsha" != "$pretip" ]]; then
    rstate="NOT deleted (it moved past PR #$pr: ${rsha:0:7})"; rc=1
    echo "origin/$branch holds commits the merged PR does not (${rsha:0:7}, the PR ended at ${pretip:0:7}); look at them, then delete it by hand if they are not wanted." >&2
  elif [[ -n "$rsha" ]]; then
    if git -C "$dir" push --quiet origin --delete "$branch" 2>/dev/null; then rstate=deleted
    else
      rstate="NOT deleted"; rc=1
      echo "The remote delete of $branch did not happen (refused or failed); run: git push origin --delete $branch" >&2
    fi
  fi
  for f in go check.log check.out grilling; do rm -f "$dir/.claude/$f"; done
  echo "$who: PR #$pr merged. Detached at origin/$TRUNK ($(git -C "$dir" rev-parse --short HEAD)); local branch $branch: $lstate; origin branch: $rstate; per-ticket files cleared."
  return $rc
}
# seed_sous_permissions: the sous runs in a mode that asks before a shell command, and nobody
# watches its pane for long. When the merge is the sous's, open seeds the main checkout's
# .claude/settings.local.json (kept out of git) with the gh lines ship uses, once.
seed_sous_permissions() {
  local f="$ROOT/.claude/settings.local.json"
  [[ "$(cfg_gate merge sous-chef)" == sous-chef ]] || return 0
  if [[ -f "$f" ]]; then
    grep -q 'gh pr merge' "$f" || echo "  sous: .claude/settings.local.json has no \"Bash(gh pr merge:*)\" allow line; kitchen.sh ship will ask in the sous's pane until you add one."
    return 0
  fi
  mkdir -p "$ROOT/.claude"
  cat > "$f" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(gh pr view:*)", "Bash(gh pr checks:*)", "Bash(gh pr merge:*)", "Bash(gh pr list:*)"
    ]
  }
}
EOF
  exclude_locally .claude/settings.local.json
  echo "  sous: permissions seeded (.claude/settings.local.json: gh pr view, checks, merge, list), so kitchen.sh ship runs without a prompt"
}

# ---------------------------------------------------------------------------
# procs — the processes the kitchen started (Contract 7). A cook that starts something which
# outlives the tool call (a dev server, a watcher, a tunnel, a poll) registers it the moment
# it starts; the sous reaps what is still registered when the ticket is done. The kitchen
# manages the processes it registered and only those: a system process, a kitchen session
# (claude, tmux, a pane's shell) and anything unregistered are never signalled. The scan
# looks for unregistered processes standing in a station and only reports them.
#   kitchen.sh procs [--add <pid> "<what>" [--ticket ID]] [--prune] [--station N]
#                    [--reap <station-N|all>] [--scan]
# The register is <station>/.claude/procs (out of git), one tab-separated line per process:
#   pid · start time · command line · what it is for · ticket · when it was added
# and <station>/.claude/procs.log keeps what a reap did. A line is `alive` while the pid still
# has the recorded start time and command line, `dead` when the pid is gone, and `reused`
# when it now belongs to another process.
# ---------------------------------------------------------------------------
PROCS_GRACE=5   # seconds a reaped process has to leave on TERM before it gets KILL

procs_clean() { tr '\t\r\n' '   ' | sed 's/  */ /g; s/^ //; s/ $//'; }   # one line: tabs and newlines squeezed
procs_start() { LC_ALL=C ps -ww -o lstart= -p "$1" 2>/dev/null | procs_clean; }
procs_cmd() { ps -ww -o command= -p "$1" 2>/dev/null | procs_clean; }
procs_ppid() { ps -o ppid= -p "$1" 2>/dev/null | tr -d ' '; }
procs_file() { printf '%s/.claude/procs' "$1"; }

# procs_state <pid> <start> <command> → alive | dead | reused
procs_state() {
  local s c
  s="$(procs_start "$1")"
  [[ -n "$s" ]] || { echo dead; return 0; }
  c="$(procs_cmd "$1")"
  if [[ "$s" == "$2" && "$c" == "$3" ]]; then echo alive; else echo reused; fi
}

# procs_kitchen_session <pid> <command> → true for claude, tmux or a pane's shell
procs_kitchen_session() {
  local a1 a2 _ pp p1
  read -r a1 a2 _ <<< "$2"
  [[ "${a1##*/}" == claude || "${a2##*/}" == claude || "${a1##*/}" == tmux* || "$a1" == */claude/* ]] && return 0
  case "${a1##*/}" in
    -*|bash|zsh|sh|fish|dash|ksh)
      [[ "$a1" == -* ]] && return 0                       # a login shell
      pp="$(procs_ppid "$1")"; [[ -n "$pp" ]] || return 1
      read -r p1 _ <<< "$(procs_cmd "$pp")"
      [[ "${p1##*/}" == tmux* ]] && return 0 ;;           # the shell tmux started in a pane
  esac
  return 1
}

# procs_mine <pid> → true for this run's own process, its ancestors (the shell, the claude
# session above it) and its descendants (the ps and lsof it runs)
procs_mine() {
  local p
  p="$$"; while [[ -n "$p" ]] && (( p > 1 )); do [[ "$p" == "$1" ]] && return 0; p="$(procs_ppid "$p")"; done
  p="$1"; while [[ -n "$p" ]] && (( p > 1 )); do [[ "$p" == "$$" ]] && return 0; p="$(procs_ppid "$p")"; done
  return 1
}

# procs_protected <pid> <command> → prints why and returns 0 when this pid may never be
# registered or reaped: a system pid, someone else's, this run's own tree, a kitchen session
procs_protected() {
  local uid
  (( $1 > 2 )) || { echo "a system process"; return 0; }
  uid="$(ps -o uid= -p "$1" 2>/dev/null | tr -d ' ')"
  [[ "$uid" == "$(id -u)" ]] || { echo "not yours (uid ${uid:-?})"; return 0; }
  procs_mine "$1" && { echo "this session's own process or its parent"; return 0; }
  procs_kitchen_session "$1" "$2" && { echo "a kitchen session (claude, tmux or a pane's shell)"; return 0; }
  return 1
}

# procs_cwd_of <pid> → the process's working directory, or nothing
procs_cwd_of() {
  if [[ -e "/proc/$1/cwd" ]]; then readlink "/proc/$1/cwd" 2>/dev/null
  else lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1; fi
}

# procs_in_station <pid> <station dir> → true when the process stands inside the station;
# its working directory is left in PROCS_CWD for the message
procs_in_station() {
  local root; root="$(cd "$2" && pwd -P)"; PROCS_CWD="$(procs_cwd_of "$1")"
  [[ -n "$PROCS_CWD" ]] && [[ "$PROCS_CWD" == "$root" || "$PROCS_CWD" == "$root"/* ]]
}

# procs_dir <station-N | N | ""> → a station's directory; "" means the station this runs in
procs_dir() {
  local s="$1" d
  if [[ -z "$s" ]]; then
    [[ -n "$(rail_actor)" ]] || { echo "Run this in a station, or name one: --station N." >&2; return 1; }
    (cd "$HERE" && pwd -P); return 0
  fi
  s="station-${s#station-}"; d="$KITCHEN/$s"
  [[ -e "$d/.git" ]] || { echo "No such station: $s" >&2; return 1; }
  printf '%s\n' "$d"
}

procs_stations() {  # procs_stations <station-N | N | all | ""> → the station dirs it names; "" is the station this runs in, else every station
  local s="$1" d
  if [[ -z "$s" && -n "$(rail_actor)" ]]; then procs_dir ""
  elif [[ -z "$s" || "$s" == all ]]; then stations
  else d="$(procs_dir "$s")" && printf '%s\n' "$d"; fi
}

procs_add() {  # procs_add <pid> <what> <ticket> <station dir>
  local pid="$1" what="$2" ticket="$3" dir="$4" start cmd why f
  [[ "$pid" =~ ^[0-9]+$ ]] || { echo "procs --add needs a pid (a number), got: ${pid:-nothing}" >&2; return 1; }
  [[ -n "$what" ]] || { echo "procs --add $pid \"<what it is for>\"" >&2; return 1; }
  start="$(procs_start "$pid")"; cmd="$(procs_cmd "$pid")"
  [[ -n "$start" && -n "$cmd" ]] || { echo "Not registered: no process $pid (or ps cannot describe it)." >&2; return 1; }
  if why="$(procs_protected "$pid" "$cmd")"; then echo "Not registered: $pid is $why." >&2; return 1; fi
  if ! procs_in_station "$pid" "$dir"; then
    echo "Not registered: $pid's cwd is ${PROCS_CWD:-unreadable}, not inside $(basename "$dir"). The kitchen registers what it started in a station: start it from there." >&2; return 1
  fi
  if [[ -z "$ticket" ]]; then ticket="$(branch_ticket "$(git -C "$dir" branch --show-current 2>/dev/null)")"; fi
  what="$(printf '%s' "$what" | procs_clean)"
  mkdir -p "$dir/.claude"; exclude_locally .claude/procs "$dir"; exclude_locally .claude/procs.log "$dir"
  f="$(procs_file "$dir")"
  if [[ -f "$f" ]] && awk -F'\t' -v p="$pid" -v s="$start" '$1==p && $2==s { found=1 } END { exit !found }' "$f"; then
    echo "$(basename "$dir"): $pid is already registered."; return 0
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$pid" "$start" "$cmd" "$what" "$ticket" "$(date +%Y-%m-%dT%H:%M)" >> "$f"
  echo "$(basename "$dir"): registered $pid ($what) · $cmd"
}

procs_list() {  # procs_list <station dir…> → every registered line with its state
  local d f name pid start cmd what ticket added state n=0 alive=0 dead=0 reused=0
  for d in "$@"; do
    f="$(procs_file "$d")"; [[ -s "$f" ]] || continue; name="$(basename "$d")"
    while IFS=$'\t' read -r pid start cmd what ticket added; do
      [[ -n "$pid" ]] || continue
      state="$(procs_state "$pid" "$start" "$cmd")"; n=$((n+1))
      case "$state" in alive) alive=$((alive+1)) ;; dead) dead=$((dead+1)) ;; *) reused=$((reused+1)) ;; esac
      printf '  %-10s %-7s %-7s %-8s %s · %s\n' "$name" "$state" "$pid" "$ticket" "$what" "$cmd"
    done < "$f"
  done
  if (( n == 0 )); then echo "No processes registered."; else echo "Registered: $alive alive, $dead dead, $reused reused."; fi
}

procs_prune() {  # procs_prune <station dir…> → drop the lines whose process is gone
  local d f name pid start cmd what ticket added keep dropped total=0
  for d in "$@"; do
    f="$(procs_file "$d")"; [[ -s "$f" ]] || continue; name="$(basename "$d")"; keep=""; dropped=0
    while IFS=$'\t' read -r pid start cmd what ticket added; do
      [[ -n "$pid" ]] || continue
      if [[ "$(procs_state "$pid" "$start" "$cmd")" == alive ]]; then
        keep="$keep$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$pid" "$start" "$cmd" "$what" "$ticket" "$added")"$'\n'
      else dropped=$((dropped+1)); fi
    done < "$f"
    printf '%s' "$keep" > "$f"; total=$((total+dropped))
    (( dropped == 0 )) || echo "$name: pruned $dropped line(s) whose process is gone or is now another process."
  done
  (( total > 0 )) || echo "Nothing to prune."
}

# procs_reap <station dir> → TERM, then KILL, each registered process that is still the same
# process and is not protected. Anything else is left alone and printed.
procs_reap() {
  local dir="$1" f name pid start cmd what ticket added state why how i keep="" line
  f="$(procs_file "$dir")"; name="$(basename "$dir")"
  [[ -s "$f" ]] || { echo "$name: nothing registered."; return 0; }
  while IFS=$'\t' read -r pid start cmd what ticket added; do
    [[ -n "$pid" ]] || continue
    line="$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$pid" "$start" "$cmd" "$what" "$ticket" "$added")"
    state="$(procs_state "$pid" "$start" "$cmd")"
    if [[ "$state" == dead ]]; then echo "$name: $pid ($what) was already gone; dropped from the register."; continue; fi
    if [[ "$state" == reused ]]; then
      echo "$name: $pid ($what) is no longer the registered process (its start time or command changed); left alone."
      keep="$keep$line"$'\n'; continue
    fi
    if why="$(procs_protected "$pid" "$cmd")"; then
      echo "$name: $pid ($what) skipped, it is $why; left alone."; keep="$keep$line"$'\n'; continue
    fi
    if ! procs_in_station "$pid" "$dir"; then
      echo "$name: $pid ($what) skipped, its cwd is now ${PROCS_CWD:-unreadable}, outside $name; left alone."; keep="$keep$line"$'\n'; continue
    fi
    how="term"; kill -TERM "$pid" 2>/dev/null
    for ((i = 0; i < PROCS_GRACE * 2; i++)); do
      [[ "$(procs_state "$pid" "$start" "$cmd")" == alive ]] || break
      sleep 0.5
    done
    if [[ "$(procs_state "$pid" "$start" "$cmd")" == alive ]]; then
      how="kill"; kill -KILL "$pid" 2>/dev/null; sleep 0.5
    fi
    if [[ "$(procs_state "$pid" "$start" "$cmd")" == alive ]]; then
      echo "$name: $pid ($what) is still running after KILL; kept in the register."; keep="$keep$line"$'\n'; continue
    fi
    printf '%s\treaped\t%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$pid" "$what" "$how" >> "$dir/.claude/procs.log"
    echo "$name: reaped $pid ($what, $how)"
  done < "$f"
  printf '%s' "$keep" > "$f"
}

# procs_cwds → "pid<TAB>cwd" for every process this user can see: /proc on Linux, one lsof elsewhere
procs_cwds() {
  local d
  if [[ -d /proc/self ]]; then
    for d in /proc/[0-9]*; do printf '%s\t%s\n' "${d#/proc/}" "$(readlink "$d/cwd" 2>/dev/null)"; done
  elif command -v lsof >/dev/null 2>&1; then
    { lsof -d cwd -Fpn 2>/dev/null || true; } | awk '/^p/ { pid = substr($0, 2) } /^n/ { print pid "\t" substr($0, 2) }'
  else
    return 1
  fi
}

# procs_scan_rows → one line per unregistered process standing in a station, tab-separated:
# station, pid, ppid, parent note, started, command. Never signals anything.
procs_scan_rows() {
  local reg d f name pid start cmd cwd cw root st pdirs="" pp ppcmd p1 a1 a2 note
  reg="$(for d in $(stations); do
    f="$(procs_file "$d")"; [[ -s "$f" ]] || continue
    while IFS=$'\t' read -r pid start cmd _; do
      [[ -n "$pid" && "$(procs_state "$pid" "$start" "$cmd")" == alive ]] && printf '%s\t%s\n' "$pid" "$(basename "$d")"
    done < "$f"
  done)"
  while IFS= read -r d; do pdirs="$pdirs$(cd "$d" && pwd -P)"$'\n'; done < <(stations)
  [[ -n "$pdirs" ]] || return 0
  cw="$(procs_cwds)" || return 1   # one read of every cwd; no /proc and no lsof is a failure, not "nothing"
  while IFS=$'\t' read -r pid cwd; do
    [[ -n "$pid" && -n "$cwd" ]] || continue
    st=""
    while IFS= read -r root; do
      [[ -n "$root" ]] || continue
      if [[ "$cwd" == "$root" || "$cwd" == "$root"/* ]]; then st="$(basename "$root")"; break; fi
    done <<< "$pdirs"
    [[ -n "$st" ]] || continue
    printf '%s\n' "$reg" | awk -F'\t' -v p="$pid" '$1==p { found=1 } END { exit !found }' && continue
    cmd="$(procs_cmd "$pid")"; [[ -n "$cmd" ]] || continue
    procs_mine "$pid" && continue
    procs_kitchen_session "$pid" "$cmd" && continue
    pp="$(procs_ppid "$pid")"; ppcmd=""; note="-"
    if [[ -n "$pp" ]]; then
      ppcmd="$(procs_cmd "$pp")"; read -r p1 _ <<< "$ppcmd"
      # the shell a claude session runs a tool call in is the cook working, not a stray
      case "$(read -r a1 _ <<< "$cmd"; echo "${a1##*/}")" in
        bash|zsh|sh|fish|dash|ksh|-*) read -r a1 a2 _ <<< "$ppcmd"; [[ "${a1##*/}" == claude || "${a2##*/}" == claude ]] && continue ;;
      esac
      printf '%s\n' "$reg" | awk -F'\t' -v p="$pp" '$1==p { found=1 } END { exit !found }' && note="child of registered $pp"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$st" "$pid" "${pp:--}" "$note" "$(procs_start "$pid")" "$cmd"
  done <<< "$cw"
}

procs_scan() {
  local rows
  rows="$(procs_scan_rows)" || { echo "Cannot read working directories: no /proc and no lsof on this machine." >&2; return 1; }
  if [[ -z "$rows" ]]; then echo "No unregistered process stands in a station."; return 0; fi
  echo "Unregistered processes standing in a station (reported, never killed):"
  printf '%s\n' "$rows" | while IFS=$'\t' read -r st pid pp note start cmd; do
    printf '  %-10s pid %-7s parent %-7s %s · started %s · %s\n' "$st" "$pid" "$pp" "$note" "$start" "$cmd"
  done
  echo "Ask that cook to register or stop each one; with the cook gone, tell the head chef. kitchen.sh procs --scan never signals anything."
}

procs_summary() {  # "<n> registered alive · <m> unregistered in stations", for the board
  local d f pid start cmd _ alive=0 sus rows
  for d in $(stations); do
    f="$(procs_file "$d")"; [[ -s "$f" ]] || continue
    while IFS=$'\t' read -r pid start cmd _; do
      [[ -n "$pid" && "$(procs_state "$pid" "$start" "$cmd")" == alive ]] && alive=$((alive+1))
    done < "$f"
  done
  if rows="$(procs_scan_rows)"; then sus="$(printf '%s' "$rows" | grep -c . || true)"; else sus="?"; fi
  printf '%s registered alive · %s unregistered in stations' "$alive" "$sus"
}

cmd_procs() {
  local act=list arg="" what="" ticket="" station="" pdirs d n me
  set -- "${PROCS_ARGS[@]+"${PROCS_ARGS[@]}"}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --add) act=add; arg="${2:-}"; what="${3:-}"; shift; [[ $# -gt 0 ]] && shift; [[ $# -gt 0 ]] && shift ;;
      --prune) act=prune; shift ;;
      --reap) act=reap; arg="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
      --scan) act=scan; shift ;;
      --ticket) ticket="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
      --station) station="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
      -h|--help) usage ;;
      *) echo "Unknown argument for procs: $1" >&2; return 1 ;;
    esac
  done
  # a cook's scope is its own station: the reap and the other stations are the sous's
  me="$(rail_actor)"
  if [[ -n "$me" ]]; then
    if [[ "$act" == reap ]]; then
      echo "procs --reap is the sous's (and bk stop's). A cook stops its own processes with kill, then procs --prune." >&2; return 1
    fi
    if [[ -n "$station" && "station-${station#station-}" != "$me" ]]; then
      echo "A cook works on its own station ($me); --station $station is the sous's." >&2; return 1
    fi
  fi
  case "$act" in
    add)
      d="$(procs_dir "$station")" || return 1
      procs_add "$arg" "$what" "$ticket" "$d" ;;
    reap)
      [[ -n "$arg" ]] || { echo "Usage: kitchen.sh procs --reap <station-N|all>" >&2; return 1; }
      pdirs="$(procs_stations "$arg")" || return 1
      if [[ "$arg" == all ]]; then   # every station: say nothing about the ones with an empty register
        n=0
        while IFS= read -r d; do
          [[ -s "$(procs_file "$d")" ]] || continue
          procs_reap "$d"; n=$((n+1))
        done <<< "$pdirs"
        (( n > 0 )) || echo "No processes registered."
      else
        procs_reap "$pdirs"
      fi ;;
    prune|list)
      pdirs="$(procs_stations "$station")" || return 1
      # shellcheck disable=SC2086  # one station dir per line, none with spaces in a kitchen's folder names
      set -- $pdirs
      if [[ "$act" == prune ]]; then procs_prune "$@"; else procs_list "$@"; fi ;;
    scan) procs_scan ;;
  esac
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
  args=(--root "$ROOT" --since 7d --debrief --register "$REC/$(cfg_docs lessons docs/lessons.md)")
  $JSON && args+=(--json)
  node "$dir/server/live/budget.js" "${args[@]}"
}

# ---------------------------------------------------------------------------
# check — the config's check command, run once per tree (#66). A pass runs the check three
# or four times on a tree that has not changed; this records each real run in
# <checkout>/.claude/check.log, one receipt per line (#90):
#   <ended> tree=<hash> rc=<n> secs=<n> cmd=<id> start=<started> out=<sha256 of the output>
#   station=<folder, % as %25 and spaces as %20>[ moved] check=<the config's check: line, to the end of the line>
# " moved" marks a run that changed the tree it ran on: it is never a receipt for the tree it
# names. The newest receipt for a tree, green and made by the config's check: line as it is
# now, is trusted and nothing runs; a red, stale or moved one never is. A skipped call writes
# nothing, so the log counts real runs (the budget and the Window read it, older lines too,
# but a line from before receipts is not one).
# ---------------------------------------------------------------------------

# tree_hash <dir> → a tree object id of <dir>'s working state, built in a throwaway index so
# nothing in <dir> is touched. Tracked, deleted and untracked files count; what git ignores
# (including .claude/check.log) does not.
tree_hash() {
  local dir="$1" tmp idx real rc
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/brigade-tree.XXXXXX")" || return 1
  idx="$tmp/index"
  real="$(git -C "$dir" rev-parse --path-format=absolute --git-path index)"
  # the copy keeps the real index's mtime: git trusts a file's stat only when it is older than
  # the index, so a fresh mtime would let a same-size edit made in the same second hash as the old tree
  if [[ -f "$real" ]]; then cp "$real" "$idx"; touch -r "$real" "$idx"; else GIT_INDEX_FILE="$idx" git -C "$dir" read-tree HEAD 2>/dev/null || true; fi
  GIT_INDEX_FILE="$idx" git -C "$dir" add -A >/dev/null 2>&1 && GIT_INDEX_FILE="$idx" git -C "$dir" write-tree
  rc=$?; rm -rf "$tmp"; return $rc
}

# sha256_of <file> → the file's sha256, hex
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else return 1; fi
}

# receipt_line <log> <tree> → the newest receipt for <tree>: a full receipt line that is not
# " moved" (a moved run never saw the tree it names). Older lines are not receipts.
receipt_line() {
  grep -E "^[^ ]+ tree=$2 rc=[0-9]+ secs=[0-9]+ cmd=[0-9a-f]{12} start=[^ ]+ out=[0-9a-f]{64} station=[^ ]+ check=" "$1" 2>/dev/null \
    | grep -v -E ' station=[^ ]+ moved check=' | tail -1
}

# receipt_field <line> <key> → the value of rc, secs, start, out or station; read only from the
# part before check=, so the config line cannot be mistaken for a field
receipt_field() { local head="${1%% check=*}"; printf '%s\n' "$head" | sed -E "s/^.* $2=([^ ]*).*$/\\1/"; }

# receipt_check <line> → the config's check: line the run used (everything after the first check=)
receipt_check() { printf '%s\n' "${1#* check=}"; }

# kitchen.sh check --receipt [<tree>]: print the newest receipt; 0 green and current, 1 none,
# 2 there is one that cannot be relied on (stale or red), the reason on stderr
cmd_receipt() {
  local dir="$HERE" tree="$RECEIPT_TREE" line cmd rc
  [[ -n "$tree" ]] || tree="$(tree_hash "$dir")" || { echo "check: couldn't hash the tree in $dir." >&2; return 1; }
  line="$(receipt_line "$dir/.claude/check.log" "$tree")"
  [[ -n "$line" ]] || { echo "no receipt for this tree" >&2; return 1; }
  printf '%s\n' "$line"
  cmd="$(cfg check)"
  [[ "$(receipt_check "$line")" == "$cmd" ]] || { echo "receipt is stale: the check changed under this tree" >&2; return 2; }
  rc="$(receipt_field "$line" rc)"
  (( rc == 0 )) || { echo "receipt is red: the check failed on this tree (rc $rc)" >&2; return 2; }
}

cmd_check() {
  local dir="$HERE" cmd cmdid log out before after start startiso secs rc line rec outsha station
  $RECEIPT && { cmd_receipt; return; }
  cmd="$(cfg check)"
  [[ -n "$cmd" ]] || { echo "No check: command in $CONFIG." >&2; return 1; }
  sha256_of /dev/null >/dev/null || { echo "check: needs shasum or sha256sum on PATH." >&2; return 1; }
  mkdir -p "$dir/.claude"; log="$dir/.claude/check.log"; out="$dir/.claude/check.out"
  exclude_locally .claude/check.log "$dir"; exclude_locally .claude/check.out "$dir"
  cmdid="$(printf '%s' "$cmd" | git hash-object --stdin | cut -c1-12)"
  before="$(tree_hash "$dir")" || { echo "check: couldn't hash the tree in $dir." >&2; return 1; }
  if ! $FORCE; then
    rec="$(receipt_line "$log" "$before")"
    if [[ -n "$rec" && "$(receipt_field "$rec" rc)" == 0 && "$(receipt_check "$rec")" == "$cmd" ]]; then
      echo "check: green on this tree, not re-run (recorded ${rec%% *}, $(receipt_field "$rec" secs)s)"
      return 0
    fi
  fi
  start="$(date +%s)"; startiso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  (cd "$dir" && bash -c "$cmd") > "$out" 2>&1; rc=$?
  secs=$(( $(date +%s) - start ))
  after="$(tree_hash "$dir")" || after="unhashable"
  outsha="$(sha256_of "$out")"; station="$(basename "$(cd "$dir" && pwd -P)")"; station="${station//%/%25}"; station="${station// /%20}"
  line="$(date -u +%Y-%m-%dT%H:%M:%SZ) tree=$after rc=$rc secs=$secs cmd=$cmdid start=$startiso out=$outsha station=$station"
  [[ "$after" == "$before" ]] || line="$line moved"
  echo "$line check=$cmd" >> "$log"
  if (( rc == 0 )); then
    echo "check: green (ran, ${secs}s)"
    [[ "$after" == "$before" ]] || echo "check: the run changed files in the tree, so this green is not trusted; the next call runs once more."
  else
    echo "check: RED (rc $rc, ${secs}s). Last lines of $out:"; tail -40 "$out"
  fi
  return $rc
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
  if $LEGACY_CLONE; then
    echo "This deletes $KITCHEN_REL/ — every old clone station, including unpushed branches and uncommitted work."
  else
    echo "This removes every worktree in $KITCHEN_REL/. Branches and commits stay in the repo;"
    echo "a station with uncommitted work is refused, not deleted."
  fi
  read -r -p "Type 'delete' to confirm: " answer
  [[ "$answer" == delete ]] || { echo "Aborted."; exit 1; }
  if $LEGACY_CLONE; then
    # The one clone path left (#85): the migration is `remove`, then `setup`.
    rm -rf "$KITCHEN"; echo "Removed. Now delete the kitchen_mode line from .claude/brigade.md and run kitchen.sh setup."
    return 0
  fi
  # git worktree remove refuses a dirty worktree, which is the point: it
  # would otherwise delete a cook's uncommitted work. Stash or commit first.
  local s failed=false
  while IFS= read -r s; do
    if git -C "$ROOT" worktree remove "$s"; then echo "  $(basename "$s"): removed"
    else echo "  $(basename "$s"): NOT removed (dirty? commit or stash it first)"; failed=true; fi
  done < <(stations)
  git -C "$ROOT" worktree prune
  $failed || { rmdir "$KITCHEN" 2>/dev/null; echo "Removed."; }
}

# A config that still says kitchen_mode: clone gets one line and an exit 1 (#85); only `remove` runs.
if $LEGACY_CLONE && [[ "$CMD" != remove ]]; then
  echo "kitchen_mode: clone is gone: stations are worktrees now. Run 'kitchen.sh remove' (it asks before it deletes the old stations/ folder; push or park any unpushed work first), delete the kitchen_mode line from .claude/brigade.md, then run 'kitchen.sh setup'." >&2
  exit 1
fi

# the commands that list what is due read the record as trunk and the open record branches hold it
case "$CMD" in
  lessons|questions|decisions|gaps|debrief)
    REC="$(record_view)"
    [[ "$REC" == "$ROOT" ]] || trap 'rm -rf "$REC"' EXIT ;;
esac

case "$CMD" in
  setup) cmd_setup ;; open) cmd_open ;; sync) cmd_sync ;; status) cmd_status ;;
  files) cmd_files ;; rail) cmd_rail_dispatch ;; here) cmd_here ;; board) cmd_board ;; leaks) cmd_leaks ;; remove) cmd_remove ;;
  role) cmd_role ;; sous) cmd_sous ;; lessons) cmd_lessons ;; questions) cmd_questions ;;
  decisions) cmd_decisions ;; inbox) cmd_inbox ;; asks) cmd_asks ;; gaps) cmd_gaps ;; doctor) cmd_doctor ;; index) cmd_index ;;
  record-pr) cmd_record_pr ;;
  procs) cmd_procs ;; scope) cmd_scope ;;
  sessions) cmd_sessions ;; clear) cmd_clear ;; ship) cmd_ship ;; done) cmd_done ;; check) cmd_check ;; live) cmd_live ;; budget) cmd_budget ;; debrief) cmd_debrief ;; *) usage ;;
esac
