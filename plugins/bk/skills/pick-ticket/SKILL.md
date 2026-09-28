---
name: pick-ticket
description: Pick up a ticket cold. Rebuilds the context behind it (why it exists, what it links to, what happened since), checks the code at origin/<trunk>, returns one of six staleness verdicts with evidence, checks nobody else owns it, then recommends the next skill and — only on a yes — claims it on the rail. Works on any rail (markdown, GitHub, Jira). Read-only until told otherwise. Use when the user says "pick a ticket", "pick up BKLG-004", "catch me up on S001-02", "is this ticket still valid", "what's the story on HYG-003".
argument-hint: "<ticket id, path, or URL>"
allowed-tools: Bash, Read, ListAgents, SendMessage, AskUserQuestion, ToolSearch
---

# /bk:pick-ticket

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md` (in an installed plugin that's `…/plugins/cache/claude-code-brigade/bk/<version>/skills/README.md`, never a file in this repo). Read `.claude/brigade.md` first; every trunk, path and rail detail comes from there.

Someone is picking up a ticket cold. Give the context back, say whether the ticket is still true, check that it's free, then help claim it — in that order.

## Contents

- [The one rule](#the-one-rule)
- [Step 0 — Resolve the ticket](#step-0--resolve-the-ticket)
- [Step 1 — Fix the code baseline](#step-1--fix-the-code-baseline)
- [Step 2 — Read the ticket and one hop out](#step-2--read-the-ticket-and-one-hop-out)
- [Step 3 — Is it free?](#step-3--is-it-free)
- [Step 4 — Verdict](#step-4--verdict)
- [Step 5 — Write it up](#step-5--write-it-up)
- [Step 6 — Next skill and the claim](#step-6--next-skill-and-the-claim)
- [What not to do](#what-not-to-do)

## The one rule

**Read freely. Anything that changes something outside this conversation waits for a yes in this run.** That covers claiming, editing a ticket, closing it, commenting, and messaging another session. Propose it, show exactly what you'd write, wait.

This skill never writes a file in the repo.

## Step 0 — Resolve the ticket

The argument is an id (`BKLG-004`, `S001-02`, `HYG-003`, `#123`, `ABC-123`), a path, or a URL. No argument → ask; don't guess from recent conversation.

Find it with the rail's **read** operation for `rail.adapter`:

- **markdown** — `docs/backlog/<ID>-*.md`, or `docs/specs/NNN-*/NN-*.md` for `SNNN-NN`. Read it **from the main checkout**: in a station, that's the absolute path the sous gave you in the `[brief]`.
- **github** — `gh issue view <N> --json number,title,body,state,labels,assignees,comments`.
- **jira** — the Jira MCP or CLI named in `.claude/brigade.local.md`.

A closed or `done` ticket is a valid target. The verdict then says what closed it.

## Step 1 — Fix the code baseline

**`origin/<trunk>` is the only ground truth for the verdict.** Code in an open PR is done in someone's branch. Code in your working tree is done nowhere but this machine. Neither counts.

Read code only through git, anchored to trunk:

```bash
git fetch origin <trunk> --quiet
git rev-parse --short origin/<trunk>                       # goes in the output header
git show origin/<trunk>:<path>                             # a file
git grep -n <pattern> origin/<trunk> -- <path>             # search
git ls-tree -r --name-only origin/<trunk> <dir>            # list
```

**The ref must come before `--`.** `git grep -n <pattern> -- <path>` is valid, silently searches your working copy, and looks identical in the output. It's the one mistake here that produces confident wrong evidence.

## Step 2 — Read the ticket and one hop out

**One hop, never further.** From the ticket: its spec (`spec:`), the tickets in `blocked_by:`, tickets that block on it, any PR that names its id, and its comments (github/jira). Include closed and merged ones — the proof that a ticket was solved sideways usually lives in something that finished.

```bash
gh pr list --state all --search "<ID>" --json number,title,state,mergedAt,url   # if the remote is GitHub
git log origin/<trunk> --oneline --grep "<ID>"
```

Also read, at `origin/<trunk>`:

| Source | Proves |
|---|---|
| `docs/plans/<id>-*.md` | a plan exists; its `status:` says how far it got |
| `docs/checklists/<id>-*.md` | it was built and reviewed |
| the parent spec | the *why*, and the decisions the ticket inherits |

`docs/research/` and `docs/brainstorm/` **don't count** as evidence. They're exploration, not commitment.

## Step 3 — Is it free?

Kept separate from the verdict. This section says **who might be on it right now**.

- **Rail status.** `backlog` and `blocked` are free. `todo`, `in-progress` and `rfr` are **somebody's claim**. Say so loudly and drop every offer in Step 6.
- **`todo` with no plan at trunk is normal, not stale.** The plan is an uncommitted file in another station. Look:

  ```bash
  ls <repo-root>/<kitchen>/*/docs/plans/<id>-* 2>/dev/null
  ```

  A hit means that station claimed it. No hit proves nothing. Read nothing else from another station.
- **A branch already exists:** `git ls-remote --heads origin | grep -i "<lowercase id>"`.
- **Other live sessions:** `ListAgents`. If any are up and you're solo, add one honest line: "N other sessions are live; I can't tell what they're on." Don't message them unless asked.

## Step 4 — Verdict

Exactly one applies.

| Verdict | Means | Offer |
|---|---|---|
| **Stands** | nothing at trunk contradicts it | claim |
| **Partially done** | some `Done when` boxes already hold at trunk | narrow the body, then claim |
| **Body drifted** | the ask is right, but files or behaviour it names have moved | rewrite the body, then claim |
| **Superseded** | the need was met another way, or its target is gone | close with a reason |
| **Done** | every `Done when` box holds at trunk | close |
| **Unclear** | too vague to check against code | name what's missing; recommend grill-me |

Every verdict cites evidence: a `file:line` at `origin/<trunk>`, a merged PR, or a commit. No evidence → `Unclear`. Walk the `Done when` boxes one at a time. For a spec with several tickets, one row per ticket plus a one-line roll-up.

## Step 5 — Write it up

Chat only. Under ~400 words for one ticket.

```markdown
**<ID> — <title>** · lane <A|B|C> · status <status> · created <date>
Code read at `origin/<trunk>` <sha>

## What this is        — plain words, why it exists
## How it got here     — only the turns that changed what it means today
## Where it stands     — evidence at trunk, with refs
## In flight           — status, cook, branches, plans in stations (omit if empty)
## Verdict             — one of six, with evidence
## Next                — Step 6
```

## Step 6 — Next skill and the claim

**(a) Recommend the next skill by name, and wait.**

- The WHAT is contested (`Unclear`, `Body drifted`, comments disagree with the body) → `/bk:grill-me <ID>`.
- The WHAT is crisp, lane A or B → `/bk:create-plan <ID>`.
- **Lane C (`HYG-*`)** → `/bk:implement <ID>`. Hygiene tickets have no plan and no checklist (Contract 9); the ticket body is the spec and the counter is the proof.

**(b) Claim it — only on a yes.** The claim for lane A/B is `todo` (it's set again by `create-plan`, harmlessly); for lane C it's `in-progress`, because nothing comes between picking and implementing.

- **In a line-cook session:** you don't write the rail. Send the sous `[rail] claim <ID> <status> cook=<station>` and wait for `[heard]`. The sous may refuse because another station owns it — believe it and stop.
- **In a sous or solo session:** do the rail's **claim** operation yourself (markdown: set `status:` and `cook:` in the ticket's frontmatter, commit per `rail.commit`; github/jira: status field + assignee).

Then restate the ids for downstream: ticket `<ID>`, branch `<lowercase id>-<slug>`.

Close, body rewrite and comment offers follow the same rule: show the text, wait for yes, and a cook routes them to the sous as `[rail]` messages.

## What not to do

- Don't act without a yes in this run.
- Don't judge against the working tree or an open PR. Don't run `git grep` without a ref.
- Don't claim a ticket in `todo`, `in-progress` or `rfr` that isn't yours.
- Don't write the rail from a cook session. Ask the sous.
- Don't produce a verdict without evidence; that's what `Unclear` is for.
- Don't run the next skill yourself. The human (or, in a station, the brief) fires it.
