---
ticket: "#68"
title: A checkpoint ref for a station's uncommitted work (kitchen.sh checkpoint / restore)
plan: docs/plans/68-checkpoint-ref.md
last_verified: 2026-11-03
---

# Acceptance — #68 A checkpoint ref for a station's uncommitted work

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

### A cook works, the station is removed, the work comes back

1. `implement` finishes a phase and runs `kitchen.sh checkpoint` → `refs/brigade/station-N/<ticket>` holds the tree; the branch, `HEAD`, the index and the files are as they were.
2. `git worktree remove --force` of the station → the ref still resolves from the main checkout.
3. `kitchen.sh setup`, then `kitchen.sh sync` → sync says `station-N: holds a checkpoint for <ticket> (kitchen.sh restore <ticket>)`.
4. `kitchen.sh restore <ticket>` on the clean station → tracked edits, new files, binary files and deletions are back as working-tree changes, nothing staged.

### The pass

1. The cook's last acts: `scope`, `check`, `checkpoint` → `checkpoint --show` says `current`.
2. The taster runs `checkpoint --show`; `current` → it diffs `merge-base(ref, trunk)..ref` in the main checkout; `behind` → `blocked`; no ref → the station diff, with a NOTE.

## Edge cases

- Main checkout or a solo session → `checkpoint` says "not in a station" and exits 0, so a skill can call it unconditionally.
- A station with no ticket branch → exit 1, says why. A branch with no uncommitted work → "nothing to checkpoint", no ref.
- Nothing changed since the last call → `unchanged`, same sha. A changed tree → a new sha on the same parent.
- `restore` refuses a dirty station, an unknown ticket, a ticket two stations hold, and a branch that is not at the checkpoint's parent (it prints the `git switch --detach` to run); a detached station at a newer trunk is moved back to the parent.
- A trunk fast-forward changes the tree → the checkpoint reads `behind` until `check` and `checkpoint` run again (said in Contract 8).
- `done` on an unmerged PR leaves the ref; on a merged one drops that ticket's ref and no other.

## Acceptance criteria

Scope: every changed path is inside the plan's `files:` (`kitchen.sh scope station-3`: outside 0).

- [x] `kitchen.sh checkpoint` and `restore` exist and never commit on the branch — `kitchen.sh:2711`, `:2758`; tests/kitchen.test.sh "…HEAD, the branch tip, the status and the index are exactly as they were (no commit on the branch)" and "…the branch has no commit of its own" pass
- [x] Nothing is forced — `kitchen.sh:2754`: `update-ref` is given the old value (or the all-zero id for a first write), so a ref that moved is refused, never overwritten
- [x] The ref holds tracked, staged, untracked and binary files and not a deleted one; its parent is `HEAD` — tests "…its parent is the station's HEAD", "…it holds the tracked edit", "…the staged new file and the untracked file", "…the binary file, byte for byte", "…and not the deleted file" pass
- [x] A checkpoint survives `git worktree remove` of the station — test "the checkpoint survives git worktree remove of the station" pass
- [x] `restore` brings back tracked, untracked, binary and deleted files, with nothing staged — tests 456–461 (restore puts the checkpoint back on a recreated station … as working-tree changes only) pass
- [x] Red without the ref — test "without the ref there is nothing to restore" passes; with `update-ref` made a no-op the ref tests went red, as did `-p HEAD` removed, `--binary` removed and `done`'s delete removed (journal)
- [x] `--show` says current / behind / none (exit 0 / 2 / 1), also from the main checkout — tests "--show says current …", "…behind …", "--show reads a station from the main checkout" pass
- [x] `done` drops the served ticket's ref and no other; an unmerged PR keeps it — `kitchen.sh:2695-2697`; tests "done leaves the checkpoint of a ticket whose PR is not merged", "done drops the served ticket's checkpoint and says so", "…and another ticket's checkpoint stays" pass
- [x] `sync` lists a clean station that still holds a checkpoint — `kitchen.sh:1003`; test "sync lists a clean station that still holds a checkpoint" pass
- [x] `implement`, `review-task` and the cook handoff call `checkpoint` — `implement/SKILL.md:92`, `review-task/SKILL.md:91`, `handoff/SKILL.md:64`
- [x] The taster reads the ref and blocks a station that is `behind` — `agents/taster.md:20,33,41`; the sous passes the `Checkpoint:` input — `sous-chef/SKILL.md:487`
- [x] Contracts 4, 5 and 8 say so — `README.md:305` (paths table), `:600` (no grant needed, not a commit), `:798` (the paragraph, beside #28's trunk-moves one)
- [x] `line-cook`'s "never commit before `[go]`" is unchanged, and so is `hooks/guard.sh` — `git diff origin/main --name-only` lists neither
- [x] `checkpoint`, `git update-ref refs/brigade/…`, `git commit-tree`, `git for-each-ref` and `restore` pass the guard with no grant — tests/guard.test.sh (12 cases, both configs) pass; they went red when the guard was made to refuse `update-ref|commit-tree`
- [x] No new shellcheck findings — `shellcheck -S info` on `kitchen.sh`: 8 notes before and after
- [?] `scripts/check.sh` passes on this exact tree — the one full gate run is the last act before the handoff (the sous asked for one run): `kitchen.sh check --receipt` prints the receipt; expect exit 0

## Known limitations

- The ref lives in the repo's own object store: it survives a removed or reset station, not a lost disk. Nothing pushes it.
- The receipt log, `scope`, the plan and the journal are still read in the station; only the diff comes from the ref (signed as a how by the sous).
- A cook can still move `refs/heads/*` with `git update-ref`; the guard does not refuse it. That is #69's, not this ticket's.
- Refs of stations that were never served are listed by `sync` and not swept.
