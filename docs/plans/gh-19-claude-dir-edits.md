---
ticket: "#19"
title: A plan that edits .claude/ is seen coming, and a denied edit is a gate, never a workaround
status: done
approved: 2026-10-25
lane: B
created: 2026-10-25
open_questions: none
migration: false
files:
  - plugins/bk/skills/README.md
  - plugins/bk/skills/create-plan/SKILL.md
  - plugins/bk/skills/line-cook/SKILL.md
  - plugins/bk/skills/implement/SKILL.md
  - plugins/bk/skills/sous-chef/SKILL.md
  - plugins/bk/skills/setup/SKILL.md
  - plugins/bk/templates/plan.md
  - README.md
  - PLAYBOOK.md
  - plugins/bk/.claude-plugin/plugin.json
  - Formula/bk.rb
  - CHANGELOG.md
  - docs/plans/INDEX.md
  - docs/plans/gh-19-claude-dir-edits.md
  - docs/journal/INDEX.md
  - docs/journal/19-claude-dir-edits.md
---

# #19 — A plan that edits .claude/ is seen coming, and a denied edit is a gate, never a workaround

## Why

Cooks run with `permission_mode: auto`. In auto mode an Edit to a file under `.claude/` (and
once, the root `CLAUDE.md`) is refused and never prompts. The sous's `[approved]` doesn't
lift it and neither does the head chef saying yes in the sous's terminal, so the ticket
sat until the head chef went to the cook's own terminal. The kitchen should have seen it
coming (the ticket's words), and a cook that gets refused should know exactly what to do.

## Current state

- **What Claude Code does** (docs, read 2026-10-25; journal fact entry): `.claude/` is a
  *protected directory* (so are `.mcp.json` and `.claude.json`; `.claude/worktrees/` is
  excepted). In auto mode a write there goes to the classifier, and "`permissions.allow`
  rules in settings files do not pre-approve protected-path writes": the check runs before
  allow rules are read. In `default` and `acceptEdits` the write prompts, in `dontAsk` it is
  denied, in `bypassPermissions` it is allowed. The classifier ignores `autoMode` in project
  settings. The docs don't list the root `CLAUDE.md` as protected, and don't say whether the
  classifier ever refuses it; the issue says one cook was.
- **Nothing in the plugin knows this.** `create-plan` writes a plan's `files:` and body with
  no protected-path step (`plugins/bk/skills/create-plan/SKILL.md:86-130`); the sous's sign-off
  looks at migrations, walk-in resources, production writes and unrecorded decisions only
  (`plugins/bk/skills/sous-chef/SKILL.md:283-291`, `plugins/bk/skills/README.md:467-471`); the
  line-cook table has no row for a denied tool call
  (`plugins/bk/skills/line-cook/SKILL.md:112-126`).
- `kitchen.sh` seeds a station's `.claude/settings.local.json` with Bash allow rules only
  (`plugins/bk/skills/kitchen/kitchen.sh:597-612`).
- The guard hook refuses a `[gate]` only when it carries a numbered question (`Q3`) with no
  `commis:` (`plugins/bk/hooks/guard.sh:75-80`), so a gate that is not a question passes.
- The commis found nothing recorded on any of this (journal A1). The contract's gap table
  already says a missing permission is an `access` gap that the head chef provides
  (`plugins/bk/skills/README.md:830`).

## Desired end state

1. The contract names **protected paths** once, says a plan that edits one goes to the head
   chef at sign-off, and says a cook refused an edit sends a `[gate]` and waits: it never
   routes around the refusal, and the sous never makes the edit for it.
2. `create-plan` makes a cook look for protected paths in its `files:`, write a "Protected
   paths" section, and say so in `[plan]`.
3. The sous's sign-off treats such a plan as the head chef's, telling them which station
   and which phase, and what they can do there.
4. `line-cook` and `implement` carry the denied-edit rule; the sous's sign-off section says
   how it answers that gate.
5. The README troubleshooting table and the PLAYBOOK say the same to the head chef.
6. Verify: `scripts/check.sh` is green, and `git grep` finds no skill that lists the
   head-chef overrides without the new one (Phase 4).

## Decisions

The first three are not in the record (journal A1: `nothing`), so they are the head chef's
to confirm at sign-off. The sous's brief says to name them here.

1. **Which of the issue's three ideas to build.** *Build idea 1 (flag the plan at
   `create-plan` and at sign-off) and idea 3 (the cook's denied-edit rule). Don't build
   idea 2 as an allow rule.* Reason, a fact: Claude Code checks protected paths before it
   reads allow rules, so a seeded or documented `Edit(.claude/**)` allow does nothing for
   `.claude/**`. What the head chef can do up front is be at the station when the cook
   reaches the edit, so the docs say that instead (README troubleshooting, PLAYBOOK). No
   permission is added or widened anywhere, `kitchen.sh` and `setup` don't change.
   *Alternative:* seed an allow rule anyway and note it may not hold. Rejected: it would
   look like a fix and not be one, and widening cooks' permissions is the head chef's call
   (contract gap table, `access`).
2. **Who signs a plan with protected paths.** *The head chef, for every kind, a new hard
   override next to a migration, a walk-in resource and a production write (Contract 5).*
   The edit can't happen without them at the cook's terminal, so their attention is needed
   either way and sooner is better than mid-build. *Alternative:* the sous signs a bug or
   chore plan by its kind and tells the head chef in its one line. Cheaper, but the cook
   starts building and the stall comes as a surprise, which is the ticket's complaint.
3. **What counts as a protected path.** *Anything under `.claude/` except
   `.claude/worktrees/`, `.mcp.json`, `.claude.json`, and the root `CLAUDE.md`.* The first
   three are the docs' list; `CLAUDE.md` is there because the issue saw a refusal, and a
   false flag costs the head chef one line, a missed one costs a stalled ticket.
4. **A denied edit is a `[gate]` that isn't a question.** Form: `[gate] <ID> edit denied:
   <path>, <the tool's words>`. No commis (there is nothing to look up) and no `Qn`, so the
   hook doesn't ask for a `commis:` line. The cook waits; it never retries through another
   route (a Bash redirect, `sed -i`, `cp`, `git apply`, a sub-agent), never edits settings
   to allow it, never changes its own permission mode.
5. **The sous never makes the edit, and never relays "yes" in place of lifting it.** The
   head chef lifts it at *that cook's terminal*: they make the edit themselves, or move that
   session to a mode that prompts for `.claude/` writes (`default` or `acceptEdits`), then
   tell the sous, who sends `[heard]`. That is a second planned exception to "the head chef
   talks to the sous only" (the first is a grilling).
6. **No code, so no new test.** Nothing mechanical is added: the flag is prose the cook and
   sous follow, the same as the other sign-off overrides. A mechanical flag (for example
   `kitchen.sh files` marking protected paths) is left out of this change.

## Not doing

- No `permissions.allow` seed, no `autoMode` setting, no `kitchen.sh`, `setup`, `guard.sh` or
  `bin/bk` change, and no new config key.
- No per-kitchen `permission_mode` advice (a mode that prompts would stall every unattended
  cook, which is why `auto` is the default).
- No change to the Window, the budget or the rail.
- Edits to `sous-chef/SKILL.md` stay in "The plan sign-off" plus one line of "Division of
  labour" that repeats the override list (the brief limited station-2 to the sign-off
  section; the sous is told about the one extra line).

## Approach

Follow the way the walk-in and the production write are handled: the contract states the
rule once (Contract 5, with the message kinds in Contract 6), each skill repeats the part
its role needs and points at the contract, and the user docs say it in plain words. The new
sign-off override reuses the existing head-chef-by-override path in Contract 5 and the sous
skill's step 4. The denied-edit gate reuses the gates-that-aren't-questions
exception already in `line-cook/SKILL.md:~110` (`needs grilling`, `production write`).

## Phase 1: The contract

**Status:** Done — `plugins/bk/skills/README.md` only: Contract 5 (two planned exceptions, override list, two new bullets, "Who answers" cook cell and new row), Contract 6 (`[gate]`, `[plan]` rows). `check`: the 7 kitchen-test failures (59, 60, 107, 109, 115, 116, 123) are identical on a clean `origin/main` (not this change); the version failure is Phase 4's.

### Changes

#### `plugins/bk/skills/README.md:402-405` (edit) — the planned exceptions

Where it says "The one planned exception is a grilling the sous hands to a cook", make it
two: the grilling, and an edit the cook's permissions refuse (the head chef must lift that
one at the cook's terminal, see below). Keep the sentence about the cook doing as told and
sending the sous one `[status]` line.

#### `plugins/bk/skills/README.md:467-471` (edit) — the override list

```
Whatever the kind, a plan goes to the **head chef** when it carries a migration, touches a
`walk_in:` resource, needs a production write, edits a protected path (below), or makes a
decision the record doesn't hold …
```

#### `plugins/bk/skills/README.md` after line 490 (edit) — two new bullets

```
- **A plan that edits a protected path goes to the head chef.** A protected path is one
  Claude Code won't let a session in auto mode edit, whatever the sous has signed: anything
  under `.claude/` (except `.claude/worktrees/`), `.mcp.json`, `.claude.json`, and the
  root `CLAUDE.md` (not on Claude Code's list, but a cook was refused it once). An allow
  rule in settings doesn't change that: Claude Code checks protected paths before it reads
  allow rules. So the head chef can't open the path in advance; they can be at the cook's
  terminal when it gets there. The plan has a "Protected paths" section (the files, the
  phase, last when the order allows), the `[plan]` message says so, and the sous shows the
  head chef which station and phase and what they will do there, before any `[approved]`.
- **A tool call the cook's permissions refuse is the head chef's to lift, never the
  sous's.** The cook sends `[gate] <ID> edit denied: <path>, <the tool's words>` (a gate
  that isn't a question: no commis, no `Qn`) and waits. It doesn't retry the edit another
  way (a shell redirect, `sed -i`, `cp`, `git apply`, a sub-agent), doesn't edit settings
  to allow it and doesn't change its own permission mode. The sous doesn't make the edit
  for it and doesn't relay a "yes" as if it lifted the refusal: either would hand the
  permission decision to a session that wasn't refused. The head chef lifts it in the
  cook's terminal (the edit themselves, or that session moved to a mode that prompts),
  tells the sous, and the sous sends `[heard]`.
```

#### `plugins/bk/skills/README.md:499` (edit) — the "Who answers" table, cook column

Add "edits a protected path" to the list after "a production write".

#### `plugins/bk/skills/README.md:509` (edit) — a new row after "Filing a public issue"

```
| A tool call the cook's permissions refuse (a protected path in auto mode) | human, at the prompt | cook sends `[gate] <ID> edit denied: <path>, …` and waits; the sous tells the head chef which station, and the head chef lifts it **in that cook's terminal**; no session does it for them |
```

#### `plugins/bk/skills/README.md:537, 543` (edit) — Contract 6

`[gate]` row: add "or the refusal `edit denied: <path>, <the tool's words>`". `[plan]` row:
add "and its protected paths, if any".

### Success criteria

- [ ] `scripts/check.sh` passes
- [ ] `grep -n 'protected path' plugins/bk/skills/README.md` shows the definition once and
      the uses pointing at it
- [ ] Contract 5's "who signs" prose, its table and the sous skill name the same overrides
      (checked by the sweep in Phase 4)

## Phase 2: The skills

**Status:** Done — create-plan, line-cook, implement, sous-chef (sign-off section + one Division-of-labour line), plan template. check as Phase 1.

### Changes

#### `plugins/bk/skills/create-plan/SKILL.md:104-130` (edit) — the plan body

Add one optional section after "Not doing" in the body list, and a line after the list:

```
## Protected paths          — only when `files:` lists one (Contract 5): each path, the phase that edits it (its own phase, last when the order allows), and "auto mode will refuse this edit; the head chef lifts it at the station"
```

#### `plugins/bk/skills/create-plan/SKILL.md:134-150` (edit) — Step 6

In point 4 (present it), add: "List any protected paths (Contract 5) in the line." In the
cook bullet, change `[plan] <ID> ready: <absolute path>` to carry `· protected paths:
<list>` when there are any, and add them to the head-chef list ("a migration, a walk-in
resource, a production write, a protected path or an unrecorded decision").

#### `plugins/bk/skills/create-plan/SKILL.md:132` (edit) — "Done only when"

Append: "every path in `files:` has been checked against the protected paths in Contract 5."

#### `plugins/bk/templates/plan.md` (edit) — add an optional `## Protected paths` section (with the contents list entry) after "Approach", with a one-line comment saying to delete it when `files:` has none.

#### `plugins/bk/skills/line-cook/SKILL.md:120` (edit) — plan sign-off row

Add "a protected path" to the list of what goes to the head chef, and "(send the paths in
`[plan]`)".

#### `plugins/bk/skills/line-cook/SKILL.md:125` (edit) — new row after "Merge, deploy"

```
| An Edit or Write the permissions refuse ("self-modification", a protected path under `.claude/`, or any denial) | **sous**, as `[gate] <ID> edit denied: <path>, <the tool's words>`, then wait. Not a question: no commis. Never retry another way, never change settings or your own permission mode, never ask the sous to make the edit. The head chef lifts it at **this** terminal (they edit, or move this session to a mode that prompts); do what they say, then send the sous a `[status]` line |
```

#### `plugins/bk/skills/line-cook/SKILL.md:193-204` (edit) — Things you never do

```
- Work around a denied tool call: another command that writes the same file, a request that someone else edit it, a change to settings or to your permission mode. Send the `[gate]` and wait.
```

Also the intro sentence of "Where each question goes" that lists non-question gates
(`needs grilling`, `need a test account`, `production write`, `no [approved] on record`):
add `edit denied`.

#### `plugins/bk/skills/implement/SKILL.md:95-103` (edit) — the stop table

```
| a tool call is refused by permissions (a protected path in auto mode) | sous by `[gate] <ID> edit denied: <path>, <the tool's words>` (solo: say so and stop). Never work around it (Contract 5); wait for `[heard]`, then retry the same edit |
```

and in "What not to do" (line 133-140): "Don't route around a refused edit. It's a gate."

#### `plugins/bk/skills/sous-chef/SKILL.md:283-291` (edit) — sign-off step 4

Add "edits a protected path (Contract 5)" to the head-chef conditions, and an instruction:
the summary to the head chef says which station and which phase, and *"auto mode won't let
the cook edit it; when it gets there you either make the edit in the cook's terminal or
move that session to a mode that prompts"*.

#### `plugins/bk/skills/sous-chef/SKILL.md` after line 316 (edit) — a paragraph at the end of the section

```
**A cook's `[gate] <ID> edit denied: <path>, …`** is not a question for the record. Tell
the head chef in one line which station and which file, and wait; the cook waits. You never
make the edit (you never write in a station) and you never send a yes as if it lifted the
refusal: the head chef lifts it in the cook's terminal. When they say it is done, send the
cook `[heard]`.
```

#### `plugins/bk/skills/sous-chef/SKILL.md:46` (edit) — Division of labour, head chef row

Add "a protected path" to "(and any plan with a migration, a walk-in resource, a production
write or an unrecorded decision)". One line outside the sign-off section; the sous is told.

### Success criteria

- [ ] `scripts/check.sh` passes (frontmatter and `## Contents` lists still hold; no heading
      is added to any skill)
- [ ] `git grep -n 'edit denied' plugins/bk` finds it in the contract, create-plan's
      neighbours (line-cook, implement) and sous-chef
- [ ] Manual: read the line-cook table and `implement` stop table: every route for a refused
      edit ends in "send the gate and wait"

## Phase 3: What the head chef reads

**Status:** Done — README troubleshooting row, PLAYBOOK paragraph, table rows and override lists. check as Phase 1.

### Changes

#### `README.md:262` (edit) — Troubleshooting table, new row

```
| a cook has sat on one edit for a long time, and the sous says "edit denied" | auto mode refuses writes under `.claude/` (and sometimes `CLAUDE.md`); an allow rule in settings doesn't help, and no session may do it for the cook | go to that cook's terminal: make the edit yourself, or move that session to a mode that prompts (`default` or `acceptEdits`), then tell the sous |
```

#### `PLAYBOOK.md:477` (edit) — "When something looks wrong", new paragraph before "A cook is waiting"

```
**A plan edits `.claude/` (or `CLAUDE.md`).** Claude Code won't let a cook in auto mode edit
those, and an allow rule in settings doesn't change that. The sous brings that plan to you
whatever its kind, saying which station and phase. When the cook reaches the edit it sends
`edit denied` and waits; the sous can't do it for the cook and your yes in the sous's
terminal doesn't lift it. Go to that cook's terminal, make the edit yourself or move that
session to a mode that prompts, then tell the sous.
```

Also the PLAYBOOK's "who signs a plan" answer (grep `plan_approval|signs off` in
`PLAYBOOK.md`) gets "a protected path" in its list of overrides, if it lists them.

### Success criteria

- [ ] `scripts/check.sh` passes
- [ ] `git grep -n 'migration, a walk-in' README.md PLAYBOOK.md` lists every place the
      overrides are listed, and each also says protected path

## Phase 4: Release and consistency

**Status:** Done — 0.28.0 (plugin.json, Formula url, CHANGELOG), INDEX rows existed; sweep ran, in-plan fixes made, the rest sent to the sous (journal). check as Phase 1.

### Changes

#### `plugins/bk/.claude-plugin/plugin.json` (edit) — `version` 0.27.3 → 0.28.0 (minor: how a kitchen runs changes). If station-1 merges first, bring `main` in and bump again.

#### `Formula/bk.rb` (edit) — `url` to the `v0.28.0` tag.

#### `CHANGELOG.md` (edit) — new top entry

```
## [0.28.0] - 2026-10-25

**A plan that edits `.claude/` now comes to you before the cook starts, and a refused edit
is a gate.** ... What you must do: nothing to install; when the sous says a plan edits a
protected path, be at that cook's terminal when it reaches the edit.
```

(Short paragraph for the busy human: what changed, the Claude Code fact that allow rules
don't lift it, and what they do.)

#### `docs/plans/INDEX.md` (new) and `docs/journal/INDEX.md` (new) — one row each for this ticket (plan and journal), so `kitchen.sh doctor` doesn't warn about a folder with no INDEX.

#### Consistency sweep (no file change unless it finds one)

`git grep -n -i -E "walk-in resource|walk_in. resource|production write" -- plugins README.md PLAYBOOK.md`
and read each hit that lists head-chef overrides; each must include "protected path". A
fresh read-only sub-agent does the whole-contract read the repo asks for after a prose change
across several skills (`CLAUDE.md`, "Checking a change").

### Success criteria

- [ ] `scripts/check.sh` passes on the branch (version above `origin/main`'s, CHANGELOG
      entry on top, formula url matches)
- [ ] `plugins/bk/hooks/guard.sh` is untouched: `git diff --stat origin/main -- plugins/bk/hooks plugins/bk/skills/kitchen/kitchen.sh bin` prints nothing
- [ ] The sweep's read-only sub-agent lists no file that disagrees with the contract

## Testing

No behaviour in `kitchen.sh`, `guard.sh`, `bin/bk` or `budget.js` changes, so the suites
need no new test (`CLAUDE.md`: a test for added script behaviour). They still run inside
`scripts/check.sh`. The prose has no automated check: the Phase 4 sweep is the check, as the
repo's `CLAUDE.md` asks.

## Risks

- **The docs may be wrong about `CLAUDE.md`.** If the classifier never refuses it, the flag
  costs a head-chef sign-off on plans that edit it. Decision 3 accepts that; it is one line
  to drop later.
- **A head-chef sign-off for every such plan slows bug plans that edit a skill under
  `.claude/` in a repo that keeps its skills there.** Accepted for the same reason as
  Decision 2: the head chef is needed at the station anyway.
- **Claude Code may change what it protects.** The contract states the list and where it
  comes from (the docs' protected-paths section), so one place changes.

## References

- Ticket: https://github.com/mhmzdev/claude-code-brigade/issues/19
- Claude Code docs: permission-modes.md ("Protected paths"), auto-mode-config.md ("Where the
  classifier reads configuration")
- Contract 5 and 6: `plugins/bk/skills/README.md:386-557`
- Same shape (a rule in the contract, repeated by role): the production-write gate,
  `plugins/bk/skills/line-cook/SKILL.md:124` and `plugins/bk/skills/README.md:183-188`
- Open question on permission rules written by setup, related, not blocking:
  `docs/questions/mechanical-enforcement.md:59` (row 12)
