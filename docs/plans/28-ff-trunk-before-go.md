---
ticket: "#28"
title: Bringing trunk in before [go] is a fast-forward, written down once
status: done
approved: 2026-11-03
lane: B
created: 2026-11-03
open_questions: none
migration: false
files:
  - plugins/bk/skills/README.md
  - plugins/bk/skills/line-cook/SKILL.md
  - plugins/bk/skills/open-pr/SKILL.md
  - plugins/bk/skills/sous-chef/SKILL.md
  - changelog.d/28-ff-trunk-before-go.md
  - docs/journal/28-ff-trunk-before-go.md
  - docs/journal/INDEX.md
  - docs/plans/28-ff-trunk-before-go.md
  - docs/plans/INDEX.md
---

# #28 — Bringing trunk in before [go] is a fast-forward, written down once

## Why

Nothing is committed in a station before the sous's `[go]` (Contract 8). When trunk moves
in that window, the usual "merge trunk" would make a commit on a branch that has none. A
cook once worked out `git merge --ff-only` and a way past clashing files, and every journal
since (66, 65, 85) repeated the discovery, because no skill says it.

## Current state

Staleness check at `origin/main` 41979fd: the case that bit in 0.15.1 no longer comes from
the skills, and the answer is still unwritten.

- `open-pr/SKILL.md:74-80` merges trunk only in step 4, after step 3's commit, so it never
  meets a branch with no commits.
- The pass (`sous-chef/SKILL.md:479-494`) and the taster diff from the merge base
  (`README.md:731-736`), so trunk moving needs no merge before `[go]`; the "branch includes
  current trunk" check (`sous-chef/SKILL.md:498`) is after `[served]`.
- Nothing says what a cook does when the sous or head chef holds the ticket and says "bring
  main in" before `[go]`. `line-cook/SKILL.md:201` says `git merge origin/<trunk>`, which is
  right only after `[served]`.
- The sous has ruled on the case (commis `settled`, journal A1): before `[go]` trunk comes in
  only as `git merge --ff-only origin/<trunk>` on a branch with no commits of its own; any
  other route counts as a commit and waits for the `commit` grant that #91 introduces
  (`station-1/docs/plans/91-positive-authorization.md:149-155`, not on trunk yet). #91 builds
  the guard; it writes no skill text for the recipe. This plan writes the prose only.

## Desired end state

A cook told to bring trunk in before `[go]` finds one paragraph (Contract 8) with the rule,
the recipe and its traps, and `line-cook`, `open-pr` and `sous-chef` point at it. Verify:
`grep -n -- '--ff-only' plugins/bk/skills/{README.md,line-cook/SKILL.md,sous-chef/SKILL.md,open-pr/SKILL.md}`
hits all four; `scripts/check.sh` is green.

## Not doing

- No guard or script change: #91 owns the guard that lets `--ff-only` through, and a
  `kitchen.sh` subcommand for the recipe would be new behaviour the ticket does not ask for.
- No checkpoint ref (#68), no commit grant (#91).
- No change to `open-pr` step 4's merge: after the commit a real merge is right.
- A branch that has already diverged before `[go]` is not covered: it waits for a grant, as
  the #91 plan says.

## Approach

One paragraph in Contract 8 next to "A station's own changes" (same subject: trunk moving
while nothing is committed); three one-line pointers. The recipe was tried in a throwaway
repo (a branch with edits, a clashing generated file and an untracked file that trunk also
added): plain `--ff-only` refuses over clashing files; `git stash push -u` → `--ff-only` →
`git stash apply <sha>` works, with two traps the paragraph names.

## Decisions

### Changes the ticket

None.

### How

- **Default is that nobody asks.** The issue offered two fixes (a recipe, or "the sous never
  asks before `[go]`"). Both go in: the sous does not ask for it as a routine step, because
  the pass reads from the merge base and `open-pr` owns the merge; the recipe is for a hold
  or a clash the sous does ask about. Settled by the sous's ruling (commis A1, 2026-11-03).
- **Stash recipe, not the issue's save-diff recipe.** `git stash push -u` also catches
  untracked files, is what the journals did (66:37), and the line-cook skill already has the
  shared-stash rule (own entry by sha or name, never a bare pop). The paragraph reuses it.
- **Where:** Contract 8, not Contract 5, so it does not collide with #91's rewrite of the
  never-list in Contract 5 (station-1).
- **Traps named:** (1) a file the cook has untracked that trunk now tracks: trunk's copy
  lands and the cook's survives only in the stash (`git show <sha>^3:<path>`), so compare
  before dropping; (2) a generated `INDEX.md` the apply leaves conflicted: run
  `kitchen.sh index` (Contract 12), then `git reset -q` to unstage. And the tree changed, so
  the receipt is stale: run `kitchen.sh check` again before `[handoff]`.

## Phase 1: Write the paragraph and the pointers
**Status:** Done. Files: README.md (Contract 8 paragraph, after the merge-base one), line-cook (a paragraph before "Being cleared", and the never-list bullet that #91 rewrote, which replaces the old line 244), sous-chef (pass item 6), open-pr step 4, the fragment. Worded against #91 (merged): a plain merge or pull is a commit and needs the grant; `--ff-only` passes the guard.

### Changes

The blocks below are the draft wording; what landed was reworded to #91's (a plain merge or pull is a commit and needs the grant), and the files are the record.

#### `plugins/bk/skills/README.md:737` (edit), after the "A station's own changes" paragraph

```markdown
**Trunk moves while nothing is committed.** Nobody asks a cook to bring trunk in before
`[go]` as a routine step: the pass reads the merge base, and `/bk:open-pr` brings trunk in
after the commit. When the sous holds a ticket and asks anyway, the only form is
`git merge --ff-only origin/<trunk>`, on a branch with no commits of its own: a merge commit,
`pull` without `--ff-only`, `rebase` and `cherry-pick` are commits by another route and wait
for the sous's `commit` grant. If `--ff-only` refuses because the working tree clashes with
what trunk changed, park the tree and put it back:
`git stash push -u -m "<station>: trunk"`, note its sha from
`git stash list --format='%H %gs'`, `git fetch origin && git merge --ff-only origin/<trunk>`,
`git stash apply <sha>`, then drop that entry by its message. Two traps: a file you added
that trunk now tracks comes back as trunk's copy and yours stays only in the stash
(`git show <sha>^3:<path>`), so compare before you drop it; and a generated `INDEX.md` the
apply leaves conflicted is rewritten by `kitchen.sh index` (Contract 12), then `git reset -q`
to unstage. The tree changed, so its receipt is stale: run `kitchen.sh check` again before
`[handoff]`. Tell the sous in the journal and in `kitchen.sh here --note`.
```

#### `plugins/bk/skills/line-cook/SKILL.md:201` (edit)

After "if it says the PR is behind or conflicting, bring trunk in (`git merge origin/<trunk>`)…" no change; add a new paragraph after line 201's block (before "**Being cleared mid-ticket**"):

```markdown
**Trunk moved before `[go]`** (the sous holds your ticket and says "bring main in"): nothing is
committed, so don't merge. Use `git merge --ff-only origin/<trunk>` with the stash recipe in
Contract 8, check again, and carry on. Otherwise leave trunk to `/bk:open-pr`.
```

and `line-cook/SKILL.md:244` (edit): `- Commit before `[go]`, force-push, or push to trunk.` →
`- Commit before `[go]` (a merge commit counts: before it, trunk comes in only by `--ff-only`), force-push, or push to trunk.`

#### `plugins/bk/skills/sous-chef/SKILL.md:494` (edit), in the pass's "Before commit" list, after item 5

```markdown
6. **Don't ask for trunk before `[go]`.** The taster diffs from the merge base and `open-pr`
   brings trunk in after the commit. If you hold a ticket and must have it current, ask for
   `git merge --ff-only origin/<trunk>` (Contract 8), never a plain merge.
```

#### `plugins/bk/skills/open-pr/SKILL.md:76` (edit)

`Trunk moved while you cooked. Merge it now, …` → add one sentence: `This is a real merge because step 3 made a commit; before the sous's `[go]` nothing is committed and trunk comes in only by `--ff-only` (Contract 8).`

#### `changelog.d/28-ff-trunk-before-go.md` (new)

```markdown
level: patch

When trunk moves while a cook has nothing committed yet, the skills now say what to do:
the sous doesn't ask for a trunk merge before `[go]` (the pass reads the merge base and
`/bk:open-pr` brings trunk in), and if it does ask, the cook uses `git merge --ff-only`, with
a stash recipe for clashing files. Nothing for you to do.
```

### Success criteria
- [x] `grep -c -- '--ff-only' plugins/bk/skills/README.md plugins/bk/skills/line-cook/SKILL.md plugins/bk/skills/sous-chef/SKILL.md plugins/bk/skills/open-pr/SKILL.md` prints a count of at least 1 for each of the four files (before the change, only `sous-chef` and `open-pr` print one, and for an unrelated `git pull --ff-only`).
- [x] `grep -n 'Trunk moves while nothing is committed' plugins/bk/skills/README.md` prints one line, and every skill pointer says "Contract 8".
- [x] No contradiction: `grep -rn 'git merge origin/<trunk>' plugins/bk/skills` shows only after-commit uses (`open-pr` step 4, `line-cook` after `[served]`).
- [x] `scripts/check.sh` passes (the release check wants the fragment and no version bump).
- [x] Manual: in a throwaway repo, run the paragraph's recipe on a branch with an edited file, a conflicted generated file and an untracked file trunk also added; the tree ends with trunk's commits, the edits kept, no commit on the branch.

## Testing

Prose only, so no automated test (CLAUDE.md: prose changes get a consistency read). The
recipe was run by hand in a throwaway repo while planning. At the end, a fresh read-only
sub-agent reads the four files against Contract 8 and lists any that disagree.

## References

- Ticket #28 and its triage comment (2026-10-25); journal `docs/journal/28-ff-trunk-before-go.md` (A1)
- `station-1/docs/plans/91-positive-authorization.md:88-92,149-155` (the sous's ruling and the guard)
- Journals 66:37, 65:33 (the recipe in practice); `README.md:697-699` (shared stashes)
- `open-pr/SKILL.md:74-92`, `line-cook/SKILL.md:194-201,244`, `sous-chef/SKILL.md:479-498`
