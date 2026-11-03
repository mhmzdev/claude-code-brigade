---
ticket: "#92"
title: the plan's files: is the ticket's write scope; kitchen.sh scope checks the diff against it and finds colliding scopes
status: active
approved: 2026-11-03
lane: B
created: 2026-11-03
open_questions: none
migration: false
files:
  - plugins/bk/skills/kitchen/kitchen.sh
  - plugins/bk/skills/README.md
  - plugins/bk/skills/create-plan/SKILL.md
  - plugins/bk/skills/implement/SKILL.md
  - plugins/bk/skills/review-task/SKILL.md
  - plugins/bk/skills/kitchen/SKILL.md
  - plugins/bk/skills/sous-chef/SKILL.md
  - plugins/bk/agents/taster.md
  - plugins/bk/templates/plan.md
  - plugins/bk/window/server/live/budget.js
  - tests/kitchen.test.sh
  - tests/budget.test.sh
  - changelog.d/92-write-scope.md
  - .claude/brigade.md
---

# #92 — the plan's `files:` is the ticket's write scope

## Why

A plan lists the files it will touch, and the board shows files in flight per station, but nothing checks the diff
against the plan, and two plans that collide are found only when the second PR conflicts. The head chef decided
the WHAT (2026-11-03, in the issue): `files:` becomes a scope the pass enforces, and overlapping scopes don't run at once.

## Current state

- `changed_files <dir>` (`kitchen.sh:625`) is a station's diff from `origin/<trunk>` plus its working tree. `cmd_files`
  (`kitchen.sh:945`) prints it per station. Nothing reads a plan's `files:`.
- `files:` is "every path the plan touches" in the template (`templates/plan.md:9`) and the create-plan frontmatter
  (`create-plan/SKILL.md:99`); Contract 4 shows it with no meaning (`README.md:399`).
- The overlap rule is judgement: "Overlapping files → one cook" (`sous-chef/SKILL.md:155`), "Two tickets that touch the
  same files go to one cook" (`README.md:743`, Contract 9). Contract 8 says nothing about it.
- The taster's item 5 "Scope" lists files the plan didn't name, as a note among others (`taster.md:51`).
- `DEBRIEF_RULES` (`budget.js:453`) has no rule for it; `spans()` already counts `[findings]` that reach a cook (`budget.js:292`).
- Precedent for a read-only `kitchen.sh` report that exits 1 on a finding: `leaks` (`kitchen.sh:1362`), `index --check`
  (`:1949`), `doctor` (`:2037`). The commis found nothing recorded that says otherwise.

## Desired end state

`kitchen.sh scope [station-N]` prints `inside` / `outside` and exits 1 when anything is outside the plan's `files:`;
the taster runs it first and `review-task` before the checklist; `kitchen.sh scope --overlap` prints every collision
as ticket × station × paths; the debrief counts `scope-drift`; Contracts 4, 8, 9 and 11 say so. Verify: `scripts/check.sh` green, and each new test red with its code removed.

## Not doing

- Blocking an edit at write time (a hook): the pass enforces, as the ticket says. The open question file
  `docs/questions/mechanical-enforcement.md` row 3 stays open.
- Matching glob against glob exactly: two patterns collide when they share a concrete path (see Approach).
- Changing the head chef's always-inside list (plan, journal, checklist, changelog fragment, INDEX files): only where the fragment's path is read from is different (Decisions → How).
- Changing `kitchen.sh files`, `board` or the rail's reading.

## Approach

One reader, three callers. `scope_plan_files` reads a plan's frontmatter `files:` (inline `[a, b]` or a `- path` list)
into one pattern per line. `scope_covers <path> <pattern…>` is a bash `case` match (a pattern ending `/` covers
everything under it; `*` crosses `/`). `scope_record <ticket> <path>` says whether a path is in the always-inside list.
On those:

- `cmd_scope` takes `station-N` (or the station it runs in), finds the plan whose `ticket:` matches the branch's id
  (`branch_ticket`, `kitchen.sh:1278`) in that station's `docs.plans`, splits `changed_files` into inside and outside,
  prints both, exits 1 on any outside. A `HYG-` ticket has no plan, so it is skipped with a line saying so; any other
  ticket with no plan found exits 1 (the pass can't check it).
- `scope --overlap` collects **parties**: every station on a ticket (scope = its plan's `files:` expanded, **plus** the files it has
  changed so far, so a plan written but not yet built and a build in progress both count; stage `planned` when it has changed
  nothing outside the record files, else `building`) and the **candidates**: the `--ticket` ids, else every ready ticket of a markdown rail
  (`cmd_rail`'s RDY column). A candidate's scope is its plan at `origin/<trunk>`, else the ticket's own `files:`;
  with neither it is listed as "no scope known". Each scope is expanded to concrete paths (literals as written, globs against
  `git ls-tree -r origin/<trunk>` plus the station's changed files), the always-inside files left out, and each pair
  of parties that are not both candidates is intersected with `comm` (so every station's plan is compared with every other
  station's plan and in-flight diff). Output is one block per collision: `ticket (station, stage) × ticket (station, stage)`,
  then the paths; a candidate has stage `ready`. Exit 1 when there is any.

The alternative, matching in node from `budget.js`, loses: `scope` is a station tool the taster and a cook call
directly, and `kitchen.sh` already holds `changed_files`, `branch_ticket` and the config readers.

## Decisions

### Changes the ticket

None.

### How

- **Overlap candidates read the ticket's own `files:` when no plan exists.** The ticket says "ready ticket's plan `files:`
  (when a plan exists)", but a ready ticket has no plan until a cook writes one in a station, so the comparison would
  almost always be empty. The ticket's `files:` field ("paths it will likely touch", Contract 3) is the sous's own map
  today. A github-rail ticket has none, so there `--ticket` ids with no plan are listed as "no scope known".
- **`scope` with no plan exits 1, except for `HYG-`.** Lane A/B always have a plan (Contract 4); a missing one at the pass is a finding.
- **`*` crosses `/`, and a pattern ending `/` covers a directory.** Plain bash matching, no gitignore semantics: simple and
  explicable in one line. It errs toward "inside", never toward a false finding.
- **The always-inside list is by ticket key, with the changelog fragment read from the config** (the sous's amendment, nothing
  repo-specific in the plugin). Built in: the plan itself; `<docs.journal>/<key>-*` and `<docs.checklists>/<key>-*`; `INDEX.md` in
  the folders `kitchen.sh index` writes (`INDEX_TYPES`: plans, journal, checklists). From `.claude/brigade.md`, a nested block:
  `scope:` with `always_inside: ["changelog.d/<id>-*.md"]`, a list of globs where `<id>` is the key (this repo's config adds the
  fragment; the plugin's default is the record files only). `<key>` is the id without `#`, matched case-insensitively (`92-…`,
  `BKLG-004-…`; also `gh-92-…` as create-plan's text names it). The block is read by a new `cfg_scope_always`, shaped like `cfg_gate`
  (`kitchen.sh:228`), and documented in Contract 2.
- **A station's scope is its plan's expansion plus its diff** (the sous's amendment): four cooks plan in parallel and build one at a
  time, and a plan written but not yet built is the case the sous sequences. Each side of a collision shows its stage.
- **Widened at the pass (2026-11-03): `plugins/bk/skills/kitchen/SKILL.md` joins `files:`.** The kitchen skill's command table and
  `argument-hint` list every `kitchen.sh` command (`leaks`, `procs`, `done` each have a row), so the new `scope` forms need theirs; the
  taster found it. The scope rule's first real use: widened on purpose, with this line, not by drift.
- **`scope_record` is also applied to what a glob or folder expands to, and `cfg_scope_always` reads both the inline and the block
  list form** (the sous's pass findings 1 and 2): two plans listing `docs/plans/` must not collide on the INDEX files, and a repo that
  writes `always_inside:` as a YAML block must not see a false "outside" on its fragment.
- **The flag is `--overlap`; candidate ids come through the existing `--ticket`** (comma-separated). A station is named by the
  existing `station-N` word the parser already accepts. No new positional shapes; the parser gets one line, the dispatcher
  one line, the rest are new functions (the sous asked for this to ease the queue behind #86, #85, #90).
- **`scope-drift` counts `[findings]` that reach a cook and say "outside the plan's files"** (the taster's exact wording),
  per ticket, one hit is enough to show on the board and two tickets make it due, like every rule. The budget cannot see
  the script's output, only the messages; the finding wording is therefore fixed in `taster.md` and the Contract.
- **The Contract names the rule in 4 (what `files:` means), 8 (a station's write scope, beside "A station's own changes") and 9
  (the overlap sentence now cites the tool)**, because the ticket says Contract 8 and the existing overlap sentence is in 9.
- **The overlap report never writes anything and does not fetch;** like `files` it is "as last fetched". The taster fetches
  before it runs `scope`.

## Protected paths

`.claude/brigade.md`, edited in Phase 5 (last): the `scope:` block with this repo's changelog-fragment glob. Auto mode will refuse this edit; the head chef lifts it at the station.

## Phases

### Phase 1 — `kitchen.sh scope` for a station

**Status:** Done — `scope [station-N]`, helpers, 22 tests in kitchen.test.sh

- `plugins/bk/skills/kitchen/kitchen.sh` (edit): add `--overlap` to the parser (beside `--adopt`, `:345`); add the `scope`
  entry to the dispatcher (`:2434`); document both in the usage header (after `leaks`, `:70`); new functions after `cmd_files`
  (`:960`): `scope_plan_files`, `scope_plan_of`, `scope_covers`, `scope_record`, `cmd_scope`.
- `tests/kitchen.test.sh` (edit): a `scope` section after "leaks" (`:373`), run in both modes through the file's existing
  fixtures: inside/outside with an exact path and a glob and a directory pattern; the always-inside files; an inline
  `files: [a, b]` plan; a `HYG-` branch; a missing plan exits 1; exit 0 when all inside.
- Check: `tests/kitchen.test.sh` passes; each new test fails with the `cmd_scope` exit removed.

```bash
scope_plan_files() {  # a plan file's frontmatter on stdin → its files: entries, one per line
  awk '
    function emit(s) { sub(/[ \t]+#.*$/, "", s); gsub(/^[ \t`"\047]+|[ \t`"\047]+$/, "", s); sub(/[ \t]+\(.*\)$/, "", s)
                       if (s != "" && s !~ /^</) print s }
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    /^files:/ { v = $0; sub(/^files:[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v)
                if (v ~ /^\[/) { gsub(/^\[|\]$/, "", v); n = split(v, a, ","); for (i = 1; i <= n; i++) emit(a[i]); inl = 1 }
                else inl = 0
                list = 1; next }
    list && /^[ \t]*-[ \t]/ { l = $0; sub(/^[ \t]*-[ \t]+/, "", l); emit(l); next }
    list && /^[^ \t-]/ { list = 0 }'
}
scope_covers() {  # scope_covers <path> <pattern…> → 0 when a pattern covers the path
  local p="$1" pat; shift
  for pat in "$@"; do
    case "$pat" in */) [[ "$p" == "$pat"* ]] && return 0 ;; *) [[ "$p" == $pat ]] && return 0 ;; esac
  done
  return 1
}
```

`scope_record <id> <path>` lowercases the key (`#92` → `92` and `gh-92`; `BKLG-004` → `bklg-004`) and returns 0 when the path is
`<plans|journal|checklists>/INDEX.md`, `<journal|checklists|plans>/<key>-*`, or matches a glob from `cfg_scope_always` with `<id>` replaced by the key.
`cfg_scope_always` (new, beside `cfg_gate`) prints the `scope: → always_inside:` globs of `.claude/brigade.md`, one per line, `[ ]` and quotes stripped.
`scope_plan_of <ticket> <dir>` echoes the path of the first `<dir>/<docs.plans>/*.md` (not INDEX) whose `ticket:` (quotes stripped) equals the id.
`cmd_scope` (station path: `$KITCHEN/<station>`, else `HERE` when `rail_actor` says it is in one) prints:

```
Scope of station-4 (#92), plan docs/plans/92-write-scope.md, 12 pattern(s) in files:
inside (14):
  plugins/bk/skills/kitchen/kitchen.sh
  docs/journal/92-write-scope.md  (record)
outside (1):
  scripts/check.sh
1 path(s) outside the plan's files: add each to the plan's files: with a line of why in Decisions → How, or revert it.
```

### Phase 2 — `kitchen.sh scope --overlap`

**Status:** Done — `scope --overlap`, 15 tests

- `plugins/bk/skills/kitchen/kitchen.sh` (edit): new functions after `cmd_scope`: `scope_expand <patterns-file> <id> <extra-files>`
  (literals as written; globs against `git -C "$ROOT" ls-tree -r --name-only "origin/$TRUNK"` ∪ the party's changed files; drops
  `scope_record` files), `scope_candidates` (the `--ticket` ids, else `cmd_rail` rows whose 5th column is `yes` when the adapter is
  markdown or absent), `scope_overlap` (collect parties, write each expansion to a temp file, `sort -u`, `comm -12` per pair, print).
- `tests/kitchen.test.sh` (edit): two stations whose plans share a file and a glob, neither built: one collision block naming both with stage `planned`, exit 1, the
  shared path listed once; a plan against another station's diff: `planned` × `building`; `always_inside` from a throwaway config keeps a fragment inside, and without the key it is outside; a candidate ticket's `files:` against a station's plan; two disjoint plans: "No collisions", exit 0; a
  candidate with no plan and no `files:` listed under "no scope known"; a station with no plan falls back to its changed files (`diff`).
- Check: `tests/kitchen.test.sh` passes; the collision tests go red with the `comm` line removed.

```
Scope collisions (vs origin/main as last fetched):
  #96 (ready) × #90 (station-2, building)   2 path(s)
      plugins/bk/skills/kitchen/kitchen.sh
      tests/kitchen.test.sh
  #86 (station-1, building) × #92 (station-4, planned)   1 path(s)
      plugins/bk/window/server/live/budget.js
No scope known (no plan, no files:): #97
Two scopes that collide do not run at once: the second waits for the first to merge, or goes to the same cook (Contract 8).
```

### Phase 3 — the debrief's `scope-drift`

**Status:** Done — `scope-drift` in budget.js, 2 tests in budget.test.sh

- `plugins/bk/window/server/live/budget.js` (edit): in `spans()` beside `findingsAfterServed` (`:292`) add
  `if (m.kind === 'findings' && m.dir === 'in' && /outside the plan'?s files/i.test(m.text || '')) cur.scopeDrift = (cur.scopeDrift || 0) + 1;`;
  carry it through the merge of two spans of one ticket (`:317`, `scopeDrift: (x.scopeDrift || 0) + (y.scopeDrift || 0)`); add the
  rule to `DEBRIEF_RULES` after `ship-rounds` (`:475`):
  `{ key: 'scope-drift', scope: 'repo', unit: 'ticket', about: 'a ticket\'s diff at the pass was outside its plan\'s files:', fix: 'a plan whose files: is honest, and a smaller ticket', test: (t) => t.scopeDrift ? \`${t.scopeDrift} pass finding${t.scopeDrift > 1 ? 's' : ''} outside the plan's files\` : null }`.
- `tests/budget.test.sh` (edit): one ticket's cook transcript gets a `peer(…, '[findings] … outside the plan\'s files: x')` line (the helper at
  `:438`); expect the finding with its evidence in the debrief, a ticket without it unflagged, and update the `--json carries the same findings` key list (`:350`).
- Check: `tests/budget.test.sh` passes; red with the rule removed.

### Phase 4 — the pass, the plan and the sous read the script

**Status:** Done — taster, sous-chef, review-task, create-plan, implement, plan template

- `plugins/bk/agents/taster.md` (edit): new Input `Scope check`, and a first step "Scope": run it; every `outside` path is a numbered
  finding, worded `outside the plan's files: <path>; add it to the plan with why, or revert`; no plan found is a finding too;
  replace item 5's "Files changed that the plan didn't name" (`:51`) with a pointer to it; add `kitchen.sh scope` to the Bash allowance sentence.
- `plugins/bk/skills/sous-chef/SKILL.md` (edit): the taster's prompt (`:460`) gains `Scope check: <abs path of kitchen.sh> scope <station-N>.`;
  "Overlapping files → one cook" (`:155`) says run `kitchen.sh scope --overlap` (ticket × station × paths) instead of eyeballing the board;
  the plan sign-off check (`:291`) and the pass look-across (`:475`) use it too.
- `plugins/bk/skills/review-task/SKILL.md` (edit): a new step 2 "Scope": run `kitchen.sh scope`; the checklist gets a Scope line, an `[x]`
  when none is outside, one `[!]` per outside path ("widen the plan's `files:` with why, or revert"); renumber the steps and the Contents list.
- `plugins/bk/skills/create-plan/SKILL.md` (edit): at the frontmatter example (`:99`) and "Done only when" (`:136`): `files:` is the
  ticket's write scope, which the pass enforces; a cook widens it on purpose (an edit to `files:` plus a line of why under Decisions → How), not by drift.
- `plugins/bk/skills/implement/SKILL.md` (edit): at step 4 (`:82`), a file outside `files:` is a plan edit first (widen `files:`, one How line), then the change.
- `plugins/bk/templates/plan.md` (edit): the `files:` comment (`:10`) says it is the write scope the pass enforces.
- Check: `scripts/check.sh` passes (frontmatter, Contents lists).

### Phase 5 — the contract, the changelog, and this repo's config

**Status:** Done — Contracts 2, 4, 8, 9, 11, changelog fragment, `.claude/brigade.md` (not refused)

- `plugins/bk/skills/README.md` (edit): Contract 4 (`:391`–`:402`, beside the plan frontmatter) a paragraph: `files:` is the write scope, always-inside list,
  widened on purpose; Contract 8, "Both modes" (`:704`), a paragraph "A station's write scope" with the command and its two forms; Contract 9
  (`:743`) the sentence cites `kitchen.sh scope --overlap`; Contract 11's debrief list (`:855`) gains `scope-drift`.
- `plugins/bk/skills/README.md` Contract 2 (edit, `:49`–`:196`): the `scope:` block (`always_inside`) beside `gates:`.
- `.claude/brigade.md` (edit, **protected path**, last): add `scope:` with `always_inside: ["changelog.d/<id>-*.md"]`. Auto mode refuses it; the head chef lifts it at this station.
- `changelog.d/92-write-scope.md` (new): `level: minor`, then the paragraph for the busy human.
- Run `kitchen.sh index` for the plan, journal rows.
- Check: `grep -rn "files: \[\]\|Overlapping files" plugins` shows no skill that still says the old thing; `scripts/check.sh` passes.

## Success criteria

- [ ] `kitchen.sh scope station-N` prints inside/outside, honours exact paths, globs and directory patterns, treats the journal, checklist, plan, changelog fragment and INDEX files as inside, and exits 1 only when something is outside (tests/kitchen.test.sh, clone and worktree).
- [ ] `kitchen.sh scope --overlap` prints `ticket × station` with the colliding paths, exits 1 on a collision, 0 on none (tests/kitchen.test.sh).
- [ ] The debrief reports `scope-drift` for a ticket whose cook was sent `[findings]` that say "outside the plan's files" (tests/budget.test.sh).
- [ ] taster.md runs the scope check first and words the finding; review-task.md lists the result; create-plan.md says `files:` is an enforced scope; sous-chef.md uses `--overlap` (read, `grep -n "scope" ` on each).
- [ ] Contracts 2, 4, 8, 9 and 11 name the rule (read); this repo's `.claude/brigade.md` carries the changelog glob and `kitchen.sh scope` on this branch's diff reports no `outside`.
- [ ] Each new test fails with its code removed (done by hand, recorded in the checklist).
- [ ] `scripts/check.sh` passes.

## Risks

- `kitchen.sh`, `tests/kitchen.test.sh`, `budget.js` and the skills are also edited by #86, #85 and #90 → this plan starts after they merge; the new code is new functions and one parser line, one dispatcher line, so a merge conflict can only be in those two lines and the usage header; re-check every `file:line` here after bringing main in.
- `*` crossing `/` hides a cook that widens into a sibling folder under a broad pattern → the plan author chooses the pattern; the report lists what was matched only as inside. Accepted: errs toward no false finding.
- The pass trusts a plan's `files:` is honest; a plan that lists `plugins/` covers everything → the `scope-drift` rule can't see it. Accepted for now: the sous reads the plan at sign-off.
- Glob-vs-glob that share no existing file is not a collision (a future file under both) → rare; documented in the Contract.
- The budget sees the finding wording only → `taster.md` fixes the words, and the Contract names them.

## References

- Issue #92 (GitHub), PROOF pack `write_scope` (quoted in the issue); head chef 2026-11-03: "Lets do it then."
- `kitchen.sh:625` `changed_files`, `:945` `cmd_files`, `:1278` `branch_ticket`, `:1362` `cmd_leaks`; `budget.js:453` `DEBRIEF_RULES`;
  `taster.md`; `README.md:743` (Contract 9 overlap), `:391` (Contract 4 plan); `sous-chef/SKILL.md:155`; precedent plan `docs/plans/65-routine-kinds-script.md` (two debrief rules added the same way).
