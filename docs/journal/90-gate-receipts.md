---
ticket: "#90"
title: gate receipts: every check run writes a receipt naming the tree, the command and its exit; the pass trusts the receipt
station: station-3
created: 2026-11-03
---

# #90 — gate receipts: journal

The story of one ticket, written only by the cook that holds it (Contract 11). Append-only.
It reaches trunk with the PR, next to the plan and checklist.

## Log

<!-- One line per entry. Questions are numbered; an answer reuses the number. The commis
     runs before every question: a question that reaches the sous carries its commis: line,
     and an answer says who gave it. "(head chef)" is what the sous's handoff promotes into
     the record, so never drop that tag.
- YYYY-MM-DD HH:MM · <session name> · A1 (commis): <answer>, per <path:line, date>
- YYYY-MM-DD HH:MM · <session name> · Q2: <question> — options: a / b — recommend: a — commis: nothing recorded in decisions, specs, journals
- YYYY-MM-DD HH:MM · <session name> · A2 (sous): <answer>, because <reason>
- YYYY-MM-DD HH:MM · <session name> · Q3: <question> — options: a / b — recommend: b — commis: nothing recorded in …
- YYYY-MM-DD HH:MM · <session name> · A3 (head chef): <their answer>, because <their reason>
- YYYY-MM-DD HH:MM · <session name> · decision: <what, and why> (copied into the plan)
- YYYY-MM-DD HH:MM · <session name> · approved (sous): per gates.plan_approval.bug
- YYYY-MM-DD HH:MM · <session name> · approved (head chef, via sous): "<their words>"
- YYYY-MM-DD HH:MM · <session name> · walk-in: cleared to run `<cmd>` (sous)
- YYYY-MM-DD HH:MM · <session name> · finding 2 (pass): <what> → fixed in <file>
- YYYY-MM-DD HH:MM · <session name> · go (sous)
-->

- 2026-11-03 15:50 · claude-code-brigade-cook-3 · brief (sous): #90, a chore, priority high, lane B; the head chef decided the WHAT in the issue (2026-11-03); sous signs the plan. Plan now, but no /bk:implement until the sous says it is my turn (#86 then #85 are ahead on kitchen.sh, tests/kitchen.test.sh and the skills; #92 touches the taster). Keep kitchen.sh work in new functions plus minimal edits to `cmd_check`, and name every existing line changed.
- 2026-11-03 15:51 · claude-code-brigade-cook-3 · claimed #90 todo (`kitchen.sh rail claim`), branch issue-90-gate-receipts off origin/main 6ce2f0d
- 2026-11-03 15:56 · claude-code-brigade-cook-3 · A1 (commis): the line format and the trust rule are #66's (one space-separated line per real run; only a green for the same tree and command is trusted; red and ` moved` never), per docs/plans/66-check-tree-hash.md:105-114 (sous-signed 2026-11-03). Nothing on record covers the sha256 digest, start time, station field or `--receipt`: new choices for #90. Facts: kitchen.sh:2318 and checklog.js:8 are end-anchored, so appended fields need both patterns updated; #78 (journal/plan/checklist edits sit inside the hashed tree) is open; station-2's #85 plan has `kitchen.sh done` remove check.log per ticket. No open question blocks #90.
- 2026-11-03 ~16:05 (approximate) · claude-code-brigade-cook-3 · decision: the receipt is the #66 line plus `start= out= station=` and, last, `check=<the config line>`; older lines stay readable by the Window and budget but are not receipts, so nothing trusts them. `--receipt` exits 0 for a green current receipt, 1 for none, 2 for one that is red or stale. Because the journal, checklist and INDEX are inside the hashed tree (#78), the cook runs `kitchen.sh check` as the last act before `[handoff]`. Copied into the plan.
- 2026-11-03 ~16:20 (approximate) · claude-code-brigade-cook-3 · plan written: docs/plans/90-gate-receipts.md (3 phases: kitchen.sh receipt; Window and budget readers; contract, skills, fragment). Changes the ticket: none. Sent [plan]; no /bk:implement until the sous signs and says it is my turn.
- 2026-11-03 ~16:30 (approximate) · claude-code-brigade-cook-3 · approved (sous): per gates.plan_approval.chore; every How line signed. Amendment: say in the plan that .claude/check.log is writable by the cook's Edit/Write today and the guard refusal belongs with #91 (done, plan "Not doing"). HOLD: no /bk:implement until the sous says it is my turn (#86, then #85, are ahead).
- 2026-11-03 ~16:40 (approximate) · claude-code-brigade-cook-3 · heard (sous): my turn; #85 merged (PR #95), main ddec05d. Merged origin/main into the branch (regenerated the two INDEX files with `kitchen.sh index`), `rail move '#90' in-progress`.
- 2026-11-03 ~16:45 (approximate) · claude-code-brigade-cook-3 · line refs shifted by #85 and re-checked, plan updated (no design change): kitchen.sh cmd_check 2309-2338 → 2696-2725, FORCE 298 → 327, `--force` parse 336 → 368, usage header 75-84 → 73-82; README log row 300 → 299; Contract 8 lost "Both modes" (receipt paragraph goes after "The sous reads stations", :716); tests/kitchen.test.sh check section 1066-1131 → 1184-1250 (changed lines 1196, 1217, 1233); taster.md report line 64 → 68; sous-chef taster spawn 466 → 483; PLAYBOOK 463 → 464; implement 90 → 91; line-cook 181-184 → 182-187. clone mode is gone, so the test for a station run is the worktree one only. `done` removes check.log per ticket (kitchen.sh:2302): no clash with receipts.
- 2026-11-03 ~17:10 (approximate) · claude-code-brigade-cook-3 · decision (found in phase 1, a #66 bug the receipts would have inherited): `tree_hash` copies the real index to a temp index, and the copy gets a fresh mtime, so git trusts a file's stat when a same-size edit lands in the same second as the index write and hashes the OLD content. The new receipt test failed about 1 in 3 runs because of it; a receipt could have vouched for a tree the check never saw. One line added to tree_hash (kitchen.sh, not in the plan's list): `touch -r "$real" "$idx"` after the `cp`, so the copy keeps the real index's mtime and git re-checks racy entries by content. Regression test: 24 same-size edits made right after `git add -A`, each must be its own tree; red 4 of 4 without the line, green with it. Background: only short test loops of tests/_focus.test.sh (a scratch subset of kitchen.test.sh, removed after), no long-lived process.
- 2026-11-03 before 17:45 · claude-code-brigade-cook-3 · gate: scripts/check.sh green once on the whole change (596 kitchen, 27 guard, 85 bk, 115 budget, 29 window, 45 release); told the sous first, who agreed the tree_hash fix is in scope (plan How updated).
- 2026-11-03 before 17:45 · claude-code-brigade-cook-3 · finding (clean check, inspector): Contract 8 named a ticket number of this repo (#91) → removed from plugins/bk/skills/README.md; the plan keeps it. Nothing else found.
- 2026-11-03 before 17:45 · claude-code-brigade-cook-3 · findings (consistency read, a fresh read-only sub-agent): (1) the Window's taster blurb (window/web/scene.js:24) still said it runs the check → fixed; (2) review-task and Contract 8 were loose about red: no or stale receipt = blocked, red = finding → both reworded; (3) open-pr ran `kitchen.sh index` after the check, which moves the tree → `index` now runs before the check; (4) review-task "ran or recorded" and a line-cook parenthesis reworded to the receipt.
- 2026-11-03 before 17:45 · claude-code-brigade-cook-3 · handoff for the pass (#90): station-3, branch issue-90-gate-receipts (main ddec05d merged in). Files: kitchen.sh (receipt, --receipt, tree_hash mtime), tests/kitchen.test.sh (+19 cases, 3 changed, sealed PATH gets shasum and sha256sum), checklog.js (+budget.js and index.js comments), tests/window-live.mjs (+4), tests/budget.test.sh (a receipt and a copied one in the fixture), Contract 1/4/8, taster, sous-chef, open-pr (index before the check, --receipt before the push), review-task, implement, line-cook, PLAYBOOK, scene.js blurb, changelog.d/90-gate-receipts.md (minor), plan, checklist, journal. Gate: scripts/check.sh green earlier (596/27/85/115/29/45), the suites touched since re-run green; the final `kitchen.sh check` receipt is the proof for this tree. Inspector: 1 finding (a ticket number in the contract), fixed. Consistency read: 3 real, 2 loose, fixed. Checklist: docs/checklists/90-gate-receipts.md, 11 [x], 2 [?], 0 [!].
- 2026-11-03 17:56 · claude-code-brigade-cook-3 · note on times: I stamped the entries after 15:56 from memory instead of `date`, so they were wrong (the last four said 18:00–18:30; the check ran 17:45–17:49). The ones marked ~ are estimates, the ones marked 'before 17:45' were written before that check and their exact time is not recovered. From here every entry is stamped with `date +%H:%M`.
- 2026-11-03 17:56 · claude-code-brigade-cook-3 · findings (the pass, sous, from the taster): (1) open-pr pushes HEAD but the receipt names the working tree, and the index change was staged, not committed → open-pr now commits the index change, and before the push requires a clean `git status --porcelain` and `kitchen.sh check --receipt "$(git rev-parse 'HEAD^{tree}')"` to exit 0; (2) a folder name with a space broke the receipt (`station=[^ ]+`, `\S+`) → the station field is encoded (% as %25, space as %20) on write and decoded by checklog.js, tests with a spaced folder in both suites; (3) `--receipt` ignored a tree id that was not 40 hex → exit 64 with "--receipt takes a full 40-hex tree id.", tests; (4) the journal times → this note. Each new test was run red by reverting its fix. Next: the sous gives me the slot, then the last `kitchen.sh check`, then `[handoff]` with the new receipt line.
- 2026-11-03 17:57 · claude-code-brigade-cook-3 · second handoff for the pass (#90): the four findings fixed (open-pr, station encoding, strict --receipt, journal times); files added to the diff since the first handoff: open-pr/SKILL.md, checklog.js, kitchen.sh (parse, encoding), tests/kitchen.test.sh and tests/window-live.mjs (new cases), the plan's How, the checklist (now 13 [x], 2 [?], 0 [!]). Suites run so far: kitchen check sections 51/51, window 30/30; the whole gate runs inside the last `kitchen.sh check`, whose receipt line goes in the [handoff] message.

- 2026-11-03 18:04 · claude-code-brigade-cook-3 · go (sous): after the second pass (the taster read the receipt of tree e7a9c0a; the sous verified `check --receipt`, `--receipt 2143481` exiting 64, the open-pr gate and the station encoding itself). Then clean around, handoff, open-pr.

## Clean around

18:03 · claude-code-brigade-cook-3 · counters run over the 23 files this branch touches, on main ddec05d, minus lines this branch added:
- shellcheck-info: 8 notes in kitchen.sh, none in my added ranges (77-85, 336, 378-382, 2691-2777): SC2015 at 854, 1788, 1793, 2114, 2142; SC2016 at 1711, 1780, 2201. Open HYG #75 ("clear the six shellcheck info notes") already covers this cluster, but it names six and there are eight now (#85 and #86 landed since), so no new HYG: its Done-when list needs the two extra lines. Sent to the sous as `[rail] #75 edit`.
- todo-comments: two hits in touched files (skills/README.md:99, skills/implement/SKILL.md:66), both the text of a grep pattern (`'TODO|FIXME'`, `TODO\(decide\)`), not comments to resolve: deliberate, nothing to file.

<!-- /bk:handoff appends sections below this line:

## Handoff — YYYY-MM-DD HH:MM · <session name>

- **Stage:** planned | implementing phase N of M | at the pass | served (PR #n)
- **Uncommitted:** <files, or "nothing">
- **Next step:** <exactly what the next session does first>
- **Pending:** <open questions by number, findings not yet fixed, or "none">
- **Follow-ups:** <drafted as tickets and sent to the sous, or "none">
- lesson(repo): <key> | <one line> | <ID>
- lesson(plugin): <key> | <one line about the Brigade itself> | <ID>
-->

## Handoff — 2026-11-03 18:03 · claude-code-brigade-cook-3

- **Stage:** at the pass, passed (the sous's `[go]` after two passes); closing steps run (`clean around`, this handoff); `open-pr` next. No PR yet.
- **Uncommitted:** everything: kitchen.sh, checklog.js (+ budget.js, index.js comments), scene.js, taster.md, Contract 1/4/8, sous-chef, open-pr, review-task, implement, line-cook, PLAYBOOK, tests/kitchen.test.sh, tests/window-live.mjs, tests/budget.test.sh, changelog.d/90-gate-receipts.md, the plan, the checklist, this journal and the three INDEX files.
- **Next step:** `/bk:open-pr`: commit, merge origin/main (it was ddec05d at 2026-11-03 18:03; if it moved the check re-runs, ask the sous for the slot), `kitchen.sh index` and commit what it changed, `kitchen.sh check`, then before the push a clean `git status --porcelain` and `kitchen.sh check --receipt "$(git rev-parse 'HEAD^{tree}')"` exit 0, push, open the PR, send `[served]`. The last receipt on file: tree e7a9c0abf5a3815f4ccc35aa981104ad7d75bc04 (13:02:11Z); this handoff and the Clean around section moved the tree, so open-pr's check will run for real (about 4 minutes).
- **Pending:** none. #75's note (eight shellcheck notes, not six) went to the sous and is on the ticket.
- **Follow-ups:** none drafted.
- lesson(plugin): check-record-paperwork | a receipt names the whole working tree, so the journal, checklist, INDEX rows and any handoff written after the last `kitchen.sh check` leave the tree with no receipt (the check's last act must come after every write) | #90
- lesson(plugin): journal-times-from-date | stamp a journal entry with `date +%H:%M` when writing it; times written from memory were hours off, and the journal is the record | #90
- 2026-11-03 18:04 · claude-code-brigade-cook-3 · cost: $9.40 · 25M tokens (in 260, out 126k, cache read 24M, cache write 372k) · brief→PR 2h 12m (plan 5m, wait 15s, build 1h 53m, pass 12m) · helpers: Explore 1 ($0.30), commis 1 ($0.53), inspector 1 ($0.18), taster 1 ($0.75) · asks: none
