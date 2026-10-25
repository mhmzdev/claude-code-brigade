---
ticket: "#13"
title: clean check / review-task: diff against the merge base, not the trunk tip
station: station-1
created: 2026-10-25
---

# #13 — clean check / review-task: diff against the merge base, not the trunk tip: journal

The story of one ticket, written only by the cook that holds it (Contract 11). Append-only.
It reaches trunk with the PR, next to the plan and checklist.
Covers #26 too (same defect, sharper fix): one PR, "Closes #13, closes #26".

## Log

- 2026-10-25 · claude-code-brigade-cook-1 · brief (sous): #13 + #26, branch issue-13-merge-base-diff off origin/main 41a60f4. Sites to fix: clean, review-task, sous-chef (the pass section only; station-2 is on #19), agents/inspector.md, agents/taster.md; kitchen.sh files/leaks if they diff.
- 2026-10-25 · claude-code-brigade-cook-1 · finding: kitchen.sh already right. `changed_files` (kitchen.sh:536) uses `origin/$TRUNK...HEAD` plus `status --porcelain`; `leaks` log uses `origin/$TRUNK..HEAD` (commits only). No kitchen.sh change needed.
- 2026-10-25 · claude-code-brigade-cook-1 · finding: two-dot sites at origin/main: clean/SKILL.md:52,54 (around), :118-125 (check), review-task/SKILL.md:44-48, agents/taster.md:27-32. sous-chef/SKILL.md:~422 passes `Trunk: origin/<trunk>` to the taster (no diff command of its own). implement/SKILL.md:57 already three-dot + status (fine). open-pr uses `origin/<trunk>..HEAD` for commit log (fine).
- 2026-10-25 · claude-code-brigade-cook-1 · A1 (commis): fact. No record chooses two-dot over merge-base; "three-dot would read empty" is a skill's own reason, not a decision. kitchen.sh `changed_files` (:536) and implement:57 already use three-dot + `status` (merge-base file set), one helper, so one instance, not a precedent. taster.md:28-32 also drops `origin/` (`git diff <trunk>`). Searched: docs/questions, README contract, PLAYBOOK, CLAUDE.md, CHANGELOG, plugins/bk. No gate: the ticket itself states the intent (diff from the merge base).
- 2026-10-25 · claude-code-brigade-cook-1 · decision: fix = `BASE=$(git merge-base HEAD origin/<trunk>)` + `git diff "$BASE"` + untracked, in clean (check, around), review-task, taster; rule written once in Contract 8 "Both modes". No kitchen.sh change (already merge-base), no new subcommand, no sous-chef/SKILL.md edit (station-2 owns it for #19). Patch bump 0.27.4. (copied into the plan)
- 2026-10-25 · claude-code-brigade-cook-1 · plan written: docs/plans/13-merge-base-diff.md; `[plan]` sent to the sous, waiting for `[approved]`.
- 2026-10-25 · claude-code-brigade-cook-1 · session cleared; fresh session resumed from this journal, checked in with sous claude-code-brigade-7d and re-sent `[plan]`.
- 2026-10-25 · claude-code-brigade-cook-1 · [approved] #13 (sous, per gates.plan_approval.bug). Rail: #13 and #26 → Todo, mine; one PR closes both. Notes: (1) PR #48 takes 0.27.4, so bump to the next patch above origin/main when opening the PR (0.27.5 if #48 has merged); CHANGELOG and Formula follow. (2) station-2 (#19) also edits README.md (Contracts 5/6), CHANGELOG, plugin.json, Formula, docs/plans/INDEX.md; stay inside Contract 8; whoever merges second brings main in and bumps again.
- 2026-10-25 · claude-code-brigade-cook-1 · A2 (commis-free fact, my own check): the 7 failing kitchen tests (59, 60, 107, 109, 115, 116, 123: session resume) fail identically on a `git archive origin/main` export, also with CLAUDE*/ANTHROPIC* env stripped. Not caused by #13; gate is red on them. Not investigated further (outside this ticket); sous to decide.
- 2026-10-25 · claude-code-brigade-cook-1 · implement done: Phase 1 (contract paragraph README.md:629-635, plugin.json/Formula/CHANGELOG at 0.27.5 since #48 took 0.27.4), Phase 2 (clean around + check, review-task step 1, taster description + step 1). Throwaway-repo proof passes (scratchpad/proof.sh). clean check: inspector "No findings".

## Handoff for the pass

- station: station-1 · branch: issue-13-merge-base-diff (off origin/main 41a60f4; origin/main is now 7897503, 0.27.4)
- files changed (7 tracked + 4 new): CHANGELOG.md, Formula/bk.rb, plugins/bk/.claude-plugin/plugin.json, plugins/bk/agents/taster.md, plugins/bk/skills/README.md, plugins/bk/skills/clean/SKILL.md, plugins/bk/skills/review-task/SKILL.md; new: docs/plans/13-merge-base-diff.md + INDEX.md, docs/checklists/13-merge-base-diff.md + INDEX.md, docs/journal/13-merge-base-diff.md
- check: scripts/check.sh RED on exactly the 7 baseline kitchen tests above (263/270); manifests, shellcheck, frontmatter, guard 27/27, bk 79/79, budget 70/70, release v0.27.5 green
- inspector: no findings
- checklist: docs/checklists/13-merge-base-diff.md · [x] 10 · [?] 2 · [!] 0 (the [?]s: the baseline-red gate, which the sous decides; the new skills loading after a restart)
- at open-pr: CHANGELOG.md, plugin.json and Formula/bk.rb will conflict with origin/main's 0.27.4; keep both entries, 0.27.5 on top. Possible overlap with station-2 (#19) on README.md, CHANGELOG, plugin.json, Formula, plans INDEX.
- 2026-10-25 · claude-code-brigade-cook-1 · A3 (sous): cause of the 7 red tests is bk's env (BRIGADE_CLAUDE_ARGS, BRIGADE_VIA_BK, TMUX/TMUX_PANE) leaking into tests/kitchen.test.sh; filed as #50, not mine. Run check as `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh`, and say so in the PR test plan, pointing at #50.
- 2026-10-25 · claude-code-brigade-cook-1 · re-ran check that way: ALL CHECKS PASSED (kitchen 270/270, guard 27/27, bk 79/79, budget 70/70, release v0.27.5). Checklist now [x] 11 · [?] 1 · [!] 0 (the one [?] is the restart-to-load check after merge). Supersedes the "RED on 7 tests" line in the handoff above.
- 2026-10-25 · claude-code-brigade-cook-1 · [findings] (sous, after the taster: check rc=0 with env cleared, Done-when 12/12, inside Contract 8). Two doc-only fixes in the plan, done: Phase 1 Status now "all green with the bk env cleared (#50)"; Phase 1 Changes now read 0.27.4 → 0.27.5 (plugin.json, Formula, CHANGELOG heading). Correction: the earlier lines here that blame origin/main for the 7 red tests (A2 and the handoff's check line) are superseded by A3: the cause is bk's env leaking into the kitchen tests, #50.
- 2026-10-25 · claude-code-brigade-cook-1 · [go] #13 (+#26) (sous). Next: clean around → handoff → open-pr; bring origin/main 7897503 in (keep #48's [0.27.4] under mine, 0.27.5 in plugin.json and Formula), re-run check with the env line, PR body 'Closes #13, closes #26', test plan names #50.

## Clean around

- 2026-10-25 · claude-code-brigade-cook-1 · clean around (from the merge base 41a60f4): counters shellcheck-info (7, none in touched files) and todo-comments (7; 2 in touched files, README.md:99 and clean/SKILL.md:76, both docs text quoting the grep command, not on lines this branch added, not real TODOs). Nothing to file; no HYG drafts, no message to the sous.

## Handoff — 2026-10-25 12:21 · claude-code-brigade-cook-1

- **Stage:** [go] received; clean around done (nothing to file); handoff written; open-pr next, no PR yet.
- **Uncommitted:** everything: CHANGELOG.md, Formula/bk.rb, plugins/bk/.claude-plugin/plugin.json, plugins/bk/agents/taster.md, plugins/bk/skills/README.md, plugins/bk/skills/clean/SKILL.md, plugins/bk/skills/review-task/SKILL.md; new docs/checklists/ (checklist + INDEX), docs/journal/ (this file + INDEX), docs/plans/ (plan + INDEX). Nothing committed.
- **Next step:** `/bk:open-pr` for #13 (+#26): bring origin/main (7897503, 0.27.4) in, keeping #48's `## [0.27.4]` CHANGELOG entry under mine and 0.27.5 in plugin.json and Formula/bk.rb; re-run `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh`; PR body "Closes #13, closes #26", test plan names #50; then `[served] #13 <url>` to the sous. Station-2 (#19) also edits README.md, CHANGELOG, plugin.json, Formula and plans INDEX, so re-check `origin/main` for a newer version right before pushing.
- **Pending:** none (A1 commis, A2 superseded by A3, A3 sous; findings fixed).
- **Follow-ups:** none from clean around; #50 (kitchen tests inherit bk's env) is already filed by the sous.
- lesson(repo): kitchen-tests-bk-env | in a session opened by `bk`, run the gate as `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh` or 7 kitchen tests fail (until #50 lands) | #13
- 2026-10-25 · claude-code-brigade-cook-1 · cost line: kitchen.sh budget --ticket 13 / '#13' found no spend recorded for the ticket; skipped (a record, not a gate).
- 2026-10-25 · claude-code-brigade-cook-1 · [findings] #13 PR #52 (sous): main moved, #49 (Window polish) took 0.27.5. Merged origin/main 4a2e5c2 in (a merge commit, no force-push); bumped to 0.27.6 (plugin.json, Formula url, CHANGELOG [0.27.6] over #49's [0.27.5] and #48's [0.27.4]); plan and checklist version mentions updated to match. Release files and docs only, no new pass.

## Handoff — 2026-10-25 13:00 · claude-code-brigade-cook-1

- **Stage:** served. PR #52 open (https://github.com/mhmzdev/claude-code-brigade/pull/52), LGTM'd by the sous; re-bumped to 0.27.6 after #49 took 0.27.5 and pushed; this section supersedes the earlier handoff's "open-pr next".
- **Uncommitted:** nothing (this section is committed with the PR).
- **Next step:** none for this ticket. A fresh session in station-1 checks in as fresh with no ticket, after `git switch --detach origin/main`. Only if the head chef asks for changes to the PR: branch `issue-13-merge-base-diff`, plan `docs/plans/13-merge-base-diff.md`, checklist `docs/checklists/13-merge-base-diff.md`.
- **Pending:** none. The sous may want a ticket for a transient failure seen once: kitchen tests 131/132 (`live --demo` on port 47471) failed in one full run on the merged tree and passed on two re-runs; cause not found.
- **Follow-ups:** none drafted.
- lesson(repo): kitchen-tests-bk-env | in a session opened by `bk`, run the gate as `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh` or 7 kitchen tests fail (until #50 lands) | #13
- 2026-10-25 · claude-code-brigade-cook-1 · [brief] #52 (sous): main moved again, #54 (Window model select) took 0.27.6. Merged origin/main 1852116 in (a merge commit, no force-push); bumped to 0.27.7 (plugin.json, Formula url, CHANGELOG [0.27.7] over #54's [0.27.6], #49's [0.27.5], #48's [0.27.4]); plan and checklist version mentions updated. Release files and docs only, no new pass.

## Handoff — 2026-10-25 14:12 · claude-code-brigade-cook-1

- **Stage:** served. PR #52 is open at head 4fd99b0 (0.27.7), LGTM'd again by the sous (`[heard]`) after #54 took 0.27.6 and the branch was re-bumped. This section supersedes the 13:00 one's "0.27.6".
- **Uncommitted:** only this section (the station was clean before it). Not pushed: the sous verified 4fd99b0, so the journal rides along with whatever next touches the branch, or the sous says to push it.
- **Next step:** none for this ticket. A fresh session in station-1 does `git switch --detach origin/main` and checks in as fresh with no ticket. Only if the head chef asks for changes to the PR: branch `issue-13-merge-base-diff`, plan `docs/plans/13-merge-base-diff.md`, checklist `docs/checklists/13-merge-base-diff.md`. If main moves again before merge, re-bump above it (plugin.json, Formula url, CHANGELOG heading, plan and checklist version mentions).
- **Pending:** none. Kitchen tests 131/132 (`live --demo`, port 47471) did not flake in the gate run on 4fd99b0, which ran alone; the cause of the earlier one is still unfound and is probably station-2's check sharing the fixed port (#50).
- **Follow-ups:** none drafted.
- No new lesson; `kitchen-tests-bk-env` above still stands.
- 2026-10-25 · claude-code-brigade-cook-1 · [findings] #13 PR #52 (sous): main moved again, #55 (Window details tabs) took 0.27.7. Merged origin/main 9f9d62b in (a merge commit, no force-push); bumped to 0.27.8 (plugin.json, Formula url, CHANGELOG [0.27.8] over #55's [0.27.7], #54's [0.27.6]); plan and checklist version mentions updated. Release files and docs only, no new pass.
