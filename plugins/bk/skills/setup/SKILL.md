---
name: setup
description: Set up The Brigade in the current repo, bottom to top — detect trunk, check command, install command and shared resources; ask one round of questions; write .claude/brigade.md; build the markdown rail folders in docs/; add a short "The Brigade" section to CLAUDE.md; gitignore the stations; commit on the human's go; then create the stations. Use when the user says "set up the brigade", "brigade setup", "install the brigade here", "/bk:setup".
argument-hint: "[--worktree | --clone]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion, ToolSearch
disable-model-invocation: true
---

# /bk:setup

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md` (in an installed plugin that's `…/plugins/cache/claude-code-brigade/bk/<version>/skills/README.md`, never a file in this repo). This skill writes the
per-repo half of the Brigade. The skills themselves stay in the plugin; never copy them in.

## Contents

- [Flags](#flags)
- [Ground rules](#ground-rules)
- [1. Preflight](#1-preflight)
- [2. Read the repo](#2-read-the-repo)
- [3. One round of questions](#3-one-round-of-questions)
- [4. Write the config](#4-write-the-config)
- [5. Build the rail](#5-build-the-rail)
- [6. The CLAUDE.md section](#6-the-claudemd-section)
- [7. Show, then commit](#7-show-then-commit)
- [8. Open the kitchen](#8-open-the-kitchen)
- [9. First service](#9-first-service)

## Flags

| Flag | Effect |
|---|---|
| *(none)* | detect the kitchen mode in step 2 and recommend it in step 3 |
| `--worktree` | use worktree stations in `../<repo>-stations/`; step 3 asks only how many |
| `--clone` | use clone stations in `stations/`; step 3 asks only how many |

Passing both is an error: say so and stop. A flag settles the mode, so don't argue with it.
If `--clone` goes against what step 2 finds (a workspace-nested or very large repo), say so
in one line in the summary, with the reason (e.g. "3 full clones of a 7 GB repo"), and
carry on.

## Ground rules

- Detect before you ask. Only ask what the repo can't tell you.
- One round of questions, plain words, recommended answer first.
- Merge into existing files (`CLAUDE.md`, `.gitignore`, `.claude/settings.json`); never replace them.
  Show every change to an existing file before writing it.
- Nothing is committed or pushed until the human says go (step 7).
- If a step fails, stop and say plainly what failed.

## 1. Preflight

Stop if any of these fail:

1. It's a git repo with an `origin` remote.
2. The working tree is clean. If not, ask the human to commit or stash first.
3. `ListAgents` and `SendMessage` load (use `ToolSearch`). Without them the sous and cooks
   can't talk. Say to update Claude Code.
4. `.claude/brigade.md` doesn't already exist. If it does, offer to review it instead.
5. **This isn't a workspace root.** A workspace root is a repo that holds other repos as
   gitignored folders (one checkout with several product repos inside it). A station can't
   be made of it: a clone of the workspace contains none of the repos inside it. Find
   nested repos with:

   ```bash
   find . -mindepth 2 -maxdepth 3 -name .git -not -path './stations/*' -not -path './.git/*' \
     | sed 's#^\./##; s#/\.git$##' \
     | while read -r d; do
         grep -qsF "path = $d" .gitmodules && continue   # submodules are fine
         git check-ignore -q "$d" && echo "$d"            # an ignored nested repo
       done
   ```

   If it prints anything, **stop**, whatever flag was passed. Say, in plain words: *"This
   looks like a workspace: it holds N repos (list up to five). The Brigade runs one
   kitchen per product repo. `cd` into the repo you want to work on and run `/bk:setup`
   there; it will recommend worktree stations next to it."* Don't write any files.

## 2. Read the repo

Note for the summary:

- **Trunk**: the branch PRs target. Recent merged PRs (`gh pr list --state merged --limit 20
  --json baseRefName`) beat the GitHub default.
- **Check command**: an existing aggregate in `package.json`, `Makefile`, `justfile`,
  `pyproject.toml`, `Cargo.toml`, `go.mod`, or CI. None? Propose lint + typecheck + test in
  this stack's terms.
- **Install command**, and untracked files a clone needs (`.env`, `.env.local`, …). Names
  only. Never print their contents.
- **Walk-in candidates**: `docker-compose*.yml`, a local database, a fixed dev port,
  seed/reset scripts. For each, its destructive commands and a safe alternative.
- **Migrations folder**, if any.
- **Existing trackers**: a GitHub Project on the repo, Jira keys in branches or commits,
  an existing `docs/` layout for specs or plans.
- **Which kitchen mode fits** (Contract 8), unless a flag already settled it. Recommend
  **`worktree`** when either is true, else **`clone`**:
  - the repo sits inside another git repo (`git -C .. rev-parse --show-toplevel` succeeds):
    a workspace checkout that holds several repos;
  - the checkout is big (`du -sh .git` over ~1 GB): N full clones would cost N copies.
- **Tools that don't read `.gitignore`** and would see `stations/` (clone mode only): `tsconfig.json`
  include globs, test-runner configs, linter configs, `pytest.ini`, `.dockerignore`.
- **Lane C counters** that fit the stack: knip or ts-prune (JS/TS), vulture (Python),
  `staticcheck -checks U1000` (Go), `cargo udeps` (Rust), plus a TODO/FIXME count.

## 3. One round of questions

Ask together, skipping any the repo answered (say what you found):

1. **Where should tickets live?** Recommend markdown in `docs/` unless the repo clearly runs
   on GitHub Projects or Jira. Options: markdown · GitHub Projects · Jira · mixed.
2. **How many stations, and which kind?** (With a flag, ask only how many.) Recommend 2,
   and the mode from step 2 with its
   one-line reason: *clones inside the repo* (simplest) or *worktrees in
   `../<repo>-stations/`* (shared history; for workspaces and big repos).
3. **Is this the check command?**
4. **Are these the shared resources and their destructive commands?**
5. **Can the sous commit rail changes straight to trunk?** Recommend yes unless trunk is
   protected; otherwise one rail PR a day.

## 4. Write the config

Write `.claude/brigade.md` with the shape in Contract 2, filled from steps 2–3. Keep the
flat keys on one line each: `kitchen.sh` reads them. Put repo-specific notes in the body
as plain sentences.

Create `.claude/brigade.local.md` (one placeholder line) and add it to `.gitignore`, together
with `.claude/sous-handoff.md` (the sous's handoff note is machine-local, Contract 11).
`docs/lessons.md` is created later, by the first lesson promotion.

Add to `.gitattributes` (create it if needed, merge if not):

```
docs/**/INDEX.md merge=union
```

Every cook's PR appends a row to a shared `INDEX.md` (plans, checklists), so two PRs
merging close together would conflict on it every time. `merge=union` keeps both rows. It
only applies to merges git runs locally, which is why `/bk:open-pr` merges trunk into the
branch before pushing. If GitHub still shows a conflict there, merge trunk locally and push;
never resolve an INDEX by picking one side, which deletes the other cook's row.
In **clone** mode, add `/stations/` to `.gitignore` too (and `stations/` to `.dockerignore`
if it exists). In **worktree** mode, set `kitchen_mode: worktree` and leave `kitchen:` out
(it defaults to `../<repo>-stations`); `kitchen.sh setup` adds the ignore line to whichever
repo contains that folder, and says which.

For each tool from step 2 that doesn't read `.gitignore`, propose the one-line exclude and
apply it once the human agrees. Example: `"exclude": ["stations"]` in `tsconfig.json`, or
`analyzer: exclude: [stations/**]` in a Dart `analysis_options.yaml`.

**Edit only tracked files in the main checkout.** Find targets with `git ls-files`, never
`find .`: once stations exist, `find` also returns every station's copy, and an edit there
leaves each station dirty before its cook arrives. When you add a key to a YAML file, merge
it into the existing top-level block; never insert it in the middle of another key's list.

## 5. Build the rail

Create each folder that doesn't exist yet, with an `INDEX.md` (one-line purpose, then a
table with one row per file):

- always: `docs/specs/`, `docs/plans/`, `docs/checklists/`, `docs/journal/`, `docs/research/`, `docs/brainstorm/`
- markdown or mixed-with-markdown-tickets rail: `docs/backlog/`

Names and ids are Contract 4, exactly. Don't create sample tickets here; step 9 offers one.

For a **github** or **jira** rail, check you can read the project (`gh project view <n>
--owner <o>`, or the Jira MCP/CLI). Record the six statuses → real column/transition
mapping in the config's body.

## 6. The CLAUDE.md section

Append (create the file if needed). Keep it this short; the detail lives in the plugin. Fill in
`<stations path>` and keep only the bullet line for the chosen mode.

```markdown
## The Brigade

This repo can run several Claude Code sessions at once. Config: `.claude/brigade.md`.

- **Head Chef** (the human) signs off plans, merges, deploys. **Sous Chef**
  (`/bk:sous-chef`, in this checkout) assigns tickets, answers routine questions,
  reviews every diff before commit, and is the **only session that writes the rail**.
  **Line Cooks** (`/bk:line-cook`) work one ticket each in `<stations path>/station-N`.
- **The rail is the claim.** A ticket not in `backlog` or `blocked` belongs to someone.
  Cooks ask the sous to change a ticket; they never edit ticket files.
- **Ask before touching the walk-in** (`walk_in:` in the config). One migration in flight at a time.
- **One ticket per session.** Pull trunk into your branch before opening a PR, and re-run the check.
- Clone mode: **never `git clean -fdx` here**: `stations/` is ignored, so `-x` deletes every station.
  Worktree mode: stashes are shared, so stash with `-m "<station>: …"` and apply only your own;
  remove stations with `kitchen.sh remove`, never `rm -rf`.
```

## 7. Show, then commit

Show: every file created or changed, the config values, anything you couldn't detect.
Then ask **one** question: *"Go? I'll commit, push, create the stations and open the
kitchen."* The one go covers steps 7 and 8. Stations clone `origin/<trunk>`, so the
setup has to be pushed before any station exists; asking twice only invites the gap.

On go: commit on trunk as `chore: set up The Brigade` and push. If trunk is protected,
push a `brigade-setup` branch, open its PR, and **stop**: stations wait until it merges.
Say so plainly.

## 8. Open the kitchen

Run `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" setup` and relay its output, including both
warnings. If it reports a station **dirty right after setup**, stop and show the diff:
something in the install step (or an edit that reached into `stations/`) changed tracked
files, and a cook must not inherit it. Otherwise run `kitchen.sh open`. Then tell the
human how to start:

1. The kitchen is open (or open one terminal per station by hand).
2. Here: `/bk:sous-chef`. In the stations there's nothing to type: `kitchen open` started each one as a line cook (unless `--bare`).
3. Tell the sous which ticket to fire, or ask it to propose one per lane.

And the one-line reminder: the sous never merges or deploys.

## 9. First service

Offer to fire one small demo ticket through `/bk:rail fire`: a real but harmless fix
you noticed while reading the repo. Print the rail afterwards with `kitchen.sh rail`.
