---
name: kitchen
description: Manage the Brigade's stations — the clones (stations/) or worktrees (../<repo>-stations/) where line cooks work. Create them, open the kitchen in tmux (the sous already running /bk:sous-chef, one session per station already running /bk:line-cook; Warp or the OS's terminal as fallbacks), sync clean ones to trunk, and print the status, files-in-flight and rail boards the sous chef reads. Use when the user says "set up stations", "open the kitchen", "open the line cooks", "station status", "what's in flight", "show the rail", "/bk:kitchen".
argument-hint: "setup [-n N] | open [-n N] [-m \"O S\"] [--terminal tmux|warp|native|print] [--bare] [--no-launch] | sync | status | files | rail | board | leaks [--dir D] [--also F] | questions | asks [--add TEXT [--ticket ID] [--gap KIND]] [--answer A3 TEXT] [--filed A3 TEXT] | gaps | decisions | inbox [--add TEXT] | doctor | lessons | sessions [--dir D] | role | sous [--set NAME] | remove"
allowed-tools: Bash, Read
---

# /bk:kitchen

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md` (in an installed plugin that's `…/plugins/cache/claude-code-brigade/bk/<version>/skills/README.md`, never a file in this repo), especially Contract 8 (stations).

This skill is a thin wrapper around one script: **`${CLAUDE_SKILL_DIR}/kitchen.sh`**. Run it
from the main checkout; it reads the flat keys in `.claude/brigade.md`.

## Contents

- [Subcommands](#subcommands)
- [How to run it](#how-to-run-it)
- [Rules](#rules)

## Subcommands

| Command | Does |
|---|---|
| `setup [-n N]` | create N stations (clones in `stations/`, or worktrees in `../<repo>-stations/` when `kitchen_mode: worktree`), add the ignore line to whichever repo contains them (and `.dockerignore` if present), copy `copy_into_stations`, seed a small `settings.local.json`, run `install`. Existing stations are left alone, so `setup -n 4` on a 2-station kitchen adds station-3 and station-4 |
| `open [-n N] [-m "O S"] [--terminal …] [--bare]` | open one `claude` session per station (every station, or the first N with `-n`), **already running `/bk:line-cook`**. A station where a `claude` session is already working is left alone, so after `setup -n 4` a plain `open` starts only the new cooks (`--bare` for a plain session). `-m` takes one model per station in order (O/S/H/F or full names; one value covers all). Terminal defaults to **tmux**: one session `<repo>-brigade` with a `sous` window in the main checkout already running `/bk:sous-chef` (model from `sous_model` in the config, else opus) and one window per station; it prints the attach line (`tmux attach -t <repo>-brigade:sous`). A Mac without tmux gets it from Homebrew; Linux is told the package line. Fallbacks, or on request with `--terminal`: Warp if installed, else the OS's own terminal (Terminal.app on macOS; Windows Terminal, or mintty in Git Bash, on Windows and WSL; the desktop's terminal on Linux), else printed commands; with those you start the sous yourself. `--no-launch` writes the Warp config or shows the native launch without opening anything. Every station it opens gets `.claude/cook` (kept out of git): a launcher that restarts that cook with the same `CLAUDE_CONFIG_DIR`, name, model and permission mode, resuming the last session by default. After a pause (`bk stop` saved a session id in `.claude/sous-session` or a station's `.claude/cook-session`), open resumes that session with `claude --resume <id>` and forgets the id. `BRIGADE_CLAUDE_ARGS` adds flags to every session it starts (the `bk` command sets `--plugin-dir`) |
| `sync` | reset **clean** stations to `origin/<trunk>` (worktrees: detached there). Dirty ones are skipped: a cook may be mid-ticket |
| `status` | branch, dirty/clean, commits ahead per station, plus open PRs against trunk |
| `files` | files in flight per station vs `origin/<trunk>` (committed and uncommitted), plans, and **unmerged migrations** flagged |
| `rail` | the markdown rail's board, computed from ticket frontmatter; `done` tickets hidden. `PRI` is the ticket's priority; `RDY` says whether a free ticket can be taken (`yes`: no open blocker; `spec`: a backlog item that is none of a bug, a chore or a precedent, so it needs a spec first); open blockers follow the title, and one that is no ticket on the rail is marked `?` and holds the ticket |
| `board` | `status`, `files`, `rail`, `questions`, and the record's counts (decisions to file, inbox lines, open asks, gaps to fix) in one snapshot. Run from the main checkout it also writes the snapshot to `.claude/board.md`, a generated file a human can keep open; it's kept out of git through `.git/info/exclude`, so no tracked file changes |
| `leaks [--dir D] [--also F]` | search a checkout's changed files and its branch's commit messages (`D`, default here; plus one extra file `F`, e.g. a PR body) for any test-account secret in `.claude/brigade.local.md`. Prints `file:line`, never the value; exits 1 on a hit. A literal search, skipping values under six characters |
| `role` | `cook <station> <main checkout>` inside a station, else `main <main checkout>`. Every lifecycle skill runs this first |
| `sous [--set NAME]` | print the sous chef's session name, from the main checkout or any station; exits 1 if none is recorded. `--set`, from the main checkout only: record it in `.claude/sous`, kept out of git through `.git/info/exclude`. `/bk:sous-chef` sets it on start; `/bk:line-cook` reads it to check in without waiting for a `[hello]` |
| `questions` | every open question file in `docs.questions` first (shown as `(record)`, each with the tickets it blocks: the head chef's oldest debt), then every unanswered question (`Qn` with no `An`) in the stations' journals: what the cooks, or the head chef, are waiting on |
| `decisions` | every `An (head chef)` answer across all journals (trunk and stations, any depth under `docs.journal`), marked `DUE` (nothing cites it yet), `filed <path>` (a doc under the docs map cites `<ID> An`) or `kept` (the register lists it). The sous runs it at handoff and files the `DUE` rows (Contract 12) |
| `inbox [--add TEXT]` | the inbox, `.claude/inbox.md`, kept out of git: things the head chef said that the record doesn't hold yet. `--add`, from the main checkout only, appends one dated line; without it, lists what's unfiled. The sous adds as it hears, and files at handoff |
| `asks [--add TEXT [--ticket ID] [--gap KIND]] [--answer A3 TEXT] [--filed A3 TEXT]` | the ask log, `.claude/asks.md`, kept out of git: every question the sous put to the head chef, written as it is asked (Contract 12). `--add` appends one and prints its id; `--answer` records the head chef's words; `--filed` records where its fix went. Without options: the open asks, then the answered ones whose gap is not fixed yet, with counts. The writes work from the main checkout only; an unanswered ask can only be filed into `docs.questions`. KIND is `context`, `ruling`, `harness` or `access` |
| `gaps` | the handoff's fourth list: every answered ask not yet filed and every answered question file with no `fix:`, grouped by gap kind with the fix that kind takes |
| `doctor` | checks the ticket files (required fields, a known status, a `kind` on every `BKLG` item, two instances and a `precedent_why:` on a `kind: precedent`, unique ids, blockers that exist) and the docs map (every mapped folder that exists has an `INDEX.md`; nothing under `docs/` is outside the map). Exit 1 on any problem. Run it after adding a doc type, or whenever the rail looks odd |
| `lessons` | lesson lines counted by distinct tickets across all journals (any depth under `docs.journal`, in trunk and every station), checked against the `docs.lessons` register, each marked `watch` / `DUE` / `promoted` (the sous runs it at handoff) |
| `budget [--ticket ID] [--since today\|7d] [--ci] [--json]` | what the kitchen spends (Contract 2): per session and per ticket, tokens (input, output, cache read, cache write), money at list prices (`prices:` in the config overrides), working time per session, brief→served and each phase per ticket, every sub-agent, and with `--ci` the CI minutes of each ticket's PR branch through `gh`. Read from the transcripts Claude Code keeps; served tickets and CI results are kept in `.claude/budget.jsonl`, out of git. `--ticket ID --journal-line [--session NAME]` prints the one line `/bk:open-pr` appends to the journal. Needs node 20+ |
| `sessions [--dir D]` | the Claude Code session transcripts saved for this checkout (or `D`, e.g. a station), newest first, from `$CLAUDE_CONFIG_DIR` (else `~/.claude`). `/bk:feedback` uses it |
| `remove` | delete every station, after showing status and asking for `delete`. Worktree mode uses `git worktree remove`, which refuses a dirty station and keeps every branch |

## How to run it

```bash
"${CLAUDE_SKILL_DIR}/kitchen.sh" <subcommand> [flags]
```

Show the user the script's output as it is; don't reformat the boards into prose. For
`setup`, relay the two warnings it prints (`git clean -fdx`, and tools that don't read
`.gitignore`) and tell the user to commit the `.gitignore` change.

**`open` with no stations yet** means setup hasn't run. Don't stop at the script's error:
check `git cat-file -e origin/<trunk>:.claude/brigade.md`. If the setup isn't pushed,
say that stations clone from `origin/<trunk>` and offer, in one question, to commit + push
the setup, run `setup`, then `open`. If it is pushed, run `setup` then `open`.

**A station dirty right after `setup`** means the install changed tracked files. Show
`git -C <station> diff` and let the human decide (usually: fix the cause in the main
checkout, then `git -C <station> checkout -- .`). Don't brief a cook into it.

`setup` and `remove` change the machine. Run `setup` when asked. Run `remove` only when
the user asks for it by name; the script's own prompt is theirs to answer.

## Rules

- The script never assigns work. Sessions start as line cooks and wait for the sous chef's `[brief]`.
- Never run `sync` to "clean up" a dirty station: dirty is a cook's work in progress.
- Every session must run under the same `CLAUDE_CONFIG_DIR` as the sous, or `ListAgents`
  won't see it. `open` passes the current one through, and writes each station a
  `.claude/cook` launcher that pins it: to restart a cook by hand (after `/exit`), run
  `.claude/cook` in its station to resume, or `.claude/cook "/bk:line-cook"` for a fresh session.
