---
name: kitchen
description: Manage the Brigade's stations — the clones (stations/) or worktrees (../<repo>-stations/) where line cooks work. Create them, open one Claude session per station already running /bk:line-cook (Warp, else the OS's own terminal, else printed commands), sync clean ones to trunk, and print the status, files-in-flight and rail boards the sous chef reads. Use when the user says "set up stations", "open the kitchen", "open the line cooks", "station status", "what's in flight", "show the rail", "/bk:kitchen".
argument-hint: "setup [-n N] | open [-n N] [-m \"O S\"] [--terminal warp|native|tmux|print] [--bare] [--no-launch] | sync | status | files | rail | board | leaks [--dir D] [--also F] | questions | lessons | sessions [--dir D] | role | remove"
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
| `open [-n N] [-m "O S"] [--terminal …] [--bare]` | open one `claude` session per station (every station, or the first N with `-n`), **already running `/bk:line-cook`**. A station where a `claude` session is already working is left alone, so after `setup -n 4` a plain `open` starts only the new cooks (`--bare` for a plain session). `-m` takes one model per station in order (O/S/H/F or full names; one value covers all). Terminal defaults to Warp if installed, else the OS's own terminal (Terminal.app on macOS; Windows Terminal, or mintty in Git Bash, on Windows and WSL; the desktop's terminal on Linux), else printed commands. tmux only when asked: `--terminal tmux`. `--no-launch` writes the Warp config or shows the native launch without opening anything. Every station it opens gets `.claude/cook` (kept out of git): a launcher that restarts that cook with the same `CLAUDE_CONFIG_DIR`, name, model and permission mode, resuming the last session by default |
| `sync` | reset **clean** stations to `origin/<trunk>` (worktrees: detached there). Dirty ones are skipped: a cook may be mid-ticket |
| `status` | branch, dirty/clean, commits ahead per station, plus open PRs against trunk |
| `files` | files in flight per station vs `origin/<trunk>` (committed and uncommitted), plans, and **unmerged migrations** flagged |
| `rail` | the markdown rail's board, computed from ticket frontmatter; `done` tickets hidden. `PRI` is the ticket's priority; `RDY` says whether a free ticket can be taken (`yes`: no open blocker; `spec`: a backlog item that isn't a bug, so it needs a spec first); open blockers follow the title, and one that is no ticket on the rail is marked `?` and holds the ticket |
| `board` | `status`, `files`, `rail` and `questions` in one snapshot. Run from the main checkout it also writes the snapshot to `.claude/board.md`, a generated file a human can keep open; it's kept out of git through `.git/info/exclude`, so no tracked file changes |
| `leaks [--dir D] [--also F]` | search a checkout's changed files and its branch's commit messages (`D`, default here; plus one extra file `F`, e.g. a PR body) for any test-account secret in `.claude/brigade.local.md`. Prints `file:line`, never the value; exits 1 on a hit. A literal search, skipping values under six characters |
| `role` | `cook <station> <main checkout>` inside a station, else `main <main checkout>`. Every lifecycle skill runs this first |
| `sous [--set NAME]` | print the sous chef's session name, from the main checkout or any station; exits 1 if none is recorded. `--set`, from the main checkout only: record it in `.claude/sous`, kept out of git through `.git/info/exclude`. `/bk:sous-chef` sets it on start; `/bk:line-cook` reads it to check in without waiting for a `[hello]` |
| `questions` | every unanswered question (`Qn` with no `An`) in the stations' journals: what the cooks are waiting on |
| `lessons` | lesson lines counted by distinct tickets across all journals, each marked `watch` / `DUE` / `promoted` (the sous runs it at handoff) |
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
