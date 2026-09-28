---
name: brainstorm
description: Explore WHAT to build and WHY before any plan or code, grounded in the real code rather than an imagined one. First stop of lane A (Specials). Writes docs/brainstorm/YYYY-MM-DD-<slug>.md. Use when the user says "brainstorm", "let's explore", "think this through", "what should we build", "is this worth doing", or when a request is too fuzzy to plan without guessing at scope.
argument-hint: "<idea to explore>"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, Agent, Skill, AskUserQuestion, SendMessage, ListAgents, ToolSearch
---

# /brigade:brainstorm

Honour `${CLAUDE_SKILL_DIR}/../README.md` (the plugin contract). Read `.claude/brigade.md` before anything repo-specific. Sub-agents can't see either file, so restate the rules they need in their prompts.

Pin down **WHAT** to build and **WHY**. Never HOW: no file lists, no phases, no code. Those belong to `/brigade:create-plan`. This is the first stop of lane A:

```
brainstorm → grill-me → spec → file-tickets → create-plan → implement → review → open-pr
```

## Contents

- [Principles](#principles)
- [Step 1 — Scope the idea](#step-1--scope-the-idea)
- [Step 2 — Ground it in the code](#step-2--ground-it-in-the-code)
- [Step 3 — Understand](#step-3--understand)
- [Step 4 — Write the brainstorm doc](#step-4--write-the-brainstorm-doc)
- [Step 5 — Hand off](#step-5--hand-off)
- [What not to do](#what-not-to-do)

## Principles

1. **YAGNI, hard.** Solve the problem in front of you, not a future one.
2. **Reuse what's settled.** The repo's `CLAUDE.md`, `docs/`, and any decisions log usually hold a decision that bears on the idea. Find it before inventing.
3. **One question at a time**, multiple choice, with your recommended answer. Then wait.
4. **Look before you ask.** If the answer is in the repo, read it.
5. **Ground before you opine.** No approach or recommendation about the code before Step 2 is done.

This skill talks to the human directly, even in a line-cook session: a brainstorm is a design conversation, which Contract 5 gives to the human. In a cook session, tell the sous in one `[status]` line that you're brainstorming and with whom.

## Step 1 — Scope the idea

Classify it. The class decides whether code gets read at all.

- **Generic**: process, tooling, docs, team practice. Skip Step 2.
- **Touches the code**: a feature, a behaviour change, a contract or data change. Step 2 is mandatory.
- **Already small and crisp**: a one-file fix, a copy tweak. Say so and recommend `/brigade:file-tickets` (one standalone ticket) or `/brigade:create-plan` directly. Don't brainstorm what doesn't need it.

Pick the slug now: lowercase-kebab, 2–5 words. The file is `<docs.brainstorm>/YYYY-MM-DD-<slug>.md` (Contract 4). If a brainstorm with the same slug already exists, read it fully and extend it. Never overwrite a file you haven't read.

## Step 2 — Ground it in the code

1. Check `<docs.research>/INDEX.md`. If an artifact already covers the question, read it and build on it. If the code has clearly moved since its date, treat it as a lead, not a fact.
2. If the repo has its own research skill (e.g. `/research-codebase`), use it and read what it produces.
3. Otherwise, dispatch `Explore` (or the repo's own `codebase-*` agents if `.claude/agents/` has them). Brief them with real directory names, ask for `file:line` references, and tell them to describe what exists, not what should change.
4. Read the 1–3 files that matter most yourself. Docs point the way; code is the source of truth.

## Step 3 — Understand

1. **Check settled decisions.** If the idea brushes a decision already made or deliberately deferred, raise that instead of re-arguing it.
2. **Question, one at a time.** Good ones:
   - Who feels the problem, and what's the smallest version that removes it?
   - Does it change a shape someone else consumes (an API, an event, a file format)? Who reads the old one?
   - Does it need new data, a migration, or a permission change? (A migration means only one station can carry it at a time: Contract 7.)
   - What is deliberately out of scope?
3. **Lay out 2–3 concrete approaches.** For each: one line, what it reuses (cite the `file:line` you read), and its main trade-off. Recommend one.

## Step 4 — Write the brainstorm doc

```markdown
---
slug: <slug>
status: exploring
research: <artifact path, or "none — generic idea">
created: <YYYY-MM-DD>
---

# <Topic> — Brainstorm

## Problem
What is broken or missing, in the words of whoever feels it.

## Goal
The smallest outcome that counts as success.

## Approaches considered
1. **<Name>** — <one line>. Reuses <X>. Trade-off: <Y>.
2. ...
**Leaning toward:** <which, and why>.

## Surfaces touched
Roughly which parts of the repo.

## Open questions
- [ ] ...

## Out of scope
- ...
```

Keep it under ~150 lines. Longer means the idea needs splitting. Add a row to `<docs.brainstorm>/INDEX.md` (`| [<slug>](<file>) | <one line> | exploring | <date> |`), creating the INDEX if it's missing.

## Step 5 — Hand off

Offer the next step with `AskUserQuestion`, then wait:

- **Grill it** → `/brigade:grill-me <doc path>`: the right next step for anything non-trivial.
- **Spec it** → `/brigade:spec`: only if the discussion already settled every fork.
- **Plan it** → `/brigade:create-plan`: only for small, low-risk work; say why skipping the spec is safe.
- **Pause** → leave the doc and stop.

## What not to do

- No phases, file lists or code.
- Don't invent requirements nobody raised. Capture what was discussed; the rest goes under open questions.
- Don't skip Step 2 for an idea that touches code. An approach that sounds good against an imagined codebase is exactly what the plan then throws away.
- Don't hard-code paths or branches. Read them from `.claude/brigade.md`.
