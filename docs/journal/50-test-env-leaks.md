---
ticket: "#50"
title: "tests: kitchen.test.sh isn't safe inside a kitchen: leaks BRIGADE_CLAUDE_ARGS, BRIGADE_VIA_BK and TMUX, and the live-demo test uses a fixed port"
station: station-1
created: 2026-11-03
---

# #50 — tests: kitchen.test.sh isn't safe inside a kitchen: journal

The story of one ticket, written only by the cook that holds it (Contract 11). Append-only.
It reaches trunk with the PR, next to the plan and checklist.

## Log

- 2026-11-03 · claude-code-brigade-cook-1 · brief (sous): #50, bug, lane B; sous signs the plan; station-2 (#65) edits tests/kitchen.test.sh too, so keep to the header's unset block and the live-demo port; fragment `level: patch`.
- 2026-11-03 · claude-code-brigade-cook-1 · claimed: `[rail] claim #50 todo cook=station-1` sent.
- 2026-11-03 · claude-code-brigade-cook-1 · pick-ticket: verdict Stands at origin/main 70e1d1c. kitchen.test.sh:27 unsets none of the four; bk.test.sh:27-28 unsets BRIGADE_CLAUDE_ARGS and TMUX only; budget.test.sh:24, guard, window, release unset none; kitchen.test.sh:346-362 still on fixed 47471. No PR or plan for #50 anywhere. Kind: bug, so create-plan.
- 2026-11-03 · claude-code-brigade-cook-1 · A1 (commis): env isolation is a precedent — each suite seals HOME/GIT_CONFIG_* and unsets BRIGADE_* at the top (bk.test.sh:24-28 is the fullest), per CLAUDE.md "Checking a change". The port has no record (nothing); walk-in `window-port-4747` lists commands, not test ports, and 47471 never conflicts with 4747/4748. The port choice is a how, not a fork.
- 2026-11-03 · claude-code-brigade-cook-1 · decision: free port from the OS via node (listen(0)), not derived from the temp dir; unsets only in kitchen.test.sh and bk.test.sh (no code in the other suites reads the vars). Both under How in the plan. No fork, no Q.
- 2026-11-03 · claude-code-brigade-cook-1 · plan written: docs/plans/50-test-env-leaks.md (3 phases); [plan] sent to the sous.
- 2026-11-03 · claude-code-brigade-cook-1 · approved (sous): per gates.plan_approval.bug. Full runs are cleared by the sous right before each batch (mutated run, two-at-once pair, mutated pair, final check.sh). If a two-at-once run flakes on EADDRINUSE (listen(0) closes the port before the Window binds it), record it here, don't retry silently.
- 2026-11-03 · claude-code-brigade-cook-1 · walk-in: batch 1 cleared by the sous. Mutated COPY (unset reverted) of kitchen.test.sh, run in this bk session: red exactly 59, 60, 107, 109, 115, 116, 123 (402 pass, 7 fail, of 409), the ticket's seven.
- 2026-11-03 · claude-code-brigade-cook-1 · batch 2 (real suite twice at once, in this bk session): run 2 green 409/409; run 1 408/409, red: 124 '…without a second sous window' (the grep found a 'new-window -t app-brigade -n sous' in tmux.log, though 123 right before passed). No EADDRINUSE; Window tests (live section) green in both. 124 is a tmux-stub test, not touched by this change; cause unknown yet (flake under load, or a race between the two runs?). Asked the sous for a rerun with KEEP=1.
- 2026-11-03 · claude-code-brigade-cook-1 · batch 2b (pair at once, KEEP=1): both 409/409 green. So test 124 went red in 1 of 4 concurrent runs (batch 2 run A, 408/409) and 0 of 3 other runs of the real suite (batch 2 run B, 2b ×2), and 0 of the mutated run (batch 1; 124 was not in its red set). No evidence kept for the red one (no KEEP then).
- 2026-11-03 · claude-code-brigade-cook-1 · shared state looked for, none found: kitchen.sh's tmux path (open, lines ~818-846) reads only the stub in $TB (under $TMP) for has-session, list-windows, display-message; the registry reads use $HOME/.claude/sessions or CLAUDE_CONFIG_DIR, both under $TMP in the suite; mktemp dirs are per-call; the only background process in that area (the deferred /clear waiter, kitchen.sh:1836) isn't started by `open`; `claude_cwds` (ps/lsof) is read-only and not on 124's path. Hypothesis, NOT reproduced: the `tmux list-windows … | grep -qx sous` pipeline runs under `set -o pipefail` (kitchen.sh:180); if the stub is cut by grep -q's early exit, the pipeline fails and `open` takes the "no sous window" branch, which logs `new-window … -n sous` and fails 124 (123 still passes, its send-keys is in both branches). I could not make that happen by hand (300 fast and a slow-writer trial, status 0 each), so it stays a guess. Verdict for the sous: not shared state, not this ticket's change; a load flake in a tmux-stub test, to file on its own with this evidence.
- 2026-11-03 · claude-code-brigade-cook-1 · walk-in: batch 3 cleared by the sous. Mutated COPY (literal 47471 back) twice at once: run b2 409/409 green, run b1 red on 131 'live --demo opens the Window' and 132 '…and prints its URL', then aborted at 'wpid: unbound variable' (exactly the symptoms in the ticket's comment of 2026-10-25). Nothing left listening on 47471. The fixed-port collision is proven, and the OS-picked port removes it (batch 2b: 0 failures in the Window section in 6 concurrent runs).
- 2026-11-03 · claude-code-brigade-cook-1 · known flake: test 124 '…without a second sous window' went red once in a concurrent run (batch 2); the sous filed it as #84 (list-windows | grep -qx under pipefail, kitchen.sh:831/:840). Not caused by or fixed in this ticket; name #84 in the PR's test plan.
- 2026-11-03 · claude-code-brigade-cook-1 · implemented, all 3 phases. kitchen.sh check green in this bk session (ran, 168s): kitchen 409, guard 27, bk 82, budget 92, window 22, release 45, v0.33.0. Next: clean check, review-task, [handoff].
- 2026-11-03 · claude-code-brigade-cook-1 · clean check: inspector (bk:inspector) reports no findings.
- 2026-11-03 · claude-code-brigade-cook-1 · handoff for the pass: station-1, branch issue-50-test-env-leaks (nothing committed). Files: tests/kitchen.test.sh (unset block +4 names; Window section on an OS-picked WPORT), tests/bk.test.sh (+BRIGADE_VIA_BK, TMUX_PANE), changelog.d/50-test-env-leaks.md (patch), plan, checklist, journal, 3 INDEX rows. Check: `kitchen.sh check` green (ran, 168s) inside this bk session before the docs-only edits since; the exact tree is the taster's to re-run. Inspector: no findings. Checklist docs/checklists/50-test-env-leaks.md: 9 [x] · 2 [?] (post-merge observations) · 0 [!].
- 2026-11-03 · claude-code-brigade-cook-1 · go (sous): the taster passed it with no findings; check.sh in the station, all four vars set, green 409/27/82/92/22/45. Main moved to d0e3be5 (#81, docs only): bring it in at open-pr; ask the sous for the gate slot before the re-run; name #84 in the PR test plan.

## Clean around

2026-11-03 · claude-code-brigade-cook-1 · both counters (shellcheck-info, todo-comments) return nothing in the files this branch touched (tests/kitchen.test.sh, tests/bk.test.sh; the shellcheck counter only reads kitchen.sh, guard.sh and bin/bk). Nothing to draft.

## Handoff — 2026-11-03 · claude-code-brigade-cook-1

- **Stage:** passed. The sous's `[go]` is in (the taster found nothing; check.sh in the station with all four vars set was green, 409/27/82/92/22/45); `/bk:clean around` found nothing (above); this closing handoff is written. Next: `/bk:open-pr`. No PR yet.
- **Uncommitted:** everything, as the sous approved: tests/kitchen.test.sh, tests/bk.test.sh, changelog.d/50-test-env-leaks.md, docs/plans/50-test-env-leaks.md, docs/checklists/50-test-env-leaks.md, docs/journal/50-test-env-leaks.md, the three INDEX files.
- **Next step:** `/bk:open-pr` commits, brings `origin/main` in (it moved to d0e3be5, #81 docs only), then asks the sous for the gate slot before the one re-run of the check on the merged tree (#65's taster is about to use the gate). Subject `[#50] …`. The version stays untouched: the fragment `changelog.d/50-test-env-leaks.md` (level: patch) carries it. PR Test plan: names the env proof (the unset reverted on a copy: 59, 60, 107, 109, 115, 116, 123 red, 402/409), the port proof (literal 47471 back, two at once: 131 and 132 red), the green runs (a gate inside a bk session; the real suite twice at once, 6 runs, no Window failure), and test 124 as the known flake **#84** (list-windows | grep -qx under pipefail), seen once in batch 2, not caused by or fixed here. The two `[?]` of the checklist are post-merge observations.
- **Pending:** nothing.
- **Follow-ups:** none new (#84 already filed by the sous).
- lesson(repo): mutate-a-copy | to prove a test can fail, mutate a COPY of the script outside the checkout; a detached loop mutating the live file survived a killed pid, left a mutation behind, and a later "restore" saved the mutation | #64 (used again here, it worked)
- lesson(repo): copy-needs-plugins-link | a copy of tests/kitchen.test.sh outside the checkout runs if its folder holds tests/ and a symlink `plugins` to the checkout's: the suite reads only $REPO/plugins (REPO is its own parent folder) | #50
- 2026-11-03 · claude-code-brigade-cook-1 · cost line: not written. `kitchen.sh budget --ticket '#50' --journal-line` answers "No spend recorded for #50" (the budget only knows S###-##, BKLG-###, HYG-### ids: #59); went on without it, as the skill allows.
- 2026-11-03 · claude-code-brigade-cook-1 · open-pr: committed c715b7d, merged origin/main d0e3be5 (docs only, no conflicts). Waiting on the sous for the gate slot (#65's taster is using check.sh).
- 2026-11-03 · claude-code-brigade-cook-1 · open-pr: gate slot given by the sous; running the one check on the merged tree.
