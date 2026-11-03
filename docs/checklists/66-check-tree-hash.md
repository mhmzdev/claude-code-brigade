---
ticket: "#66"
title: kitchen check — run the config's check once per tree, record the result with the tree's hash
plan: docs/plans/66-check-tree-hash.md
last_verified: 2026-11-03
---

# Acceptance — #66 `kitchen.sh check`: the check runs once per tree

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

### Two calls on one tree

1. `kitchen.sh check` on a tree with no record → runs the config's `check:`, logs one line, prints `check: green (ran, Ns)`.
2. `kitchen.sh check` again, nothing changed → prints `check: green on this tree, not re-run (recorded <time>, Ns)`, runs nothing, writes no line.
3. Edit, add or delete a file → the next call runs again.

### The pass

1. The cook's last `kitchen.sh check` is green and recorded.
2. The taster runs the sous's `Check:` line (`kitchen.sh check`) on the same tree → trusts the record and reports `CHECK: trusted the record of <time>`; on a changed tree it runs and reports `CHECK: ran`.

## Edge cases

- A red run → exit code is the check's own, logged `rc=<n>`, run again next call (never trusted).
- A run that rewrites a tracked file → logged `moved`, not trusted; the next call runs once more.
- The config's `check:` changed → old greens do not match (`cmd=` id).
- A station (worktree) → its own log in the station, config from the main checkout, git status clean.
- No `check:` in the config → error naming the config.
- A station whose log has no line in a ticket's span → the budget and the Window fall back to the runners' replies.

## Acceptance criteria

- [x] `kitchen.sh check` wraps the config's `check`, hashes the working state (tracked, deleted and untracked, minus ignored) and runs only when no green is recorded for that hash — `kitchen.sh:1508` (`tree_hash`), `:1518` (`cmd_check`); `tests/kitchen.test.sh` "a second call on the unchanged tree runs nothing"
- [x] it prints the recorded verdict otherwise — "…and says it trusted the record" (`tests/kitchen.test.sh`)
- [x] `--force` re-runs — `kitchen.sh:269`; "--force runs it again"
- [x] a changed file runs it again; an untracked file runs it again; a deleted file runs it again — "a changed tracked file…", "a new untracked file…", "a deleted tracked file runs it again"
- [x] goes red without the hash check — broke `tree_hash` to a constant: 14 cases red; dropped the `cmd=` match: 3 red; trusted `moved` lines: 1 red (journal, phase 1); all restored
- [x] a red result is logged and never trusted; a tree-moving run is logged `moved` and not trusted; a changed config command invalidates a green — "a red result is run again, not trusted", "…so the next call runs it again", "a green recorded for another command is not trusted"
- [x] a station keeps its own log, outside git — "a station run reads the main checkout's config and runs", "…leaving the station's git status clean"
- [x] `implement`, `review-task`, `open-pr` call `kitchen.sh check` — `implement/SKILL.md:90`, `review-task/SKILL.md:54`, `open-pr/SKILL.md:79`
- [x] the taster calls it through the sous's `Check:` line, trusts a green for the exact tree and says which it did — `sous-chef/SKILL.md:457`, `agents/taster.md:38-42,64`; contract `skills/README.md:35`
- [x] the budget's check results read the same log, so a skipped run is not counted — a skipped call writes no line (`kitchen.sh` "…and writes no log line"); `budget.js:318-331,425`; `tests/budget.test.sh` "the check log" section (5 cases); breaking `finish` to ignore the log turned 4 red
- [x] the Window's check machine reads the same log and stops counting runner replies once a log has spoken — `state.js:47,111`, `live/index.js:87`; `tests/window-live.mjs` (6 cases); 2 deliberate breaks red
- [x] the full gate is green through `kitchen.sh check` — `check: green (ran, 133s)`: kitchen 297, guard 27, bk 82, budget 92, window 22, release v0.31.0; `review-task` then got `check: green on this tree, not re-run` from the same record
- [x] no stale "re-runs the check" wording is left — `git grep 're-runs the check' plugins/bk` is empty; a fresh read-only read found two stale lines (PLAYBOOK, open-pr description), fixed
- [?] the taster, on the sous's next pass, prints `CHECK: trusted the record of <time>` when the cook's last check was this exact tree — run: after `[handoff]`, `cd <station> && kitchen.sh check` and expect `not re-run`; it only holds if nothing in the tree changed since the cook's last check (see Known limitations)
- [?] `open-pr`'s bring-main-in on a real conflict-free merge that adds nothing to the tree reports the recorded green — needs a live PR; expect `not re-run` when `git merge origin/main` says "Already up to date"

## Known limitations

- **The key is the exact tree, so the pass's own paperwork moves it.** The journal, plan status, checklist and INDEX rows are in the tree; each edit after the cook's last check makes the next call run again (here: this checklist and the handoff are written after the green, so the taster will run once more). The log only saves runs between edits. Excluding the paperwork paths from the hash, or sequencing the writes before the last check, would save more, but a check may read those files (this repo's INDEX check does), so it is a choice for a follow-up, not a quiet default. Flagged to the sous.
- No lock across stations: two stations can still run full checks at once (#50's port); the sous's "one gate at a time" stays.
- Trunk's sha is not in the key; `open-pr` merges trunk first, which changes the tree whenever trunk moved. `--force` covers the rest.
- A check that writes untracked, non-ignored files (a coverage folder) is logged `moved` once, then settles.
