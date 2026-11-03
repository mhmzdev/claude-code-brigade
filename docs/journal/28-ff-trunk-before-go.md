---
ticket: "#28"
title: "line-cook / open-pr: bringing trunk in before [go] needs a fast-forward, not a merge commit"
station: station-2
created: 2026-11-03
---

# #28 — bringing trunk in before [go]: journal

The story of one ticket, written only by the cook that holds it (Contract 11). Append-only.
It reaches trunk with the PR, next to the plan and checklist.

## Log

- 2026-11-03 18:19 · claude-code-brigade-cook-2 · brief from sous (claude-code-brigade-4d): #28, plan now, no /bk:implement until the sous says it's my turn (#92 building; #91, #89 queued, same skills)
- 2026-11-03 18:19 · claude-code-brigade-cook-2 · claimed #28 → todo; branch issue-28-ff-trunk-before-go off origin/main 41979fd
- 2026-11-03 18:19 · claude-code-brigade-cook-2 · staleness (origin/main 41979fd): open-pr step 4 (L74-80) merges trunk only after step 3's commit, so it is never the no-commit case; the pass (sous-chef L479-494) and taster diff from the merge base, so nothing there needs trunk in before [go]; sous-chef L498 says "includes current trunk" only after [served]. Nothing tells a cook what to do if trunk must come in before [go]. #68 and #91 both cite this gap
- 2026-11-03 18:20 · claude-code-brigade-cook-2 · Q1: before [go] with nothing committed, may the sous ask for trunk in, and how does the cook do it? — options: a) nobody asks, open-pr owns it / b) ff-only recipe in the skills — recommend: both, a as the default and b for the case it is asked
- 2026-11-03 18:20 · claude-code-brigade-cook-2 · A1 (commis): settled. Before [go] trunk comes in only as `git merge --ff-only origin/<trunk>` while the branch has no commits of its own; a plain merge/pull/rebase counts as a commit by another route and needs the `commit` grant; open-pr step 4 owns the real merge at ship time. Per the sous's amendment in station-1 docs/plans/91-positive-authorization.md:149-155 (2026-11-03; #91 not on trunk yet) and journal 91:19. Practice seen in journals 66:37, 65:33 (dirty tree: ff-only can refuse; 65 parked the diff and re-applied 3-way). #68: no record
- 2026-11-03 18:22 · claude-code-brigade-cook-2 · decision: prose only. Contract 8 paragraph "Trunk moves while nothing is committed" (rule, stash + ff-only recipe tried in a throwaway repo, two traps), three pointers (line-cook, sous-chef pass, open-pr step 4); no guard or script change (#91 owns the guard); stash recipe, not the issue's save-diff one (copied into the plan)
- 2026-11-03 18:22 · claude-code-brigade-cook-2 · plan written docs/plans/28-ff-trunk-before-go.md, sent [plan]; implement waits for [approved] and the sous's "your turn"
- 2026-11-03 18:22 · claude-code-brigade-cook-2 · approved (sous): per gates.plan_approval.bug. HOLD: my turn comes after #91 (same line-cook and sous-chef lines; makes a non-ff merge need a grant) and #89. Then bring main in and fit my sentences to #91's wording. Use the exact commands tried in the throwaway repo
- 2026-11-03 18:22 · claude-code-brigade-cook-2 · throwaway run (while planning): origin repo with trunk commits A, B; clone on branch feat with no commits and uncommitted edits to f, idx (generated) and an untracked file "added" that B also adds. `git fetch -q origin; git merge --ff-only origin/main` → refused ("local changes … would be overwritten": f, idx; "untracked … would be overwritten": added). Recipe: `git stash push -u -m "station-2: trunk" -q`; `SHA=$(git stash list --format='%H %gs' | grep 'station-2: trunk' | cut -d' ' -f1)`; `git merge --ff-only origin/main` → fast-forwarded, 3 files; `git stash apply "$SHA"` → f merged ("M "), idx conflicted ("UU"), added: trunk's copy kept, mine only in the stash (checked: cat added = "new"). Entry stays in `git stash list` until dropped. Recipe holds; traps as in the plan
- 2026-11-03 21:45 · claude-code-brigade-cook-2 · [heard] your turn (sous): #89 merged, main 7129073 brought in by stash + ff-only (plain ff-only refused on the two INDEX files; stash applied clean, entry dropped); ticket → in-progress; implement started under the sous's [approved]. #91's wording read: non-ff merge/pull is a commit and needs the grant; --ff-only passes the guard (guard.sh:133-135)
- 2026-11-03 21:46 · claude-code-brigade-cook-2 · clean check (inspector): 2 low-confidence findings, none fixed on purpose. (1) plan is long for prose and its pasted wording drifted from what landed: added a note to the plan that the files are the record. (2) line-cook says the ff-only rule twice (a how-to paragraph and the never-list bullet): kept, one is what to do and one what not to do; the pointers were asked for by the plan. Dead-code: none
- 2026-11-03 21:48 · claude-code-brigade-cook-2 · consistency read (fresh read-only sub-agent): no step, agent, template or contract tells a cook to merge/pull/rebase trunk before [go]; guard.sh:120-141 lets `merge --ff-only` and `pull --ff-only` through and has no stash arm (`stash push -u`, `apply`, `drop` pass), tests/guard.test.sh:201-202,222-226 cover them; Contract refs resolve. Fixed in my lines: "the only form" now names `git pull --ff-only` too (README, sous-chef pass); the line-cook never-list's bare "merge" now says `gh pr merge`
- 2026-11-03 21:48 · claude-code-brigade-cook-2 · follow-ups seen, pre-existing, not mine to fix here: (a) stash wording differs across line-cook:81/85-87, README Contract 8 stash rule, setup:219 (`push -m`, apply `stash@{N}`) vs open-pr:165 ("a stash without -u" is a never) vs the new recipe (`-u`, sha); (b) open-pr:53 uses a bare `git stash pop`, against the shared-stash rule; (c) README hooks section (~1103) doesn't mention the --ff-only exemption that guard.sh:15 states
- 2026-11-03 21:48 · claude-code-brigade-cook-2 · handoff for the pass: station-2, branch issue-28-ff-trunk-before-go (nothing committed, main 7129073 brought in); files: plugins/bk/skills/{README,line-cook/SKILL,sous-chef/SKILL,open-pr/SKILL}.md, changelog.d/28-ff-trunk-before-go.md, plan, journal, checklist + INDEXes; scope 9 inside / 0 outside; inspector: 2 low findings kept (journaled); consistency read: clean, 2 wording fixes made; checklist docs/checklists/28-ff-trunk-before-go.md 9 [x] / 0 [?] / 0 [!]; kitchen.sh check is my last act
- 2026-11-03 21:55 · claude-code-brigade-cook-2 · go (sous), with the grant (`grant --show`: station-2: commit push open-pr); receipt green for tree dd14525 per the sous

## Clean around

Files my branch touched outside docs/: plugins/bk/skills/{README,line-cook/SKILL,sous-chef/SKILL,open-pr/SKILL}.md. Counters at origin/main 7129073: shellcheck-info has no finding in them (they are not shell files; 9 findings elsewhere, none touched); todo-comments: one hit, README.md:101, which is the example counter command's own text ("git grep -n -E 'TODO|FIXME'"), not a TODO. Nothing in lines my branch added. The sous asked for the three pre-existing items from the consistency read, drafted below (prose, not counter findings). No edits made.

### Draft HYG-a — one stash rule across the skills
- Why: three wordings of the same rule. A cook parks work with `git stash push -m "<station>: …"` and applies by `stash@{N}` (line-cook/SKILL.md:81,85-87; README.md:732-734 Contract 8; setup/SKILL.md:219), the recipe in Contract 8 uses `-u` and the sha (README.md:782-786), and open-pr/SKILL.md:165 lists "a stash without `-u`" among the never-dos. One rule means one set of words.
- Done when: [ ] all four places say the same thing about `-u`, the name and how to apply (by sha or by entry found through the name); [ ] `grep -n 'git stash' plugins/bk/skills/**/*.md plugins/bk/skills/README.md` shows no two that disagree; [ ] `scripts/check.sh` passes. files: line-cook/SKILL.md, setup/SKILL.md, open-pr/SKILL.md, README.md
### Draft HYG-b — open-pr's rescue path uses a bare stash pop
- Why: open-pr/SKILL.md:53 ends the dirty-tree rescue with `git stash pop`, against the shared-stash rule (README.md:733-734: never a bare pop).
- Done when: [ ] open-pr/SKILL.md:53 applies its own entry by name or sha and drops it, as Contract 8's recipe does; [ ] `scripts/check.sh` passes. files: open-pr/SKILL.md
### Draft HYG-c — the hooks section says nothing about the --ff-only exemption
- Why: README.md:1104 says the guard refuses "the commands that make a commit"; hooks/guard.sh:15 and :133-135 let `merge` and `pull` through with `--ff-only` and `--abort`/`--quit`, and tests/guard.test.sh:201-202,222-223 pin it.
- Done when: [ ] the hooks paragraph names the exemption; [ ] `scripts/check.sh` passes. files: README.md
(a and b touch open-pr/SKILL.md and a touches README.md: the sous may want one ticket, or a and b together.)

## Handoff — 2026-11-03 21:55 · claude-code-brigade-cook-2

- **Stage:** passed ([go] with the grant: commit push open-pr); about to run /bk:open-pr. No PR yet
- **Uncommitted:** everything: README.md, line-cook, sous-chef and open-pr SKILL.md; changelog.d/28-ff-trunk-before-go.md; the plan, journal and checklist and the three INDEX.md files
- **Next step:** /bk:open-pr (commit with `git commit -F <file>`, bring main in; if the tree moves, ask the sous for the slot, re-check, push), then `[served] #28 <url>`
- **Pending:** none. The sous got `[rail] fire HYG ×3` for the drafts under "Clean around"
- **Follow-ups:** the three HYG drafts above (stash wording, open-pr:53 bare pop, hooks paragraph and the ff-only exemption), sent
- **Processes:** none
- 2026-11-03 21:55 · claude-code-brigade-cook-2 · cost: $3.38 · 7.2M tokens (in 140, out 39k, cache read 6.9M, cache write 197k) · brief→PR 3h 38m (plan 4m, wait 13s, build 3h 32m, pass 26s) · helpers: commis 1 ($0.37), inspector 1 ($0.10), Explore 1 ($0.36) · asks: none
