---
name: file-tickets
description: Put work on the rail. Two modes — slice an approved spec into thin end-to-end tickets (lane A, ids SNNN-NN, with blocked-by edges), or fire one standalone ticket for something found mid-flight (lane B, BKLG-NNN). Works on a markdown, GitHub or Jira rail through /brigade:rail. Use when the user says "file a ticket", "make tickets", "break this into tickets", "slice this spec", "fire a ticket", "log this as a ticket".
argument-hint: "[<path to spec> | <description of the one ticket>]"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, Agent, Skill, AskUserQuestion, SendMessage, ListAgents, ToolSearch
---

# /brigade:file-tickets

Honour `${CLAUDE_SKILL_DIR}/../README.md` (the plugin contract). Read `.claude/brigade.md` before anything repo-specific. Every rail action goes through the six operations of Contract 3, performed by `/brigade:rail` for whichever adapter the config names.

## Contents

- [Who writes the rail](#who-writes-the-rail)
- [Pick the mode](#pick-the-mode)
- [Mode A — Slice a spec](#mode-a--slice-a-spec)
- [Mode B — One standalone ticket](#mode-b--one-standalone-ticket)
- [What not to do](#what-not-to-do)

## Who writes the rail

Firing a ticket is a rail write, and **only the sous chef writes the rail** (Contract 3).

- **Sous or solo session**: draft, get approval, then **fire** and **link** through `/brigade:rail`. On a markdown rail, commit per `rail.commit`: `direct` → one commit on trunk (`rail: fire S003-01..04`); `daily-pr` → onto the day's `rail/YYYY-MM-DD` branch.
- **Line-cook session**: never write. Draft the ticket(s) in full, then send the sous one `[rail]` message: `fire <n> ticket(s)` plus the drafts (or the absolute path of a scratch file holding them). The sous numbers and fires them, and replies with the ids.

## Pick the mode

| Mode | When | Creates |
|---|---|---|
| **A — Slice a spec** | a spec in `<docs.specs>` is approved, or the user says "break this into tickets" | one ticket per thin slice, `SNNN-NN`, lane A, with `blocked_by` edges |
| **B — Standalone** | something found mid-flight: a bug, a chore, a follow-up | one `BKLG-NNN` ticket, lane B |

If it's ambiguous, ask. Hygiene tickets (`HYG-NNN`, lane C) come from `/brigade:clean`, not from here.

**Mode B isn't for new capability.** Before firing standalone, ask yourself:

- Would a user notice the behaviour and have opinions about it?
- Would it plausibly need more than one slice?
- Is there a real fork in *what* to build, not just *how*?

Any yes → say so in one sentence and recommend `/brigade:brainstorm` or `/brigade:spec` first. If the human says fire it anyway, fire it, and note in the body that it has no spec. Never refuse.

## Mode A — Slice a spec

1. **Read the spec** and everything it links: brainstorm, research, decisions. If `<docs.specs>/NNN-<slug>/` already holds tickets, ask whether to add to them rather than re-slicing.
2. **Light code pass** (optional) with `Explore` or the repo's `codebase-*` agents, to guess each ticket's `files:` and to spot **prefactoring** ("make the change easy, then make the easy change"). A prefactor gets its own early ticket.
3. **Draft the slices.** Each ticket is a **tracer bullet**: it cuts through every layer it needs, can be demoed on its own, and fits one context window.
   - Slice by visible behaviour ("a user opens the page and sees X"), never by layer ("the migration", then "the API").
   - Prefactors first.
   - **Schema changes many readers depend on**: add first, move the readers while the check stays green, drop the old in a later ticket. One ticket per stage. Only one of them may carry a migration at a time (Contract 7), so chain them with `blocked_by`.
   - A dependency on **another spec's** ticket goes under `## Notes` in the body, not in `blocked_by`.
4. **Approval gate.** Present a numbered list: title, blocked by, what it delivers and who sees it, likely files. Ask: is the size right? Are the edges real? Merge or split anything? **Fire nothing until the human approves.** A cook sends this list to the sous as a `[gate]`; the sous takes it to the human if the slicing is a real product question.
5. **Fire.** Tickets go in `<docs.specs>/NNN-<slug>/NN-<slug>.md`, numbered `01`, `02`, … in dependency order. Their ids are `SNNN-01`, `SNNN-02`, …. Each starts from `${CLAUDE_SKILL_DIR}/../../templates/ticket.md` with `lane: A`, `spec: SNNN`, `status: backlog` (or `blocked` if a `blocked_by` entry is still open), `blocked_by`, and `files`. The body:

   ```markdown
   ## Why
   The end-to-end behaviour, in observable terms. Who sees it.

   ## Done when
   - [ ] <observable outcome>
   - [ ] `<check from config>` passes

   ## Notes
   Spec: SNNN. Cross-spec dependencies, prefactor reasoning.
   ```

   `/brigade:create-plan` mines the `Done when` boxes for its success criteria, so write them provable.

   On a github or jira rail, `/brigade:rail fire` creates the issues and `link` wires the blocked-by edges. The spec stays in `docs/specs/`; put the spec's path in each issue body.
6. **Update the spec.** Set its `status: sliced` and its INDEX row to `sliced · N tickets`. Create `<docs.specs>/NNN-<slug>/INDEX.md` with one row per ticket.
7. **Hand off.** Report every ticket id, which start blocked, and the first free one. Offer, by name, and wait: `/brigade:create-plan <id>` to plan now, or `/brigade:pick-ticket <id>` for picking it up cold later. The sous can assign free tickets to stations straight away.

## Mode B — One standalone ticket

1. **Raise the spec question once.** Accept the answer and move on.
2. **Ground it in reality.**
   - **Measure it.** Real numbers from the real system, not impressions.
   - **Name the code.** A `file:line` for the mechanism, read in this run.
   - **Check for siblings.** Use `/brigade:rail list` and search titles and bodies for the same keywords. If an existing ticket owns half of this, add to it instead (a rail write, so: sous only).
3. **Write it.** Next number = highest existing `BKLG-NNN` (on a markdown rail) plus one, zero-padded. The file is `<docs.backlog>/BKLG-NNN-<slug>.md`, from the ticket template with `lane: B`, `status: backlog`:

   ```markdown
   ## Why
   What's wrong (or missing), with the measurement that proves it. Who's affected.

   ## Options            <!-- only if there's a real fork -->
   1. … — trade-off

   ## Done when
   - [ ] <observable outcome>
   - [ ] `<check from config>` passes

   ## Notes
   The mechanism (file:line) and what you ruled out.
   ```

4. **Fire** through `/brigade:rail fire`, add the row to `<docs.backlog>/INDEX.md`, commit per `rail.commit`. Report the id and offer `/brigade:create-plan <id>` or `/brigade:pick-ticket <id>`, then wait.

## What not to do

- **Don't write the rail from a cook session.** Draft and send `[rail]`.
- **Don't reuse or skip a number**, and don't pick one outside the sous or a solo session.
- **Don't slice by layer.** A ticket is a slice with visible behaviour.
- **Don't oversize.** One ticket, one context window.
- **Don't invent labels, statuses or tracker fields.** Use the six operations and the statuses from Contract 3.
- **Don't set a claimed status** (`todo`, `in-progress`, `rfr`) here. Claiming belongs to `/brigade:pick-ticket` and `/brigade:create-plan`.
- **Don't fabricate** an id, a `file:line`, or a ticket you didn't read in this run.
