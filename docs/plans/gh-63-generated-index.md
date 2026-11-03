---
ticket: "#63"
title: Generate the INDEX.md tables of plans, journals and checklists from frontmatter, so concurrent tickets stop conflicting
status: done
approved: 2026-11-03
lane: B
created: 2026-11-03
open_questions: none
migration: false
files:
  - plugins/bk/skills/kitchen/kitchen.sh
  - plugins/bk/skills/kitchen/SKILL.md
  - plugins/bk/skills/README.md
  - plugins/bk/skills/create-plan/SKILL.md
  - plugins/bk/skills/implement/SKILL.md
  - plugins/bk/skills/review-task/SKILL.md
  - plugins/bk/skills/handoff/SKILL.md
  - plugins/bk/skills/line-cook/SKILL.md
  - plugins/bk/skills/open-pr/SKILL.md
  - plugins/bk/skills/setup/SKILL.md
  - plugins/bk/templates/SCHEMA.md
  - plugins/bk/templates/checklist.md
  - tests/kitchen.test.sh
  - plugins/bk/.claude-plugin/plugin.json
  - Formula/bk.rb
  - CHANGELOG.md
  - docs/plans/INDEX.md
  - docs/plans/gh-63-generated-index.md
  - docs/journal/INDEX.md
  - docs/journal/63-generated-index.md
  - docs/checklists/INDEX.md
  - docs/checklists/gh-63-generated-index.md
---

# #63 — Generate the INDEX.md tables of plans, journals and checklists from frontmatter

## Contents

- [Why](#why)
- [Current state](#current-state)
- [Desired end state](#desired-end-state)
- [Decisions](#decisions)
- [Protected paths](#protected-paths)
- [Not doing](#not-doing)
- [Approach](#approach)
- [Phase 1: The command and its tests](#phase-1-the-command-and-its-tests)
- [Phase 2: The contract and the templates](#phase-2-the-contract-and-the-templates)
- [Phase 3: The skills](#phase-3-the-skills)
- [Phase 4: This repo adopts it, and the release](#phase-4-this-repo-adopts-it-and-the-release)
- [Testing](#testing)
- [Risks](#risks)
- [References](#references)

## Why

Every ticket adds one row to `docs/plans/INDEX.md`, `docs/journal/INDEX.md` and
`docs/checklists/INDEX.md`, at the same place in the same file. Two tickets cooked at the
same time therefore conflict when the second merges, by construction: PR #52 needed five
rounds of "merge main, re-run the gate, push, sous re-verify" and PR #53 three, and the
sous's decision 001 ("kitchen PRs merge first") is a human workaround. The rows hold nothing
the files' own frontmatter doesn't, so a script can write them.

## Current state

- **No command writes an INDEX.** `kitchen.sh` has no `index` command
  (`plugins/bk/skills/kitchen/kitchen.sh:1567-1573`, the dispatcher). The contract says the
  opposite: "Every docs folder has an `INDEX.md` with one row per file; the skill that writes
  a file adds its row" (`plugins/bk/skills/README.md:289-290`, mirrored in
  `plugins/bk/templates/SCHEMA.md:26`).
- **Seven places type a row by hand** for these three folders: `create-plan/SKILL.md:136`,
  `review-task/SKILL.md:56` (and `:99`), `handoff/SKILL.md:38`, `implement/SKILL.md:115`
  ("update its INDEX row", though the table has no status column to update),
  `open-pr/SKILL.md:66` (stages "their INDEX rows"), and `open-pr/SKILL.md:82` (a conflict
  keeps **both** rows). Others write rows into folders outside this ticket (`spec`,
  `brainstorm`, `file-tickets`, `rail`, `handoff:97,115`, `sous-chef:346,372,375`).
- **`setup` already tries to cope** with `docs/**/INDEX.md merge=union` in a consuming repo's
  `.gitattributes` (`plugins/bk/skills/setup/SKILL.md:149-159`, from 0.5.1). It only works
  for merges git runs locally, and this repo has no `.gitattributes`, so it never applied here.
- **`doctor` does not parse these files.** It reads ticket frontmatter only, from the backlog
  and a spec's sub-folder (`kitchen.sh:1366-1396`), and warns about a mapped folder with no
  INDEX (`:1412`). The ticket's "doctor already parses it" holds for tickets, not for plans,
  journals and checklists. What it does have is the awk frontmatter pattern to copy
  (`:1383-1393`) and the `find … ! -name INDEX.md | sort` shape (`:1367`, `:1085`).
- **The rows today** are `| [file](file) | summary | ticket |` under `# Plans`, `# Journals`,
  `# Checklists` (`docs/*/INDEX.md`). The summary is the plan's `title:` (plan and journal
  frontmatter both carry one; the checklist's has none: `plugins/bk/templates/checklist.md:1-5`),
  and the ticket is `ticket:`. Row order is whatever a hand or a union merge left.
- **`ROOT` is the main checkout when `kitchen.sh` runs in a station**
  (`kitchen.sh:141-153`), and `HERE` is the checkout it was run from. A cook's files are in
  `HERE`, so `index` must read and write `HERE`, while the docs paths come from the config
  at `ROOT`.
- **The commis found nothing recorded** (journal A1): no decision on generating INDEX files,
  the command, the order, or hand-written rows. Related: `merge=union` shipped in 0.5.1 with a
  reason (`CHANGELOG.md:534-535`), and `docs/questions/mechanical-enforcement.md:53` lists
  "INDEX rows" among hand edits a script could take over. Decision 001 is not on trunk and is
  about merge order, not INDEX files.
- **Precedent in the code:** `kitchen.sh board` already generates a file nobody edits
  (`README.md` Contract 3, "No hand-kept summary page"), but it is untracked, and one instance
  is not a precedent for a tracked table.

## Desired end state

1. `kitchen.sh index` rewrites the INDEX of `docs.plans`, `docs.journal` and `docs.checklists`
   in the checkout it runs in, from the files' frontmatter, one row per file, in a fixed
   order. The same files give byte-identical output on any branch.
2. `kitchen.sh index --check` writes nothing and exits 1 if one of those INDEX files would
   change. `kitchen.sh doctor` warns about the same.
3. A repo's hand-written INDEX is never overwritten unasked: `index` skips it and says how to
   adopt it (`--adopt`).
4. Contract 4 and 12 say the three tables are generated and never typed. `create-plan`,
   `review-task`, `handoff` and `implement` stop editing rows; `open-pr` runs the command
   after bringing trunk in and resolves an INDEX conflict by running it.
5. This repo's three INDEX files are generated.
6. Verify: `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh`
   is green (until #50 lands), the new test goes red when the regeneration is removed, and
   `git grep` finds no skill that still tells a cook to add a plan, journal or checklist row.

## Decisions

None of these is in the record (journal A1: `nothing`). The sous's brief asks that each be
confirmed by the head chef at sign-off.

1. **Where the table lives: committed and regenerated.** *The three INDEX files stay in git,
   and the command rebuilds them; they are never typed.* This is what the ticket asks for.
   What it does and does not buy: a conflict stops needing judgement, because the cook runs
   the command instead of hand-merging rows, so each round shrinks to "merge, run `index`,
   check, push". It does **not** stop GitHub from flagging two PRs that add adjacent rows,
   since GitHub merges the text without our command. *Alternative:* gitignore the three
   `INDEX.md` files and generate them on demand. That removes the conflict for good (no PR
   touches them) and the "stale index" problem, but a repo browsed on GitHub loses its
   index pages, every consuming repo has to `git rm --cached` its own, and
   `doctor`'s "folder has an INDEX" check changes meaning. Recommend the committed version;
   say if you want the other.
2. **The command is `kitchen.sh index [--check] [--adopt]`, not `doctor --fix`.** `doctor`
   stays read-only (it is a check you run when something looks odd, and `--fix` that
   rewrites files would surprise anyone who runs it as one), and it gains a warning when a
   generated INDEX is out of date. The command takes no folder argument: it always does the
   three folders.
3. **Scope: plans, journals and checklists only.** These are the three every cook adds a
   row to, so they are the ones that conflict. The other mapped folders (specs, backlog,
   brainstorm, research, decisions, conventions, knowledge, questions) are written one at a
   time by the sous in the main checkout, and their tables carry hand-written columns that
   frontmatter can't give (`sliced · N tickets`, `→ SNNN`, `exploring`). They stay
   hand-kept, and Contract 4 says which is which. This is narrower than the ticket's "every
   mapped folder"; adding another folder later is one line in the command's type list.
   *Alternative:* every mapped folder with a column set per type, which would rewrite the
   specs and brainstorm tables on first run.
4. **Shape and order.** Columns stay `File | Summary | Ticket`, as today. File is the path
   relative to the folder (a journal moved to `completed/` keeps its row). Summary is the
   file's `title:`, else the `title:` of the plan its `plan:` points at (a checklist), else
   its first `# ` heading, else its filename. Ticket is `ticket:` as written, else `—`. Rows
   are sorted by that path, byte order (`LC_ALL=C`), so `13-…` sorts before `gh-19-…`; it is
   the order `doctor` and `journal_files` already use. A `|` in a title is escaped. The
   checklist template gains a `title:` line so a new checklist carries its own. One visible
   change: row "#13, #26" becomes "#13" (the second id was typed by hand, and the frontmatter
   says `"#13"`).
5. **A repo's own hand-written INDEX is left alone until it opts in.** A generated file's
   second line carries `<!-- Generated by kitchen.sh index … -->`. A folder whose INDEX lacks
   that line is hand-written (or belongs to a repo with its own doc schema): `index` prints
   `hand-written, left alone`, writes nothing, exits 0, and a skill then adds the row by hand
   as it does today. `index --adopt` takes it over: it rebuilds the table from the files and
   lists any old row whose file is gone, so the cost is visible before it is committed.
   Nobody is migrated by an upgrade.
6. **A conflict in a generated INDEX is resolved by running the command**, never by keeping
   both rows or picking a side (this replaces `open-pr/SKILL.md:82` for these three; a
   hand-kept INDEX keeps the old rule). It works even when the conflict markers sit inside the
   file, because the command rewrites the whole file from the tree. `setup`'s
   `merge=union` line stays, now for the hand-kept INDEX files only.

## Protected paths

None. No file in `files:` is under `.claude/` (Contract 5), and `plugins/bk/.claude-plugin/`
is not `.claude/`.

## Not doing

- The other mapped folders' INDEX files (Decision 3).
- Putting `kitchen.sh index --check` in `scripts/check.sh`: a stale INDEX on `main` would turn
  the release gate red for a reason no cook can fix before merge. `doctor` warns instead.
- A git merge driver or a `.gitattributes` for this repo. GitHub ignores both, and the
  command already makes a local merge mechanical.
- Any change to `hooks/guard.sh`, `bin/bk`, the Window, or the budget and debrief functions
  (station-1 is on #62).
- `CLAUDE.md`/`AGENTS.md`: the layout list stays as it is.

## Approach

Add one function group to `kitchen.sh` next to `doctor`, copying `doctor`'s awk-over-frontmatter
shape and the `find … ! -name INDEX.md | sort` listing, in bash 3.2 style (the macOS CI job
pins it: no associative arrays, no `mapfile`). The file list and the render are separate from
the write, so `index`, `index --check` and `doctor` share one `index_state` that says
`missing`, `hand`, `fresh` or `stale`. Tests build throwaway repos the way the `doctor` tests
do. Contract first (Phase 2 follows the code only so that Phase 1 is green on its own and the
prose names a command that exists), then every skill, then this repo adopts it.

## Phase 1: The command and its tests

**Status:** Done

### Changes

#### `plugins/bk/skills/kitchen/kitchen.sh:1354` (edit) — new functions before `cmd_doctor`'s comment block

```bash
# ---------------------------------------------------------------------------
# index — the INDEX.md of plans, journals and checklists, generated from the files'
# frontmatter (Contract 12), so two branches that each add a file merge to the same
# table. A folder's INDEX that lacks the marker below is hand-written and left alone
# until --adopt. Runs on the checkout it is run from (a station's files), with the
# docs paths from the config at the main checkout.
# ---------------------------------------------------------------------------
INDEX_MARK='Generated by kitchen.sh index'
INDEX_TYPES="plans:Plans journal:Journals checklists:Checklists"

fm_get() {  # fm_get <file> <key> → the frontmatter value, unquoted ("" if absent)
  awk -v k="$2" '
    NR==1 { if ($0 != "---") exit; fm=1; next }
    fm && $0=="---" { exit }
    fm && index($0, k ":")==1 { v=substr($0, length(k)+2); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v=substr(v, 2, length(v)-2); print v; exit }' "$1"
}
first_heading() {  # the first "# " line outside the frontmatter
  awk 'NR==1 && $0=="---" { fm=1; next } fm && $0=="---" { fm=0; next } !fm && /^# / { sub(/^# +/, ""); print; exit }' "$1"
}
index_summary() {  # index_summary <checkout> <file>
  local t p
  t="$(fm_get "$2" title)"
  if [[ -z "$t" ]]; then p="$(fm_get "$2" plan)"; [[ -n "$p" && -f "$1/$p" ]] && t="$(fm_get "$1/$p" title)"; fi
  [[ -n "$t" ]] || t="$(first_heading "$2")"
  [[ -n "$t" ]] || t="$(basename "$2")"
  printf '%s' "${t//|/\\|}"
}
index_render() {  # index_render <checkout> <folder> <heading> → the whole INDEX.md
  local base="$1" dir="$2" rel tk
  printf '# %s\n\n<!-- %s from the files'"'"' frontmatter (Contract 12). Do not edit by hand: run `kitchen.sh index`. -->\n\n' "$3" "$INDEX_MARK"
  printf '| File | Summary | Ticket |\n|---|---|---|\n'
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    tk="$(fm_get "$base/$dir/$rel" ticket)"; [[ -n "$tk" ]] || tk="—"
    printf '| [%s](%s) | %s | %s |\n' "$rel" "$rel" "$(index_summary "$base" "$base/$dir/$rel")" "$tk"
  done < <(cd "$base/$dir" && find . -type f -name '*.md' ! -name INDEX.md | sed 's#^\./##' | LC_ALL=C sort)
}
index_state() {  # index_state <checkout> <folder> <heading> → missing | hand | fresh | stale
  local dest="$1/$2/INDEX.md"
  [[ -f "$dest" ]] || { echo missing; return 0; }
  grep -qF "$INDEX_MARK" "$dest" || { echo hand; return 0; }
  [[ "$(index_render "$1" "$2" "$3")" == "$(cat "$dest")" ]] && echo fresh || echo stale
}
cmd_index() {
  local base="$HERE" pair key heading path state stale=0 n old gone
  for pair in $INDEX_TYPES; do
    key="${pair%%:*}"; heading="${pair#*:}"
    path="$(docs_path "$key")"; path="${path%/}"
    [[ -z "$path" || "$path" == none || "$path" == *.md || ! -d "$base/$path" ]] && continue
    state="$(index_state "$base" "$path" "$heading")"
    if [[ "$state" == hand ]] && ! $ADOPT; then
      echo "  $path/INDEX.md: hand-written, left alone (kitchen.sh index --adopt makes it generated)"; continue
    fi
    if $CHECK_INDEX; then
      case "$state" in
        fresh|hand) echo "  $path/INDEX.md: up to date" ;;
        *) echo "  $path/INDEX.md: out of date"; stale=$((stale+1)) ;;
      esac
      continue
    fi
    if [[ "$state" == fresh ]]; then echo "  $path/INDEX.md: up to date"; continue; fi
    if [[ "$state" == hand ]]; then   # --adopt: say which old rows name a file that isn't there
      old="$base/$path/INDEX.md"
      while IFS= read -r gone; do
        [[ -f "$base/$path/$gone" ]] || echo "  $path/INDEX.md: dropped row for $gone (no such file)"
      done < <(grep -oE '\]\([^)]+\)' "$old" | sed 's/^](//; s/)$//' | sort -u)
    fi
    index_render "$base" "$path" "$heading" > "$base/$path/INDEX.md"
    n=$(grep -c '^| \[' "$base/$path/INDEX.md" || true)
    echo "  $path/INDEX.md: regenerated ($n row(s))"
  done
  (( stale == 0 )) || { echo "$stale INDEX file(s) out of date: run kitchen.sh index."; return 1; }
}
```

(One `grep -oE` row link per old row: `[name](name)` gives `name`; rows with an absolute or
`../` link just show as "no such file" under `--adopt`, which is the cost the flag exists
to show.)

#### `plugins/bk/skills/kitchen/kitchen.sh:218-258` (edit) — flags

Add `CHECK_INDEX=false; ADOPT=false` next to the other flag defaults (`:218-231`), and two
cases in the parse loop (before `-m|--model` at `:258`):

```bash
    --check) CHECK_INDEX=true; shift ;;
    --adopt) ADOPT=true; shift ;;
```

#### `plugins/bk/skills/kitchen/kitchen.sh` in `cmd_doctor` (edit) — warn on a stale generated index

After the `docs map` `while … done < <(docs_keys)` loop (`:1413`), before the
`if [[ -d "$ROOT/docs" ]]` block:

```bash
  local pair ikey ipath
  for pair in $INDEX_TYPES; do
    ikey="${pair%%:*}"; ipath="$(docs_path "$ikey")"; ipath="${ipath%/}"
    [[ -z "$ipath" || "$ipath" == none || "$ipath" == *.md || ! -d "$ROOT/$ipath" ]] && continue
    [[ "$(index_state "$ROOT" "$ipath" "${pair#*:}")" == stale ]] && warn "docs.$ikey: $ipath/INDEX.md is out of date (run kitchen.sh index)"
  done
```

#### `plugins/bk/skills/kitchen/kitchen.sh:1567-1573` (edit) — dispatcher and usage

Add `index) cmd_index ;;` to the `case "$CMD"` and a usage entry in the header comment
(after `doctor`, `:84-92`):

```
#   kitchen.sh index [--check] [--adopt]  the INDEX.md of plans, journals and checklists,
#                                         generated from the files' frontmatter (Contract
#                                         12), in the checkout it is run from. --check
#                                         writes nothing and exits 1 if one is out of
#                                         date. A hand-written INDEX is left alone until
#                                         --adopt takes it over
```

#### `plugins/bk/skills/kitchen/SKILL.md:40` (edit) — the command table

A row after `doctor`: `` `index [--check] [--adopt]` `` | what it generates, the three folders, that it runs in the
checkout it is run from (a cook's station), the marker, `--check`, `--adopt`, and that `doctor` warns when out of date.

#### `tests/kitchen.test.sh` (edit) — new section `index`, before the final summary (`:608-612`)

A throwaway repo from `new_repo` with `docs/plans`, `docs/journal`, `docs/checklists`:

1. a plan with `title:` and `ticket:` gives `index` a row `| [20-a.md](20-a.md) | Alpha | #1 |`
   and the marker line; a second run says `up to date` and leaves the file byte-identical.
2. a checklist without `title:` takes its plan's title (via `plan:`); a file with no
   frontmatter takes its first heading; a `|` in a title is escaped; `13-…` sorts before
   `gh-…`; a journal in `completed/` keeps its row.
3. **the ticket's case:** two branches each add a plan with adjacent names (`21-a`, `22-b`) and
   each run `index`; merging one into the other conflicts on `INDEX.md` (asserted, so the
   test is about a real conflict); after `index` the file has no `<<<<<<<`/`>>>>>>>`, both
   rows, `index --check` passes, and `git add` + `git commit --no-edit` completes the merge.
4. `--check` exits 1 and writes nothing when a plan has no row yet; `doctor` warns "out of
   date"; after `index`, both are quiet.
5. an INDEX without the marker is left alone (bytes unchanged, "hand-written, left alone");
   `--adopt` replaces it and prints `dropped row for gone.md`.
6. run from a worktree station, `index` rewrites the station's INDEX and leaves the main
   checkout's alone.
7. a repo whose config maps `plans: none` or a folder that doesn't exist is skipped without
   error.

### Success criteria

- [x] `bash -n plugins/bk/skills/kitchen/kitchen.sh` and `shellcheck -S info -f gcc plugins/bk/skills/kitchen/kitchen.sh` print nothing new
- [x] `tests/kitchen.test.sh` passes, and with `index_render`'s write removed from `cmd_index` the case-3 test fails (checked on purpose, then restored)
- [x] `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh` passes
- [x] Manual: in a scratch repo with two plan files, `kitchen.sh index` prints `regenerated (2 row(s))`, `git diff` shows the table, a second run prints `up to date`

## Phase 2: The contract and the templates

**Status:** Done

### Changes

#### `plugins/bk/skills/README.md:289-290` (edit) — Contract 4

Replace "Every docs folder has an `INDEX.md` with one row per file; the skill that writes a
file adds its row." with: every docs folder has an `INDEX.md` with one row per file. For the
plans, journals and checklists the table is generated (`kitchen.sh index`, Contract 12): the
skill that writes the file gives it `title:` and `ticket:` and runs the command, it never
types a row. For every other folder the skill that writes a file still adds its row.

#### `plugins/bk/skills/README.md` after the Four rules, before "A decision that the domain has moved past" (`:856`) (edit) — Contract 12

A paragraph, **The INDEX of plans, journals and checklists is generated.** It says: why
(every ticket adds a row at the same place, so concurrent tickets conflict by construction);
what (`kitchen.sh index` rebuilds the table from the files' frontmatter, one row per file,
sorted by path, with a marker line; same files, same bytes, on any branch); who runs it (the
skill that writes the file, and `open-pr` after bringing trunk in); what a conflict in one
is (run the command, never keep both rows or pick a side); what stays hand-kept (every other
folder, and any INDEX without the marker, until `--adopt`); and the limit (GitHub may still
flag two PRs that add adjacent rows: bring trunk in locally and run the command).

#### `plugins/bk/templates/SCHEMA.md:26` (edit) — the `index` row

Writer becomes "`kitchen.sh index` for plans, journals and checklists; the skill that adds a
file for the rest". Add `title` to the checklist row's frontmatter (`:20`), noted as what its
INDEX row shows.

#### `plugins/bk/templates/checklist.md:1-5` (edit) — frontmatter

Add `title: <one line, same as the plan's>` after `ticket:`.

### Success criteria

- [x] `scripts/check.sh` (env unset as above) passes
- [x] `git grep -n 'adds its row' -- plugins` prints nothing for the three folders

## Phase 3: The skills

**Status:** Done

### Changes

#### `plugins/bk/skills/create-plan/SKILL.md:136` (edit) — Step 6.1

"Add a row to `<docs.plans>/INDEX.md` (…); create the index if missing." becomes: run
`"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" index` (the row is the plan's `title:` and
`ticket:`); if it says the folder's INDEX is hand-written, add the row by hand as before.

#### `plugins/bk/skills/review-task/SKILL.md:56, :99` (edit)

Step 6: the checklist's frontmatter carries `ticket:`, `plan:`, `title:` and `last_verified:`;
run `kitchen.sh index` instead of writing a row. The closing "writes only the checklist, its
INDEX row" line says "and runs `kitchen.sh index`".

#### `plugins/bk/skills/handoff/SKILL.md:38` (edit) — Cook handoff step 2

"Add its row to `<docs.journal>/INDEX.md`" becomes "run `kitchen.sh index`" with the same
hand-written fallback. The sous-side lines (`:97`, `:115`) are for decisions and questions
and stay.

#### `plugins/bk/skills/line-cook/SKILL.md:139` (edit) — The journal

The cook creates the journal here, so the clause the other skills carry goes in: fill `ticket:` and `title:`, run `kitchen.sh index` for the row, same hand-written-INDEX fallback (added at the pass, sous finding 1).

#### `plugins/bk/skills/implement/SKILL.md:115` (edit) — Step 4.1

"…and update its `INDEX.md` row" is dropped: the table carries no status, so there was
nothing to update, and a generated table needs nothing from this step.

#### `plugins/bk/skills/open-pr/SKILL.md` (edit) — three places

- `:66` (staging): the INDEX files are staged as generated output, not as rows; the staging
  list says so.
- Step 3, before staging: run `kitchen.sh index`, so the PR carries the tables for the files
  it adds.
- `:82` (Step 4): replace the INDEX bullet with the rule of Decision 6. After
  `git merge origin/<trunk>`, run `kitchen.sh index` and `git add` the INDEX files it
  rewrote; a conflict whose only files are generated INDEX files is resolved by that and a
  `git commit --no-edit`; a hand-kept INDEX keeps "keep both rows".
- `:143` (the stop table): "A merge conflict outside INDEX rows" becomes "outside generated
  INDEX files".

#### `plugins/bk/skills/setup/SKILL.md:149-159, :176` (edit)

Reword the `.gitattributes` paragraph: `merge=union` is now for the INDEX files the Brigade
doesn't generate, and a conflict in a generated one is resolved by `kitchen.sh index`. Step 5
(`:176`): after creating the folders, run `kitchen.sh index` for plans, journal and
checklists instead of writing three empty tables by hand; the other folders keep their
hand-written INDEX.

### Success criteria

- [x] `scripts/check.sh` passes (frontmatter and `## Contents` checks cover each edited skill)
- [x] `git grep -n -i -E "(add|adds|update) (a |its |the )?(INDEX )?row" -- plugins/bk/skills` lists only `spec`, `brainstorm`, `file-tickets`, `rail`, `handoff` (decisions, questions) and `sous-chef`, plus the approved "if it says that INDEX is hand-written, add the row by hand" fallback lines in `create-plan`, `review-task`, `handoff`, `open-pr` and `line-cook`
- [x] A fresh read-only sub-agent given Contract 4, 12 and each edited skill lists no contradiction (the sweep, Phase 4)

## Phase 4: This repo adopts it, and the release

**Status:** Done

### Changes

#### `docs/plans/INDEX.md`, `docs/journal/INDEX.md`, `docs/checklists/INDEX.md` (edit)

`kitchen.sh index --adopt` in this station. It rebuilds each table with this ticket's rows
and the marker; "#13, #26" becomes "#13" (Decision 4).

#### `plugins/bk/.claude-plugin/plugin.json` (edit) — `version` 0.28.0 → 0.29.0

A minor: it changes how a kitchen runs. If another PR lands first, bring `main` in and bump again.

#### `Formula/bk.rb:9` (edit) — `url` to the `v0.29.0` tag.

#### `CHANGELOG.md` (edit) — new top entry, above `## [0.28.0]`

```markdown
## [0.29.0] - 2026-11-03

**The plan, journal and checklist indexes now write themselves, so two cooks stop
conflicting on them.** …(what changed for the head chef, and that a repo's own hand-written
INDEX is left alone until you run `kitchen.sh index --adopt`)…
```

#### Consistency sweep (no file change unless it finds one)

A fresh read-only sub-agent reads Contract 4 and 12, the edited skills, `PLAYBOOK.md` and
`README.md`, and lists every sentence that still says a cook types an INDEX row for the three
folders. Fix each in the files above; anything outside them goes to the sous first.

### Success criteria

- [x] `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh` passes (version 0.29.0, the changelog entry on top, the Formula tag)
- [x] `kitchen.sh index --check` prints three `up to date` lines in this repo
- [ ] Manual: `git merge` a scratch branch that added a plan row at the same place as this one; the INDEX conflicts; `kitchen.sh index` clears it with no marker left

## Testing

`tests/kitchen.test.sh` reaches `index`, `index --check`, `--adopt`, `doctor`'s warning, the
two-branch merge, and the worktree-station case, in both kitchen modes the suite already
runs. The prose changes have no automated check; the sweep covers them. Every new test is
broken on purpose before it is trusted (remove the write, the sort, the marker test, the
`HERE` base) and must go red.

## Risks

- **bash 3.2 on the macOS job.** No `mapfile`, no associative arrays, no `${var,,}`; the
  code above uses none. The `${t//|/\\|}` escape is checked in a test.
- **A summary with a trailing `#` comment or unusual quoting** in a hand-made file. The value
  is the line as written, trimmed and unquoted; not parsed as YAML.
- **GitHub still flags adjacent rows** (Decision 1). The release note and Contract 12 say so,
  so nobody expects the rounds to vanish.
- **A repo with its own schema** is untouched until `--adopt` (Decision 5).
- **Station-1 (#62)** edits `kitchen.sh`'s budget and debrief functions. This change adds
  functions before `doctor` and two lines in the flag parser and dispatcher, away from those;
  whoever merges second brings main in and re-runs the gate.

## References

- Ticket: GitHub issue #63; EPIC #71 section 2.
- Journals `docs/journal/13-merge-base-diff.md` and `docs/journal/19-claude-dir-edits.md`: the
  merge rounds this removes.
- `plugins/bk/skills/kitchen/kitchen.sh:1359-1428` (`cmd_doctor`: the frontmatter awk to copy),
  `:1080-1086` (`journal_files`), `:141-153` (`ROOT` and `HERE`).
- `plugins/bk/skills/setup/SKILL.md:149-159` (the `merge=union` paragraph), `CHANGELOG.md:534-535`.
