---
name: kitchen
description: Manage the Brigade's stations — the clones (stations/) or worktrees (../<repo>-stations/) where line cooks work. Create them, open one Claude session per station already running /bk:line-cook (Warp, tmux, or printed commands), sync clean ones to trunk, and print the status, files-in-flight and rail boards the sous chef reads. Use when the user says "set up stations", "open the kitchen", "open the line cooks", "station status", "what's in flight", "show the rail", "/bk:kitchen".
argument-hint: "setup [-n N] | open [-n N] [-m \"O S\"] [--terminal warp|tmux|print] [--bare] [--no-launch] | sync | status | files | rail | questions | lessons | role | remove"
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
| `setup [-n N]` | create N stations (clones in `stations/`, or worktrees in `../<repo>-stations/` when `kitchen_mode: worktree`), add the ignore line to whichever repo contains them (and `.dockerignore` if present), copy `copy_into_stations`, seed a small `settings.local.json`, run `install`. Existing stations are left alone |
| `open [-n N] [-m "O S"] [--terminal …] [--bare]` | open one `claude` session per station, **already running `/bk:line-cook`** (`--bare` for a plain session). `-m` takes one model per station in order (O/S/H/F or full names; one value covers all). Terminal defaults to Warp if installed, else tmux, else printed commands |
| `sync` | reset **clean** stations to `origin/<trunk>` (worktrees: detached there). Dirty ones are skipped: a cook may be mid-ticket |
| `status` | branch, dirty/clean, commits ahead per station, plus open PRs against trunk |
| `files` | files in flight per station vs `origin/<trunk>` (committed and uncommitted), plans, and **unmerged migrations** flagged |
| `rail` | the markdown rail's board, computed from ticket frontmatter; `done` tickets hidden |
| `role` | `cook <station> <main checkout>` inside a station, else `main <main checkout>`. Every lifecycle skill runs this first |
| `questions` | every unanswered question (`Qn` with no `An`) in the stations' journals: what the cooks are waiting on |
| `lessons` | lesson lines counted by distinct tickets across all journals, each marked `watch` / `DUE` / `promoted` (the sous runs it at handoff) |
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
  won't see it. `open` passes the current one through.
