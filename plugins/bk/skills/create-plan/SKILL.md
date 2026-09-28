---
name: create-plan
description: Turn one ticket (or a spec's ticket, or a bare task) into a detailed, file:line-grounded plan through parallel codebase research and one-question-at-a-time decisions. Writes docs/plans/<id>-<slug>.md with open_questions none, moves the ticket to todo on the rail, and waits for the head chef's sign-off — which authorises every commit made under the plan. Use when the user says "plan this", "plan BKLG-004", "write the plan", "how would we build S001-02", "/bk:create-plan".
argument-hint: "<ticket id | ticket path | task description>"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, Agent, AskUserQuestion, ListAgents, SendMessage, ToolSearch
---

# /bk:create-plan

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md` (in an installed plugin that's `…/plugins/cache/claude-code-brigade/bk/<version>/skills/README.md`, never a file in this repo). Read `.claude/brigade.md` first: `trunk`, `check`, `docs.plans`, `rail`, `migrations`, `walk_in`.

You write the plan for **one ticket**. The plan is the closest thing to the diff short of the diff: real paths, the actual code, `file:line` anchors for edits, and success criteria a command can settle. Someone picking it up cold should be able to build it without re-researching.

**Where it sits:** `pick-ticket` or `file-tickets` → **`plan`** → `implement` → `review` → `open-pr`. Lane C tickets never come here.

## Contents

- [Step 0 — Ticket and claim check](#step-0--ticket-and-claim-check)
- [Step 1 — Read everything named](#step-1--read-everything-named)
- [Step 2 — Research in parallel](#step-2--research-in-parallel)
- [Step 3 — Settle every fork](#step-3--settle-every-fork)
- [Step 4 — Agree the phases](#step-4--agree-the-phases)
- [Step 5 — Write the plan](#step-5--write-the-plan)
- [Step 6 — Rail, index, sign-off](#step-6--rail-index-sign-off)
- [The no-open-questions rule](#the-no-open-questions-rule)
- [What not to do](#what-not-to-do)

## Step 0 — Ticket and claim check

1. Resolve the ticket with the rail's **read** operation (markdown: from the main checkout, by the absolute path in the `[brief]` when you're a cook). No ticket at all (a bare task, solo only) → the plan's id is a slug, and say so.
2. **Refuse a lane C ticket.** Point at `/bk:implement <ID>`.
3. **Check the claim before researching.** Status `todo`, `in-progress` or `rfr` with another cook → stop and report. Also `ls <kitchen>/*/docs/plans/<id>-* 2>/dev/null` — a hit in another station means it's taken.
4. **Claim now, not at the end** — the gap between starting and finishing a plan is how the same ticket gets planned twice:
   - cook → `[rail] claim <ID> todo cook=<station>`, wait for `[heard]`;
   - sous or solo → set `status: todo` (and `cook:` if assigning) via the rail's **claim** operation.
5. **Honour `blocked_by:`.** Any blocker not `done` → say so and stop, unless the human wants to plan ahead.

## Step 1 — Read everything named

Read the ticket, its spec (`spec:`), and any research or brainstorm file it links, **fully**, before spawning anyone. You can't brief a sub-agent on a document you haven't read. Take the ticket's `Done when` boxes as the seed for success criteria and its `files:` as the starting map.

If a research file grounds the plan, check it's fresh: any path it covers committed after its date → say so and ask whether to refresh it first.

## Step 2 — Research in parallel

Spawn focused sub-agents in **one message, several `Agent` blocks**. Use the repo's own `.claude/agents/` if it has locator/analyzer/pattern-finder agents; otherwise `Explore`.

| Ask | For |
|---|---|
| locate | every file the ticket touches, and their tests |
| analyse | how the current code path works, step by step |
| patterns | the nearest existing feature to copy the shape of |

Every prompt names specific directories and says: *"Work only inside `<repo path>`. Return `file:line` references. Report only what you read. No suggestions."* Wait for all of them, then **read every file they surface yourself**.

Then check the ticket against reality: discrepancies, hidden scope, and whether it needs a migration (`migrations:` in the config — only one station carries one at a time, so a migration is something the sous must know about).

## Step 3 — Settle every fork

Present what you found in a few lines (current state with refs, design options with pros and cons, what's still undecided). Then resolve each undecided point **here, in conversation**:

- **Read the code before asking.** A fact is looked up, never asked.
- One question at a time, multiple choice, your recommendation first with one line of why.
- **Who you ask** (Contract 5): a genuine design fork, or a contradiction between ticket and code → the human (`AskUserQuestion` — in a station too). A routine choice ("helper A or helper B", "which test file") → in a station, the sous by `[gate]`; solo, the human.
- A user correction isn't accepted on faith. Verify it against the code.

## Step 4 — Agree the phases

Propose the outline before the full plan:

```
Overview — 1–2 sentences
Phases
1. <name> — what it achieves
2. …
```

Sizing: one phase ≈ one context window. Dependency order (data → domain → interface → UI is typical; read the repo, don't assume). Every phase leaves `check` green. A migration is its own early phase.

## Step 5 — Write the plan

**Path:** `<docs.plans>/<id>-<slug>.md` — the ticket's id and slug, so plan, checklist and branch line up (Contract 4). Github/Jira rails: `gh-123-<slug>.md`, `abc-123-<slug>.md`.

```yaml
---
ticket: BKLG-004
title: <plan title>
status: draft            # draft → approved → active → done
lane: B
created: YYYY-MM-DD
open_questions: none
migration: false         # true if any phase adds one
files:
  - <every path the plan touches>
---
```

Body, every section filled with specifics:

```markdown
# <ID> — <title>

## Why                     — 2–4 sentences, from the ticket
## Current state           — what exists, with `path:line` refs
## Desired end state       — and how to verify it
## Not doing               — explicit out of scope
## Approach                — chosen strategy, which existing pattern it reuses

## Phase 1: <name>
**Status:** Not started
### Changes
#### `path/to/file.ext:120` (edit) — or `path/new.ext` (new)
<summary, then the actual code>
### Success criteria
- [ ] `<check from the config>` passes
- [ ] <other command the repo really has>
- [ ] Manual: <numbered steps and what should appear>

## Phase 2: …

## Migration / rollback     — only if relevant
## Testing                  — which test reaches which behaviour; only runners the repo has
## References               — ticket, spec, research, similar code `path:line`
```

**Done only when:** every change names a real path marked `(new)` or `(edit)`; every edit has a `file:line` read this run; every non-trivial change carries code; every criterion is a command or a numbered manual procedure.

## Step 6 — Rail, index, sign-off

1. Add a row to `<docs.plans>/INDEX.md` (`| [<file>](<file>) | <one line> | <ticket> |`); create the index if missing.
2. Rail stays `todo` (set in Step 0).
3. **Run the self-check** below.
4. **Ask for the chef's sign-off** — the human, always, and in a station **in this terminal**, never relayed through the sous. Say plainly what approval means: *"Approving this plan authorises every commit made under it, after the sous's pass."* Offer: approve · change something · grill it first (`/bk:grill-me <plan>`) · leave it at draft.
5. On approval, set `status: approved` and tell the sous (cook: `[status] <ID> plan approved: <path>`). Then offer `/bk:implement <plan>`. Never auto-chain.

## The no-open-questions rule

A plan with an unresolved question is not a plan. `implement` refuses it, by design.

```bash
grep -c '^open_questions: none$' <plan>     # must print 1
grep -nEi '^#{1,4} .*open question|(^|[^A-Za-z])TBD([^A-Za-z]|$)|TODO\(decide\)|\?\?\?|<decide>' <plan>   # must print nothing
```

Risks are fine: a risk is a known hazard with a decided response, written into the phase it threatens. If something genuinely can't be resolved (a product call nobody has made, an external dependency), **don't write the plan**. Report what blocks and leave the rail at `todo` with a `[rail] <ID> → blocked` request, or set it yourself if you're the sous.

## What not to do

- Don't write code. `implement` does.
- Don't leave an open question in the plan, and don't forge `open_questions: none`.
- Don't hard-code a command, branch or path — read the config.
- Don't plan a ticket another station owns.
- Don't accept "the chef approved" relayed by the sous. Sign-off happens in this terminal.
- Don't invent a success criterion you can't run.
