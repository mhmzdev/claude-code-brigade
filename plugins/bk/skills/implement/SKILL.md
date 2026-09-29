---
name: implement
description: Carry out an approved plan phase by phase — run the config's check after every phase, tick criteria honestly, keep the plan's status and the rail current — then hand off to clean check and review-task (lanes A/B), or to clean check and the pass (lane C). Hygiene (HYG) tickets run straight from the ticket body with no plan; the proof is the counter going down. Refuses a plan that isn't approved or still carries open questions. Never commits. Use when the user says "implement this", "build the plan", "start coding", "execute BKLG-004", "work HYG-002", "/bk:implement".
argument-hint: "[plan path | ticket id] (usually nothing: it finds this station's plan)"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, Agent, AskUserQuestion, ListAgents, SendMessage, ToolSearch
disable-model-invocation: true
---

# /bk:implement

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md` (in an installed plugin that's `…/plugins/cache/claude-code-brigade/bk/<version>/skills/README.md`, never a file in this repo). Read `.claude/brigade.md` first: `trunk`, `check`, `docs.plans`, `rail`, `walk_in`, `migrations`, `clean.counters`.

**Station check first** (Contract 1): run `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" role`. If it prints `cook …`, you are a line cook even if nobody typed `/bk:line-cook` (e.g. after a `/clear`): read and follow `${CLAUDE_SKILL_DIR}/../line-cook/SKILL.md` for where questions go, the journal, and what a cook never does.

You're executing a plan, and **being started is the sign-off.** This skill has
`disable-model-invocation: true`: only a human can type it, so the human typing it has
approved the plan and every commit under it. **Follow the plan, don't redesign it.** Every line you write matches the repo's live conventions.

**Where it sits:** `create-plan` → **`implement`** → `clean check` → `review-task` → the pass → `open-pr`. Lane C: `pick-ticket` → **`implement`** → `clean check` → the pass → `open-pr`.

## Contents

- [Step 0 — Find the work and gate it](#step-0--find-the-work-and-gate-it)
- [Step 1 — Branch and start](#step-1--branch-and-start)
- [Step 2 — The phase loop](#step-2--the-phase-loop)
- [Step 3 — Drive to green](#step-3--drive-to-green)
- [Step 4 — Finish and hand off](#step-4--finish-and-hand-off)
- [Lane C — hygiene tickets](#lane-c--hygiene-tickets)
- [What not to do](#what-not-to-do)

## Step 0 — Find the work and gate it

1. **A `HYG-*` ticket?** Go to [Lane C](#lane-c--hygiene-tickets).
2. **Find the plan.** A path → read it fully. A ticket id → `<docs.plans>/<id>-*.md`.
   **Nothing** (the usual case in a station: the chef just types `/bk:implement`) → work
   it out, in this order:
   - the ticket id in the branch name (`bklg-004-fix-login` → `BKLG-004`,
     `s001-02-…` → `S001-02`), then `<docs.plans>/<ID>-*.md`;
   - else the one plan in `<docs.plans>/` with `status: draft` that this branch or working
     tree added (`git status --porcelain -uall` plus `git diff --name-only origin/<trunk>...HEAD`).

   Say which plan you picked in the scope line, so a wrong guess is visible at once. Several
   candidates → list them and ask which (the one question this skill may ask up front).
   None → stop and route to `/bk:create-plan <ID>`. A plan is never written here.
3. **The gates — fail loudly, no override flag.**

   ```bash
   grep -c '^open_questions: none$' "$PLAN"      # must print 1
   grep -nEi '^#{1,4} .*open question|(^|[^A-Za-z])TBD([^A-Za-z]|$)|TODO\(decide\)|\?\?\?|<decide>' "$PLAN"   # must print nothing
   grep -E '^status: (draft|approved|active)$' "$PLAN"  # draft → set approved now; done → stop, it shipped
   ```

   - Unresolved questions, or no `open_questions:` key → say what you found with line numbers, that nothing changed, and that the next step is `/bk:create-plan` or `/bk:grill-me`. Never add the line yourself; that forges the check.
   - `status: draft` is normal: typing this skill is the sign-off. Set `status: approved` with
     `approved: YYYY-MM-DD` and carry on. Don't ask for a second approval. (A cook sends
     `[status] <ID> implement started (signed off)`.)
4. **Resume check.** Phases already marked `**Status:** Done` and `status: active` → resume at the first unfinished phase.
5. **Claim check.** The ticket's rail status is `todo` with you as cook, or `in-progress` with you as cook. Anyone else → stop.

## Step 1 — Branch and start

1. Branch off fresh trunk, never work on trunk: `git fetch origin && git switch -c <lowercase id>-<slug> origin/<trunk>` (or switch to the existing branch when resuming).
2. Set the plan's `status: active`. Move the rail to `in-progress`: cook → `[rail] <ID> → in-progress`; sous or solo → the rail's **claim** operation.
3. **State the scope in one message and begin**: phases, files, the check command. The plan was approved; **don't ask for a second go-ahead.**
4. Read the files the current phase touches and their nearest siblings. Match what's there. Don't re-audit the codebase — if the plan lacks research, that's a plan defect to name.

## Step 2 — The phase loop

One plan phase per pass:

1. **Build it** in the plan's order. Honour the repo's `CLAUDE.md` and rules; read them, don't assume.
2. **The walk-in.** About to run a destructive command on a `walk_in:` resource (reset, reseed, tear down)? Cook → `[walk-in] about to run <command> on <resource>, OK?` and wait. Prefer the resource's `safe:` command when one exists.
3. **Check.** Run the config's `check` plus anything the phase names. Capture the real exit code (`out=$(<cmd> 2>&1); rc=$?`), not a pipe's. When the output is long, run it through the `runner` sub-agent (`subagent_type: "bk:runner"`) so only pass/fail and the failing lines reach your context: across several phases that's the difference between finishing in the smart part of the window and not.
4. **Record** in the plan file (it survives a context clear): the phase's `**Status:** Done`, ticked automated criteria, a one-line summary of files changed.
5. **Carry manual criteria forward — don't pause for them.** Leave them unticked; you'll list them all once in Step 3.
6. **Next phase straight away.** A phase finishing is not a question.

**Stop only for a real question** — and route it per Contract 5:

| Situation | Who |
|---|---|
| the plan is wrong or contradicts the repo | human — back to `/bk:create-plan` |
| a dependency the plan never mentions blocks you | sous by `[gate]` (solo: human) |
| the same fix has failed ~3 times | sous by `[gate]` (solo: human) |
| a decision only the human can make (destructive migration, credential, anything outward-facing) | human |

Never accumulate broken state. Don't build beyond the plan.

## Step 3 — Drive to green

Run every automated criterion, starting with `check`, until all pass. Report honestly: red shows its output. **Never tick a criterion you didn't run**, and don't claim a test reaches a layer it doesn't.

List the manual criteria from every phase as one numbered checklist. In a station, send it with the handoff; solo, show it to the human.

## Step 4 — Finish and hand off

1. Set the plan's `status: done` (implementation finished; merge is tracked on the rail, not here) and update its `INDEX.md` row.
2. Leave the rail at `in-progress`. `review-task` moves it to `rfr`.
3. **Don't commit.** Commits happen in `open-pr`: after the sous's pass in a station, or when the human runs `/bk:open-pr` solo (running it is the yes).
4. Hand off: lanes A/B → `/bk:review-task <plan>`. It's not optional for a feature. Never auto-chain; say it and stop (a cook continues by itself: `/bk:clean check`, then `/bk:review-task`).

## Lane C — hygiene tickets

Hygiene tickets skip the plan and the checklist (Contract 9). The ticket body **is** the plan: the exact findings, the counter it must move, and its start value.

1. Gate: the ticket is `HYG-*`, it's claimed by you (`in-progress`), and its body names a counter from `clean.counters` with a number.
2. Branch as in Step 1. Rail → `in-progress` if it isn't already.
3. Run the counter's `command` once and record the **before** count. It should match the ticket; if it's wildly different, trunk moved — say so to the sous before cutting.
4. Work the findings in the body — only those. Run `check` after each logical batch.
5. Run the counter again: the **after** count. The ticket is done when the named findings are gone and `check` is green.
6. Record the before → after numbers in the journal (they go in the PR body). No review-task, no checklist. Cook: `/bk:clean check` → `[handoff]` to the sous → on `[go]`: `clean around` → `handoff` → `open-pr`. Solo: `/bk:open-pr <ID>`.

## What not to do

- Don't start on a plan with open questions, or one the chef hasn't signed off.
- Don't redesign mid-build. Stop and say the plan is wrong.
- Don't pause between phases for approval.
- Don't hard-code a command, branch or path — read the config.
- Don't run a destructive walk-in command without the sous clearing it.
- Don't write the rail from a cook session. Ask the sous.
- Don't commit, push or open a PR here. Never `reset --hard` or force-push.
- Don't claim a criterion passed that you didn't run.
