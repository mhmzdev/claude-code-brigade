---
ticket: "#13"
title: Diff a station against its merge base with trunk, not the trunk tip
status: done
approved: 2026-10-25
lane: B
created: 2026-10-25
open_questions: none
migration: false
files:
  - plugins/bk/skills/README.md
  - plugins/bk/skills/clean/SKILL.md
  - plugins/bk/skills/review-task/SKILL.md
  - plugins/bk/agents/taster.md
  - plugins/bk/.claude-plugin/plugin.json
  - CHANGELOG.md
  - Formula/bk.rb
  - docs/plans/INDEX.md
---

# #13 — Diff a station against its merge base, not the trunk tip

Also closes #26: same defect, filed later with the sharper fix. One PR: "Closes #13, closes #26".
A `kind: bug` (labels `bug`, `lane:B`), so the sous signs it off (`gates.plan_approval.bug`).

## Why

`/bk:clean check`, `/bk:clean around`, `/bk:review-task` and the taster build "the branch's own
changes" with a two-dot `git diff origin/<trunk>`. Once another station's PR merges, trunk moves
past this branch's base, and that diff also holds the merged work, shown reversed as this cook's
deletions. The inspector and taster then review code the branch never touched. Cooks have worked
around it by hand (`git merge-base`) in 7+ tickets.

## Current state

The same job is done three different ways today, and that split is the defect:

| Where | Method | Right when trunk moves? |
|---|---|---|
| `plugins/bk/skills/clean/SKILL.md:52` (`around`, file list) | `git diff --name-only origin/<trunk>` | no, includes trunk's newer commits reversed |
| `plugins/bk/skills/clean/SKILL.md:54` (`around`, added ranges) | `git diff -U0 origin/<trunk> -- <file>` | no |
| `plugins/bk/skills/clean/SKILL.md:118-125` (`check`, inputs for the inspector) | `git diff origin/<trunk> --` and `--name-only`, plus untracked | no. Its stated reason, "a three-dot diff would read empty", is a skill's own explanation, no recorded decision |
| `plugins/bk/skills/review-task/SKILL.md:44-50` (step 1) | `git diff origin/<trunk> --stat` / `git diff origin/<trunk>` | no |
| `plugins/bk/agents/taster.md:27-34` | `git diff <trunk>` (two-dot, same flaw) | no |
| `plugins/bk/skills/kitchen/kitchen.sh:536-539` (`changed_files`, used by `files` and `leaks`) | `git diff --name-only origin/$TRUNK...HEAD` plus `git status --porcelain -uall` | **yes** |
| `plugins/bk/skills/implement/SKILL.md:57` | same three-dot plus `status` | **yes** |

`kitchen.sh:983` (`leaks`, commit messages) and `:844` (`status`, commits ahead) use
`origin/$TRUNK..HEAD` with `log` / `rev-list`, which asks "commits on HEAD not on trunk": already
correct. `open-pr/SKILL.md:40` is the same kind of read. `agents/inspector.md` computes nothing:
it reads the diff path the caller hands it, so it is fixed through `clean check`. The sous's pass
(`sous-chef/SKILL.md:~422`) only passes `Trunk: origin/<trunk>` to the taster, and the taster
builds its own diff, so no `sous-chef/SKILL.md` edit is needed (station-2 owns that file for #19).

The two reasons the two-dot form was chosen are real and both must survive: in a station
**nothing is committed before the sous's `[go]`**, so three-dot `origin/<trunk>...HEAD` alone
reads empty and a dirty branch passes by accident.

## Desired end state

Every place that builds a station's own changes measures from the merge base:

```bash
BASE=$(git merge-base HEAD origin/<trunk>)
git diff "$BASE"                              # tracked files: committed, staged and unstaged work together
git ls-files --others --exclude-standard      # untracked files, as before
```

`git diff <commit>` with one ref compares that commit to the working tree, so it holds the
branch's committed work **and** its uncommitted work, before and after `[go]`, and nothing from
trunk's newer commits. Verified in Phase 2 with a throwaway repo (trunk moves, the branch has
committed, staged, unstaged and untracked work).

The shared rule is written once in the contract (Contract 8, "Both modes"); the skills and the
taster carry the command.

## Not doing

- No `kitchen.sh` change: `changed_files` is already a merge-base file set, and `leaks`/`status`
  use commit ranges that are correct. So no new `kitchen.sh` test; nothing in it can fail
  differently. (AGENTS.md asks for a test only when behaviour is added to `kitchen.sh`.)
- No new `kitchen.sh diff` subcommand: three lines of git in two skills and the taster don't
  earn one, and a new subcommand would be new behaviour for a prose bug.
- No edit to `sous-chef/SKILL.md` (station-2 is on #19) or `agents/inspector.md` (it computes nothing).
- No change to `implement/SKILL.md:57`, already correct.
- No new automated check that greps the skills for the two-dot form. AGENTS.md's answer for prose
  across several skills is a consistency read, which Phase 2 does.

## Approach

Replace the ref `origin/<trunk>` with `"$BASE"` (the merge base) in every `git diff` that means
"this branch's own work", keep the untracked-files line, and replace the "use two-dot, three-dot
reads empty" explanation with the real rule: the merge base, because trunk moves; one ref after
`diff`, because nothing is committed yet. Follows `kitchen.sh:536` (`changed_files`) and
`implement/SKILL.md:57`, which already measure from the merge base; the change makes the rest
agree with them. The taster resolves the base against its `Trunk` input
(`git -C <station> merge-base HEAD <trunk>`), since it runs from outside the station.

A new contract paragraph, per AGENTS.md ("change the contract first, then grep every skill for
the old wording"): the diff base is a rule shared by four files.

## Phase 1: Release bookkeeping and the contract

**Status:** Done. plugin.json, Formula/bk.rb, CHANGELOG.md (all 0.27.7, since #48 took 0.27.4, #49 0.27.5 and #54 0.27.6), Contract 8 "Both modes" paragraph. `check.sh`: all green with the bk env cleared (`env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE`); without it 7 kitchen tests fail, on an untouched `origin/main` too (#50).

Version and changelog first, so `scripts/check.sh` (release step) is green after every phase.

### Changes

#### `plugins/bk/.claude-plugin/plugin.json` (edit)
`"version": "0.27.6"` → `"0.27.7"` (a patch: fixes how skills diff, no change in how a kitchen
runs). Read the line first; `origin/main` is already at 0.27.6 (#48 took 0.27.4, #49 0.27.5, #54 0.27.6), so bump above that, and
use the same number in the CHANGELOG and formula.

#### `Formula/bk.rb:9` (edit)
`.../archive/refs/tags/v0.27.6.tar.gz` → `.../archive/refs/tags/v0.27.7.tar.gz` (the gate checks it).

#### `CHANGELOG.md` (edit, new top entry above `## [0.27.6] - 2026-10-25`)

```markdown
## [0.27.7] - 2026-10-25

**Reviews show a station's own work again, however far trunk has moved.** `/bk:clean check`,
`/bk:clean around`, `/bk:review-task` and the taster diffed a station against the tip of
`origin/main`. Once another station's PR merged, that diff held the merged work, backwards, as
the cook's deletions, and the inspector and taster reviewed code the branch never touched. They
now diff from the branch's merge base with trunk (`git merge-base HEAD origin/<trunk>`), which
covers committed and uncommitted work and nothing else. Nothing to do: restart your sessions to
load the new skills. Closes #13 and #26.
```

#### `plugins/bk/skills/README.md:623` (edit; the "Both modes" section, after the paragraph that ends "A finding goes to the owning cook.")
Add one paragraph:

```markdown
**A station's own changes** are the diff from its merge base with trunk, never from trunk's
tip: `BASE=$(git merge-base HEAD origin/<trunk>)`, then `git diff "$BASE"` (tracked files,
committed or not) plus `git ls-files --others --exclude-standard`. Trunk moves while a cook
works, and `git diff origin/<trunk>` then shows the other stations' merged commits reversed as
this branch's deletions. The three-dot `origin/<trunk>...HEAD` alone is no better: before the
sous's `[go]` nothing is committed, so it reads empty. `/bk:clean check` and `around`,
`/bk:review-task` and the taster all use this form.
```

#### `docs/plans/INDEX.md` (new)
```markdown
# Plans

| File | Summary | Ticket |
|---|---|---|
| [13-merge-base-diff.md](13-merge-base-diff.md) | Diff a station against its merge base with trunk, not the trunk tip | #13, #26 |
```

### Success criteria
- [x] `scripts/check.sh` passes (with the bk env unset, see #50; release check v0.27.7)
- [x] CHANGELOG top entry is `## [0.27.7]` (`grep -m1 '^## \[' CHANGELOG.md`)
- [x] `grep -n 'v0.27.7' Formula/bk.rb` shows the url line

## Phase 2: The skills and the taster

**Status:** Done. clean/SKILL.md (around :52-55, check :118-127), review-task/SKILL.md step 1, agents/taster.md (description and step 1) now diff from `git merge-base HEAD origin/<trunk>`. `check.sh`: only the 7 baseline kitchen tests fail (same as untouched origin/main); every other step green.

### Changes

#### `plugins/bk/skills/clean/SKILL.md:52` and `:54` (edit, `around`)
1. line 52: ``The files your branch touched: `git diff --name-only "$BASE"` plus untracked files, with
   `BASE=$(git merge-base HEAD origin/<trunk>)` (`git fetch origin --quiet` first).``
2. line 54: ``(`git diff -U0 "$BASE" -- <file>` gives the added ranges)``.

#### `plugins/bk/skills/clean/SKILL.md:118-125` (edit, `check`)
Replace the sentence "Use the **two-dot** diff: …" and the block with:

```markdown
1. Build the inputs from the **merge base**, not the trunk tip: trunk moves while you cook, and a diff against its tip shows other stations' merged work reversed. One ref after `diff`, not `origin/<trunk>...HEAD`: in a station nothing is committed before the sous's `[go]`, so the three-dot form would read empty and pass by accident.
   ```bash
   git fetch origin --quiet
   BASE=$(git merge-base HEAD origin/<trunk>)
   DIFF=$(mktemp); FILES=$(mktemp)
   { git diff "$BASE" --
     git ls-files --others --exclude-standard | while read -r f; do git diff --no-index /dev/null "$f"; done
   } > "$DIFF"
   { git diff "$BASE" --name-only; git ls-files --others --exclude-standard; } > "$FILES"
   ```
```

#### `plugins/bk/skills/review-task/SKILL.md:44-50` (edit, step 1)

```markdown
1. **Read the whole diff.** Committed, staged, unstaged and untracked work together, measured from the merge base with trunk so another station's merged work never shows as this branch's deletions. In a station nothing is committed until the sous says go, so the three-dot form (`origin/<trunk>...HEAD`) would read empty and look like a clean pass.
   ```bash
   git fetch origin --quiet
   BASE=$(git merge-base HEAD origin/<trunk>)
   git diff "$BASE" --stat
   git diff "$BASE"
   git ls-files --others --exclude-standard
   ```
```

#### `plugins/bk/agents/taster.md:27-34` and `:3` (edit)
Line 3 (`description:`): "Reads the station's diff against trunk" → "Reads the station's diff from its merge base with trunk". Step 1:

```markdown
1. **The diff.** From the merge base with trunk, never trunk's tip (trunk moves while the cook
   works, and a tip diff shows other stations' merged work reversed). Nothing is committed
   before the pass, so one ref after `diff`, plus untracked files:
   ```bash
   git -C <station> fetch origin --quiet
   BASE=$(git -C <station> merge-base HEAD <trunk>)
   git -C <station> diff "$BASE" --stat
   git -C <station> diff "$BASE"
   git -C <station> ls-files --others --exclude-standard
   ```
```

#### Consistency read (no edit unless it finds a leftover)
`git grep -n -E 'git diff[^|]*origin/<trunk>|git diff <trunk>|two-dot' -- plugins PLAYBOOK.md README.md`
must print nothing except the contract paragraph's explanatory text and `implement/SKILL.md:57`
(which has `origin/<trunk>...HEAD` plus `status`, already right).

### Success criteria
- [x] `scripts/check.sh` passes, run as `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh` (without it 7 kitchen tests fail, identical on untouched origin/main: #50)
- [x] The consistency grep prints only the contract paragraph's explanatory text (README.md:632) and `implement/SKILL.md:57`; no `git diff origin/<trunk>` / `git diff <trunk>` / "two-dot" left in a skill or agent
- [x] Throwaway repo proof (`scratchpad/proof.sh`): the tip diff lists `other.txt` (the bug); the merge-base diff plus untracked lists exactly `own.txt`, the staged file, the unstaged file (`base.txt`) and the untracked file, never `other.txt`; same after committing everything
- [x] The `/bk:clean check` block, run verbatim with `<trunk>` = `main` in that repo: `$FILES` holds only the branch's own files and `$DIFF` has no `other.txt`

## Testing

No runner covers skill prose or agent prose; the repo's tests cover `kitchen.sh`, `guard.sh`,
`bin/bk` and the budget, none of which change. The proof is the throwaway-repo script in Phase 2,
plus a fresh read-only consistency read of the changed files against the contract (the sub-agent
read AGENTS.md asks for on prose changes across several skills).

## References

- Issues #13 and #26 on mhmzdev/claude-code-brigade (Project 4)
- Journal: `docs/journal/13-merge-base-diff.md` (the commis's verdict: no record chooses two-dot; it is a fact, not a decision)
- Already-correct precedent in the code: `plugins/bk/skills/kitchen/kitchen.sh:536-539`, `plugins/bk/skills/implement/SKILL.md:57`
- AGENTS.md "The contract is the source of truth", "Prose changes across several skills", "Releasing"
