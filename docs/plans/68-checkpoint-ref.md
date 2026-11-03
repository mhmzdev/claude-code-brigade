---
ticket: "#68"
title: A checkpoint ref for a station's uncommitted work (kitchen.sh checkpoint / restore)
status: done
approved: 2026-11-03
lane: B
created: 2026-11-03
open_questions: none
migration: false
files:
  - plugins/bk/skills/kitchen/kitchen.sh
  - plugins/bk/skills/kitchen/SKILL.md
  - plugins/bk/skills/README.md
  - plugins/bk/skills/implement/SKILL.md
  - plugins/bk/skills/review-task/SKILL.md
  - plugins/bk/skills/handoff/SKILL.md
  - plugins/bk/skills/sous-chef/SKILL.md
  - plugins/bk/agents/taster.md
  - tests/kitchen.test.sh
  - tests/guard.test.sh
  - changelog.d/68-checkpoint-ref.md
---

# #68 — A checkpoint ref for a station's uncommitted work

## Why

Nothing is committed in a station before the sous's `[go]` (Contract 5), so a ticket's whole
tree sits uncommitted for hours: if the station is removed or reset, that work is gone, and the
pass has to read it out of the live folder. A checkpoint is a copy of the tree kept in a ref,
which is not a commit on the branch, so the rule "no commit before `[go]`" stays exactly as it is.

## Current state

- `tree_hash <dir>` already builds a tree object of a station's working state (tracked,
  deleted, untracked; ignored files out) in a throwaway index, touching nothing: `kitchen.sh:3054`.
  The check's receipts are keyed on that tree (`kitchen.sh:3101`), so a checkpoint built from the
  same function has **the same tree id as the receipt for that tree**.
- Git's refs outside `HEAD` are shared by every worktree (one object store, one ref store), so a
  ref a station writes is readable from the main checkout and survives `git worktree remove`.
- `branch_ticket` gives the ticket id a branch carries (`kitchen.sh:1551`); `done` knows the PR
  merged and deletes the branch (`kitchen.sh:2619`); `sync` detaches clean stations
  (`kitchen.sh:966`).
- The taster diffs the live station from its merge base and runs `check --receipt` there
  (`taster.md` steps 1 and 2); the sous spawns it (`sous-chef/SKILL.md:482`).
- `hooks/guard.sh` judges the word that runs: `git commit` and the commit-making subcommands need
  a grant, `push` is judged, everything else passes (`guard.sh:122-143`). `git update-ref` and
  `git commit-tree` are not in that list, and `kitchen.sh` itself is not `git`, so the guard
  never sees what the script does inside. (The brief feared #91's guard might refuse an
  `update-ref`; it does not. It also means a cook could move `refs/heads/*` with `update-ref`:
  that is #91's gap, not this ticket's, and is named under Not doing.)

## Desired end state

`kitchen.sh checkpoint` run in a station writes the working tree to
`refs/brigade/<station>/<ticket>` and prints one line; run again with nothing changed it says
`unchanged`. `kitchen.sh restore` puts a checkpoint back on a clean station. The skills call
`checkpoint` at the points the ticket names; `done` drops the ref once the PR merged; the taster
reads the diff from the ref and refuses a station that has moved since. Verify: the new test
section is green, and red with `update-ref` removed from `checkpoint`.

## Not doing

- Pushing a checkpoint to origin. A ref in this repo survives a removed or reset station and a
  stray `git checkout .`; it does not survive losing the disk. The ticket's "machine dies" is
  met for the folder, not the disk; a push needs a `push` grant and a remote ref namespace, which
  is a separate decision.
- Moving the check's receipt log, `scope`, the plan or the journal out of the station. The taster
  still reads those there; only the diff comes from the ref (see Decisions → How).
- Closing the guard's `update-ref refs/heads/*` gap (#91's).
- An automatic checkpoint inside `kitchen.sh check`. The ticket names the skills as the callers.
- `line-cook`: its "never commit before `[go]`" stays as it is, and #28 (station-2) is editing it.

## Approach

Two new commands, one change to `done` and `sync`, a line in four skills and the taster, and the
contract. The ref points at a commit object made with plumbing, `git commit-tree <tree> -p HEAD`:
its tree is `tree_hash`'s, its one parent is the station's `HEAD`, so the diff from the merge
base with trunk is the same diff the taster reads today, and untracked files appear in it as
additions. Writing it uses `git update-ref <ref> <new> <old>`, which refuses when the ref moved
since it was read, so nothing is ever forced. `HEAD`, the branch, the index and the working tree
are never touched. The alternative, `git stash create`, was rejected: it needs `-u`-style
handling for untracked files and records the index as a second parent, which the diff does not
need.

### Command shapes

```
kitchen.sh checkpoint                  write the checkpoint (in a station, on a ticket branch)
kitchen.sh checkpoint --show [station-N]   print "<ref> <sha> tree=<tree> current|behind"
kitchen.sh restore [<ticket>]          put the checkpoint back on this clean station
```

- `checkpoint` in the main checkout (a solo session): says "not in a station" and exits 0, so a
  skill can call it unconditionally. In a station with no ticket branch: exits 1 and says why.
  A tree equal to `HEAD`'s: "nothing to checkpoint", no ref. Otherwise writes the ref.
- `--show` exits 0 `current` (the station's tree is the ref's tree), 2 `behind` (it has changed
  since), 1 when there is no ref. From the main checkout it takes the station.
- `restore` refuses a dirty station, an unknown ticket and (two stations holding the same
  ticket) an ambiguous one. It moves a detached station to the checkpoint's parent and refuses a
  station on a branch that is not at that parent, printing the command to run. It applies
  `git diff --binary <parent> <ref>` with `git apply`, so deletions, new files, modes and
  binaries come back, and the index is left alone.

## Decisions

### Changes the ticket

None.

### How

- **Ref name:** `refs/brigade/<station>/<ticket>`, the ticket id as `branch_ticket` gives it,
  lower-cased, `#` dropped (`refs/brigade/station-3/68`), as the ticket says.
- **One ref per ticket, overwritten each time, no history.** The latest tree is what a crash
  needs, and the journal and plan already hold the story. `update-ref` with the old value is the
  compare-and-swap that keeps it from clobbering a concurrent writer.
- **Parent is `HEAD`, not the previous checkpoint**, so `merge-base` with trunk and the taster's
  diff work unchanged.
- **Identity:** `commit-tree` needs a committer. If git has none, the command supplies
  `Brigade <brigade@localhost>` for that one call and changes no config.
- **`done` deletes the ref** (`refs/brigade/<station>/<ticket>`) after it has proved the merge
  and detached, and its summary line says so; an unserved station's ref is never touched. A
  station removed with `kitchen.sh remove` keeps its refs: that is the case they are for.
- **`sync`** prints one line for a clean station that is detached but still holds a checkpoint
  ("holds a checkpoint for #68: kitchen.sh restore #68"), so a recreated station or a fresh
  session finds it. It restores nothing itself: `sync` changing files would surprise a cook.
- **`handoff`'s "Reading a handoff on start"** gets the matching sentence, in place of an edit to
  `line-cook`.
- **The taster** gets a `Checkpoint:` input, the `checkpoint --show` command. `current`: it diffs
  `merge-base(<ref>, trunk)..<ref>` with `git -C <main checkout>`, and the receipt for the
  station's tree is a receipt for the ref's. `behind`: `VERDICT: blocked` ("the station changed
  after its last checkpoint: the cook runs `kitchen.sh checkpoint` as its last act"). No ref:
  it falls back to today's station diff and says so under NOTES. **The ticket's prose says the
  pass then needs no entry into the station; its Done-when box only says the taster reads the
  ref.** The receipt log, `scope`, the plan and the journal still live in the station, so the
  pass still reads those there. The sous should read this line and say if it counts as changing
  the ticket.
- **Order of a cook's last acts:** `scope`, `check`, then `checkpoint` (the ref lives outside the
  tree, so it does not move the receipt's tree), then `[handoff]`.
- **Guard:** no change. Two tests pin that `git update-ref refs/brigade/…` and `git commit-tree`
  pass in a station with no grant, and that `kitchen.sh checkpoint` does.

## Phases

### Phase 1 — The commands

**Status:** Done

- `plugins/bk/skills/kitchen/kitchen.sh` (edit): `CHECKPOINT_ARGS` read like `GRANT_ARGS`
  (before the flag loop, `checkpoint|restore`); `cmd_checkpoint`, `cmd_restore`, helpers
  `checkpoint_ref <station> <ticket>` and `checkpoint_find <ticket>`; dispatch; the usage header;
  `done` drops the ref and says so; `sync` prints the held-checkpoint line.
- `plugins/bk/skills/kitchen/SKILL.md` (edit): the two commands in the argument-hint and the table.
- Check: `scripts/check.sh` passes (this phase adds no test yet; shellcheck must be clean)

### Phase 2 — Tests

**Status:** Done

- `tests/kitchen.test.sh` (edit): a section `checkpoint / restore: a ref for a station's
  uncommitted work (#68)` in a throwaway repo with a bare origin and a worktree station:
  - not in a station: exit 0, no ref · detached station: exit 1 · clean branch: no ref;
  - a tracked edit, a staged new file, an untracked file and a deleted file: the ref exists,
    its parent is `HEAD`, its tree holds all four states, and **`HEAD`, the branch tip, `git
    status --porcelain` and the index are byte-identical before and after**;
  - a second call is `unchanged` (same sha); an edit makes a new sha with the same parent;
  - `--show`: `current` exit 0, `behind` exit 2 after an edit, none exit 1; from the main
    checkout with `station-N`;
  - the ref **survives `git worktree remove --force`** of the station and its files read back
    with `git show`;
  - `restore` in a recreated station: tracked edit, staged-new, untracked and deleted all back,
    index untouched; refuses a dirty station, an unknown ticket, a branch not at the parent;
  - with the ref deleted, `restore` fails (red without the ref);
  - `done` (stub `gh`) deletes the ref and an unserved station's ref stays; `sync` prints the
    held-checkpoint line for a clean detached station;
  - each test checked red by breaking the code on purpose (the `update-ref` removed; the
    `-p HEAD` removed; `done`'s delete removed).
- `tests/guard.test.sh` (edit): `git update-ref refs/brigade/…`, `git commit-tree` and `kitchen.sh
  checkpoint` pass in a station with no grant.
- Check: `scripts/check.sh` passes

### Phase 3 — Skills, the taster and the contract

**Status:** Done

- `implement/SKILL.md` (edit, Step 2 item 3): after a green check, `kitchen.sh checkpoint`.
- `review-task/SKILL.md` (edit, step 8's last act and the sentence at line 91): `check`, then
  `checkpoint`, then the message.
- `handoff/SKILL.md` (edit, Cook handoff step 4/5, and "Reading a handoff on start"):
  `checkpoint` after the journal is written; a clean station that still holds one is restored.
- `sous-chef/SKILL.md` (edit, the taster prompt at line 484): the `Checkpoint:` line.
- `agents/taster.md` (edit): the input, step 1 as in Decisions → How.
- `README.md` (edit): Contract 5, where it says nothing is committed before `[go]` (a checkpoint
  is not a commit on the branch); Contract 8, a bullet for the ref (shared by every worktree,
  survives a removed station, dropped by `done`, read by the taster, not pushed) and the taster's
  diff form; Contract 4's paths table, a row for the ref. **#28 (station-2) edits Contract 8
  too:** I rebase onto its merge before `open-pr`, and the sous should not run the two at once
  (`kitchen.sh scope --overlap`).
- `changelog.d/68-checkpoint-ref.md` (new): `level: minor`.
- Check: `scripts/check.sh` passes; a consistency read of every skill against the contract for
  the words "commit" and "checkpoint" (a fresh read-only sub-agent).

## Protected paths

None: nothing under `.claude/` is edited.

## Success criteria

- [ ] `scripts/check.sh` passes (the one full run is the last act; its receipt is the proof)
- [x] `kitchen.sh checkpoint` and `restore` exist; the tests prove they leave `HEAD`, the branch
      and the index alone, and force nothing (`update-ref` is given the old value)
- [x] The ref survives `git worktree remove --force`; `restore` brings back tracked, staged,
      untracked and deleted files; both tests are red when the ref is not written
- [x] `implement`, `review-task` and the cook handoff call `checkpoint`; the taster reads the ref
      and blocks a station behind it
- [x] Contracts 4, 5 and 8 say so; `line-cook` is unchanged
- [x] `git diff` shows no change to `hooks/guard.sh`

## Risks

- **#28 edits the same Contract 8 and `line-cook`** → the plan keeps off `line-cook`, and Contract
  8's edit is a new bullet, not a rewording; rebase before `open-pr`.
- **A checkpoint older than the work** (a cook forgets) → the taster blocks on `behind`, so the
  pass cannot go through on a stale ref.
- **`git apply` of a binary diff on a station whose files differ** → `restore` insists on a clean
  station at the checkpoint's parent, where the patch is exact.
- **Refs accumulate for stations never served** → named and left: `sync` lists them, and
  `done` drops the served one. A sweep for abandoned refs is a follow-up if it bites.
