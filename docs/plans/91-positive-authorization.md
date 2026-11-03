---
ticket: "#91"
title: "Positive authorization: a cook may commit, push or open a PR only on a grant the sous writes (kitchen.sh grant); merge never"
status: done
approved: 2026-11-03
lane: B
created: 2026-11-03
open_questions: none
migration: false
files:
  - plugins/bk/skills/kitchen/kitchen.sh
  - plugins/bk/hooks/guard.sh
  - plugins/bk/hooks/hooks.json
  - tests/guard.test.sh
  - tests/kitchen.test.sh
  - plugins/bk/skills/README.md
  - plugins/bk/skills/line-cook/SKILL.md
  - plugins/bk/skills/implement/SKILL.md
  - plugins/bk/skills/open-pr/SKILL.md
  - plugins/bk/skills/review-task/SKILL.md
  - plugins/bk/skills/sous-chef/SKILL.md
  - plugins/bk/skills/kitchen/SKILL.md
  - plugins/bk/skills/setup/SKILL.md
  - PLAYBOOK.md
  - docs/questions/mechanical-enforcement.md
  - changelog.d/91-positive-authorization.md
  - docs/plans/91-positive-authorization.md
  - docs/plans/INDEX.md
  - docs/journal/91-positive-authorization.md
  - docs/journal/INDEX.md
  - docs/checklists/91-positive-authorization.md
  - docs/checklists/INDEX.md
---

# #91 — Positive authorization

## Why

A cook may today do anything the contract does not forbid, and the never-list (commit
before `[go]`, push to trunk, force-push, `reset --hard`, `clean -fdx`) is prose. A
blocklist of Bash patterns (#69) is the wrong shape: every new route has to be added. The
head chef decided (2026-11-03, in the issue) to invert it: every outward action is
**off by default** and a cook holds only what the sous has written to a file the cook
cannot write. The sous grants `commit`+`push`+`open-pr` with its `[go]`; `merge` is never
granted to a cook.

## Current state

- `plugins/bk/hooks/hooks.json:4` hooks `PreToolUse` for `AskUserQuestion|SendMessage`
  only: no hook sees a Bash call or a file edit.
- `plugins/bk/hooks/guard.sh:29-62` decides "is this a station?" and finds `$main`;
  `:64-82` is one `case "$tool"` with two branches; `:83` is the closing `exit 0`. The
  header (`:3-19`) lists two rules and says the hook is a guardrail, not a wall.
- `plugins/bk/skills/kitchen/kitchen.sh`: `cmd_clear` (`:2163-2230`) types `/clear` after
  its three checks; the dispatcher is `:2776-2783`; the argument parser is `:340-390`
  (`procs` takes its words raw, `:343`, because its arguments are not flags); the header
  usage block is `:93-100` for `clear`/`ship`; `rail_actor` (`:1112`) says whether this
  runs in a station; `exclude_locally` (`:612`) keeps a machine-local file out of git;
  `cmd_sous --set` (`:1448-1456`) is the pattern for "only from the main checkout".
- Prose that says the never-list: `README.md` Contract 5 (`:579-580`, "A cook never
  merges or deploys"), Contract 6's `[go]` row (`:613`), `line-cook/SKILL.md:239`,
  `implement/SKILL.md:142`, `open-pr/SKILL.md:16,18,152`, `review-task/SKILL.md:99`,
  `sous-chef/SKILL.md:494-501`, `PLAYBOOK.md:256-262`.
- `tests/guard.test.sh` feeds the hook the JSON Claude Code sends (`guard()` at `:28`,
  sections at `:56-100`); `tests/kitchen.test.sh` has `rail_suite` (`:1147`), run once per
  kitchen mode, as the pattern for a per-mode suite, and the `clear` tests at `:899-973`.

## Desired end state

- `kitchen.sh grant <station-N> <action>...` (from the main checkout only) writes
  `<main>/.claude/grants/<station-N>`, one action per line, out of git; `--none` removes
  it; `--show` prints what a station holds (a cook may run it for its own station).
  `kitchen.sh clear <station>` removes it too. Actions: `commit`, `push`, `open-pr`.
  `merge` and anything else is refused, naming why.
- In a station the guard refuses `git commit`, `git push`, `gh pr create` unless the
  grant file names that action; `gh pr merge` always; a push to trunk or any force or
  delete or `--all`/`--mirror` push whatever the grant; `git reset --hard` and a
  `git clean` with `-x`/`-X` always. The refusal says which grant is missing and who gives
  it. The main checkout, a solo session and a repo without the Brigade are untouched.
- The guard also refuses a cook's Edit/Write/MultiEdit/NotebookEdit to the station's own
  `.claude/check.log`, `.claude/procs` and `.claude/served` (the sous asked for the first
  two in the brief and added `served`, the marker `kitchen.sh done` will write in #89:
  receipts only their script writes) and to anything under `<main>/.claude/grants/`; a
  Bash command that names `.claude/grants` is refused.
- Verify: `scripts/check.sh` green; each new test goes red with its rule removed.

## Not doing

- #69's SessionStart role hook and its "edits outside the station" rule: they stay in #69.
  This plan's file-tool branch refuses only the three paths above.
- Guarding anything that does not make a commit or leave the station. (Amended by the sous
  on `[approved]`: `git merge` and `git pull` unless `--ff-only`, `rebase`, `cherry-pick`,
  `revert` and `am` make commits on the branch, so before `[go]` they are a commit by
  another route and need the `commit` grant; `--ff-only` forms, and `--abort`/`--quit`,
  pass. See Decisions → How.)
- `gh api` and other routes to a remote. The header says so: patterns catch a mistake,
  not a cook set on it. A real boundary is a branch protection rule and the sous merging.
- A grant per ticket id. The file's life is the ticket's: written with `[go]`, removed
  after `[served]`, and by `clear`. A grant file never holds a ticket.
- Bash writes to `check.log` and `procs` (a redirect, `sed -i`). Edit/Write only, as asked.

## Approach

Three new things and prose that follows them.

1. `kitchen.sh grant`, modelled on `cmd_sous --set` (main checkout only, the file kept out
   of git with `exclude_locally`) and on `cmd_procs` (takes its words raw). `cmd_clear`
   removes a station's file after its checks pass.
2. `guard.sh` gets a Bash branch and a file-tool branch. Station detection is untouched.
   The Bash branch splits the command into command-position segments (separators:
   newline, `; & | ( ) { }`, backtick and both quotes), skips env assignments and
   wrappers (`env command sudo exec nohup time nice xargs builtin then do else !`), and
   looks at the word that runs: `git` (after its global options, so `git -C d commit` is
   seen) or `gh` (after `-R`). A quoted string that *starts* with `git push` therefore
   counts; the refusal text explains and the cook rewords. That false positive is the
   price of seeing `bash -c "git push"` and `$(git push)`.
3. Prose: Contract 5 states the grant rule; the skills that named the never-list name the
   grant; the sous grants with `[go]`, revokes at `[served]`.

The **hook's input** is read with one new helper that pulls the first JSON string value
of a key out of stdin (no jq, as today), with `\"` and `\n` undone; if it can't read the
field the call passes, as every rule in the file does.

## Decisions

### Changes the ticket

None.

### How

- **Where the checks run: inside `guard.sh`, one file.** Hooks already carry the station
  test; a second script would repeat it. New code goes in at three places only (see the
  line list in Phase 2), so #85's rewrite of lines 29-62 does not touch it.
- **Grant file format: the action words, one per line, nothing else.** `grep -qxF`
  reads it in the guard with no parsing. Written whole each time (`tmp` + `mv`): a second
  `grant` replaces the set, it never appends.
- **`merge` is not an action word.** `kitchen.sh grant station-1 merge` is refused with
  "the sous ships" so there is no way to write it; `gh pr merge` is refused in the guard
  whatever the file says.
- **Revoke at `[served]`; re-grant for the "behind" loop.** The issue says `--none` after
  `[served]`. The line-cook loop (`line-cook/SKILL.md:194-196`) has the sous ask a cook to
  bring trunk in and push again: that needs `commit` and `push`, so the sous's request
  carries `kitchen.sh grant station-N commit push` first. No rule changes; the sous's
  skill says it.
- **`kitchen.sh grant --show` prints one line, `station-N: commit push open-pr`** (or
  `station-N: none`); from the main checkout with no station it prints one line for every
  station. `open-pr` reads it as its first step.
- **A cook with no grant sends `[gate] <ID> no grant on record: <action>`** (not a
  question: no commis, no `Qn`), like `no [approved] on record`. Added to Contract 6's
  `[gate]` row.
- **Commits by another route need the `commit` grant (the sous's amendment).** `git merge`
  and `git pull` without `--ff-only`, `rebase`, `cherry-pick`, `revert` and `am` (and
  `commit --amend`, which is `git commit`) are refused without it; `--ff-only` passes for
  `merge` and `pull`, and `--abort`/`--quit` pass for all of them (they end an operation,
  they make no commit). A consequence the sous's brief already accepts: bringing main in
  before `[go]` works only as `git merge --ff-only origin/main` (a branch with no commits
  of its own yet); a branch that has diverged waits for a grant.
- **Trunk name in the guard** is read as `kitchen.sh` does (`:277-279`): the config's
  `trunk:`, else `origin/HEAD`, else `main`.
- **A bare `git push` (or `HEAD`) is a push to trunk when the station's branch is trunk.**
  Otherwise the branch is not named, and the grant decides.
- **`git clean`: refused when any short flag cluster contains `x` or `X`** (`-fdx`,
  `-xfd`, `-fdX`, `-x`). `git clean -fd` and `-n` pass.
- **`-f` and `-d` in a short cluster on `git push`** (`-f`, `-fu`, `-d`) count as force
  or delete; `--force*`, `--delete`, `--all`, `--mirror`, `--prune` and a `+` refspec do
  too. `-u` and `--set-upstream` do not.
- **Pre-filter:** a Bash call whose text has no `git`, `gh` or `grants` in it leaves the
  hook at once, before the station test, so ordinary commands cost nothing.
- **Tests:** the hook is fed JSON with a `command` or `file_path`; two helpers escape the
  string for JSON. Both kitchen modes are covered (`$S` clone, `$WS` worktree). The
  refusals were mutated on copies (lesson `mutate-a-copy`, #86) and the result goes in
  the journal.
- **No new dependency** (`jq`, `python`): bash 3.2 and `sed -E`, which macOS and Linux
  both have. No arrays in the guard (an empty array under `set -u` fails on bash 3.2).

## Protected paths

None. Everything in `files:` sits outside the root `.claude/`; `plugins/bk/.claude-plugin/`
is not touched.

## Phase 1: kitchen.sh grant, and clear revokes

**Status:** Done (kitchen.sh: GRANT_ARGS, cmd_grant, grant_file/grant_line, usage header, dispatcher, revocation in cmd_clear and cmd_done; tests/kitchen.test.sh: grant section of 24 tests plus clear/done assertions; tests/kitchen.test.sh 667/667 green)

### Changes

#### `plugins/bk/skills/kitchen/kitchen.sh:329` (edit)
Add the raw-words array beside `PROCS_ARGS`:
```bash
GRANT_ARGS=()     # everything after `grant`: station, actions, --none, --show
```

#### `plugins/bk/skills/kitchen/kitchen.sh:343` (edit)
Beside the `procs` line (line 343):
```bash
if [[ "$CMD" == grant ]]; then GRANT_ARGS=("$@"); set --; fi
```

#### `plugins/bk/skills/kitchen/kitchen.sh:93-100` (edit, usage header)
After the `clear` entry, before `ship`:
```
#   kitchen.sh grant <station-N> <commit|push|open-pr>...
#                                         the sous lets a cook commit, push and open a PR
#                                         (Contract 5): writes .claude/grants/<station-N> in
#                                         the main checkout, out of git, replacing what was
#                                         there. The guard refuses the cook's git commit, git
#                                         push and gh pr create without it. merge is never an
#                                         action: the sous ships. Refused from a station
#   kitchen.sh grant <station-N> --none   take every grant away (the sous does it at [served];
#                                         clear does it too)
#   kitchen.sh grant --show [station-N]   what a station holds: "station-N: commit push open-pr"
#                                         or "station-N: none". A cook sees its own; the main
#                                         checkout sees every station
```

#### `plugins/bk/skills/kitchen/kitchen.sh:2163` (edit: `cmd_clear`) and new `cmd_grant` above `cmd_clear`
In `cmd_clear`, after the "3. nothing open" block ends (just before the `# act:` comment),
a station's grant goes:
```bash
  [[ "$who" == sous ]] || rm -f "$ROOT/.claude/grants/$who"
```
New function (placed just above the `# ---…` banner of `cmd_clear`):
```bash
# ---------------------------------------------------------------------------
# grant — positive authorization (Contract 5). A cook may commit, push or open a PR only
# when the sous has written that action for its station: .claude/grants/<station> in the
# main checkout, one action per line, kept out of git. hooks/guard.sh reads it. Written only
# from the main checkout; a station can read its own with --show. merge is never an action.
# ---------------------------------------------------------------------------
GRANT_ACTIONS="commit push open-pr"
grant_file() { printf '%s/.claude/grants/%s' "$ROOT" "$1"; }
grant_line() {  # grant_line <station> → "station-N: commit push open-pr" or "station-N: none"
  local f; f="$(grant_file "$1")"
  if [[ -s "$f" ]]; then printf '%s: %s\n' "$1" "$(tr '\n' ' ' < "$f" | sed 's/ $//')"; else printf '%s: none\n' "$1"; fi
}
cmd_grant() {
  local act=set st="" a me want="" d acts=""
  set -- "${GRANT_ARGS[@]+"${GRANT_ARGS[@]}"}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --show) act=show ;;
      --none) act=none ;;
      station-*) st="$1" ;;
      commit|push|open-pr) acts="$acts $1" ;;
      merge) echo "merge is never granted to a cook: the sous merges (kitchen.sh ship), or the head chef with gates.merge: head-chef." >&2; return 1 ;;
      -h|--help) usage ;;
      *) echo "Unknown grant action: $1 (commit, push, open-pr)" >&2; return 1 ;;
    esac
    shift
  done
  me="$(rail_actor)"
  if [[ "$act" == show ]]; then
    if [[ -n "$me" ]]; then
      [[ -z "$st" || "$st" == "$me" ]] || { echo "A cook reads its own grants ($me); $st is the sous's to read." >&2; return 1; }
      grant_line "$me"; return 0
    fi
    if [[ -n "$st" ]]; then [[ -e "$KITCHEN/$st/.git" ]] || { echo "No such station: $st" >&2; return 1; }; grant_line "$st"; return 0; fi
    while IFS= read -r d; do grant_line "$(basename "$d")"; done < <(stations)
    return 0
  fi
  if [[ -n "$me" ]]; then
    echo "Only the sous grants, from the main checkout ($ROOT_REAL): a cook asks for it with its handoff and waits for [go]." >&2; return 1
  fi
  [[ -n "$st" ]] || { echo "Usage: kitchen.sh grant <station-N> <commit|push|open-pr>... | <station-N> --none | --show [station-N]" >&2; return 1; }
  [[ -e "$KITCHEN/$st/.git" ]] || { echo "No such station: $st" >&2; return 1; }
  if [[ "$act" == none ]]; then
    [[ -z "$acts" ]] || { echo "grant --none takes no actions." >&2; return 1; }
    rm -f "$(grant_file "$st")"; echo "$st: none"; return 0
  fi
  [[ -n "$acts" ]] || { echo "Usage: kitchen.sh grant $st <commit|push|open-pr>... (or --none)" >&2; return 1; }
  mkdir -p "$ROOT/.claude/grants"; exclude_locally .claude/grants
  for a in $GRANT_ACTIONS; do case " $acts " in *" $a "*) want="$want$a"$'\n' ;; esac; done
  printf '%s' "$want" > "$(grant_file "$st").tmp" && mv "$(grant_file "$st").tmp" "$(grant_file "$st")"
  grant_line "$st"
}
```

#### `plugins/bk/skills/kitchen/kitchen.sh:2778-2782` (edit, dispatcher)
Add `grant) cmd_grant ;;` on the `procs) cmd_procs ;;` line's neighbour.

#### `tests/kitchen.test.sh` (new section after the `clear` tests, ~`:973`, and a `grant_suite` run in both modes)
`grant_suite <label> <app repo> <stations dir>`, same shape as `rail_suite` (`:1147`):
- `grant station-1 commit push open-pr` from the main checkout prints
  `station-1: commit push open-pr` and writes the file with three lines;
- a second `grant station-1 commit` **replaces** it (`station-1: commit`), actions in
  canonical order whatever order they were typed;
- `grant station-1 --none` removes it (`station-1: none`); `--none` with actions refuses;
- `merge` refused, message names "the sous"; an unknown action refused; an unknown
  station refused; `grant station-1` with no actions refused;
- from `cd $S1`: `grant station-1 commit` refused, nothing written; `--none` refused;
  `--show` prints that station's own line; `--show station-2` refused;
- from main, `--show` with no station prints a line per station;
- the file is in `.git/info/exclude`'s reach: `git status --porcelain` stays clean after a
  grant;
- `clear` empties it: reuse the idle-cook setup (`:933-937`), grant first, run `clear`,
  the file is gone; and a refused `clear` (busy cook, `:920`) leaves it.

### Success criteria
- [x] `bash -n plugins/bk/skills/kitchen/kitchen.sh && shellcheck plugins/bk/skills/kitchen/kitchen.sh` clean (no note on a line this phase added; the file's older notes are #75's)
- [x] `tests/kitchen.test.sh` green, the new grant tests among them (one worktree kitchen: clone mode is gone since #85)
- [ ] with `cmd_grant`'s station refusal removed, the "refused from a station" tests go red; with the `rm -f` in `cmd_clear` removed, the "clear empties it" test goes red
- [ ] Manual: in a throwaway Brigade repo, `kitchen.sh grant station-1 push commit`, then `kitchen.sh grant --show` → `station-1: commit push`

## Phase 2: the guard, and the hook matcher

**Status:** Done (guard.sh: header, Bash pre-filter, helpers, Bash and file-tool branches; hooks.json matcher; tests/guard.test.sh: 347 tests, the new ones run for a station and a legacy-config station; mutations still owed in Phase 4)

### Changes

Every existing `guard.sh` line this phase changes, by line at `025fb38`:

| Line | Change |
|---|---|
| 3-19 | header comment: "Two rules" becomes four (the two new ones named), and "Everything else passes" gains the grant sentence. Text only |
| 24 | none. A new line is inserted **after** it (the Bash pre-filter) |
| 62 | none. New helper block inserted **after** it (before `case "$tool" in`) |
| 82 | `esac` stays; two new branches are inserted **before** it |
| 83 | none |

Lines 25-62 (the station and main detection) are not touched: #85 rewrites them.

#### `plugins/bk/hooks/guard.sh:24` (edit: insert after) — the pre-filter
```bash
# a Bash call that names none of git, gh or the grants folder has nothing to check
if [[ "$tool" == Bash ]]; then case "$input" in *git*|*gh*|*grants*) ;; *) exit 0 ;; esac; fi
```

#### `plugins/bk/hooks/guard.sh:62` (edit: insert after) — helpers
```bash
station="$(basename "$top")"
grant_file="$main/.claude/grants/$station"
refuse() { echo "Brigade: $*" >&2; exit 2; }
granted() { [[ -f "$grant_file" ]] && grep -qxF "$1" "$grant_file"; }
need() {  # need <action> <what was run>
  granted "$1" && return 0
  refuse "you are a line cook in $station and hold no grant for \`$1\`, so \`$2\` is refused (Contract 5). Only the sous grants it, with its [go]. Finish your handoff and wait; kitchen.sh grant --show says what you hold. A reworded command that does not start with \`$2\` is not the problem: a quoted string that starts with it counts."
}
json_str() {  # json_str <key> → the first string value of "key" in the hook input, JSON escapes undone
  printf '%s' "$input" | sed -nE 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -1 \
    | sed -e 's/\\"/"/g' -e 's/\\t/ /g' -e 's/\\n/\
/g' -e 's/\\\\/\\/g'
}
trunk="$(sed -n '2,/^---$/{s/^trunk:[[:space:]]*//p;}' "$main/.claude/brigade.md" | head -1 | sed 's/[[:space:]]*#.*$//; s/^"//; s/"$//')"
trunk="${trunk:-$(git -C "$main" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')}"
trunk="${trunk:-main}"

guard_push() {
  local a n=0 spec dst cur
  for a in "$@"; do
    case "$a" in
      --force*|--delete|--mirror|--all|--prune) refuse "a force, delete, --all or --mirror push is refused in a station whatever you hold (Contract 5)." ;;
      --*) ;;
      -*) if [[ "$a" =~ ^-[A-Za-z]*[fd] ]]; then refuse "a force or delete push (\`$a\`) is refused in a station whatever you hold (Contract 5)."; fi ;;
      +*) refuse "a \`+\` refspec forces the push; it is refused in a station whatever you hold (Contract 5)." ;;
      *) n=$((n+1))
         if (( n > 1 )); then
           spec="$a"; dst="${spec##*:}"; dst="${dst#refs/heads/}"
           [[ "$dst" == "$trunk" ]] && refuse "a push to $trunk is refused in a station whatever you hold: the sous merges (Contract 5)."
           [[ "$spec" == HEAD ]] && n=1
         fi ;;
    esac
  done
  if (( n < 2 )); then   # no refspec, or HEAD: the branch you stand on goes
    cur="$(git -C "$cwd" branch --show-current 2>/dev/null)"
    [[ "$cur" == "$trunk" ]] && refuse "this station stands on $trunk, so \`git push\` would push to it; branch first (Contract 5)."
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
    merge|pull|rebase|cherry-pick|revert|am)   # commits by another route (sous's amendment on [approved])
      for a in "$@"; do
        case "$a" in --abort|--quit) return 0 ;; --ff-only) [[ "$sub" == merge || "$sub" == pull ]] && return 0 ;; esac
      done
      need commit "git $sub" ;;
    push) guard_push "$@" ;;
    reset) for a in "$@"; do [[ "$a" == --hard ]] && refuse "git reset --hard is refused in a station (Contract 5)."; done ;;
    clean) for a in "$@"; do if [[ "$a" =~ ^-[A-Za-z]*[xX] ]]; then refuse "git clean with -x or -X is refused in a station: it deletes ignored files, and a kitchen keeps its state there (Contract 5)."; fi; done ;;
  esac
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
}
guard_command() {
  local sep segs line base
  sep=$';&|(){}`"\''
  segs="$(printf '%s' "$1" | tr "$sep" '\n')"
  while IFS= read -r line; do
    set -f; set -- $line; set +f
    while [[ $# -gt 0 ]]; do
      case "$1" in
        [A-Za-z_]*=*|env|command|sudo|exec|nohup|time|nice|xargs|builtin|then|do|else|'!'|-*) shift ;;
        *) break ;;
      esac
    done
    [[ $# -gt 0 ]] || continue
    base="${1##*/}"; shift
    case "$base" in git) guard_git "$@" ;; gh) guard_gh "$@" ;; esac
  done <<< "$segs"
}
```

#### `plugins/bk/hooks/guard.sh:82` (edit: insert before `esac`) — the two branches
```bash
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
      "$top/.claude/check.log") refuse "$p is written only by kitchen.sh check: no model writes a receipt (Contract 3)." ;;
      "$top/.claude/procs") refuse "$p is written only by kitchen.sh procs --add (Contract 7)." ;;
      "$top/.claude/served") refuse "$p is written only by kitchen.sh done (#89): the sous, not a cook, says a ticket is served." ;;
      "$main/.claude/grants/"*) refuse "$p is the sous's grant: only kitchen.sh grant, from the main checkout, writes it (Contract 5)." ;;
    esac
    exit 0 ;;
```

#### `plugins/bk/hooks/hooks.json:4` (edit)
`"matcher": "AskUserQuestion|SendMessage|Bash|Edit|Write|MultiEdit|NotebookEdit"`.

#### `tests/guard.test.sh` (edit: helpers after `reason()` at `:35`; sections before the closing `echo` at `:98`)
Two helpers: `gbash <cwd> <command>` and `gfile <cwd> <tool> <path>` that JSON-escape (`\` and
`"`) and send `{"cwd":…,"tool_name":"Bash","tool_input":{"command":"…","description":"x"}}`,
printing the exit code like `guard()`. A `grants <main> <station> <actions…>` helper writes
or removes `<main>/.claude/grants/<station>`. Sections, each run for `$S` (main `$A`) and
`$WS` (main `$B`):
- **no grant file:** `git commit -m x`, `git push origin br`, `gh pr create --title x`
  refused (2), reason names `commit` / `push` / `open-pr`, the sous and `[go]`;
- **granted:** `commit` alone → `git commit` passes, `git push` still refused; all three →
  each passes; a grant for `push` only → `git commit` refused;
- **always refused with every grant:** `git push origin main`, `git push origin HEAD:main`,
  `git push origin HEAD:refs/heads/main`, `git push origin :main`, `git push --force`,
  `git push -f`, `git push -fu origin x`, `git push --force-with-lease`, `git push origin +x`,
  `git push --all`, `--mirror`, `--delete origin x`, `gh pr merge 12`, `gh pr merge --auto 12`,
  `git reset --hard`, `git reset --hard origin/main`, `git clean -fdx`, `git clean -xfd`,
  `git clean -fdX`; and `git push` with the station on trunk (checked out in a scratch clone);
- **pass-through with every grant:** `git push -u origin feature`, `git push origin
  feature:feature`, `git merge --ff-only origin/main`, `git pull --ff-only`, `git merge --abort`,
  `git rebase --abort`, `git reset --soft HEAD~1`, `git reset HEAD file`, `git clean -fd`,
  `git clean -n`;
- **commits by another route, no grant:** `git merge origin/main`, `git pull`, `git pull
  --rebase`, `git rebase origin/main`, `git cherry-pick abc`, `git revert abc`, `git am x.patch`,
  `git commit --amend`: refused (2), reason names `commit`; with `commit` granted each passes;
- **found in a wrapper:** `cd x && git commit -m y`, `git -C /tmp commit -m y`, `git -c a=b
  push origin x`, `GIT_X=1 git commit`, `env git commit`, `bash -c "git commit -m y"`, `echo
  $(git push origin x)`, `sudo git commit`, a newline-separated two-liner, `/usr/bin/git
  commit`, `gh -R a/b pr create`, `/opt/homebrew/bin/gh pr merge 1`: refused with no grant;
- **not a git or gh call at command position:** `git status`, `git diff`, `git log
  --grep "git push"`, `git add -A`, `gh pr view 1`, `gh issue view 91`, `gh pr checks`,
  `kitchen.sh rail claim '#91' todo`, `echo hello`, `ls .claude`, and a `kitchen.sh grant
  --show` pass with no grant;
- **the grants folder:** `cat ../app/.claude/grants/station-1` and `echo push >
  /x/.claude/grants/station-1` are refused (Bash); `Write` to `$A/.claude/grants/station-1`
  refused;
- **receipts:** `Write`, `Edit`, `MultiEdit` to `<station>/.claude/check.log` and
  `<station>/.claude/served`, and a
  `NotebookEdit` `notebook_path` aimed at `.claude/procs`, are refused; a relative path
  from a subfolder that resolves to them is refused; `Write` to `<station>/src/x.txt`,
  `<station>/.claude/grilling` and `<station>/.claude/here` pass;
- **left alone:** the same refusable commands in the main checkout (`$A`, `$B`), in a repo
  without the Brigade (`$P`), in the nested repo, the `claude --worktree` folder, the
  `scratch` clone and `station-9` pass (0); `Write` to `$A/.claude/check.log` from the main
  checkout passes;
- **garbage:** a Bash call whose command cannot be read passes; a command with an
  unbalanced quote passes or refuses cleanly (never crashes: exit is 0 or 2).

### Success criteria
- [x] `bash -n` and `shellcheck -S info` clean on `guard.sh` (the test file keeps the SC2016/SC2015 notes its older lines already had)
- [ ] `python3 -c 'import json;json.load(open("plugins/bk/hooks/hooks.json"))'`-style check by `scripts/check.sh` step 3 passes
- [x] `tests/guard.test.sh` green in a station and a legacy-config station (347/347)
- [ ] each of these, applied to a **copy** of `guard.sh` outside the checkout, turns named tests red: (a) `need()` returns 0, (b) `guard_push`'s trunk test removed, (c) the force case removed, (d) `gh pr merge` removed, (e) `reset`/`clean` removed, (f) the pre-filter inverted, (g) the file-tool branch removed, (h) `granted()` always true
- [ ] Manual (a live check I owe in the journal, not a criterion the gate can see): `claude --plugin-dir ./plugins/bk` in a throwaway Brigade station: `git commit` refused with the grant text; `kitchen.sh grant` from main; the same commit passes

## Phase 3: the contract and the skills

**Status:** Done (README Contracts 3, 5, 6, 7, 8 and 'Hooks that back this up'; line-cook, implement, open-pr, review-task, sous-chef, setup, kitchen skills; PLAYBOOK; docs/questions row; changelog fragment, minor; `setup/SKILL.md` added to files: after the consistency read found its CLAUDE.md text)

### Changes

#### `plugins/bk/skills/README.md:579-580` (edit: Contract 5)
After the gate table, replace the two lines "A cook that receives … no message stands in
for them." with: the **grant rule** (every outward action is off by default; the grant is
`<main>/.claude/grants/<station>`, written only by `kitchen.sh grant` from the main
checkout; the sous grants `commit push open-pr` with `[go]` and takes them away with
`--none` after `[served]` and when it asks for a second push; `clear` takes them too;
`merge` and deploy are never granted), then the existing "chef said go" sentence, kept.
The cook's never-list sentence "never merges or deploys" stays beside it.

#### `plugins/bk/skills/README.md:613-614` (edit: Contract 6)
`[go]` row: "commit approval after the pass; the sous runs `kitchen.sh grant <station>
commit push open-pr` first, so the guard lets the cook commit, push and open the PR".
`[served]` row: add "the sous then runs `kitchen.sh grant <station> --none`".
`[gate]` row (`:605`): add "or the refusal `no grant on record: <action>`" next to `edit denied`.

#### `plugins/bk/skills/README.md:300` (edit: Contract 3's files table, after the check-log row)
New row for `.claude/grants/<station>` (main checkout, kept out of git, one action per line,
written only by `kitchen.sh grant`; read by `hooks/guard.sh`). The check-log row gains
"the guard refuses a cook's Edit/Write to it", and Contract 7 Processes paragraph (`:654-668`) gains the same for `.claude/procs`.

#### `plugins/bk/skills/README.md:1018-1027` (edit: "Hooks that back this up")
Name the new rules: Bash (`git commit`, `git push`, `gh pr create` need a grant; trunk
pushes, force pushes, `gh pr merge`, `reset --hard` and `clean -x` never), and the
file-tool refusals. The closing "guardrails against a slip, not a wall" stays, with the
routes it does not see (`gh api`, a quoted string that starts with `git push`).

#### `plugins/bk/skills/line-cook/SKILL.md:239` (edit: Things you never do)
"Commit before `[go]`, force-push, or push to trunk." becomes "Commit, push or open a PR
without a grant (`kitchen.sh grant --show` says what you hold; the sous writes it with
`[go]`), push to trunk, force-push, or merge." The loop's step 9 (`:188`) gains "the sous's
`[go]` comes with the grant"; step 10 (`:194-196`) gains "the sous re-grants `commit push`
when it asks you to bring trunk in". A refused hook call is a `[gate] <ID> no grant on
record: <action>` (not a question: no commis).

#### `plugins/bk/skills/implement/SKILL.md:142` (edit)
"Don't commit, push or open a PR here. Never `reset --hard` or force-push." → "...: a
cook holds no grant yet, and the guard refuses them."

#### `plugins/bk/skills/open-pr/SKILL.md:16,18,152` (edit)
Line 16: first step for a cook: `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" grant --show`
must list `commit`, `push` and `open-pr`; if one is missing, stop and send `[gate] <ID> no
grant on record: <action>`. Line 18: the go is the sous's `[go]` **and** the grant. Line
152 (`## Never`): add "`gh pr merge`" and "a command the guard refuses: don't look for
another way".

#### `plugins/bk/skills/review-task/SKILL.md:99` (edit)
"A cook never commits, pushes or edits a ticket file from this skill." gains "(it holds no
grant before `[go]`)".

#### `plugins/bk/skills/sous-chef/SKILL.md:494` (edit) and `:496-501`, `:525`, `:539`
Step 5: "When clean, run `kitchen.sh grant station-N commit push open-pr`, then send `[go]`
(the commit approval; the guard lets the cook commit, push and open the PR from now)."
After the PR opens (`:496`): `kitchen.sh grant station-N --none`. In End of shift step 1
(`:525`): a "behind or conflicting" request first re-grants `commit push`, then asks. Step
3 (`:539`): `clear` removes the grants too.

#### `plugins/bk/skills/kitchen/SKILL.md:35` (edit: command table) and the `argument-hint`
New row `grant <station-N> <actions>... | <station-N> --none | --show [station-N]` after
`clear`; add `grant` to `argument-hint`. `ship` and `clear` rows are untouched except
`clear`'s: "it also removes the station's grants".

#### `PLAYBOOK.md:256-262` (edit)
Steps 7-9: the sous grants with `[go]`, revokes at `[served]`.

#### `docs/questions/mechanical-enforcement.md` (edit: Taken on, rows 3 and 4)
New "Taken on" rows for the Bash part of row 4 (replaced by grants, #91) and the receipts
part of row 3 (`check.log`, `procs`), pointing at `guard.sh`; the "Still open" line loses
nothing it did not take.

#### `changelog.d/91-positive-authorization.md` (new)
`level: minor`, then a short paragraph: a cook can now commit, push or open a PR only on a
grant the sous writes with its `[go]`; trunk pushes, force pushes, merges, `reset --hard`
and `clean -x` are refused; nothing for you to do unless you edit a station's `.claude/`
by hand.

### Success criteria
- [x] `grep -rn "Commit before \`\[go\]\`" plugins/bk` prints nothing
- [x] consistency read by a read-only sub-agent: it listed review-task:93, implement:119/:16, line-cook:187/:176, PLAYBOOK:442, setup:218, kitchen/SKILL:28 and a tension about `rail claim`; all fixed or answered in Contract 5 (a cook's `rail claim`/`move` run inside the script, so need no grant). create-plan:149 and docs/the-names.md:25 describe the solo sign-off, which is still true, and were left
- [x] `kitchen.sh index` up to date; `scripts/release-check.sh` accepts the fragment; `kitchen.sh scope` has 0 outside

## Phase 4: the gate

**Status:** Done (gate: one run red on a shellcheck SC2034 in the new test, fixed; the receipt of the final tree is the last act before the handoff; 22 mutations red, journal)

### Changes
Run `scripts/check.sh` once (tell the sous before: four stations share the machine); do
the Phase 2 mutations; fill in the checklist; no further code.

### Success criteria
- [x] `scripts/check.sh` green (`kitchen.sh check`, once per tree): the receipt `kitchen.sh check --receipt` prints
- [x] the mutation table (journal) shows every mutation red, controls green
- [x] nothing left running that I started (`procs` register empty; the scan lists only this session's own MCP servers and `caffeinate`)

## Re-anchored on fbd3ba1 (after #85, #90, #92 merged)

Read this section as the current line list: where it differs from the phases above, it wins.
The phases were written against `025fb38`; their line numbers are stale, their anchors
(named functions, "after the station test", "before the `esac`") still hold.

- **Clone mode is gone (#85).** Stations are worktrees of the main checkout, always. The
  guard's station test is now `guard.sh:29-56`; the tool parse is `:22-27`; the `case
  "$tool"` is `:58-76` with `esac` at `:76` and the closing `exit 0` at `:77`. Insert points:
  the Bash pre-filter after `:24`, the helpers after `:56`, the two branches before `:76`.
  Lines changed: `:3-19` (header text) only. `tests/guard.test.sh` now has `$S` (a worktree
  station of `$A`, `$TMP/app-stations/station-1`) and `$WS` (a station of a config that
  still says `kitchen_mode: worktree`, main `$B`); the new sections run for both, which is
  the "both modes" of the plan's test list. There is no clone-mode suite left to extend.
- **`kitchen.sh` (3120 lines now):** `PROCS_ARGS` is `:350` and its raw-words line `:364`
  (add `GRANT_ARGS` and its line beside them); `exclude_locally` `:639`; `rail_actor` `:1338`;
  `cmd_sous` `:1674`; `cmd_clear` `:2389` (the `# act:` comment is the insert point for the
  grant removal); `cmd_ship` `:2458`; **`cmd_done` `:2501` is new and also removes the
  grant**: `rm -f "$ROOT/.claude/grants/$who"` goes beside its `for f in go check.log …`
  loop, since `done` is what the sous runs after the merge and before `clear`; `cmd_procs`
  `:2834`; dispatcher `:3112-3119` (`done`, `scope` are there; add `grant`). The usage header
  has `clear` at `:~106` and `done` after `ship`; the `grant` entry goes between `clear` and
  `ship`. `cmd_scope` `:1082` is new: **`kitchen.sh scope` runs before `[handoff]`**, and
  `files:` above lists every path this plan writes.
- **`tests/kitchen.test.sh` (1859 lines):** `clear` section `:902`, `done` section `:1017`,
  `rail_suite` `:1332` run once for `worktree` (`:1462`), `procs` section `:1545`. The
  `grant_suite` follows `rail_suite`'s shape and runs once; the `clear` and `done` tests each
  gain "the grant is gone" assertions (a `done` that removes it, a refused one that keeps it).
- **README:** Contract 5's gate table ends at `:593` ("the chef said go"); Contract 6 rows
  `[gate]` `:619`, `[go]` `:627`, `[served]` `:628`; Contract 3's check-log row `:303`;
  Contract 7 `Processes` `:668`; Contract 8's receipt paragraph `:735-744`, whose last two
  lines ("until a guard refuses an Edit or Write on `.claude/check.log`, that is a rule, not a
  lock") **become true with this PR and are rewritten**: "the guard refuses an Edit or Write
  on `.claude/check.log`"; "Hooks that back this up" `:1046`.
- **Skills:** `line-cook/SKILL.md` step 9 `:190`, step 10 `:196-201`, never-list `:244`;
  `implement/SKILL.md:142`; `open-pr/SKILL.md` `:16`, `:18`, `## Never` `:163-165` (its push
  gate now also needs a clean status and a receipt for `HEAD^{tree}`: the grant check is the
  step before it); `review-task/SKILL.md:102`; `sous-chef/SKILL.md` `[go]` `:500`, after the
  PR opens `:503`, End of shift `:528`, the clear step `:556` (End of shift is now ship,
  done, reap, clear: the grant goes away at `done` and `clear`); `kitchen/SKILL.md` table
  rows `clear` `:38`, `done` `:28`, `ship` `:40`; `PLAYBOOK.md` `:255-261`.
- **Deviation from the "quoted `git push` counts" call, in the direction of fewer false
  refusals (found by the tests):** a quote is no longer a separator, so `git log --grep
  "git push"`, `git grep "git commit"`, `kitchen.sh here --note "git push done"` and `gh issue
  comment --body "…"` pass. The only quoted text read as a command is the script after
  `sh -c` / `bash -c` / `zsh -c` / `eval` (the sed in `guard_command` puts a line break after
  the opening quote), and quote characters are then deleted. `ssh host "git push"` and other
  quoted-command routes pass: the header says guardrail, not wall. The journal tells the sous.
  (Superseded at the pass: the awk `split_command` now keeps quoted text whole, skips heredoc
  bodies, joins backslash-newline, and reads `$( )` and backticks inside double quotes; the
  wrapper loop skips option values for env, sudo, nice, xargs, timeout and strips a leading
  backslash. The `sed` line described above is gone.)
- **The guard's file-tool list is `check.log`, `procs`, `served`** (the sous's last word),
  plus anything under `<main>/.claude/grants/`.

## Sequencing

#85 (station-2) rewrites `guard.sh:29-62` and much of `kitchen.sh`; #90 and #92 queue
behind it. This plan is written against `025fb38`. I do not start `/bk:implement` on the
sous's `[approved]` until the sous says it is my turn; then `git merge origin/main` and
every `file:line` above is re-read before the first edit (the guard insertions are anchored
to the `case "$tool"` block and the helper insertion to "after the station test", not to
line numbers, so a shifted file does not change what goes where).

## Testing

`tests/guard.test.sh` (hook, JSON in, exit code out) and `tests/kitchen.test.sh` (the
script, both modes, throwaway repos). No `bin/bk` change: `bk` forwards `grant` to
`kitchen.sh` untouched.

## References

- Issue #91; #69 (the Bash blocklist this replaces; the SessionStart hook stays there);
  head chef 2026-11-03 "Lets do it then."
- `plugins/bk/skills/README.md` Contracts 3, 5, 6, 7; `docs/questions/mechanical-enforcement.md` rows 3-4
- Pattern for "main checkout only": `kitchen.sh:1448-1456` (`cmd_sous --set`); raw-words
  command: `kitchen.sh:343,2548` (`procs`); per-mode suite: `tests/kitchen.test.sh:1147`
- Lessons applied: `mutate-a-copy`, `trap-deferred-by-child`, `bsd-sed-no-word-boundary` (#86)
