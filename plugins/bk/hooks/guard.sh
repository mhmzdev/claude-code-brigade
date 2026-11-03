#!/usr/bin/env bash
# =============================================================================
# hooks/guard.sh — the Brigade's PreToolUse guard (Contract 5 and 12, mechanical).
#
# Four rules that used to rest on a cook remembering them:
#   1. In a station, AskUserQuestion is refused unless a grilling is under way
#      (<station>/.claude/grilling exists and is under four hours old: grill-me
#      and brainstorm write it when they start in a station, and remove it when
#      they finish; a stale one from a cleared session doesn't count). Nobody
#      watches a cook's terminal, so a dialog there only stalls the station.
#   2. A [gate] message that carries a numbered question (Q3) is refused when it
#      names no commis result ("commis:"): look it up before you ask.
#   3. Positive authorization (Contract 5): every outward action is off by default.
#      A Bash command that runs git commit, git push or gh pr create, or makes a commit
#      another way (git merge or git pull without --ff-only, rebase, cherry-pick,
#      revert, am), is refused unless the sous has granted that action to this station
#      (<main>/.claude/grants/<station>, written only by kitchen.sh grant from the main
#      checkout). A push to trunk, any force, delete, --all or --mirror push, gh pr merge,
#      git reset --hard and git clean with -x or -X are refused whatever is granted.
#   4. A cook's Edit or Write to the receipts only a script writes (<station>/.claude/
#      check.log, procs, served) or to anything under <main>/.claude/grants/ is refused,
#      and so is a Bash command that names the grants folder.
#
# The Bash rules read the word that runs. split_command cuts the command into simple commands
# (at ; & | ( ) { } and backticks, after joining backslash-newline), and the first word of each
# (after env assignments, a leading backslash and wrappers like env, sudo, xargs, timeout,
# eval, with their options; git's own options are skipped) is what is judged. Quoted text is
# not a command, so git log --grep "x; git push" passes, and a heredoc body (a commit message
# or PR body that names git push) is skipped. What is read as commands: the script quoted
# after sh -c, bash -c or eval, and $( ) and backticks inside double quotes. A route this does
# not see (gh api, a script file that pushes, ssh host "git push") passes: these are
# guardrails against a slip, not a wall. A real boundary is a branch protection rule and the
# sous being the one who merges.
#
# Everything else passes. The hook exits 0 at once outside a Brigade repo (no
# .claude/brigade.md up the tree) and in the main checkout, so it never touches a
# solo session or another project. Blocking is exit 2 with the reason on stderr.
# No jq: the fields are pulled out of the stdin JSON with sed, defensively; when
# a field can't be read, the call is allowed.
# =============================================================================
set -u

input="$(cat 2>/dev/null)" || exit 0
tool="$(printf '%s' "$input" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[[ -n "$tool" ]] || exit 0
# a Bash call that names none of git, gh or the grants folder has nothing to check
if [[ "$tool" == Bash ]]; then case "$input" in *git*|*gh*|*grants*) ;; *) exit 0 ;; esac; fi
cwd="$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
cwd="${cwd:-${BRIGADE_HOOK_CWD:-$PWD}}"
[[ -d "$cwd" ]] || exit 0

# Which checkout is this, and is it a station? The same test kitchen.sh uses: the
# folder is named station-*, and it is a worktree of a main checkout that has
# .claude/brigade.md. The kitchen is the config's `kitchen:` key, else
# ../<repo>-stations next to the main checkout. A nested repo, a submodule, or Claude
# Code's own --worktree session is none of those, and the human is at that terminal:
# leave them alone.
top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
top="$(cd "$top" && pwd -P)"
case "$(basename "$top")" in station-*) ;; *) exit 0 ;; esac
kitchen="$(cd "$(dirname "$top")" && pwd -P)"
main=""
# the station shares git's common dir with the main checkout
if common="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  c="$(cd "$(dirname "$common")" 2>/dev/null && pwd -P)"
  [[ -n "$c" && "$c" != "$top" && -f "$c/.claude/brigade.md" ]] && main="$c"
fi
[[ -n "$main" ]] || exit 0
# and the kitchen must be the one the config names (or the default)
cfg_kitchen="$(sed -n '2,/^---$/{s/^kitchen:[[:space:]]*//p;}' "$main/.claude/brigade.md" | head -1 | sed 's/[[:space:]]*#.*$//; s/^"//; s/"$//')"
want=""
if [[ -n "$cfg_kitchen" ]]; then
  case "$cfg_kitchen" in /*) want="$cfg_kitchen" ;; *) want="$main/$cfg_kitchen" ;; esac
  want="$(cd "$want" 2>/dev/null && pwd -P)"
  [[ "$kitchen" == "$want" ]] || exit 0
else
  sibling="$(cd "$(dirname "$main")/$(basename "$main")-stations" 2>/dev/null && pwd -P)"
  [[ -n "$sibling" && "$kitchen" == "$sibling" ]] || exit 0
fi

# --- what a station may do outward (rules 3 and 4) ---------------------------------
station="$(basename "$top")"
grant_file="$main/.claude/grants/$station"
refuse() { echo "Brigade: $*" >&2; exit 2; }
granted() { [[ -f "$grant_file" ]] && grep -qxF "$1" "$grant_file"; }
need() {  # need <action> <what was run>
  granted "$1" && return 0
  refuse "you are a line cook in $station and hold no grant for \`$1\`, so \`$2\` is refused (Contract 5). Only the sous grants it, with its [go]: finish your handoff and wait; kitchen.sh grant --show says what you hold. (If this was quoted text, not a command, reword it.)"
}
json_str() {  # json_str <key> → the first string value of "key" in the hook input, JSON escapes undone
  local ph; ph="$(printf '\001')"   # an escaped backslash is set aside while \n and \" are undone
  printf '%s' "$input" | sed -nE 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -1 \
    | sed -e "s/\\\\\\\\/$ph/g" -e 's/\\"/"/g' -e 's/\\t/ /g' -e 's/\\n/\
/g' -e "s/$ph/\\\\/g"
}
trunk="$(sed -n '2,/^---$/{s/^trunk:[[:space:]]*//p;}' "$main/.claude/brigade.md" | head -1 | sed 's/[[:space:]]*#.*$//; s/^"//; s/"$//')"
trunk="${trunk:-$(git -C "$main" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')}"
trunk="${trunk:-main}"

guard_push() {
  local a n=0 spec dst cur
  for a in "$@"; do
    case "$a" in
      --force*|--delete|--mirror|--all|--prune) refuse "a force, delete, --all, --prune or --mirror push is refused in a station whatever you hold (Contract 5)." ;;
      --*) ;;
      -*) if [[ "$a" =~ ^-[A-Za-z]*[fd] ]]; then refuse "a force or delete push (\`$a\`) is refused in a station whatever you hold (Contract 5)."; fi ;;
      +*) refuse "a \`+\` refspec forces the push: it is refused in a station whatever you hold (Contract 5)." ;;
      *) n=$((n+1))
         if (( n > 1 )); then   # the first word is the remote, the rest are refspecs
           spec="$a"; dst="${spec##*:}"; dst="${dst#refs/heads/}"
           [[ "$dst" == "$trunk" ]] && refuse "a push to $trunk is refused in a station whatever you hold: the sous merges (Contract 5)."
           [[ "$spec" == HEAD ]] && n=1
         fi ;;
    esac
  done
  if (( n < 2 )); then   # no refspec, or HEAD: the branch the station stands on goes
    cur="$(git -C "$cwd" branch --show-current 2>/dev/null)"
    [[ "$cur" == "$trunk" ]] && refuse "this station stands on $trunk, so \`git push\` would push to it: branch first (Contract 5)."
  fi
  need push "git push"
}
guard_git() {
  local sub="" a
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -C|-c|--git-dir|--work-tree|--namespace|--exec-path) shift; [[ $# -gt 0 ]] && shift ;;
      -*) shift ;;
      *) sub="$1"; shift; break ;;
    esac
  done
  case "$sub" in
    commit) need commit "git commit" ;;
    merge|pull|rebase|cherry-pick|revert|am)   # commits by another route; --abort and --quit make none
      for a in "$@"; do
        case "$a" in --abort|--quit) return 0 ;; --ff-only) [[ "$sub" == merge || "$sub" == pull ]] && return 0 ;; esac
      done
      need commit "git $sub" ;;
    push) guard_push "$@" ;;
    reset) for a in "$@"; do [[ "$a" == --hard ]] && refuse "git reset --hard is refused in a station (Contract 5)."; done ;;
    clean) for a in "$@"; do if [[ "$a" =~ ^-[A-Za-z]*[xX] ]]; then refuse "git clean with -x or -X is refused in a station: it deletes ignored files, and a kitchen keeps its state there (Contract 5)."; fi; done ;;
  esac
  return 0
}
guard_gh() {
  while [[ $# -gt 0 ]]; do
    case "$1" in -R|--repo) shift; [[ $# -gt 0 ]] && shift ;; -*) shift ;; *) break ;; esac
  done
  [[ "${1:-}" == pr ]] || return 0
  case "${2:-}" in
    create) need open-pr "gh pr create" ;;
    merge) refuse "gh pr merge is never granted to a cook: the sous merges (kitchen.sh ship) (Contract 5)." ;;
  esac
  return 0
}
# split_command: stdin is one Bash command, stdout is its pieces, one per line, each the text
# of one simple command. It cuts at ; & | ( ) { } and backticks, joins backslash-newline
# continuations, and keeps quoted text whole (a newline inside quotes is a space): a quoted
# argument is not a command. What it does read as commands: the script after sh -c, bash -c,
# zsh -c or eval when it is quoted, and $( ) or backticks inside double quotes. A heredoc body
# (<<WORD up to the line WORD) is skipped, so a commit message or a PR body that names git push
# is not one. Quote characters are dropped from the pieces.
split_command() {
  awk '
    function emit() { if (seg != "") print seg; seg = "" }
    function shq(s) { return (s ~ /(^|[ \t\/])(sh|bash|zsh|dash|ksh)([ \t]+-[A-Za-z]+)*[ \t]+-[A-Za-z]*c[ \t]*$/ || s ~ /(^|[ \t])eval[ \t]*$/) }
    function heredoc(l, p,   w, ch) {   # <<WORD at p: remember the delimiter; the body starts after this line
      if (substr(l, p + 2, 1) == "<") return
      p += 2; if (substr(l, p, 1) == "-") p++
      while (substr(l, p, 1) == " " || substr(l, p, 1) == "\t") p++
      if (substr(l, p, 1) == AP || substr(l, p, 1) == DQ) p++
      w = ""
      while (p <= length(l)) { ch = substr(l, p, 1); if (ch ~ /[A-Za-z0-9_]/) { w = w ch; p++ } else break }
      if (w ~ /^[A-Za-z_]/) pend = w
    }
    BEGIN { q = ""; ret = ""; iq = ""; depth = 0; AP = "\047"; DQ = "\042"; SEP = ";&|(){}`"; hd = ""; pend = "" }
    {
      line = $0
      if (hd != "") { l = line; sub(/^\t+/, "", l); if (l == hd) hd = ""; next }
      n = length(line); cont = 0
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (c == "<" && substr(line, i + 1, 1) == "<" && (q == "" || q == "c")) heredoc(line, i)
        if (q == "") {
          if (c == "\\") { if (i == n) { cont = 1; break } seg = seg c substr(line, i + 1, 1); i++; continue }
          if (c == AP || c == DQ) { if (shq(seg)) { emit(); q = "c"; cq = c; ret = ""; iq = ""; depth = 0 } else q = c; continue }
          if (index(SEP, c)) { emit(); continue }
          seg = seg c
        } else if (q == "c") {
          if (c == "\\" && i < n) { seg = seg substr(line, i + 1, 1); i++; continue }
          if (iq != "") { if (c == iq) iq = ""; else seg = seg c; continue }
          if (cq == ")") {
            if (c == "(") { depth++; emit(); continue }
            if (c == ")") { emit(); if (depth == 0) q = ret; else depth--; continue }
          } else if (c == cq) { emit(); q = ret; continue }
          if ((c == AP || c == DQ) && c != cq) { iq = c; continue }
          if (index(SEP, c)) { emit(); continue }
          seg = seg c
        } else {
          if (q == DQ) {
            if (c == "\\" && i < n) { seg = seg substr(line, i + 1, 1); i++; continue }
            if (c == "$" && substr(line, i + 1, 1) == "(") { emit(); ret = DQ; q = "c"; cq = ")"; iq = ""; depth = 0; i++; continue }
            if (c == "`") { emit(); ret = DQ; q = "c"; cq = "`"; iq = ""; depth = 0; continue }
          }
          if (c == q) { q = ""; continue }
          seg = seg c
        }
      }
      if (pend != "") { hd = pend; pend = "" }
      if (cont) seg = seg " "
      else if (q == "" || (q == "c" && iq == "")) emit()
      else seg = seg " "
    }
    END { emit() }
  '
}
guard_command() {  # guard_command <the Bash command>: judge the word that runs in each piece
  local segs line base w vo
  segs="$(printf '%s\n' "$1" | split_command)"
  while IFS= read -r line; do
    # splitting the piece into words is the point here, with globbing off
    set -f
    # shellcheck disable=SC2086
    set -- $line
    set +f
    while [[ $# -gt 0 ]]; do
      w="${1#\\}"
      case "$w" in
        [A-Za-z_]*=*|command|exec|nohup|time|builtin|eval|then|do|else|'!'|-*) shift ;;
        env|sudo|nice|xargs|timeout)   # a wrapper: skip its options (and their values), then judge the word it runs
          case "$w" in
            env) vo=" -u -C -S " ;;
            sudo) vo=" -u -g -h -p -C -D -R -r -t -U " ;;
            nice) vo=" -n " ;;
            xargs) vo=" -n -I -L -P -s -d -E -a " ;;
            *) vo=" -k -s " ;;
          esac
          shift
          while [[ $# -gt 0 && "$1" == -* ]]; do
            case "$vo" in *" $1 "*) shift ;; esac
            [[ $# -gt 0 ]] && shift
          done
          [[ "$w" == timeout && $# -gt 0 ]] && shift ;;   # timeout's duration
        *) break ;;
      esac
    done
    [[ $# -gt 0 ]] || continue
    base="${1#\\}"; base="${base##*/}"; shift
    case "$base" in git) guard_git "$@" ;; gh) guard_gh "$@" ;; esac
  done <<< "$segs"
}

case "$tool" in
  AskUserQuestion)
    # a grilling marker younger than four hours lets the dialog through; an older one
    # was left behind by a cleared or crashed grilling and no longer counts
    if [[ -e "$top/.claude/grilling" ]] && [[ -n "$(find "$top/.claude/grilling" -mmin -240 2>/dev/null)" ]]; then exit 0; fi
    echo "Brigade: you are a line cook in $(basename "$top"); nobody watches this terminal. Don't open a dialog: send the sous a [gate] (Contract 5). A grilling the sous briefed you for writes .claude/grilling first." >&2
    exit 2 ;;
  SendMessage)
    msg="$(printf '%s' "$input" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -1)"
    [[ -n "$msg" ]] || exit 0
    case "$msg" in
      '[gate]'*|'\[gate\]'*) ;;
      *) exit 0 ;;
    esac
    printf '%s' "$msg" | grep -qE '(^|[^A-Za-z])Q[0-9]+' || exit 0
    printf '%s' "$msg" | grep -qi 'commis:' && exit 0
    echo "Brigade: a [gate] with a question goes up with the commis's result in it (\"commis: nothing recorded in <places>\", or the decision it found). Spawn bk:commis first, then send the gate (Contract 5)." >&2
    exit 2 ;;
  Bash)
    cmd="$(json_str command)"
    [[ -n "$cmd" ]] || exit 0
    case "$cmd" in *.claude/grants*) refuse "the grants folder is the sous's: a cook neither reads nor writes it. kitchen.sh grant --show says what you hold (Contract 5)." ;; esac
    guard_command "$cmd"
    exit 0 ;;
  Edit|Write|MultiEdit|NotebookEdit)
    p="$(json_str file_path)"; [[ -n "$p" ]] || p="$(json_str notebook_path)"
    [[ -n "$p" ]] || exit 0
    [[ "$p" == /* ]] || p="$cwd/$p"
    pd="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || pd="$(dirname "$p")"
    p="$pd/$(basename "$p")"
    case "$p" in
      "$top/.claude/check.log") refuse "$p is written only by kitchen.sh check: no model writes a receipt (Contract 8)." ;;
      "$top/.claude/procs") refuse "$p is written only by kitchen.sh procs --add (Contract 7)." ;;
      "$top/.claude/served") refuse "$p is written only by kitchen.sh done: the sous, not a cook, says a ticket is served." ;;
      "$main/.claude/grants/"*) refuse "$p is the sous's grant: only kitchen.sh grant, from the main checkout, writes it (Contract 5)." ;;
    esac
    exit 0 ;;
esac
exit 0
