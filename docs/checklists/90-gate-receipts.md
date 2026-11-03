---
ticket: "#90"
title: gate receipts: every check run writes a receipt naming the tree, the command and its exit; the pass trusts the receipt
plan: docs/plans/90-gate-receipts.md
last_verified: 2026-11-03
---

# Acceptance — #90 gate receipts

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

### The cook's check leaves a receipt, the taster reads it

1. The cook runs `kitchen.sh check` as its last act before `[handoff]` → one receipt line is appended to `.claude/check.log`.
2. The sous spawns the taster with `Check: kitchen.sh check --receipt` → the taster prints the receipt for the exact tree and never runs the check.
3. `open-pr` brings trunk in, runs the index and the check, then `kitchen.sh check --receipt` right before `git push` → a push only with exit 0.

## Edge cases

- A tree nobody checked → `--receipt` exits 1, "no receipt for this tree"; the taster says `blocked`.
- The config's `check:` line changed since → exit 2, "the check changed under this tree"; `check` runs again instead of trusting the old green.
- A red run → exit 2, "receipt is red"; the taster reports it as finding 1.
- A run that moved its own tree, or a line from before receipts → not a receipt.
- A same-size edit in the same second as the index write → still its own tree (the `tree_hash` fix).
- A folder name with a space or a `%` → the station field is encoded, so its receipts match.
- `git push` sends `HEAD`, not the working tree → `open-pr` requires a clean status and the receipt for `HEAD`'s tree.
- A copied receipt that names another station → not counted by the Window or the budget.

## Acceptance criteria

- [x] `kitchen.sh check` appends a receipt with the tree, start and end, the exit, the sha256 of the output, the station and the config's `check:` line — `a run writes a receipt with every field` and `…its out= is the sha256 of the output it captured` pass; the log stays out of git (`…keeping the log and the output out of git`); `kitchen.sh:2751-2783` (`cmd_check`)
- [x] `kitchen.sh check --receipt [<tree>]` prints the newest receipt for the current or a given tree, or exits 1 with "no receipt for this tree" — `--receipt prints the newest receipt for this tree and exits 0`, `…a tree given to --receipt finds that tree's receipt`, `a tree with no receipt exits 1`, `…and says so`, `a tree hash that starts with a digit is read by --receipt` pass
- [x] A changed config line makes a receipt stale, and a red, a moved or a pre-receipt line is not trusted — `a receipt from another check: line is stale: exit 2`, `…and check runs again instead of trusting it`, `a red receipt exits 2`, `a moved line is not a receipt`, `a pre-receipt log line is not a receipt: exit 1`, `…and check runs again over it` pass
- [x] The receipt names the right tree even for a same-size edit made in the same second as the index write — `24 same-size edits made right after the index was written are 24 trees, each checked` passes (red 4 of 4 without the `touch -r` line in `tree_hash`, `kitchen.sh:2711`)
- [x] The taster starts from `kitchen.sh check --receipt`, treats a green receipt for the exact tree as the proof, says blocked for none or stale and a finding for red, and never runs the check — `plugins/bk/agents/taster.md:11-12,20,38-47,70,80` (read)
- [x] `open-pr` refuses to push a tree without a green receipt, and runs the index before the check so the receipt names the tree it pushes — `plugins/bk/skills/open-pr/SKILL.md:74-92,124-138` (read); it commits what `index` changed and, before the push, requires a clean `git status --porcelain` and `--receipt "$(git rev-parse 'HEAD^{tree}')"` to exit 0, so the receipt names the commit pushed (the pass's finding 1)
- [x] A station or checkout folder with a space or a `%` in its name keeps its receipts — `a checkout folder with a space in its name still has a findable receipt`, `…its station field is encoded, one word` (tests/kitchen.test.sh), `a station folder with a space and a percent sign reads its own receipts by the encoded name` (tests/window.test.sh); red when the encoding or the decoding is reverted
- [x] `--receipt` with anything but a full 40-hex tree id is an error, never an answer for the current tree — `--receipt with a short tree id is refused (exit 64), not answered for the current tree`, `…and says it takes a full 40-hex tree id`, `--receipt with a word that is not a tree id is refused too`; red when the check is reverted
- [x] `kitchen.sh ship` is unchanged — `git diff -U0` has no hunk near `cmd_ship` (`kitchen.sh:2225`; read of the diff)
- [x] The budget and the Window read receipts through one reader and drop a receipt that names another station — `a receipt carries its station, output digest and the config line, and is marked a receipt`, `a receipt naming another station is dropped, a receipt for this one and an older line stay` (tests/window.test.sh), `two red log runs are not a check-red-repeat finding even with three red-reading runners` with a red receipt for `station-99` in the fixture (tests/budget.test.sh; red 5 failures without the filter) pass
- [x] Contract 8 names the receipt as a check's proof, and `implement` and `review-task` say a phase is done when the receipt is green — `plugins/bk/skills/README.md:721-728`, `plugins/bk/skills/implement/SKILL.md:91`, `plugins/bk/skills/review-task/SKILL.md:54,90` (read); a fresh read-only sub-agent's consistency read found 3 disagreements and 2 loose wordings, all fixed (journal)
- [x] The test cases are red with the write removed — with `cmd_check` writing the old line, 25 of 46 cases in the check sections failed; restored, 46 pass
- [x] The whole gate passes on the final tree — the cook's last `kitchen.sh check` runs `scripts/check.sh`; its receipt is the proof (the line goes in the `[handoff]` message, since writing it here would move the tree)
- [?] The receipt line of this very station — after the cook's final `kitchen.sh check`: `tail -1 .claude/check.log` shows `start=`, `out=<64 hex>`, `station=station-3` and `check=scripts/check.sh`, and `kitchen.sh check --receipt` exits 0. Not written down here, because writing it would move the tree the receipt names.
- [?] At the pass, the taster with `Check: kitchen.sh check --receipt` on this branch reports `CHECK: receipt of <time> rc=0` and does not run the check: the sous spawns it and reads its report.

## Known limitations

- `.claude/check.log` is still writable by a cook's Edit or Write; "no model writes a receipt" is a rule until a guard refuses it (the sous carries that to the guard ticket). The digest shows a line was made by a run, not that nobody forged one.
- Each upgrade costs one extra real run per tree: lines from before receipts are not receipts.
- The journal, checklist and INDEX are inside the hashed tree (#78), so the cook runs the check after its last write; the skills now say so.
- `check.out` is overwritten by the next run, so the digest cannot be re-verified against it later.
