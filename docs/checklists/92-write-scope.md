---
ticket: "#92"
title: the plan's files: is the ticket's write scope; kitchen.sh scope checks the diff against it and finds colliding scopes
plan: docs/plans/92-write-scope.md
last_verified: 2026-11-03
---

# Acceptance — #92 the plan's files: is the ticket's write scope

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

### The pass checks the diff against the plan

1. A cook edits a file its plan's `files:` doesn't cover; the sous spawns the taster with `Scope check: kitchen.sh scope station-N` → exit 1, `outside (1):` with the path, and the taster reports `outside the plan's files: <path>; add it to the plan with why, or revert` as a numbered finding.
2. The cook adds the path to `files:` with a line of why under Decisions → How → the next `kitchen.sh scope` exits 0.

### The sous sequences overlapping tickets

1. Two stations plan; one has built, one has not → `kitchen.sh scope --overlap` prints `#A (station-1, planned) × #B (station-2, building)` with the shared paths and exits 1.
2. The sous briefs the second after the first merges (or the same cook) → the next run exits 0.

## Edge cases

- A `HYG-` ticket has no plan → skipped, exit 0. A branch with no ticket id → exit 0. A ticket with no plan → exit 1 and says so.
- A changelog fragment is inside only where the repo's config lists it under `scope: always_inside:`; with no key it is outside (nothing repo-specific in the plugin).
- Another ticket's journal is not this ticket's record → outside.
- Two globs that share no file on trunk do not collide (see Known limitations).

## Acceptance criteria

- [x] `kitchen.sh scope [station-N]` reads the plan whose `ticket:` is the branch's id and compares `changed_files` with its `files:`; prints inside and outside; exit 1 only when something is outside — `scope: a diff inside the plan's files: exits 0`, `scope: a path the plan never named is outside, and the exit is 1`, `scope: back inside, the exit is 0 again` pass; `kitchen.sh:1082` (`cmd_scope`)
- [x] exact paths, globs (`*` crosses `/`), folders ending in `/`, a trailing `(new)` and an inline `files: [a, b]` are all read — `scope: an exact path is inside`, `…a glob is inside, and * crosses /`, `…a folder pattern covers what is under it`, `…a trailing (new) and a comment on an entry are ignored`, `…an inline files: [a, b] reads the same` pass; `kitchen.sh:1032` (`scope_plan_files`), `:1045` (`scope_covers`)
- [x] the journal, checklist, plan, INDEX files and the config's changelog glob are always inside — `scope: the ticket's journal and checklist are inside, as record`, `…the INDEX files, the plan itself and the config's changelog glob are inside` pass; `kitchen.sh:1054` (`scope_record`), `:1013` (`cfg_scope_always`, inline and block list forms — `scope: the block form of always_inside: reads the same as the inline form`)
- [x] nothing repo-specific in the plugin: without the config key the fragment is outside — `scope: without the config's always_inside:, a changelog fragment is outside (nothing repo-specific in the plugin)` passes; this repo's `.claude/brigade.md` carries the key (the head chef's approved protected-path edit) and `kitchen.sh scope` on this branch reports `outside (0)`
- [x] no plan → exit 1, HYG and no-ticket skipped — `scope: no plan names the ticket: exit 1, and it says so`, `…a HYG ticket has no plan and is skipped, exit 0`, `…a detached station has no ticket, exit 0` pass
- [x] `kitchen.sh scope --overlap` compares every station's plan and diff with every other station's and with ready tickets' plan or `files:`, one row per collision as ticket (station, stage) × ticket with the paths, exit 1 on any — `overlap: a collision exits 1`, `…a plan written but not built collides with a build, each side with its stage`, `…a ready ticket's own files: is compared with a station's plan and diff`, `…a folder pattern is expanded against the files on trunk`, `…a station with no plan falls back to what it has changed (stage building)` pass; `kitchen.sh:1158` (`scope_overlap`)
- [x] `--ticket` limits the candidates; a ready ticket with no scope is named, not guessed; a held ticket isn't a candidate; the record is never a collision; disjoint scopes exit 0 — `overlap: --ticket limits the candidates to the ids named`, `…a ready ticket with no plan and no files: is named, not guessed`, `…a ticket a station already holds is not a candidate`, `…the record (INDEX files) is never a collision`, `…record files that a glob or folder pattern expands to (INDEX files, the stations' own plans) are never a collision`, `…disjoint scopes exit 0` pass
- [x] the collision tests can fail: with the `comm` line replaced by `common=""` seven overlap tests went red; with `cmd_scope`'s exit changed and `scope_record` disabled, seven scope tests went red (run by hand, restored)
- [x] the debrief gains `scope-drift` (scope repo, fix "a plan whose files: is honest, and a smaller ticket") — `a pass finding outside the plan's files is a repo finding, per ticket, with its fix`, `a ticket whose findings were about something else is not scope drift`, `--json carries the same findings` pass; `budget.js:293` (counted per ticket), `:318` (merged across sessions), `:476` (rule); red with the regex broken (two tests went red, restored)
- [x] the taster runs the scope check first and words the finding for the budget; `review-task` runs it before the checklist and lists the result; `create-plan` says `files:` is an enforced scope and how to widen it on purpose; `implement` makes a file outside `files:` a plan edit first; the sous-chef uses `--overlap` for assignment, plan sign-off and the pass — read: `taster.md:23`, `:28`; `review-task/SKILL.md:52`; `create-plan/SKILL.md:104`; `implement/SKILL.md:82`; `sous-chef/SKILL.md:155`, `:161`, `:298`, `:489`, `:497`; `templates/plan.md:10`
- [x] Contract 2 (`scope.always_inside`), Contract 4 (the rule), Contract 8 (a station's write scope), Contract 9 (the overlap sentence) and Contract 11 (the debrief) name it — `README.md:128`, `:407`, `:754`, and the Contract 9 and 11 sentences (`grep -n "scope" plugins/bk/skills/README.md`)
- [x] the pass's four findings are fixed: the block list form, glob expansions filtered through `scope_record`, the kitchen skill's `scope` rows (`plugins/bk/skills/kitchen/SKILL.md`, added to the plan's `files:` with a line of why), and the plan's Not doing line; the two new tests were red on the old code (run by hand)
- [x] the inspector's two findings are fixed (`scope_fm_ticket` replaced by `fm_text_get ticket`; the create-plan paragraph cut to a pointer at Contract 4) — `kitchen.sh` has no `scope_fm_ticket`; the scope tests still pass
- [x] no new shellcheck notes (`shellcheck -S info` on `kitchen.sh`: 8 before, 8 after) and `shellcheck -S warning` is clean on `kitchen.sh` and `tests/kitchen.test.sh`
- [x] this branch is itself inside its plan: `kitchen.sh scope` prints `outside (0):`, the output is in the handoff
- [?] the whole gate is green on the final tree — the receipt line from the cook's last `kitchen.sh check` is in the handoff (the check is the last act, after every write)
- [?] the next real pass: the sous spawns the taster with `Scope check: <kitchen.sh> scope <station-N>` and the finding appears in its report when a path is outside — runs after merge, on the next ticket

## Known limitations

- `*` crosses `/` (plain bash matching): a broad pattern covers a lot. The pass trusts the plan's `files:` is honest; the sous reads it at sign-off.
- Two globs that share no file that exists on trunk are not a collision: A's `lib/*.sh` against B creating `lib/new.sh` (a file that exists on neither trunk nor A's diff) is a blind spot until one of them has the file in its diff.
- A github-rail ticket has no `files:`, so a candidate is compared only by an existing plan or named with `--ticket`; otherwise it is listed as "no scope known".
- `scope-drift` sees the taster's wording in the `[findings]` the cook received; it cannot see the script's output.
