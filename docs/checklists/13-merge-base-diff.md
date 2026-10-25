---
ticket: "#13"
plan: docs/plans/13-merge-base-diff.md
last_verified: 2026-10-25
---

# Acceptance — #13 Diff a station against its merge base with trunk, not the trunk tip

Also closes #26 (same defect).

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

### A cook reviews its own work after another station's PR merged

1. Trunk moves past the branch's base (another PR merges) → `git merge-base HEAD origin/<trunk>` still returns the branch's fork point.
2. `/bk:clean check` / `/bk:review-task` / the taster diff from that base → the diff holds the branch's own committed, staged, unstaged and untracked work, and nothing from the newer trunk commits.
3. The inspector and taster read only the branch's own files → no review of code the branch never touched.

## Edge cases

- Nothing committed yet (before the sous's `[go]`) → `git diff "$BASE"` compares the base to the working tree, so it still shows the work; the three-dot form would read empty.
- Everything committed (after `[go]`, at `clean around`) → same command, same file set.
- The taster runs outside the station → it resolves the base with `git -C <station> merge-base HEAD <trunk>`.

## Acceptance criteria

- [x] Contract 8 states the rule once, with the command and both reasons — `plugins/bk/skills/README.md:629-635` (the "A station's own changes" paragraph in "Both modes")
- [x] `clean around` lists files and added ranges from the merge base — `plugins/bk/skills/clean/SKILL.md:52-55`
- [x] `clean check` builds `$DIFF` and `$FILES` from the merge base — `plugins/bk/skills/clean/SKILL.md:121-128`
- [x] `review-task` step 1 reads the diff from the merge base — `plugins/bk/skills/review-task/SKILL.md:44-51`
- [x] The taster diffs from the merge base and its description says so — `plugins/bk/agents/taster.md:3`, `:27-35`
- [x] No skill or agent still diffs against the trunk tip — `git grep -n -E 'git diff[^|]*origin/<trunk>|git diff <trunk>|two-dot' -- plugins PLAYBOOK.md README.md` prints only the contract's explanatory text (`README.md:632`) and `implement/SKILL.md:57` (three-dot plus `status`, already right)
- [x] The merge-base form excludes trunk's newer commits and keeps every kind of own work — throwaway repo run (`scratchpad/proof.sh`): the tip diff lists `other.txt`; the merge-base diff plus untracked lists exactly `own.txt`, `staged.txt`, `base.txt` (unstaged) and `untracked.txt`; the same after committing everything
- [x] The `clean check` block works verbatim — the same run of its `BASE`/`DIFF`/`FILES` lines: `$FILES` holds only the branch's files and `$DIFF` has no `other.txt`; run for real on this branch (`origin/main` is past its base after #48): 10 own files, none of #48's
- [x] The inspector found nothing on this diff — `/bk:clean check`, "No findings"
- [x] Version, changelog and formula agree — `plugin.json` 0.27.5, `CHANGELOG.md` top entry `## [0.27.5]`, `Formula/bk.rb:9` `v0.27.5`; the gate's release step is green. (0.27.4 is taken by #48, already on `origin/main`)
- [x] `scripts/check.sh` is green — `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh` exits 0: kitchen 270/270, guard 27/27, bk 79/79, budget 70/70, manifests, shellcheck, frontmatter, release v0.27.5. Run that way because a session opened by `bk` carries those variables and 7 kitchen tests (59, 60, 107, 109, 115, 116, 123) fail without it, on an untouched `origin/main` too; filed as #50, not part of #13
- [?] The new skills load in live sessions — runtime: after merge, update the plugin and restart the sessions (the installed copy still shows the two-dot block); expect `/bk:clean check` to build `BASE`

## Known limitations

- No automated test: the change is skill and agent prose, and no runner covers it. The proof is the throwaway-repo script plus the read above.
- `kitchen.sh` is not touched: `changed_files` (`kitchen.sh:536`) already measures from the merge base, and `leaks`/`status` use commit ranges, which were right.
- `sous-chef/SKILL.md` is not touched (station-2 owns it for #19). It only passes `Trunk: origin/<trunk>` to the taster, and the taster builds its own diff.
- `CHANGELOG.md`, `plugin.json` and `Formula/bk.rb` will conflict with `origin/main`'s 0.27.4 changes when `open-pr` brings trunk in; resolve keeping both entries (0.27.5 on top).
