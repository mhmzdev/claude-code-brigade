---
ticket: "#62"
plan: docs/plans/62-budget-sous-role.md
last_verified: 2026-11-03
---

# Acceptance — #62 The budget counts only the real sous as the sous

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

### A shift with a sous, cooks and the head chef's own session in the main checkout

1. `.claude/sous` names `app-sous`; the registry lists `app-sous` (sous2) and `chef` (chef1), both in the main checkout → `kitchen.sh budget --json` gives sous2 role `sous` and chef1 role `head chef`.
2. `kitchen.sh budget` → a `head chef` row in Sessions, and a `Head chef (not in the shift): …` line; the Shift line leaves their spend out.
3. `kitchen.sh debrief` → `context-bloat` counts only the cook's heavy session, not chef1's.

## Edge cases

- A past shift's sous (no longer in the registry) that sent `[go]`, and a sous that sent `[brief]` → still `sous`.
- No name in `.claude/sous` → the newest live main-checkout session is the sous (the Window's pick); the older live one is the head chef unless it spoke as the sous.
- A name recorded that no live session carries → no fallback: the live sessions are the head chef's; a past sous is still found by what it sent.
- A head-chef session that sent a `[plan]` naming a ticket → makes no ticket row.

## Acceptance criteria

- [x] The budget's role for a main-checkout session is `sous` only for the session named in `.claude/sous` (or, with no name recorded, the one the Window would pick, or one that spoke as the sous per A1); every other one is `head chef` — `tests/budget.test.sh` 15 "the live session named in .claude/sous is the sous", 16 "another main-checkout session is the head chef, not the sous", 25, 26; code `plugins/bk/window/server/live/budget.js:192-203` (`sousSessionId`) and `:225` (`session()` resolves `main`)
- [x] A recorded name with no live session gets no "newest" fallback (plan choice 1, approved) — test 27; `budget.js:200`
- [x] A past shift's sous and a sous before a `/clear` stay the sous (A1, rule B) — tests 17, 18, 28; `budget.js:225` (`SOUS_ONLY`)
- [x] `kitchen.sh budget` shows `head chef` rows separately and outside the shift — tests 22, 23, 20; `budget.js:501` (the line), `:362` and `:371` (the shift leaves them out, `headChef` reports them)
- [x] `kitchen.sh budget --json` carries the role and a `headChef` figure and an `actors["head chef"]` row — tests 16, 19, 20 (all read the JSON)
- [x] The debrief's `context-bloat` rule never calls a head-chef session the sous; it skips it (plan choice 3, approved) — test 24; `budget.js:431`
- [x] A head-chef session is not treated as a cook (no ticket spans) — test 21; `budget.js:353`
- [x] The new tests go red with the old classification — with `session()` forced to `role = 'sous'`, 9 cases failed (16, 19, 20, 22, 23, 24, 26, 27, 61); five more single mutations each turned their case red (journal has the list); restored, 85/85
- [x] The whole gate is green — `scripts/check.sh`: kitchen 270, guard 27, bk 82, budget 85, window 16, release v0.28.1
- [x] Contract 2 and 11 say who the sous is and that head-chef sessions are apart and skipped — `plugins/bk/skills/README.md` (The budget paragraph, "Who is the sous"; the debrief list); Contract 12 untouched
- [x] Version 0.28.1, CHANGELOG entry, formula url — `scripts/check.sh` step 5 passes
- [?] The Ledger page shows `head chef` rows separately and leaves their spend out of the top strip — `web/ledger.js:14-15` (name, colour), `:25` (`kitchen`/`chef`), `:38-40` (spend and the head-chef line). Only a syntax check exists (no browser runner, and the demo data has no head-chef session). To run: from a kitchen whose main checkout holds a second, un-named session, `bk live` (or the Window on a free port, never 4747) → Ledger → Sessions: expect a `Head Chef` row with its own grey mark, and under the Models line `Head chef $X · N session(s) of your own, not in this spend`; the Kitchen figure should not rise when that session works.

## Known limitations

- `alive(pid)` and the registry read in `budget.js` repeat what `live/sessions.js` does; the plan keeps the two files independent on purpose (the inspector flagged it; accepted).
- A running head-chef session is the sous if `.claude/sous` is empty and it is the newest live main-checkout session; that is the Window's own rule (A1) and the cost of having no name.
- The registry only knows live sessions, so a dead session is the sous only by what it sent; a sous that never sent `[brief]`, `[hello]`, `[go]`, `[approved]` or `[findings]` and is no longer running counts as the head chef.
