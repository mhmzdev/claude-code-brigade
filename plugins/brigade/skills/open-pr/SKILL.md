---
name: open-pr
description: Commit, bring trunk in, re-run the check, push and open (or update) the pull request for the current ticket — branch <lowercase id>-<slug>, title "[ID] summary", body Why / Change summary / Linked ticket / Test plan / Deploy prerequisites. Rescues work stranded on trunk onto a branch. Never force-pushes, never pushes to trunk. In a line-cook session it runs only after the sous chef's [go] and reports the PR URL back. Use when the user says "open a PR", "ship this", "put this up for review", "push this up", "/brigade:open-pr".
argument-hint: "[<ticket id> | title hint] [--base <branch>]"
allowed-tools: Read, Grep, Glob, Bash, SendMessage, ListAgents, ToolSearch
---

# /brigade:open-pr — put the plate on the pass

Honour `${CLAUDE_SKILL_DIR}/../README.md` (the plugin contract). Read `.claude/brigade.md` first.

Position: `… → review → **open-pr**`. For lane C it follows `implement` directly.

**Typing this skill is the go-ahead** to commit, push and open the PR. Don't ask again. Present the plan so the human can correct it as it scrolls past, and stop only on a real fork (listed below).

**Line cook:** run this only after the sous has sent `[go]` for this ticket. No `[go]` in this session → stop and send `[handoff]` via `/brigade:review` instead.

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

Stage only the ticket's files: the ones in the diff that the plan, the ticket's `files:` and the checklist account for. A file you had to guess about is a fork: ask. Never `git add -A` unasked.

Commit message: `[<ID>] <imperative summary>`, then a short body of why. Keep the repo's attribution trailer if its history uses one.

## 4 — Bring trunk in and re-check

Trunk moved while you cooked. Merge it now, so the PR is reviewed against today's trunk:

```bash
git fetch origin
git merge origin/<trunk>
<check>
```

- A merge conflict in an `INDEX.md` table → keep **both** rows. `--ours`/`--theirs` deletes another station's entry.
- Any other conflict → stop and ask (cook: `[gate]` to the sous).
- A red check → stop. Fix it, re-run `/brigade:review` for anything it touched, and don't push red.

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

```bash
git push -u origin <branch>
gh pr create --base <trunk> --head <branch> --title "<title>" --body-file "$body_file"
# already open → gh pr edit <n> --title "<title>" --body-file "$body_file"
```

**No `gh`, or the remote isn't GitHub** → push, then print the compare URL the host gives (GitHub `…/compare/<trunk>...<branch>`, GitLab `…/-/merge_requests/new?merge_request[source_branch]=<branch>`, Bitbucket `…/pull-requests/new?source=<branch>`) with the rendered title and body to paste.

## 7 — Report

The PR URL, title, base, created or updated, every Deploy prerequisite repeated in full, and the unchecked Test plan items.

- **Line cook** → send the sous: `[served] <ID> <url> · deploy prereqs: <none | list>`. Then tell the human this session's ticket is done and it should be cleared before the next one.
- **Solo or sous** → leave the ticket at `rfr`. The merge is what makes it `done` (a tracker's own close-on-merge, or the sous closing it through `/brigade:rail` after the human merges).

## Stop and ask only for

| Fork | Why |
|---|---|
| Rescuing work stranded on trunk | it moves trunk itself; the one path that can lose commits |
| Files whose inclusion you had to guess | a commit is hard to take back |
| A merge conflict outside INDEX rows | never auto-resolve |
| Base branch other than `trunk` | the wrong base retargets someone's release |

## Never

- `git push --force` in any form, a push to trunk, `reset --hard`, a stash without `-u`.
- A second PR for a branch that already has one open.
- An approval-sounding line ("LGTM", "ready to merge"). That's the reviewer's call.
- A board or rail change from here. `review` owns `rfr`; the merge owns `done`.
- Merging. Only the head chef merges.
