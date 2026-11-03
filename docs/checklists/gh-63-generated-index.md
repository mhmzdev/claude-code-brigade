---
ticket: "#63"
title: Generate the INDEX.md tables of plans, journals and checklists from frontmatter, so concurrent tickets stop conflicting
plan: docs/plans/gh-63-generated-index.md
last_verified: 2026-11-03
---

# Acceptance — #63 Generate the INDEX.md tables of plans, journals and checklists from frontmatter

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

1. A cook adds a plan, runs `kitchen.sh index` → the plan's row appears in `docs/plans/INDEX.md` with its title and ticket.
2. Two branches each add a plan and a row; one merges into the other → `INDEX.md` conflicts; `kitchen.sh index` rewrites it → one table, both rows, no markers; `git commit --no-edit` completes the merge.
3. `open-pr` brings trunk in, runs `kitchen.sh index`, stages the rewritten INDEX files.

## Edge cases

- A repo's hand-written INDEX (no marker) → `index` says "hand-written, left alone" and writes nothing; `--adopt` takes it over and names any row whose file is gone.
- A checklist with no `title:` → its row takes the linked plan's title; a file with no frontmatter → its first heading.
- A `|` in a title → escaped, the table stays intact.
- `index` run in a worktree station → writes the station's files, not the main checkout's.
- A folder the map sets to `none` → skipped without error.

## Acceptance criteria

- [x] `kitchen.sh index` regenerates the plans, journal and checklists INDEX from frontmatter, in byte order of the path — tests 238–247 (`tests/kitchen.test.sh:637`), `kitchen.sh:1406` (`cmd_index`)
- [x] The same files give the same bytes: a second run says "up to date" and leaves the file untouched — tests 242–243
- [x] The ticket's merge case: two branches each add a plan, merge → conflict (asserted), then `index` yields one table with both rows and no markers, and the merge completes — tests 248–252; broke the write on purpose (`index_render … > /dev/null`) and the tests went red
- [x] Each new test goes red when its behaviour is removed — seven deliberate breaks (write, sort, pipe escape, `ROOT` for `HERE`, marker check, doctor warning, plan-title fallback), each failing its own tests (journal, 2026-11-03)
- [x] `--check` writes nothing and exits 1 when an INDEX is out of date; `doctor` warns about the same — tests 253–258, `kitchen.sh:1508`
- [x] A hand-written INDEX is left alone byte for byte; `--adopt` takes it over and lists dropped rows — tests 259–263
- [x] In a station, `index` writes the station's INDEX and not the main checkout's — tests 264–265, `kitchen.sh:1407` (`base="$HERE"`)
- [x] A folder mapped to `none` is skipped — test 266
- [x] `create-plan`, `review-task`, `handoff` and `line-cook` (which creates the journal) call `kitchen.sh index` instead of typing a row — `create-plan/SKILL.md:137`, `review-task/SKILL.md:56`, `handoff/SKILL.md:38`, `line-cook/SKILL.md:139-143`; `implement` no longer touches a row (`implement/SKILL.md:116`)
- [x] `open-pr` runs it before committing and after bringing trunk in, and clears a generated-INDEX conflict with it — `open-pr/SKILL.md:66`, `:84`
- [x] Contract 4 and Contract 12 say the three INDEX files are generated and never typed — `plugins/bk/skills/README.md:289`, `:882`; SCHEMA and the checklist template carry the same (`templates/SCHEMA.md:26`, `templates/checklist.md:3`)
- [x] No skill still tells a cook to type a row for these three folders — fresh read-only sweep (journal), every remaining "add the row" is for a hand-kept folder
- [x] This repo's three INDEX files are generated and current — `kitchen.sh index --check` prints three "up to date" lines (run 2026-11-03)
- [x] Version 0.29.0 in `plugin.json`, the Formula tag and the top CHANGELOG entry — `CHANGELOG.md:15`; release check in the gate
- [x] `scripts/check.sh` (env unset: `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE`) is green on the final tree — rc 0: kitchen 299, guard 27, bk 82, budget 71, window 16, release v0.29.0 (run after the last wording fixes, 2026-11-03)
- [?] A cook runs `/bk:open-pr` on a real branch whose INDEX conflicts with main — step 4 follows `open-pr/SKILL.md:84`: `git merge origin/main`, `kitchen.sh index`, `git add docs/*/INDEX.md`, `git commit --no-edit`; expect no marker left and `kitchen.sh index --check` quiet
- [?] After the first merge to main that adds two plans on two PRs, GitHub still flags adjacent rows (known limitation) and merging main locally, running `kitchen.sh index` and pushing clears it

## Known limitations

- GitHub can still report a conflict when two PRs add adjacent rows, because it merges the text without our command. The fix is the same and mechanical (Decision 1, Contract 12).
- Only plans, journals and checklists are generated; the other folders' INDEX files stay hand-kept (Decision 3).
- The row "#13, #26" is now "#13": the second id lived only in the hand-typed row (Decision 4).
