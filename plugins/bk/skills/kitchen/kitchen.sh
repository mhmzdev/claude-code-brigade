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
#   kitchen.sh setup  [-n N]              create N stations (clone, gitignore,
#                                         copy files, seed permissions, install)
#   kitchen.sh open   [-n N] [-m "O S"] [--terminal warp|tmux|print] [--bare]
#                                         open one claude session per station, already
#                                         running /bk:line-cook (--bare: a plain session;
#                                         --no-launch: write the Warp config, open nothing)
#   kitchen.sh sync   [-n N]              reset CLEAN stations to origin/<trunk>
#                                         (dirty ones are skipped)
#   kitchen.sh status                     branch / dirty / ahead per station + open PRs
#   kitchen.sh files                      files in flight per station vs origin/<trunk>,
#                                         plans, and unmerged migrations
#   kitchen.sh rail                       the board, computed from ticket frontmatter
#                                         (markdown rail only)
#   kitchen.sh remove                     delete every station (asks first)
#
# Env overrides:
#   BRIGADE_TRUNK, BRIGADE_KITCHEN_MODE, BRIGADE_KITCHEN, BRIGADE_STATIONS, BRIGADE_MODEL (default sonnet),
#   BRIGADE_PERMISSION_MODE (default: auto — cooks run unattended, so a mode that
#   stops on every permission would stall them), BRIGADE_TERMINAL
#
# Requires: git, claude. Optional: gh (status), Warp or tmux (open).
# =============================================================================

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not inside a git repo." >&2; exit 1; }
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
cfg_docs() {
  local v=""
  [[ -f "$CONFIG" ]] && v=$(awk -v k="$1" '
    NR==1 && $0=="---" { inside=1; next }
    inside && $0=="---" { exit }
    inside && /^docs:/ { indocs=1; next }
    indocs && /^[^ ]/ { indocs=0 }
    indocs && $0 ~ "^  " k ":" { sub("^  " k ":[ ]*", ""); sub(/[ ]+#.*$/, ""); print; exit }' "$CONFIG")
  printf '%s' "${v:-docs/$1}"
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
INSTALL="$(cfg install)"
COPY_FILES="$(cfg copy_into_stations)"
MIGRATIONS="$(cfg migrations)"; [[ "$MIGRATIONS" == "none" ]] && MIGRATIONS=""
MODEL="${BRIGADE_MODEL:-sonnet}"
PERMISSION_MODE="${BRIGADE_PERMISSION_MODE:-$(cfg permission_mode)}"; PERMISSION_MODE="${PERMISSION_MODE:-auto}"
TERMINAL="${BRIGADE_TERMINAL:-}"
BARE=false
NO_LAUNCH=false
MODELS=()

usage() { awk 'NR>2 { if (/^# =+$/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; exit 1; }

CMD="${1:-}"; shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) N="$2"; shift 2 ;;
    --terminal) TERMINAL="$2"; shift 2 ;;
    --bare) BARE=true; shift ;;
    --no-launch) NO_LAUNCH=true; shift ;;
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

claude_cmd() {  # claude_cmd <model> <station dir>
  local prefix=""
  [[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && prefix="CLAUDE_CONFIG_DIR=$(printf '%q' "$CLAUDE_CONFIG_DIR") "
  printf '%sclaude --name %s --model %s --permission-mode %s' "$prefix" \
    "$(printf '%q' "$(session_name "$2")")" "$1" "$PERMISSION_MODE"
  # Start as a line cook: it checks in with the sous, or waits for the sous's [hello].
  $BARE || printf ' "/bk:line-cook"'
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
  Brigade setup (config, CLAUDE.md section, docs/ folders). Commit and push
  the setup first, then run this again:

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
  cat <<EOF

  Next: kitchen.sh open   (then /bk:sous-chef here, /bk:line-cook in each station)
EOF
}

# ---------------------------------------------------------------------------
# open
# ---------------------------------------------------------------------------
cmd_open() {
  local list=() s i norm bad=()
  while IFS= read -r s; do list+=("$s"); done < <(stations)
  if (( ${#list[@]} == 0 )); then
    echo "No stations yet. Create them first: kitchen.sh setup"
    echo "(setup needs the Brigade setup committed and pushed to origin/$TRUNK — stations clone from there)"
    exit 1
  fi
  (( ${#list[@]} > N )) && list=("${list[@]:0:$N}")

  for i in "${!MODELS[@]}"; do
    if norm=$(normalize_model "${MODELS[$i]}"); then MODELS[$i]="$norm"; else bad+=("${MODELS[$i]}"); fi
  done
  (( ${#bad[@]} > 0 )) && { echo "Unknown model(s): ${bad[*]} (use O/S/H/F, full names, or claude-*)"; exit 1; }

  if [[ -z "$TERMINAL" ]]; then
    if [[ -d "/Applications/Warp.app" ]]; then TERMINAL=warp
    elif command -v tmux >/dev/null; then TERMINAL=tmux
    else TERMINAL=print; fi
  fi

  case "$TERMINAL" in
    warp)
      local dir="$HOME/.warp/launch_configurations" file
      file="$dir/${REPO_NAME}-brigade.yaml"; mkdir -p "$dir"
      {
        echo "---"; echo "name: ${REPO_NAME}-brigade"; echo "windows:"; echo "  - tabs:"
        for i in "${!list[@]}"; do
          echo "      - title: \"$(session_name "${list[$i]}") · $(model_for "$i")\""
          echo "        layout:"
          echo "          cwd: \"${list[$i]}\""
          echo "          commands:"
          echo "            - exec: '$(claude_cmd "$(model_for "$i")" "${list[$i]}")'"
        done
      } > "$file"
      if $NO_LAUNCH; then echo "Warp config written, not launched: $file"; return 0; fi
      open "warp://launch/$(basename "$file")" 2>/dev/null \
        && echo "Warp window opened with ${#list[@]} bare line-cook session(s)." \
        || { echo "Warp launch failed; commands:"; TERMINAL=print; }
      ;;
    tmux)
      local sess="${REPO_NAME}-brigade"
      tmux has-session -t "$sess" 2>/dev/null && { echo "tmux session '$sess' already exists: tmux attach -t $sess"; return 0; }
      for i in "${!list[@]}"; do
        if (( i == 0 )); then
          tmux new-session -d -s "$sess" -n "$(basename "${list[$i]}")" -c "${list[$i]}"
        else
          tmux new-window -t "$sess" -n "$(basename "${list[$i]}")" -c "${list[$i]}"
        fi
        tmux send-keys -t "$sess:$(basename "${list[$i]}")" "$(claude_cmd "$(model_for "$i")" "${list[$i]}")" Enter
      done
      echo "tmux session '$sess' started: tmux attach -t $sess"
      ;;
  esac

  if [[ "$TERMINAL" == print ]]; then
    for i in "${!list[@]}"; do
      echo "  $(basename "${list[$i]}"):  cd $(printf '%q' "${list[$i]}") && $(claude_cmd "$(model_for "$i")" "${list[$i]}")"
    done
  fi
  if $BARE; then
    echo "Sessions open bare. In each one run /bk:line-cook, or let the sous brief them."
  else
    echo "Each session starts as a line cook and checks in with the sous (or waits for it)."
  fi
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
  printf '%-10s %-4s %-12s %-11s %s\n' ID LANE STATUS COOK TITLE
  awk '
    FNR==1 { if (id!="") out(); id=lane=status=cook=title=""; fm=0 }
    FNR==1 && $0=="---" { fm=1; next }
    fm && $0=="---" { fm=0; next }
    fm {
      line=$0; key=line; sub(/:.*/, "", key); val=line; sub(/^[^:]*:[ ]*/, "", val); sub(/[ ]+#.*$/, "", val); gsub(/^"|"$/, "", val)
      if (key=="id") id=val; else if (key=="lane") lane=val; else if (key=="status") status=val
      else if (key=="cook") cook=val; else if (key=="title") title=val
    }
    function out() { if (cook=="null"||cook=="") cook="-"; printf "%-10s %-4s %-12s %-11s %s\n", id, lane, status, cook, title }
    END { if (id!="") out() }' "${files[@]}" | awk '$3!="done"'
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
  files) cmd_files ;; rail) cmd_rail ;; remove) cmd_remove ;; *) usage ;;
esac
