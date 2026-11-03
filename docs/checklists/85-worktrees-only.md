---
ticket: "#85"
title: worktrees only; drop clone mode; `kitchen.sh done` deletes a merged ticket's branch and resets the station
plan: docs/plans/85-worktrees-only.md
last_verified: 2026-11-03
---

# Acceptance — #85 worktrees only; `kitchen.sh done`

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

### A kitchen is set up and run

1. `kitchen.sh setup` in a repo with no mode line → stations appear at `../<repo>-stations/station-N`, each a worktree (`.git` is a file), clean, detached at `origin/<trunk>`.
2. `kitchen.sh sync` → a clean station is re-detached at `origin/<trunk>`; a dirty one is skipped.

### A ticket is served

1. The sous runs `kitchen.sh ship <PR>` → merged. Then `kitchen.sh done station-N` → one line: `station-N: PR #N merged. Detached at origin/main (<sha>); local branch <b>: deleted; origin branch: deleted; per-ticket files cleared.`
2. Then the reap, then `kitchen.sh clear station-N` → the pane is cleared; the folder, `.claude/cook` and `settings.local.json` were never touched.

### A clone kitchen meets this release

1. A config with `kitchen_mode: clone` → every `kitchen.sh` command but `remove` prints one line and exits 1.
2. `kitchen.sh remove` (typing `delete`) → the old `<repo>/stations/` is deleted and the output says to drop the line and run `kitchen.sh setup`.

## Edge cases

- PR still open, closed unmerged, or none → `done` refuses, naming it; both branches survive.
- The station holds a commit the merged PR does not → refused with both shas.
- Dirty station, or a busy cook → refused.
- Already detached → "nothing to do", exit 0.
- Origin branch already deleted by GitHub → reported as `already gone`, exit 0.
- The remote delete refused (auto mode, a hook) → the station is still reset and the local branch gone; the line says `origin branch: NOT deleted`, prints `git push origin --delete <b>`, exit 1.
- `kitchen_mode: worktree` still in a config → ignored, no error.

## Acceptance criteria

- [x] `kitchen_mode` is gone from `kitchen.sh`; stations are worktrees at `../<repo>-stations` (or `kitchen:`) — `worktree stations (the suite)` in `tests/kitchen.test.sh`: "setup creates station-1 and station-2", "stations are worktrees (.git is a file)", "setup adds no ignore line for a kitchen next to the repo", `kitchen.sh:283-287`
- [x] Every clone-only branch is removed (`stations/` default, the clone's own install, sync's fetch-and-reset, the root `elif`) — `git grep -n -i clone plugins/bk/skills/kitchen/kitchen.sh` shows only the legacy refusal, `remove`'s legacy path and `git clone` of none; `kitchen.sh:283-287,664,923`
- [x] A config saying `kitchen_mode: clone` gets one line and exit 1, with what to do — "a config that still says kitchen_mode: clone is refused, with one line" passes; red with the refusal disabled (checked on a copy); `kitchen.sh:2801`
- [x] `kitchen_mode: worktree` is ignored — "kitchen_mode: worktree is ignored, not an error", and the workspace-repo section still runs on a config that carries it
- [x] `kitchen.sh done <station>` detaches the station at trunk, deletes the ticket branch locally and on origin, removes `.claude/go`, `check.log`, `check.out`, `grilling` — the `done` section: "the local branch is gone", "the origin branch is gone", "the station is detached at origin/main", "check.log, check.out, grilling and go are gone", "the cook's launcher and its permissions stay"; `kitchen.sh:2256`
- [x] `done` deletes a branch only when its PR is merged, never an unmerged one — "done refuses a branch whose PR is still open, naming it", "…closed without merging", "…no PR at all", "…and deleted nothing"; red with the merged check removed
- [x] `done` never loses a commit the PR doesn't carry — "done refuses a station whose tip is not the merged PR's head, with both shas"; red with the tip check removed
- [x] `done` refuses a dirty station and a busy cook — the two named tests; each red with its check removed
- [x] `done` never deletes a branch whose PR went into another branch, nor one on trunk's own name — "done refuses a merged PR that went into another branch (a stacked PR), naming it", "done refuses a station that is on trunk itself"; red with either check removed
- [x] `done` never deletes unmerged commits on origin: the origin branch is deleted only while it is at the PR's head, by its exact ref — "an origin branch that moved past the merged PR is kept, named, and exits 1", "an origin ref that only ends in the branch's name does not count"; red with the sha check removed and with a loose `ls-remote` pattern
- [x] `done` never force-pushes and says what was and wasn't deleted — "the summary says what was deleted", "a refused remote delete exits 1 and the summary says NOT deleted", "…and prints the command to run", "…the station was still reset"; red when the delete never runs, when a refusal is reported as success, and when the local delete is skipped
- [x] An origin branch already gone, and a station already on trunk, are reported and are not errors — "an origin branch that is already gone is reported, not an error", "done on a station already on trunk has nothing to do"
- [x] `hooks/guard.sh` keeps only the worktree test — `guard.sh:30-55`; `tests/guard.test.sh` "a worktree named station-* outside the kitchen" is red without the sibling-kitchen check (checked on a copy)
- [x] `bin/bk` no longer globs `stations/station-*` — `bin/bk:246`; `tests/bk.test.sh` 85/85
- [x] The Window has no kitchen mode (`config.js`, `state.js`, `demo.js`, `live/index.js`, `web/main.js`, `web/ledger.js`) — `tests/window-live.mjs` "the stations live in ../<repo>-stations by default" and "the config carries no kitchen mode", both red on the old reader (checked)
- [x] Contract 8 has one kind of station and says what `done` does; the sous-chef's End of shift is ship → done → reap → clear; line-cook, setup, kitchen, open-pr, feedback, README, PLAYBOOK, AGENTS.md carry no clone text — `plugins/bk/skills/README.md` Contract 8, `sous-chef/SKILL.md` End of shift steps 1-6; the final `git grep` sweep and a fresh read-only consistency read (below)
- [x] The tests are the worktree suite and the workspace-repo case stays — `tests/kitchen.test.sh` "worktree mode, inside a workspace repo" section
- [x] The changelog fragment says **Breaking** in bold, `level: minor`, with the migration line — `changelog.d/85-worktrees-only.md`; the release check in `scripts/check.sh` passes (v0.33.0, no bump)
- [x] The check is green on this tree — `kitchen.sh check`: green (ran, 247s) — kitchen 577, guard 27, bk 85, budget 115, window 25, release 45 , v0.33.0
- [?] The first live `done` — after this PR merges, the sous runs `kitchen.sh done station-2` with the real gh and the real origin, in its own session (where auto mode refused a `git push origin --delete` this morning). Expect the one summary line with `origin branch: deleted`, or `NOT deleted` with the command to run, exit 1. A post-merge check, the sous's to run.

## Known limitations

- **Cases that left with clone mode:** the suite went from 647 to 577 tests. 110 left: the two per-mode suites ran once per kitchen mode, so their clone copy is gone while the worktree copy still runs (57 of the rail suite, 53 of #86's `procs` suite). Five clone-only cases were replaced one for one: "stations are full clones" → "stations are worktrees (.git is a file)"; "setup gitignores /stations/" → "setup adds no ignore line for a kitchen next to the repo"; "setup prints the git clean -fdx warning" → "…skips it", plus "setup prints the shared-stash warning"; "an invalid kitchen_mode is refused" → the clone refusal and the worktree-ignored case; "remove (clone)" → "remove with a legacy clone config" (five tests). New: 35 `done` tests; +3 in `tests/window-live.mjs`. Net: 647 − 110 + 35 + 5 = 577.
- `remove` keeps one legacy path, so the ticket's "kitchen.sh remove, then setup" works on a clone config; it is the only clone text left in `kitchen.sh`.
- `.claude/brigade.md` in this repo still says `kitchen_mode: worktree`. It is ignored now; the line is a protected path (`.claude/`), so the head chef can delete it any time.
- `docs/the-names.md` (hand-written, outside the map) still calls a station "one gitignored clone, `stations/station-N`" (`:20`) and maps "Clone" in its alternate-name table (`:66`). Left as `.claude/brigade.md` says.
- `done` deletes the local branch with `-D` (a squash merge needs it) only at the merged PR's head, and never force-pushes; the remote delete is a plain `git push origin --delete`, made only while origin's branch is at that head.
- **A small race, accepted by the sous:** `done` compares origin's branch with the PR's head (`ls-remote`) and then deletes it with a plain `git push origin --delete`. A push that lands between the two, within milliseconds, would be deleted with the branch. A `--force-with-lease` would close it, but reads like a force, so it is not used.
- `done` does not run from `ship` or `bk stop`; the sous runs it in End of shift.
- #89 (`clear` vs a served cook on trunk) is not taken in. `done` runs before `clear`, leaves the journal alone and adds no cook turn, so it neither fixes nor worsens that check.
