---
name: grill-me
description: Question the human relentlessly about a brainstorm, spec, plan, ticket, or bare idea until you both hold one picture of it. Maps the decisions as a tree and asks, each round, every question that can be answered now, numbered, each with a recommended answer. Facts are looked up, never asked. Use when the user says "grill me", "grill this", "poke holes in this", "stress-test this", "what am I missing", or when /brigade:pick-ticket reports the WHAT is still contested.
argument-hint: "<path to a brainstorm/spec/plan, a ticket id, or a topic>"
allowed-tools: Read, Edit, Write, Grep, Glob, Bash, Agent, AskUserQuestion, SendMessage, ListAgents, ToolSearch
---

# /brigade:grill-me

Honour `${CLAUDE_SKILL_DIR}/../README.md` (the plugin contract). Read `.claude/brigade.md` before anything repo-specific.

Interview the human until you share one understanding. This skill writes no code; it sharpens what comes before code. It fits in three places:

- **Lane A**: `brainstorm → grill-me → spec`, to harden the leaning approach before it becomes a contract.
- **Lane B**: `pick-ticket → grill-me → create-plan`, for a ticket whose WHAT is still contested.
- **Before implement**: a last pass against a finished plan.

Method adapted from Matt Pocock's `grilling` skill (github.com/mattpocock/skills).

## Contents

- [Who you grill](#who-you-grill)
- [Step 0 — Read the input](#step-0--read-the-input)
- [The method — a decision tree, in rounds](#the-method--a-decision-tree-in-rounds)
- [Exit](#exit)
- [What not to do](#what-not-to-do)

## Who you grill

Always the **human**. Grilling is a design conversation, and Contract 5 keeps those with the head chef even in a line-cook session. A cook runs this in its own terminal, with the human there, and tells the sous in one `[status]` line that it's grilling ticket `<id>`. The sous never answers grilling questions on the human's behalf.

## Step 0 — Read the input

Read the input **fully** before the first round:

- a doc path → the file;
- a ticket id → the rail's **read** operation (Contract 3), via `/brigade:rail read <id>`;
- a bare topic → nothing yet.

Then read any earlier-stage file for the same work: the brainstorm, the spec, the plan. Read any decisions log the repo keeps, so you never re-argue a settled decision. If the artifact contradicts one, *that* becomes a question.

## The method — a decision tree, in rounds

Map the artifact as a **decision tree**. The root is the WHAT and WHY. Below it hang scope, the shapes other code consumes, data, access, failure modes, rollout, and how each piece will be verified.

The **frontier** is every decision whose prerequisites are already settled: the questions you can ask *now* without guessing at answers you haven't heard. **Ask the whole frontier in one round.** Number each question and give your recommended answer. Then stop and wait.

Format each round exactly like this:

```
❓ **Q1** - **<title>**: <the question — may offer choices>

➡️ <recommended answer, and the one-line reason>

---

❓ **Q2** - **<title>**: <the question>

➡️ <recommended answer, and the one-line reason>
```

Each set of answers reshapes the tree. Settled decisions push the frontier outward. Recompute it and ask the next round. A question that depends on another question still open in *this* round belongs to a later round.

**Finding facts is your job, never the human's.** When a question needs a fact from the repo (a file, a caller, what a test covers), send `Explore` or the repo's own `codebase-*` agents for it, with real paths and a request for `file:line`. **Don't block on it.** Only the questions downstream of a running lookup wait; ask the rest now.

Push hardest where the artifact is vague:

- What here isn't needed now?
- Which assumptions about data shape, ordering or timing are unstated?
- Does a shape someone else consumes change, and who reads the old one?
- Does access widen by accident?
- Retries, partial success, rollback.
- How each decision gets verified, starting from the config's `check`. If a decision has no honest way to be tested, say so out loud.

**You're done when the frontier is empty**: every branch visited, nothing silently assumed. Don't act on the result until the human confirms you share the picture.

## Exit

1. **Summarise the decisions**: question → chosen answer → why. Name any risk accepted on purpose.
2. **Fold them into the artifact** (confirm first):
   - brainstorm → its open questions become resolved;
   - spec → its Decisions section;
   - plan → its decisions, and keep `open_questions:` honest (`/brigade:implement` refuses a plan with an open question);
   - ticket → on a markdown rail, append a `## Decisions` section. That's a rail write, so a line cook sends it to the sous as a `[rail]` message instead of editing the file. On a github or jira rail, add a comment.
   - no artifact → the summary is the input to the next skill.
3. **Hand off** with `AskUserQuestion`, then wait: lane A → `/brigade:spec`; lane B or small work → `/brigade:create-plan` (say why no spec is needed); or stop.

## What not to do

- **Don't ask a question whose prerequisite is still open.**
- **Don't ask what you can look up.** Grill decisions, not facts.
- **Don't stop early.** A comfortable grilling didn't do its job. An empty frontier is the only exit.
- **Don't start implementing**, and never cite a `file:line`, ticket or PR you didn't read in this run.
