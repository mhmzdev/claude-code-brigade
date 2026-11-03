---
name: open-pr
description: Commit, bring trunk in, run the check (once per tree; it leaves a receipt), push only a tree with a green receipt, and open (or update) the pull request for the current ticket — branch <lowercase id>-<slug>, title "[ID] summary", body Why / Change summary / Linked ticket / Test plan / Deploy prerequisites. Rescues work stranded on trunk onto a branch. Never force-pushes, never pushes to trunk. In a line-cook session it runs only after the sous chef's [go] and reports the PR URL back. Use when the user says "open a PR", "ship this", "put this up for review", "push this up", "/bk:open-pr".
argument-hint: "[<ticket id> | title hint] [--base <branch>]"
allowed-tools: Read, Grep, Glob, Bash, SendMessage, ListAgents, ToolSearch
---

# /bk:open-pr — put the plate on the pass

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md` (in an installed plugin that's `…/plugins/cache/claude-code-brigade/bk/<version>/skills/README.md`, never a file in this repo). Read `.claude/brigade.md` first.

**Station check first** (Contract 1): run `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" role`. If it prints `cook …`, you are a line cook even if nobody typed `/bk:line-cook` (e.g. after a `/clear`): read and follow `${CLAUDE_SKILL_DIR}/../line-cook/SKILL.md` for where questions go, the journal, and what a cook never does.

Position: `… → review-task → **open-pr**`. For lane C it follows the pass (cook) or `implement` (solo).

**Line cook:** run this only after the sous has sent `[go]` for this ticket, and after `/bk:clean around` and `/bk:handoff`. No `[go]` recorded in the ticket's journal → stop and send `[handoff]` via `/bk:review-task` instead. **First step: check the grant** (Contract 5): `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" grant --show` must list `commit`, `push` and `open-pr`. One missing → stop and send `[gate] <ID> no grant on record: <action>` (not a question: no commis), then wait: the guard refuses the commit, the push and `gh pr create` without it, and there is no other route to try.

**Invoking this skill is the go** (Contract 5): commit, bring trunk in, re-check, push and
open the PR without asking again. It stops only for what's listed under "Stop and ask only
for". For a cook, the prerequisite is the sous's `[go]`; that's the pass, not a question.

## Contents

- [1 — State](#1--state)
- [2 — Branch](#2--branch)
- [3 — Commit](#3--commit)
- [4 — Bring trunk in and re-check](#4--bring-trunk-in-and-re-check)
- [5 — Title and body](#5--title-and-body)
- [6 — Push and open](#6--push-and-open)
- [7 — Report](#7--report)
- [Stop and ask only for](#stop-and-ask-only-for)
- [Never](#never)

## 1 — State

```bash
git status --short
git branch --show-current
git fetch origin --quiet
git log --oneline origin/<trunk>..HEAD
gh pr view --json number,url,state 2>/dev/null     # an open PR → update it, never open a second
```

Resolve the ticket: argument, else the id in the branch name, else the plan's frontmatter. Read the ticket, its plan (`docs.plans/<id>-*`) and its checklist (`docs.checklists/<id>-*`).

## 2 — Branch

The branch is `<lowercase id>-<slug>`, e.g. `bklg-004-fix-login`, reusing the plan's slug.

- **On a feature branch** → use it.
- **On trunk with a dirty tree or local commits** → **rescue** (this is on the fork list):
  - Local commits: `git checkout -b <branch>` first, so they travel. Then put trunk back with `git branch -f <trunk> origin/<trunk>`. Never `reset --hard` a checked-out trunk.
  - Only a dirty tree: `git stash push -u` → `git checkout <trunk> && git pull --ff-only` → `git checkout -b <branch>` → `git stash pop`. A conflict or a diverged trunk → stop and ask.
- **On trunk, clean, nothing ahead** → nothing to ship. Say so.

## 3 — Commit

**The cost line first** (Contract 11). Append the ticket's cost line to its journal, after the closing handoff:

```bash
"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" budget --ticket <ID> --journal-line --session <this session's name> >> <docs.journal>/<ID>-<slug>.md
```

It prints one dated line (money, tokens, brief→PR with the phases known so far, the helpers) read from the transcripts of every cook session on the ticket and the sous's sub-agents for it, so it costs nothing to write. If it fails (no node, or nothing recorded), say so in one line and go on: the line is a record, not a gate. The ship phase and the CI minutes are not known yet; they land in `.claude/budget.jsonl` later (the sous's handoff and the open Window fetch CI).

**Regenerate the indexes** (Contract 12): `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" index`. It rebuilds the plans, journals and checklists INDEX from the files' frontmatter, so the PR carries the rows for the files it adds; a folder it reports as hand-written keeps its hand-added row.

Stage only the ticket's files: the ones in the diff that the plan, the ticket's `files:` and the checklist account for, plus the ticket's plan, checklist and **journal** (`<docs.journal>/<ID>-<slug>.md`) and the INDEX files `kitchen.sh index` rewrites for them. The journal is the one file allowed to have changed since the sous's `[go]`: it carries the closing handoff and the cost line. A file you had to guess about is a fork: ask. Never `git add -A` unasked.

**Leak check before the commit, and again before the push** (Contract 2): `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" leaks`, the second time with `--also <the PR body file>`. It prints `file:line` for any test-account secret that reached a file, a commit message or the PR body. A non-zero exit → stop, remove it (name the account instead), and run it again; a cook then sends `[handoff]` again if the fix changed anything but the journal.

Commit message: `[<ID>] <imperative summary>`, then a short body of why. Keep the repo's attribution trailer if its history uses one. Write it to a file and commit with `git commit -F <file>`, as the PR body goes in with `--body-file`: the guard reads a command line, and a long message in quotes is more to get wrong.

## 4 — Bring trunk in and re-check

Trunk moved while you cooked. Merge it now, so the PR is reviewed against today's trunk:

```bash
git fetch origin
git merge origin/<trunk>
"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" index      # rewrites the generated INDEX files
git add -A -- '*INDEX.md' && { git diff --cached --quiet || git commit -m "[<ID>] index"; }   # commit what it changed
"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" check
```

The index is committed before the check, so the receipt names the tree of the commit you will push.

The merge changes the tree whenever trunk moved, so the check runs and writes a receipt; when trunk added nothing, the last green receipt for this exact tree is reported instead. A check that does not exit 0 stops here.

- A merge conflict in a generated `INDEX.md` (plans, journals, checklists; Contract 12) → run `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" index`. It rewrites the whole table from the files now in the tree, so no row is lost and no marker is left; then `git add` the INDEX files and finish the merge (`git commit --no-edit`). Never pick a side by hand. After a clean merge, run it anyway (it is in the block above, before the check) and commit what it changed. A conflict in a hand-kept `INDEX.md` (any other folder, or one `index` calls hand-written) → keep **both** rows: `--ours`/`--theirs` deletes another station's entry.
- Any other conflict → stop and ask (cook: `[gate]` to the sous).
- A red check → stop, and don't push red. Solo: fix it and re-run `/bk:review-task` for anything it touched. Cook: fixing it changes code after `[go]`, so fix it, then send `[handoff]` again for a new pass before pushing.

## 5 — Title and body

**Title**: `[<ID>] <imperative summary>`, under ~70 characters.

**Body**, headings verbatim, in this order. A section that doesn't apply says `_None._`, except Why, which never does, and Deploy prerequisites, which appears only when needed.

```markdown
## Why
<2–4 plain sentences for someone who hasn't seen the diff: what was wrong or missing, who it
affected, what's true after this merges. No paths, no symbols. From the ticket's ## Why, else the
spec, else the plan.>

## Change summary
<2–4 factual sentences for the reader who will open the diff: the approach, the parts touched,
what was chosen over the obvious alternative. Paths belong here.>

## Linked ticket
<markdown rail: the ticket's repo path, e.g. docs/backlog/BKLG-004-fix-login.md ·
github rail: Closes #N · jira rail: ABC-123>

## Test plan
<unchecked boxes a reviewer can do. Copy every [?] from the checklist as a box; [x] items
with a named test become "`<test>` passes". End with: "`<check>` passes (run locally before
opening this PR)". An [!] in the checklist means stop: it isn't done.>

## Deploy prerequisites
<only when needed: a new env var or secret, an unapplied migration, a one-time step. One bullet
each, naming where it must be set.>
```

Find the prerequisites concretely: changed files under `migrations:`, env example files, deploy manifests, and new env reads in the diff.

Write the body to a tempfile so Markdown survives the shell.

## 6 — Push and open

A commit is pushed only with a green receipt (Contract 8: a check's proof is its receipt). `git push` sends `HEAD`, and the receipt names a working tree, so right before the push require both that nothing is uncommitted and that the receipt is for the tree of `HEAD`:

```bash
test -z "$(git status --porcelain)"                                                     # the working tree is the commit
"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" check --receipt "$(git rev-parse 'HEAD^{tree}')"   # must exit 0
```

Either failing → don't push. A dirty status: commit or remove what it lists, then run `kitchen.sh check` again. `--receipt` exit `1` (`no receipt for this tree`): something changed the tree after the check, so run `kitchen.sh check` again. `2`: the receipt is red, or the config's `check:` line changed since it was written; say which it printed. Never edit `.claude/check.log` to get past it. Only now is it true that the receipt names the commit you push.

```bash
git push -u origin <branch>
gh pr create --base <trunk> --head <branch> --title "<title>" --body-file "$body_file"
# already open → gh pr edit <n> --title "<title>" --body-file "$body_file"
```

**No `gh`, or the remote isn't GitHub** → push, then print the compare URL the host gives (GitHub `…/compare/<trunk>...<branch>`, GitLab `…/-/merge_requests/new?merge_request[source_branch]=<branch>`, Bitbucket `…/pull-requests/new?source=<branch>`) with the rendered title and body to paste.

## 7 — Report

The PR URL, title, base, created or updated, every Deploy prerequisite repeated in full, and the unchecked Test plan items.

- **Line cook** → send the sous: `[served] <ID> <url> · deploy prereqs: <none | list>`. Then tell the sous your shift is over; after the merge it puts the station back on trunk (`kitchen.sh done <station>`) and clears this session (`kitchen.sh clear <station>`) once you are idle, your handoff is written and nothing you sent is unanswered.
- **Solo or sous** → leave the ticket at `rfr`. The merge is what makes it `done` (a tracker's own close-on-merge, or the sous closing it through `/bk:rail` after the merge: the sous's own with `kitchen.sh ship` when `gates.merge` is `sous-chef`, else the head chef's).

## Stop and ask only for

| Fork | Why |
|---|---|
| Rescuing work stranded on trunk | it moves trunk itself; the one path that can lose commits |
| Files whose inclusion you had to guess | a commit is hard to take back |
| A merge conflict outside the INDEX files | never auto-resolve |
| Base branch other than `trunk` | the wrong base retargets someone's release |

## Never

- `git push --force` in any form, a push to trunk, `reset --hard`, a stash without `-u`, `gh pr merge`.
- A way round a refusal from the guard. Send the `[gate]`.
- A second PR for a branch that already has one open.
- An approval-sounding line ("LGTM", "ready to merge"). That's the reviewer's call.
- A board or rail change from here. `review-task` owns `rfr`; the merge owns `done`.
- Merging. The sous merges a passed, green PR with `kitchen.sh ship` (the head chef when `gates.merge` is `head-chef`); never this skill.
