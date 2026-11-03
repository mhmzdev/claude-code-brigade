---
ticket: "#64"
title: The record reaches a protected trunk, and a docs-only change needs no release
plan: docs/plans/64-record-protected-trunk.md
last_verified: 2026-11-03
---

# Acceptance — #64 The record reaches a protected trunk, and a docs-only change needs no release

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

### The sous's handoff on a protected trunk

1. The handoff writes decisions, question files and the register into the main checkout → nothing is committed (handoff steps 1 to 6).
2. Step 7, `kitchen.sh record-pr` → the files go to trunk if it takes the push, else to a `record/<date>` PR; the checkout ends on a clean trunk; the PR url goes in the note's Notes.
3. `lessons`, `decisions`, `questions`, `gaps`, `debrief` → what was just filed is not listed as due.

### A cook's PR, then a release

1. The cook adds `changelog.d/<id>-<slug>.md` and leaves the version alone → `scripts/check.sh` step 5 passes, however far `main` has moved.
2. The sous runs `scripts/release.sh` when the head chef says ship → a `release/vX.Y.Z` PR with the entry, the bump and no fragments.
3. The head chef merges it → `release.yml` tags it; any other merge finds the tag already there.

## Edge cases

- A commit that fails inside `record-pr` (a hook, no identity) → says so, exits 1, files stay in the working tree, nothing staged, no branch left.
- Main releases while a cook's branch is in flight → the cook's branch is judged against the version it started from, not main's tip.
- A record branch already merged into trunk → read as trunk, no temp view made.
- Two open record branches → the register is their union.
- A docs-only PR with the tree dirty (before the commit) → still passes.

## Acceptance criteria

Box 1 (plugin: the handoff opens a record PR itself, and says so):

- [x] On a protected trunk `record-pr` opens a PR from `record/<date>`, returns the checkout to a clean trunk and commits only the record files — `tests/kitchen.test.sh` "record-pr" cases "a protected trunk: the record goes to a PR" through "…and not the unrelated rail edit" (`kitchen.sh:1449` `cmd_record_pr`)
- [x] On an unprotected trunk with `rail.commit: direct` it files on trunk and calls no `gh`; with `daily-pr` it opens a PR; a second run the same day gets `-2`; `gh` failing leaves the branch pushed and prints the `gh pr create` line; run from a station it is refused; a failing commit backs out — same section, the cases named for each
- [x] The sous handoff calls it and records the PR in its note — `handoff/SKILL.md:158` (step 7) and `:197` (`- record PR: <url, or "none">`); steps 1, 3 and 4 no longer commit (they say "step 7 lands the files")
- [x] Contract 12 says who files the record and where it lands — `plugins/bk/skills/README.md` "Who writes what"

Box 2 (plugin: the readers see an open record PR's branch):

- [x] `lessons` — the key a record branch lists is promoted, one it doesn't is still DUE — `tests/kitchen.test.sh` "the record on a branch": "lessons: the key the record branch lists is promoted" / "…while a key it does not list is still DUE" (`kitchen.sh:1077`)
- [x] `gaps`, `decisions`, `questions` — the branch's question file replaces trunk's; a decision on the branch makes the answer `filed`; an open question only on the branch is listed — the same section (`kitchen.sh` `$REC` in `cmd_gaps`, `cmd_decisions`, `cmd_questions`)
- [x] `debrief` reads the register with the branch's row — "debrief reads the register with the branch's row" (`kitchen.sh:1842`)
- [x] Deleting the branches makes the items DUE again, so the branch was the only source; a merged branch is not read as a branch; two branches give the union; the temp view is removed — the cases of the same names (`kitchen.sh:1225` `record_branches`, `:1237` `record_view`, `:1935` the dispatcher's `trap`)
- [x] Each of those cases goes red against a broken copy of `kitchen.sh` — journal 2026-11-03, "proof the tests can fail": 11 mutations, each red in the case it should

Box 3 (this repo: a docs-only PR needs no release; `release.yml` skips tagging when the version did not change):

- [x] A PR that touches only `docs/` merges with no fragment and the same version, also before the commit — `tests/release.test.sh` "docs/ only: passes with no fragment and the same version", "docs/ only, uncommitted: still passes" (`release-check.sh:56-61`)
- [x] Anything else needs a fragment (`level: minor|patch` and a paragraph) and cannot bump or add a `## [x.y.z]` heading — `tests/release.test.sh` cases 4 to 18 of "a branch that changes more than docs/" and "a cook that bumps"
- [x] A release PR must raise the version and leave no fragment — "a release PR" cases; `release.sh` builds a branch that passes the check — "the branch it builds passes the release check"
- [x] A branch cut before main released is not mistaken for a bump — "main released while a branch was in flight" (found by gate run 1; seen red against the old comparison)
- [x] `release.yml` tags only when the version moved — `.github/workflows/release.yml:45` (an existing tag exits that step, as it did, and says why); the logic is unchanged
- [?] The first docs-only or fragment-only merge to main after this lands creates no tag and no GitHub release — recipe: merge it, `gh release list --limit 2` and `git tag --sort=-creatordate | head -2` still show the previous version; the "release" workflow run's log says "this merge did not move the version, nothing to tag"

Box 4 (this repo: a cook never bumps; Releasing section):

- [x] `AGENTS.md` says a cook never bumps, what a fragment is, how the release is made, and what a PR open at the time does — `AGENTS.md:188` ("A cook never bumps the version"); also "Checking a change" step 5, the Layout lines and `CHANGELOG.md`'s header
- [x] This PR obeys its own rule: a fragment (`changelog.d/64-record-protected-trunk.md`), no bump — `scripts/check.sh` step 5 passes on it (gate run 2: "release v0.31.0", ALL CHECKS PASSED)
- [?] `scripts/release.sh` against real GitHub: opens the PR with the right title and body (the test uses a stub `gh`) — recipe after this merges: `scripts/release.sh --dry-run` from the sous's checkout (prints `release: v0.32.0 (minor)…`, leaves the checkout untouched), then without `--dry-run`; the PR shows one entry above 0.32.0, the bump in `plugin.json` and the formula url, the fragments deleted, and its `check` runs green
- [?] `record-pr` against the real protected `main`: the push is refused by GitHub (the test uses a pre-receive hook) and `gh pr create` opens the PR — recipe at the next sous handoff: file something under `docs/decisions/`, run `kitchen.sh record-pr`; expect "Record PR: <url>", the checkout on a clean `main`, and `kitchen.sh lessons` / `decisions` already counting the filing

Findings of the pass (2026-11-03):

- [x] The temp view carries what `record_dirs` searches, specs included: an answer only a spec cites is `filed` while a record branch is open — `tests/kitchen.test.sh` "decisions: an answer only a spec cites is still filed while a record branch is open" (seen red against a view without specs)
- [x] `.claude/brigade.md` states the new rule (no PR bumps; a fragment; the release PR sets the version) — `.claude/brigade.md:59`
- [x] A config-notes edit is not a record path: `record-pr` leaves it, and the handoff says so — `handoff/SKILL.md` step 5 and step 7
- [x] The record PR body gives its own reason per path — "…and the PR body says the push was refused" and "…gives daily-pr as the reason, not a refusal"

Plan success criteria not above:

- [x] `bash tests/release.test.sh` 45/45, each case seen red (journal) — and gate run 2: kitchen 360, guard 27, bk 82, budget 87, window 16, release 45, shellcheck clean, 18 skills and 4 agents
- [x] No repo-specific text in the plugin — the inspector grepped `plugins/bk` for `changelog.d`, `release.sh`, `release-check`, `CHANGELOG`: no hits
- [x] None of #58's lines touched — `git diff` of `kitchen.sh` is additions in `rail_commit`/`record_*`/`cmd_record_pr`, the usage entry, five `$REC` substitutions and the dispatcher; the handoff skill's changes are steps 1, 3, 4, 7 to 10 and the note

## Known limitations

- The readers look at `record/*` branches by ref, as of the last fetch (no network, no `gh`). A record PR closed unmerged counts until its branch is deleted.
- The old record branch `docs/sous-record-2026-10-25` is not named `record/…`, so the readers do not see it. The sous should rebase it onto `main` and rename it, or open its PR as it is.
- Two open record PRs that both edit `docs/lessons.md` or an INDEX conflict at the second merge; it is brought up to date like any PR.
- Changes on `main` wait for the release PR; the marketplace cache is keyed on the version, so users get them at the release.
- `PLAYBOOK.md` was not touched (#58 rewrote lines there); it carries no release instructions that this contradicts (`grep -i release PLAYBOOK.md` is empty).
