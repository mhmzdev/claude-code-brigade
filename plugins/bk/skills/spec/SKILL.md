---
name: spec
description: Turn a hardened discussion into a numbered written spec — the WHAT/WHY contract with problem, solution, user stories, decisions and how it will be tested — saved to docs/specs/NNN-<slug>.md and registered in its INDEX. Lane A (Specials). Use when the user says "write this up as a spec", "spec this out", "make a spec", "turn this into a spec". Synthesises the conversation; does not re-interview.
argument-hint: "[brainstorm doc path or slug]"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, Agent, AskUserQuestion, SendMessage, ListAgents, ToolSearch
---

# /bk:spec

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md` (in an installed plugin that's `…/plugins/cache/claude-code-brigade/bk/<version>/skills/README.md`, never a file in this repo). Read `.claude/brigade.md` before anything repo-specific.

**Station check first** (Contract 1): run `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" role`. If it prints `cook …`, you are a line cook even if nobody typed `/bk:line-cook` (e.g. after a `/clear`): read and follow `${CLAUDE_SKILL_DIR}/../line-cook/SKILL.md` for where questions go, the journal, and what a cook never does.

Write down a discussion that already happened as a durable **spec**: the WHAT/WHY contract every ticket under it inherits. The HOW comes later, in `/bk:create-plan`.

```
brainstorm → grill-me → spec → file-tickets → create-plan → …
```

Specs are numbered Markdown in `docs/specs/` on **every** rail, markdown, github or jira alike (Contract 4).

## Contents

- [Who runs this](#who-runs-this)
- [Step 1 — Gather the material](#step-1--gather-the-material)
- [Step 2 — How it gets tested](#step-2--how-it-gets-tested)
- [Step 3 — Number and write](#step-3--number-and-write)
- [Step 4 — Register](#step-4--register)
- [Step 5 — Hand off](#step-5--hand-off)
- [What not to do](#what-not-to-do)

## Who runs this

A spec number is handed out like a ticket number, so **the sous chef or a solo session** runs this skill (Contract 4: only one session hands out numbers).

In a **line-cook** session, don't pick a number. Write the draft to `<docs.specs>/draft-<slug>.md`, then send the sous a `[rail]` message: `spec draft ready: <absolute path>, please number it`. The sous reads it by that absolute path and writes it as `NNN-<slug>.md` in the main checkout (the sous never writes in a station), registers it, and tells you; then delete your draft.

## Step 1 — Gather the material

- The conversation above is the main source. **Don't re-interview.**
- Read the brainstorm doc for this work if it exists (`<docs.brainstorm>/*-<slug>.md`), and any research artifact it cites.
- Only if the discussion never touched the code: a light pass over the area with `Explore` (or the repo's `codebase-*` agents). Ask for `file:line`; describe what exists, don't propose.
- Use the repo's own vocabulary from its `CLAUDE.md`, not generic terms. Stay consistent with its settled decisions.

## Step 2 — How it gets tested

This is **the one question you may ask**. Decide where the feature gets verified and confirm it:

- Start from the config's `check`. Those are the real gates.
- Prefer **existing** ways of testing. Name the kind (unit, integration, schema or contract, migration applies, manual check) and what a test would exercise. Don't spec a new test harness into existence casually.

Ask with `AskUserQuestion`. A line cook sends it to the sous as a `[gate]` instead, unless it's a real design fork (Contract 5).

## Step 3 — Number and write

1. List `<docs.specs>/`. The new number is the highest existing `NNN-` prefix plus one, zero-padded to three digits. Empty or missing → `001`.
2. Write `<docs.specs>/NNN-<slug>.md`. Its id is `SNNN`.

```markdown
---
id: SNNN
slug: <slug>
status: ready-to-slice        # ready-to-slice | sliced | done | superseded
brainstorm: <path or none>
created: <YYYY-MM-DD>
---

# SNNN — <Feature> — Spec

## Problem
Who feels it, when, and what it costs them. No implementation.

## Solution
The solution in plain terms. Still no implementation.

## User stories
1. As a <role>, I can <do X> so that <benefit>.

## Decisions
Interfaces, data shape, permissions, migrations, shapes other code must absorb:
what the grilling settled. Which existing patterns it reuses.

## Testing decisions
Where it's verified (Step 2), and the closest existing test or check to mirror.

## Out of scope
- ...

## Further notes
Open items, links to the brainstorm and research.
```

Give the file a `## Contents` list if it grows past a screen.

## Step 4 — Register

Add a row to `<docs.specs>/INDEX.md`:

```markdown
| [SNNN](NNN-<slug>.md) | <title> | ready-to-slice | <date> |
```

Create the INDEX if it's missing (a heading, the table header, this row). On a markdown rail with `rail.commit: direct`, the sous commits the spec and its INDEX row to trunk (`spec: SNNN <slug>`). With `daily-pr`, it goes on the day's rail branch.

## Step 5 — Hand off

Present the finished spec and wait. Offer with `AskUserQuestion`:

- **Slice it into tickets** → `/bk:file-tickets <spec path>`: the expected next step.
- **Plan it directly** → `/bk:create-plan`: only for a one-slice feature; say why.
- **Stop** → the spec is saved.

## What not to do

- **Don't interview.** The only question is how it gets tested.
- **Don't write the HOW.** Phases and file changes belong to `/bk:create-plan`. The exception is a shape that *is* the decision (a schema, a field list): include that verbatim.
- **Don't invent** a rule or number the discussion didn't settle. Flag it under Further notes.
- **Don't skip the INDEX row.**
