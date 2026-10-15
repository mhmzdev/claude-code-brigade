---
name: grill-me
description: Question the human relentlessly about a brainstorm, spec, plan, ticket, or bare idea until you both hold one picture of it. Maps the decisions as a tree and asks, each round, every question that can be answered now, numbered, each with a recommended answer. Facts are looked up, never asked, and decisions the record already holds are shown as settled, not asked again (the commis checks every round). Use when the user says "grill me", "grill this", "poke holes in this", "stress-test this", "what am I missing", or when /bk:pick-ticket reports the WHAT is still contested.
argument-hint: "<path to a brainstorm/spec/plan, a ticket id, or a topic>"
allowed-tools: Read, Edit, Write, Grep, Glob, Bash, Agent, Skill, AskUserQuestion, SendMessage, ListAgents, ToolSearch
---

# /bk:grill-me

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md` (in an installed plugin that's `…/plugins/cache/claude-code-brigade/bk/<version>/skills/README.md`, never a file in this repo). Read `.claude/brigade.md` before anything repo-specific.

**Station check first** (Contract 1): run `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" role`. If it prints `cook …`, you are a line cook even if nobody typed `/bk:line-cook` (e.g. after a `/clear`): read and follow `${CLAUDE_SKILL_DIR}/../line-cook/SKILL.md` for where questions go, the journal, and what a cook never does.

Interview the human until you share one understanding. This skill writes no code; it sharpens what comes before code. It fits in three places:

- **Lane A**: `brainstorm → grill-me → spec`, or `pick-ticket → grill-me → spec` for a backlog item that needs a spec, to harden the leaning approach before it becomes a contract.
- **Lane B**: `pick-ticket → grill-me → create-plan`, for a bug whose intended behaviour turns out to be unclear.
- **Before implement**: a last pass against a finished plan.

Method adapted from Matt Pocock's `grilling` skill (github.com/mattpocock/skills).

## Contents

- [Who you grill](#who-you-grill)
- [Step 0 — Read the input](#step-0--read-the-input)
- [The method — a decision tree, in rounds](#the-method--a-decision-tree-in-rounds)
- [Exit](#exit)
- [What not to do](#what-not-to-do)

## Who you grill

Always the **human**. Grilling is a design conversation, so it happens wherever the human chose to have it: usually the sous's or a solo session. The sous never answers grilling questions on the human's behalf.

**In a line-cook session, never start this yourself** (Contract 5): nobody is watching your terminal. Send the sous `[gate] <ID> needs grilling: <what's contested>` and wait. The sous grills the head chef, folds the decisions into the ticket (or sends you the ones that belong in your plan), and replies `[heard]`.

**The sous sent you a grilling `[brief]`, or the human typed `/bk:grill-me` in your station themselves?** Then the human is coming to this terminal: grill them, and ask with `AskUserQuestion` as this skill says. This is the one job where a cook asks the human directly. Four things differ from a sous session:

- Write `.claude/grilling` in your station first (`mkdir -p .claude && touch .claude/grilling`): the plugin's hook refuses `AskUserQuestion` in a station without it. Remove it when the grilling ends, before the `[status]` below.
- Send the sous `[status] grilling <ID> with the head chef` at the start.
- You can't write the rail, and specs and tickets live in the main checkout. So **log every decision where the brief says**:
  - a backlog item that needs a spec → go straight on to `/bk:spec`. It writes `<docs.specs>/draft-<slug>.md` in your station with the decisions in its Decisions section, and sends `[rail] spec draft ready: <absolute path>`, naming the item, for the sous to number and file;
  - an existing spec, or a ticket → write the decisions to `<docs.journal>/grill-<slug>.md` in your station (not `<ID>-…`, which is a ticket journal's name) and send `[rail] <ID> add decisions: <absolute path>`; delete the file on `[heard]`;
  - a bare topic, with nothing to attach them to → the same file, and give its path in the `[status]` line below; the sous decides where it belongs;
  - your own ticket's plan → straight into the plan.
- **Tell the sous it's done**: `[status] <ID> grilled: <one line of what was decided, and where it's written>`. Don't offer the next skill with a dialog; the brief already said what comes next.
- This session is now spent. Say so: it should be cleared before it takes a ticket.

## Step 0 — Read the input

Read the input **fully** before the first round:

- a doc path → the file;
- a ticket id → the rail's **read** operation (Contract 3), via `/bk:rail read <id>`;
- a bare topic → nothing yet.

Then read any earlier-stage file for the same work: the brainstorm, the spec, the plan. The record (Contract 12: `docs.decisions`, `docs.conventions`, `docs.knowledge`, `docs.questions`, past journals) holds decisions already made; the commis checks it for you every round, so you never re-argue one. If the artifact contradicts a recorded decision, *that* becomes a question.

## The method — a decision tree, in rounds

Map the artifact as a **decision tree**. The root is the WHAT and WHY. Below it hang scope, the shapes other code consumes, data, access, failure modes, rollout, and how each piece will be verified.

The **frontier** is every decision whose prerequisites are already settled: the questions you can ask *now* without guessing at answers you haven't heard. **Run the frontier past the commis before you ask it**: one `bk:commis` call (model: the config's `commis_model`, if set) with the whole round's questions, the artifact's path, the main checkout, the stations folder and the `docs:` map. A question it returns `settled` for, with a decision as its source, is not asked: it's shown as already settled, with the source, so the human can say "that changed". A `fact` answers the question outright: fold the fact in and drop the question. `nothing` and `conflict` are asked (a conflict is asked with both records cited). **Ask the whole remaining frontier in one round.** Number each question and give your recommended answer. Then stop and wait.

Format each round exactly like this:

```
✅ **Already settled** (say if any of these changed):
- <title>: <the decision> — <source path>, <date>

---

❓ **Q1** - **<title>**: <the question — may offer choices>

➡️ <recommended answer, and the one-line reason>

---

❓ **Q2** - **<title>**: <the question>

➡️ <recommended answer, and the one-line reason>
```

Leave the settled block out when there's nothing in it. A settled decision the human
overturns becomes a decision in this grilling's summary, marked `supersedes <source>`, so
the record is corrected when the decisions are filed.

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
   - plan → its decisions, and keep `open_questions:` honest (`/bk:implement` refuses a plan with an open question). A plan in a station is the cook's file: the sous sends the decisions as `[findings]` and the cook folds them in;
   - ticket → on a markdown rail, append a `## Decisions` section. That's a rail write, which the sous or a solo session may make. On a github or jira rail, add a comment.
   - no artifact → the summary is the input to the next skill.
3. **Hand off.** Solo or sous: offer with `AskUserQuestion`, then wait: lane A, or a backlog item that needs a spec → `/bk:spec` (name the item, so the spec closes it); a `kind: bug` or `kind: chore` backlog item → `/bk:create-plan`; or stop. In a station: no dialog; remove `.claude/grilling`, do what the brief said comes next, and send the `[status] <ID> grilled: …` line from [Who you grill](#who-you-grill).

The decisions a grilling produces are head-chef answers: once folded into the artifact they're in the record, and the sous's handoff promotes any that outlive the artifact into `docs.decisions` (Contract 12).

## What not to do

- **Don't ask a question whose prerequisite is still open.**
- **Don't ask what you can look up.** Grill decisions, not facts, and not decisions already made: the commis runs before every round.
- **Don't stop early.** A comfortable grilling didn't do its job. An empty frontier is the only exit.
- **Don't start implementing**, and never cite a `file:line`, ticket or PR you didn't read in this run.
