---
ticket: "#28"
title: Bringing trunk in before [go] is a fast-forward, written down once
plan: docs/plans/28-ff-trunk-before-go.md
last_verified: 2026-11-03
---

# Acceptance — #28 Bringing trunk in before [go]

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

### The sous holds a ticket and asks the cook to bring main in

1. The cook reads `line-cook/SKILL.md:209`: don't merge, use `git merge --ff-only origin/<trunk>` with Contract 8's recipe → trunk is in, nothing is committed.
2. The tree clashes (an edited generated INDEX, a file trunk now tracks) → plain `--ff-only` refuses; the stash recipe (`README.md:782-786`) parks the tree, fast-forwards and applies it back.
3. The tree changed → `kitchen.sh check` runs again before `[handoff]`.

## Edge cases

- A file the cook added that trunk now tracks → comes back as trunk's copy; the cook's stays in the stash (`git show <sha>^3:<path>`), said in Contract 8. Seen in the throwaway run, not in the repo's tests.
- A generated INDEX conflicted by the apply → `kitchen.sh index`, then `git reset -q` (Contract 8).
- A branch that already has commits → waits for a grant (Contract 8's last sentence; the #91 plan says the same).

## Acceptance criteria

- [x] Contract 8 says nobody asks for trunk before `[go]` as a routine step, and gives the one form (`--ff-only`) and the stash recipe with its two traps — `plugins/bk/skills/README.md:773-793`
- [x] The wording matches #91's guard: a plain merge/pull/rebase/cherry-pick is a commit needing the grant; `--ff-only` passes — `README.md:777-781` read against `hooks/guard.sh:133-135`, which `tests/guard.test.sh:201-202,222-223` (ff-only passes, with and without a grant) and `:226` (`stash push -u` passes) pin; the consistency read confirmed there is no stash arm
- [x] `line-cook` has a how-to paragraph and the never-list names the rule — `line-cook/SKILL.md:209-211`, `:254-257` (`gh pr merge` now named, not a bare "merge")
- [x] The pass tells the sous not to ask, and to ask for `--ff-only` if it must — `sous-chef/SKILL.md:505-508`
- [x] `open-pr` step 4 says its merge is a real merge because step 3 committed — `open-pr/SKILL.md:76`
- [x] No skill tells a cook to merge trunk before `[go]` — `grep -rn 'git merge origin/<trunk>' plugins/bk/skills` shows only `open-pr/SKILL.md:80` (step 4, after the commit) and `line-cook/SKILL.md:207` (after `[served]`); fresh read-only consistency read found no contradiction (journal)
- [x] The recipe works — run in a throwaway repo (clashing edit, conflicted generated file, untracked file trunk also added) and for real in this station to bring in 7129073 (journal)
- [x] One patch fragment, no version bump — `changelog.d/28-ff-trunk-before-go.md` (`level: patch`); `kitchen.sh scope`: 9 inside, 0 outside the plan's `files:`
- [x] Inspector: two low-confidence findings (a long plan; the rule stated in two places in line-cook), kept on purpose, journaled; no dead code

## Known limitations

- Prose only: no test pins the wording, and there is none to write (CLAUDE.md: prose changes get a consistency read, done).
- Pre-existing and left alone, as follow-ups in the journal: stash wording differs across `line-cook`, Contract 8, `setup` and `open-pr:165`; `open-pr:53` uses a bare `git stash pop`; the README's hooks section doesn't mention the `--ff-only` exemption that `guard.sh:15` states.
- `git pull --ff-only` passes the guard too; Contract 8 and the pass say so.
