---
name: file-tickets
description: Put work on the rail. Two modes — slice an approved spec into thin end-to-end tickets (lane A, ids SNNN-NN, with blocked-by edges), or add one backlog item (lane B, BKLG-NNN): a bug, a chore, a follow-up, or a capability nobody has grilled or specced yet. Works on a markdown, GitHub or Jira rail through /bk:rail. Use when the user says "file a ticket", "make tickets", "break this into tickets", "slice this spec", "fire a ticket", "log this as a ticket", "add this to the backlog", "park this idea".
argument-hint: "[<path to spec> | <description of the one backlog item>]"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, Agent, Skill, AskUserQuestion, SendMessage, ListAgents, ToolSearch
---

# /bk:file-tickets

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md` (in an installed plugin that's `…/plugins/cache/claude-code-brigade/bk/<version>/skills/README.md`, never a file in this repo). Read `.claude/brigade.md` before anything repo-specific. Every rail action goes through the six operations of Contract 3, performed by `/bk:rail` for whichever adapter the config names.

**Station check first** (Contract 1): run `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" role`. If it prints `cook …`, you are a line cook even if nobody typed `/bk:line-cook` (e.g. after a `/clear`): read and follow `${CLAUDE_SKILL_DIR}/../line-cook/SKILL.md` for where questions go, the journal, and what a cook never does.

## Contents

- [Who writes the rail](#who-writes-the-rail)
- [Pick the mode](#pick-the-mode)
- [Mode A — Slice a spec](#mode-a--slice-a-spec)
- [Mode B — One backlog item](#mode-b--one-backlog-item)
- [What not to do](#what-not-to-do)

## Who writes the rail

Firing a ticket is a rail write, and **only the sous chef writes the rail** (Contract 3).

- **Sous or solo session**: draft, get approval, then **fire** and **link** through `/bk:rail`. On a markdown rail, commit per `rail.commit`: `direct` → one commit on trunk (`rail: fire S003-01..04`); `daily-pr` → onto the day's `rail/YYYY-MM-DD` branch.
- **Line-cook session**: never write. Draft the ticket(s) in full, write the drafts into your ticket's journal, then send the sous one `[rail] fire <n> ticket(s), see journal`. The sous numbers and fires them, and replies with the ids.

## Pick the mode

| Mode | When | Creates |
|---|---|---|
| **A — Slice a spec** | a spec in `<docs.specs>` is approved, or the user says "break this into tickets" | one ticket per thin slice, `SNNN-NN`, lane A, with `blocked_by` edges |
| **B — Backlog item** | anything that isn't a ticket yet: a capability, a change, a follow-up that changes behaviour (`kind: item`), a bug (`kind: bug`), or a chore whose outcome is already fixed (`kind: chore`) | one `BKLG-NNN` item, lane B |

If it's ambiguous, ask. Hygiene tickets (`HYG-NNN`, lane C) come from `/bk:clean`, not from here.

**Capturing a backlog item is cheap, whatever its size** (Contract 4). Don't push back on a big one and don't ask for a spec first: the backlog is where work waits before it becomes tickets. **Set `kind:` when you file it.** `bug` only when something that exists works wrong, measured against how it's meant to work. `chore` only when the outcome is already fixed and nobody would argue about it (a bump, a rename, a missing checklist item, a doc catching up with the code): nothing to decide, so no spec and the sous signs its plan. Everything else, however small, is `item`: it becomes a spec and tickets before anyone builds it. Not sure → `item`.

## Mode A — Slice a spec

1. **Read the spec** and everything it links: brainstorm, research, decisions. If `<docs.specs>/NNN-<slug>/` already holds tickets, ask whether to add to them rather than re-slicing.
2. **Light code pass** (optional) with `Explore` or the repo's `codebase-*` agents, to guess each ticket's `files:` and to spot **prefactoring** ("make the change easy, then make the easy change"). A prefactor gets its own early ticket.
3. **Draft the slices.** Each ticket is a **tracer bullet**: it cuts through every layer it needs, can be demoed on its own, and fits one context window.
   - Slice by visible behaviour ("a user opens the page and sees X"), never by layer ("the migration", then "the API").
   - Prefactors first.
   - **Schema changes many readers depend on**: add first, move the readers while the check stays green, drop the old in a later ticket. One ticket per stage. Only one of them may carry a migration at a time (Contract 7), so chain them with `blocked_by`.
   - A dependency on **another spec's** ticket goes under `## Notes` in the body, not in `blocked_by`.
4. **Approval gate.** Present a numbered list: title, blocked by, what it delivers and who sees it, likely files. Ask: is the size right? Are the edges real? Merge or split anything? **Fire nothing until the human approves.** A cook spawns `bk:commis` first (model: the config's `commis_model`, if set; the spec's Decisions may already settle the slicing), logs this list in its journal as a numbered `Qn` with the commis line, and sends `[gate] <ID> Qn, see journal. commis: <result>`; the sous takes it to the human if the slicing is a real product question.
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

   `/bk:create-plan` mines the `Done when` boxes for its success criteria, so write them provable.

   On a github or jira rail, `/bk:rail fire` creates the issues and `link` wires the blocked-by edges. The spec stays in `docs/specs/`; put the spec's path in each issue body.
6. **Update the spec.** Set its `status: sliced` and its INDEX row to `sliced · N tickets`. Create `<docs.specs>/NNN-<slug>/INDEX.md` with one row per ticket.
7. **Hand off.** Report every ticket id, which start blocked, and the first free one. Offer, by name, and wait: `/bk:create-plan <id>` to plan now, or `/bk:pick-ticket <id>` for picking it up cold later. The sous can assign free tickets to stations straight away.

## Mode B — One backlog item

1. **Check for siblings.** Use `/bk:rail list` and search titles and bodies for the same keywords. If an existing ticket owns half of this, add to it instead (a rail write, so: sous only).
2. **Ground it as far as it's known.**
   - **A bug (`kind: bug`):** measure it (real numbers from the real system, not impressions), name the code (a `file:line` for the mechanism, read in this run), and say what the intended behaviour is and where that's written. It gets a `## Done when`: a cook will plan straight from it.
   - **A chore (`kind: chore`):** say exactly what changes and what stays the same, and point at what fixed the outcome (the reviewer's comment, the checklist item, the dependency's changelog). It gets a `## Done when` too.
   - **An item (`kind: item`):** the `## Why` is enough: who wants it and what they can't do today. Don't design it here; that's the spec's job. Leave `## Done when` out, since the spec's tickets will carry it.
3. **Write it.** Next number = highest existing `BKLG-NNN` (on a markdown rail) plus one, zero-padded. The file is `<docs.backlog>/BKLG-NNN-<slug>.md`, from the ticket template with `lane: B`, `kind: item`, `kind: bug` or `kind: chore`, `status: backlog`:

   ```markdown
   ## Why
   What's wrong (or missing), with the measurement that proves it. Who's affected.

   ## Options            <!-- only if there's a real fork -->
   1. … — trade-off

   ## Done when         <!-- kind: bug and kind: chore; an item leaves this out -->
   - [ ] <observable outcome>
   - [ ] `<check from config>` passes

   ## Notes
   A bug: the mechanism (file:line) and what you ruled out. An item: links and constraints.
   ```

4. **Fire** through `/bk:rail fire`, add the row to `<docs.backlog>/INDEX.md`, commit per `rail.commit`. Report the id and its kind, and offer the next step by name: a bug or a chore → `/bk:pick-ticket <id>`; an item → `/bk:grill-me <id>`, then `/bk:spec`. Then wait.

## What not to do

- **Don't write the rail from a cook session.** Draft and send `[rail]`.
- **Don't reuse or skip a number**, and don't pick one outside the sous or a solo session.
- **Don't slice by layer.** A ticket is a slice with visible behaviour.
- **Don't oversize.** One ticket, one context window.
- **Don't invent labels, statuses or tracker fields.** Use the six operations and the statuses from Contract 3.
- **Don't set a claimed status** (`todo`, `in-progress`, `rfr`) here. Claiming belongs to `/bk:pick-ticket` and `/bk:create-plan`.
- **Don't fabricate** an id, a `file:line`, or a ticket you didn't read in this run.
