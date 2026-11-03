---
ticket: "#63"
title: record: generate the INDEX.md tables from frontmatter, so concurrent tickets stop conflicting
station: station-2
created: 2026-11-03
---

# #63 — generate the INDEX.md tables from frontmatter: journal

The story of one ticket, written only by the cook that holds it (Contract 11). Append-only.
It reaches trunk with the PR, next to the plan and checklist.

## Log

- 2026-11-03 · station-2 · brief (sous, claude-code-brigade-42): issue #63, kind chore, lane B, EPIC #71 section 2. Branch issue-63-generated-index from origin/main f390e36 (0.27.9). Station-1 is on #62 (budget.js, sessions.js, Ledger page, budget and debrief functions in kitchen.sh): stay out. PR #53 (0.28.0) waits for the head chef, so plan 0.29.0 and bring main in once it lands. Decision 001 holds. Anything the record doesn't settle (the command's name and shape, the row order, existing hand-written rows, a repo with its own doc schema) goes under the plan's Decisions for the head chef. Run the gate as `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh`, one station at a time, telling the sous first.
- 2026-11-03 · station-2 · pick-ticket: verdict Stands. At origin/main f390e36 `kitchen.sh` has no `index` command; `doctor` parses only ticket files (backlog and a spec's sub-folder), not plan, journal or checklist frontmatter, so the "doctor already parses it" premise holds only in part. No PR names #63. Repo has no `.gitattributes`, so the `merge=union` that `setup` tells a consuming repo to add isn't in force here.
- 2026-11-03 · station-2 · Q1: has the record decided that the plans/journal/checklists INDEX files are generated, the command's name or shape, the row order, what happens to hand-written rows or a repo's own doc schema? — sent to the commis (opus)
- 2026-11-03 · station-2 · A1 (commis): nothing recorded. Contract 4 says the opposite (the skill that writes a file adds its row, README.md:289-290); `merge=union` (setup/SKILL.md:149-159, 0.5.1) is the current answer to the conflicts and nothing marks it for removal; decision 001 is not on trunk and is about merge order only; `docs/questions/mechanical-enforcement.md:53` lists "INDEX rows" among hand edits a script could take over (open, related). Only precedent is `kitchen.sh board`, which is untracked.
- 2026-11-03 · station-2 · origin/main moved to 0.28.0 (820a3fd, #53 merged); branch fast-forwarded (nothing was committed). Version is 0.29.0.
- 2026-11-03 · station-2 · plan written: docs/plans/gh-63-generated-index.md, open_questions none, four phases (command + tests, contract + templates, skills, this repo adopts + release). Six Decisions for the head chef (record has none): 1 committed-and-regenerated vs untracked INDEX, 2 `kitchen.sh index [--check] [--adopt]` not `doctor --fix`, 3 scope = plans/journal/checklists only (narrower than the issue's "every mapped folder"), 4 columns, row order (path, byte order) and summary fallbacks, 5 hand-written INDEX left alone until `--adopt`, 6 an INDEX conflict is resolved by running the command. No protected paths. The plan's own INDEX rows are not hand-added: Phase 4 runs `index --adopt`, which writes all three. Sending `[plan]`.

## Handoff — 2026-11-03 11:54 · claude-code-brigade-cook-2

- **Stage:** planned. The plan is written (`docs/plans/gh-63-generated-index.md`, `open_questions: none`, status `draft`) and `[plan] #63 ready` is with the sous. Nothing is built; `/bk:implement` has not started and must not until an `[approved]` is copied into this journal.
- **Uncommitted:** two untracked files, `docs/journal/63-generated-index.md` and `docs/plans/gh-63-generated-index.md`. Branch `issue-63-generated-index` is at origin/main 820a3fd (0.28.0), no commits.
- **Next step:** wait for the sous's `[approved]` (the six Decisions are the head chef's, relayed) or `[findings]` (revise the plan, send `[plan]` again). On `[approved]`: copy it into the Log, send `[rail] #63 → in-progress`, then `/bk:implement`, Phase 1 first (the `index` command in `kitchen.sh` next to `doctor`, plus the tests; break each new test on purpose). Tell the sous before running the gate, one station at a time: `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh`. Before editing, `git fetch origin` and bring main in if it moved past 0.28.0 (PR #62 from station-1 touches `kitchen.sh`'s budget and debrief functions: stay out of those).
- **Pending:** the plan's sign-off; no numbered question is open (Q1 was answered by the commis, `nothing`). I did not hand-add the plan's or journal's INDEX rows (the ticket removes that step); Phase 4 runs `kitchen.sh index --adopt`, which writes all three INDEX files.
- **Follow-ups:** none yet.
- **Lessons:** none new.
- **Session:** work only under this station's own path (`/Users/hamza/Development/Work/claude-code-brigade-stations/station-2`), never the skill base path (it points into the main checkout; see `lesson(plugin): skill-base-path-is-main`, #19).
- 2026-11-03 · station-2 · [approved] (sous claude-code-brigade-4d, head chef relayed): "Approve", covering the plan and its six decisions. Gate: `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh`, telling the sous before each full run (station-1 runs one too). Sous: contract first, then grep every skill for the old wording in the same change. I'll do the plan's Phase 2 (contract + templates) before Phase 1 (the command) for that reason; same files, same PR, plan unchanged.
- 2026-11-03 · station-2 · phase 2 (contract, SCHEMA, checklist template) and phase 1 (`kitchen.sh index [--check] [--adopt]`, `doctor` warning, usage header, 29 tests under `section "index"`) written. Mutation check: seven deliberate breaks (no write, no sort, no pipe escape, ROOT for HERE, no marker check, no doctor warning, no plan-title fallback) each turned its tests red; code restored. shellcheck-info count on kitchen.sh unchanged (6, same as trunk). Full gate not run yet (station-1 is using it).
- 2026-11-03 · station-2 · phases 3-4 written: create-plan, review-task, handoff, implement, open-pr, setup, kitchen skill; this repo's three INDEX files adopted (`kitchen.sh index --adopt`; "#13, #26" is now "#13"); 0.29.0 in plugin.json, Formula, CHANGELOG. Gate (env unset, told the sous first): rc 0, kitchen 299, guard 27, bk 82, budget 71, window 16, release green.
- 2026-11-03 · station-2 · sweep (fresh read-only agent): no skill still tells a cook to type a row for the three folders. Fixed: Contract 12 now says `—` for a missing ticket and that open-pr runs the command before it commits and again after trunk comes in; kitchen skill `argument-hint` lists `index`; setup says the `merge=union` glob also matches the three generated files (harmless); review-task's description says it regenerates the row. Left alone: line-cook says to create the journal from the template without naming `index` (handoff and open-pr run it, so the rule is met; line-cook isn't in the plan's files).
- 2026-11-03 · station-2 · clean check: inspector (bk:inspector, diff vs merge base 820a3fd, bundled list) — no findings.
- 2026-11-03 · station-2 · review-task: checklist docs/checklists/gh-63-generated-index.md, 14 [x], 3 [?] (final gate re-run owed; a real open-pr INDEX conflict; GitHub's adjacent-row flag), 0 [!]. Inspector reused from clean check (same diff, no findings). Gate not re-run yet: waiting for the sous to say it is free.
- 2026-11-03 · station-2 · final gate (told the sous first), env unset: rc 0 — kitchen 299, guard 27, bk 82, budget 71, window 16, release v0.29.0. Checklist now 15 [x], 2 [?], 0 [!].

## Handoff for the pass

- station: station-2 (worktree), branch `issue-63-generated-index`, based on origin/main 820a3fd (0.28.0). Nothing committed.
- files changed: `plugins/bk/skills/kitchen/kitchen.sh` (new `index`, `doctor` warning, flags, usage), `tests/kitchen.test.sh` (29 tests, `section "index"`), `plugins/bk/skills/README.md` (Contracts 4, 12), skills `create-plan`, `review-task`, `handoff`, `implement`, `open-pr`, `setup`, `kitchen`, templates `SCHEMA.md` and `checklist.md`, `plugins/bk/.claude-plugin/plugin.json` (0.29.0), `Formula/bk.rb`, `CHANGELOG.md`, and the three generated INDEX files. New: `docs/plans/gh-63-generated-index.md`, `docs/journal/63-generated-index.md`, `docs/checklists/gh-63-generated-index.md`. hooks/, bin/, the Window and the budget/debrief functions untouched.
- check: `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh` rc 0 (kitchen 299, guard 27, bk 82, budget 71, window 16, v0.29.0). Seven deliberate breaks each turned their tests red.
- inspector: no findings. Sweep (fresh read-only agent): none outstanding; line-cook's "create the journal from the template" doesn't name `index` (handoff and open-pr run it; line-cook is not in the plan's files).
- checklist: docs/checklists/gh-63-generated-index.md, 15 [x] / 2 [?] / 0 [!]. The [?]: a real `/bk:open-pr` on a branch whose INDEX conflicts with main; GitHub still flagging adjacent rows (known limitation).
- main will move (#62, 0.28.1): bring it in at open-pr; expect conflicts in CHANGELOG/plugin.json/Formula (keep 0.29.0 above 0.28.1) and near Contracts 2/11 in skills/README.md; after any INDEX conflict, run `kitchen.sh index`.
- 2026-11-03 · station-2 · finding 1 (pass, sous): line-cook creates the journal but didn't say to run `kitchen.sh index` → fixed in plugins/bk/skills/line-cook/SKILL.md:139-143 (fill `ticket:`/`title:`, run the command, same hand-written fallback). Plan `files:` and Phase 3 now name line-cook, and the Phase 3 grep criterion allows the approved fallback lines. Prose-only: no heading changed (`## Contents` still matches), `kitchen.sh index --check` up to date; gate not re-run, per the sous.

## Clean around

- 2026-11-03 · station-2 · counters over the files this branch touched. shellcheck-info: 6 hits in `kitchen.sh`, none on a line this branch added (added ranges 89-94, 237-238, 266-267, 1357-1436, 1504-1509, 1667), so all are old; the one other hit in the counter's scope is `bin/bk:213`, a file this branch doesn't touch. todo-comments: 5 hits in touched files (`skills/README.md:99`, `create-plan/SKILL.md:162`, `implement/SKILL.md:66`, `setup/SKILL.md:109`, and `.claude/brigade.md:39`, which is the counter's own command), all deliberate: they document the counter and the open-questions gate's pattern. No ticket for those.
- Draft HYG-1 (one cluster, PR-sized): **kitchen.sh: clear the six shellcheck info notes**
  - Why: the `shellcheck-info` counter reads 7 on trunk; six are in `kitchen.sh`. The `A && B || C` notes hide a case where C runs after A succeeds; the single-quote notes are printf text with backticks.
  - Done when: these findings are gone, `shellcheck-info` drops by 6 (7 → 1; `bin/bk:213` stays), and `scripts/check.sh` passes:
    - `plugins/bk/skills/kitchen/kitchen.sh:740` SC2015 (Warp message `&& echo … \`)
    - `:1224` SC2016 (inbox header printf)
    - `:1293` SC2016 (asks header printf)
    - `:1301` SC2015 (`[[ -f ]] && grep || { … }`, `--answer`)
    - `:1306` SC2015 (the same, `--filed`)
    - `:1653` SC2015 (`worktree remove … && echo … ||`, `cmd_remove`)
  - files: `plugins/bk/skills/kitchen/kitchen.sh`. Line numbers are from this branch (they move by about 90 lines against trunk).

## Handoff — 2026-11-03 12:33 · claude-code-brigade-cook-2

- **Stage:** at the pass, `[go]` received (finding 1, line-cook, fixed and read by the sous); `clean around` done (one HYG draft sent: kitchen.sh's six old shellcheck notes); next is `open-pr`. PR #73 (#62, 0.28.1) is still open, so origin/main is 820a3fd (0.28.0).
- **Uncommitted:** everything (nothing is committed): 19 edited files plus the new plan, journal and checklist (`git status --short` lists 22 entries). All three INDEX files are generated and current (`kitchen.sh index --check`).
- **Next step:** `/bk:open-pr`. Tell the sous before the full gate. Fetch and bring origin/main in first. If #73 has merged, expect conflicts in `CHANGELOG.md`, `plugins/bk/.claude-plugin/plugin.json`, `Formula/bk.rb` (keep `[0.29.0]` above `[0.28.1]`, version and Formula tag at 0.29.0) and possibly near Contracts 2/11 in `plugins/bk/skills/README.md`; then run `kitchen.sh index` for the INDEX files (never keep both rows), `git add` them, `git commit --no-edit`. Re-run `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh`, then push (merge commit, no force), open the PR "[#63] …" with "Closes #63", test plan naming #50 and the two `[?]` recipes, and send `[served] #63 <url>`. If #73 is still open, open the PR anyway (decision 001: the head chef merges #73 first; I bring main in after).
- **Pending:** none. Two `[?]` checklist items are live-session recipes (a real INDEX conflict through `open-pr`; GitHub flagging adjacent rows).
- **Follow-ups:** HYG draft ×1 (kitchen.sh's six shellcheck info notes) is with the sous, see `## Clean around`. Not filed: the todo-comments hits (all deliberate).
- **Lessons:** none new.
- **Session:** my shift is over after `[served]`; clear this session before any other ticket. Only the head chef merges the PR.
- 2026-11-03 · station-2 · cost line: `kitchen.sh budget --ticket 63 --journal-line` found no spend recorded for 63; not a gate, going on.
- 2026-11-03 · station-2 · slip at open-pr: after committing I read `git log -1 origin/main` wrong and told the sous main was still 820a3fd, started the gate on a conflicted tree, then stopped it (no gate result from that run) and said so. main was already ab1ffc8 (0.29.0, #74 / #72 merged). Always read the sha off the line labelled for origin/main.
- 2026-11-03 · station-2 · merged origin/main (ab1ffc8, 0.29.0) into the branch: only CHANGELOG.md conflicted; kept `[0.30.0]` (this ticket) above `[0.29.0]` (#72), set plugin.json and the Formula to 0.30.0; skills/README.md, create-plan, plan.md, line-cook, sous-chef merged without conflict and my Contract 4/12 edits and the index lines are intact. `kitchen.sh index` after the merge: all three up to date. #73 (#62, 0.29.1) merges first, so expect one more main merge.
- 2026-11-03 · station-2 · open-pr gate on the merged tree (told the sous; station-1's overlapping run was stopped), env unset: rc 0 — kitchen 299, guard 27, bk 82, budget 73, window 16, release v0.30.0.
- 2026-11-03 · station-2 · merged origin/main (18d49d0, 0.29.1 from #73) into the branch: conflicts in CHANGELOG (kept 0.30.0 above 0.29.1), plugin.json and Formula (kept 0.30.0), and the three INDEX files (cleared with `kitchen.sh index`, `--check` up to date). skills/README.md merged without conflict, so #62's Contract 2/11 edits and my 4/12 edits both stand.
- 2026-11-03 · station-2 · gate on the merged tree (env unset): rc 0 — kitchen 299, guard 27, bk 82, budget 87, window 16, release v0.30.0. Pushed e4acc04 (merge, no force) to PR #76.
