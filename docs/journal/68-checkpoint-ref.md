---
ticket: "#68"
title: A checkpoint ref for a station's uncommitted work (kitchen.sh checkpoint / restore)
station: station-3
created: 2026-11-03
---

# #68 — A checkpoint ref for a station's uncommitted work: journal

The story of one ticket, written only by the cook that holds it (Contract 11). Append-only.
It reaches trunk with the PR, next to the plan and checklist.

## Log

- 2026-11-03 21:49 · claude-code-brigade-cook-3 · briefed by the sous (chore, lane B, EPIC #71, the sous signs the plan); branch issue-68-checkpoint-ref at origin/main 7129073; claimed todo
- 2026-11-03 21:49 · claude-code-brigade-cook-3 · sequencing (sous): plan now, do not /bk:implement on [approved] until the sous says it is my turn (#28 in station-2 edits Contract 8 and line-cook)
- 2026-11-03 21:49 · claude-code-brigade-cook-3 · fact: guard.sh does not refuse git update-ref or git commit-tree (guard_git has no case for them), and kitchen.sh's inner git calls are never seen by it; no guard change needed
- 2026-11-03 21:49 · claude-code-brigade-cook-3 · decision: ref = commit-tree of tree_hash with parent HEAD; one ref per ticket, update-ref with old value; taster reads diff from the ref, receipt/scope/journal still in the station (copied into the plan)
- 2026-11-03 21:49 · claude-code-brigade-cook-3 · approved (sous): per gates.plan_approval.chore; all three flagged points signed as how: (1) no guard change, pin tests only, the update-ref refs/heads/* gap goes to #69; (2) taster reads the diff from the ref via the main checkout, receipt/scope/plan/journal stay station-local; (3) a lost disk is out of scope
- 2026-11-03 21:49 · claude-code-brigade-cook-3 · HOLD (sous): do not start /bk:implement until the sous says it is my turn; #28 merges first, then bring main in with a fast-forward or merge (no rebase) before building
- 2026-11-03 22:08 · claude-code-brigade-cook-3 · go (sous): "your turn" after #28 merged (PR #101); brought origin/main (4eba176) in with git merge --ff-only (the INDEX.md files were regenerated copies: restored, then rebuilt with kitchen.sh index)
- 2026-11-03 22:08 · claude-code-brigade-cook-3 · shifts from #28: Contract 8 gained a "Trunk moves while nothing is committed" paragraph (ff-only, stash recipe): my checkpoint bullet goes beside it; a trunk fast-forward changes the tree, so the checkpoint reads behind until the cook checkpoints again (say so in the bullet). sous-chef/SKILL.md gained a step 6 after the taster steps: my Checkpoint line goes in the taster prompt, not there. line-cook untouched by me.
- 2026-11-03 22:28 · claude-code-brigade-cook-3 · phase 1 done: kitchen.sh checkpoint / --show / restore, done drops the ref, sync lists a held one; kitchen/SKILL.md rows. shellcheck: same 8 notes as main, none new
- 2026-11-03 22:28 · claude-code-brigade-cook-3 · phase 2 done: 38 kitchen tests (434-471) and 6 guard pins, all green; broken on purpose, each went red: no update-ref write (many), no -p HEAD (parent + restore), restore without --binary (restore tests), done without the ref delete (470); guard.sh with update-ref|commit-tree refused → the pins went red (4)
- 2026-11-03 22:28 · claude-code-brigade-cook-3 · phase 3 done: implement 3b, review-task last act, handoff step 5 and reading-on-start, sous-chef taster prompt, taster.md step 1 (current / behind / none), Contracts 4/5/8 (the checkpoint paragraph sits after #28's trunk-moves one), changelog fragment (minor)
- 2026-11-03 22:28 · claude-code-brigade-cook-3 · fact: the installed kitchen.sh the skills name is the main checkout's older copy with no checkpoint command, so dogfooding used this station's plugins/bk/skills/kitchen/kitchen.sh (checkpoint wrote refs/brigade/station-3/68, current)
- 2026-11-03 22:30 · claude-code-brigade-cook-3 · clean check: inspector, no findings (bundled list)
- 2026-11-03 22:30 · claude-code-brigade-cook-3 · handoff for the pass: station-3, branch issue-68-checkpoint-ref (at 4eba176, nothing committed); 15 files (kitchen.sh, kitchen/SKILL.md, README Contracts 4/5/8, implement, review-task, handoff, sous-chef, taster.md, 2 test files, fragment, plan, journal, checklist and INDEX rows); scope outside 0; checklist docs/checklists/68-checkpoint-ref.md 15 [x], 1 [?] (the gate), 0 [!]; the one full gate run (scripts/check.sh) is my last act, per the sous: its receipt is the proof (kitchen.sh check --receipt)
- 2026-11-03 22:35 · claude-code-brigade-cook-3 · finding (own gate): the one full run was red on shellcheck only (SC1010, an unquoted done in two new test lines); every test suite was green (719/431/85/117/30/45). Quoted them like the existing done calls; running the gate once more, as the sous allowed on red

## Clean around

Files this branch touched, counters from `clean.counters`, findings on lines this branch added dropped (none were on them). `todo-comments`: two matches in touched files, both patterns in prose and config (`README.md:101`, `implement/SKILL.md:66`), not TODO comments: nothing to file.

### Draft HYG: shellcheck-info notes in kitchen.sh

- `lane: C`, `status: backlog`, `files: plugins/bk/skills/kitchen/kitchen.sh`
- Why: the `shellcheck-info` counter reads 8, all in `kitchen.sh`; clearing them lets the counter mean "something new".
- Done when: the counter drops 8 → 0 and `scripts/check.sh` passes. Findings (file:line at origin/main 4eba176 + 0; line numbers as on this branch):
  - `kitchen.sh:905` SC2015 (`A && B || C` in the Warp-opened echo)
  - `kitchen.sh:1984` SC2016, `:2053` SC2016, `:2574` SC2016 (single-quoted text that is meant literally: quote or disable with a reason)
  - `kitchen.sh:2061`, `:2066`, `:2391`, `:2426` SC2015 (`A && B || C`)

## Handoff — 2026-11-03 22:42 · claude-code-brigade-cook-3

- **Stage:** passed ([go] from the sous, grant held: commit push open-pr); clean around and this handoff written; /bk:open-pr next, then [served]
- **Uncommitted:** everything on branch issue-68-checkpoint-ref (17 files: kitchen.sh, kitchen/SKILL.md, README Contracts 4/5/8, implement, review-task, handoff, sous-chef, taster.md, the two test files, fragment, plan, journal, checklist and the three INDEX rows); green receipt for tree 99d0d42 before the journal's last lines
- **Next step:** /bk:open-pr (it commits, brings origin/main in, re-runs the check, pushes, opens the PR), send [served] with the url; stay ready to bring main in if the sous says the PR is behind
- **Pending:** none (no open Qn). The HYG draft for the 8 shellcheck notes duplicates #75, which the sous says already carries the count
- **Follow-ups:** none new
- **Processes:** none
- lesson(repo): mutate-a-copy | I mutated the live kitchen.sh in place with a backup; a run that outlived its timeout left the file mutated in the background for minutes, so I could not edit it. Mutate a copy outside the checkout | #68
- lesson(repo): shellcheck-after-tests | an unquoted done as the command word in a test (`"$K" done …`) is SC1010 and only the full gate showed it; run shellcheck on a test file as soon as it is written, and quote it as the existing tests do | #68
- 2026-11-03 22:43 · claude-code-brigade-cook-3 · cost: $5.16 · 17M tokens (in 200, out 74k, cache read 16M, cache write 196k) · brief→PR 58m (plan 5m, wait 13s, build 51m, pass 34s) · helpers: inspector 1 ($0.34) · asks: none
