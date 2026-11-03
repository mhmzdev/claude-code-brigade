---
ticket: "#90"
title: gate receipts: every check run writes a receipt naming the tree, the command and its exit; the pass trusts the receipt
status: done
approved: 2026-11-03
lane: B
created: 2026-11-03
open_questions: none
migration: false
files:
  - plugins/bk/skills/kitchen/kitchen.sh
  - tests/kitchen.test.sh
  - plugins/bk/window/server/live/checklog.js
  - plugins/bk/window/server/live/budget.js
  - plugins/bk/window/server/live/index.js
  - tests/window-live.mjs
  - plugins/bk/skills/README.md
  - plugins/bk/agents/taster.md
  - plugins/bk/skills/sous-chef/SKILL.md
  - plugins/bk/skills/open-pr/SKILL.md
  - plugins/bk/skills/review-task/SKILL.md
  - plugins/bk/skills/implement/SKILL.md
  - plugins/bk/skills/line-cook/SKILL.md
  - PLAYBOOK.md
  - changelog.d/90-gate-receipts.md
---

# #90 — gate receipts

## Why

The pass trusts words. A cook says the check passed, and the taster or the sous decides from
prose. Since #66 the check log says "this tree was green", but not which command ran, under
which config, or what it printed, so nobody downstream can lean on it as proof. The head chef
wants the PROOF pack's idea: a step is not done when you say so, it is done when its receipt
says so, and a receipt is written by the script, never by a model.

## Current state

Read at `origin/main` 6ce2f0d; line refs re-checked after bringing in ddec05d (#85 merged: kitchen.sh lost clone mode and gained `procs` and `done`; one test mode; Contract 8 rewritten).

- `kitchen.sh check` is `cmd_check`, `kitchen.sh:2696-2725` (header comment `:2674-2681`). It
  hashes the working state with `tree_hash` (`:2686-2694`), looks for a green line of the same
  tree and command (`:2705`, a `grep` anchored at the end of the line on `cmd=$cmdid`), runs the
  config's `check:` line into `.claude/check.out` (`:2712`), and appends one line
  `<time> tree=<hash> rc=<n> secs=<n> cmd=<12 hex>[ moved]` to `.claude/check.log` (`:2715-2717`).
  `cmdid` is a hash of the config line (`:2702`). `done` removes `check.log` and `check.out` per ticket (`:2302`); receipts are per ticket, so no conflict.
- Flags: `FORCE` is declared at `:327` and parsed at `:368`. A bare word starting with a digit is
  taken as a PR number for `ship` (`:375`), so a tree hash given to a new flag must be consumed
  by that flag.
- Usage header for `check`: `kitchen.sh:73-82`.
- The Window and the budget read the log through one parser: `window/server/live/checklog.js`
  (`LINE` at `:8`, `parseCheckLog` `:10-17`, `readCheckLog` `:19-21`), used by
  `budget.js:340-343` and `live/index.js:84-97` (`watchChecks`). Both only count lines that match.
- The taster runs `kitchen.sh check` itself and trusts "green on this tree, not re-run"
  (`agents/taster.md:38-46`, the report line at `:68`); the sous hands it that command
  (`sous-chef/SKILL.md:483`). `open-pr` re-checks after bringing trunk in (`open-pr/SKILL.md:74-88`)
  and pushes at step 6 (`:124-127`) without looking at the check again. `review-task` runs the
  check at step 4 (`:54`) and writes the checklist after it (step 6); `implement` runs it at
  step 3 of its loop (`implement/SKILL.md:90`).
- Contract text: the log row is `skills/README.md:299`; the taster's row is `:35`; Contract 8
  (`:672`, now one section with no "Both modes" subheading; its "The sous reads stations" paragraph is `:716`). `PLAYBOOK.md:464` repeats the taster's row.
- Tests: `tests/kitchen.test.sh` section "check: the config's check runs once per tree"
  (`:1184-1250`); the Window's log fixture is `tests/window-live.mjs:108-122`.
- Facts from the record (the commis): the line format and trust rule are #66's
  (`docs/plans/66-check-tree-hash.md:105-114`); #78 is open (the journal, plan, checklist and
  INDEX are inside the hashed tree); station-2's #85 plan has `kitchen.sh done` remove
  `check.log` per ticket.

## Desired end state

Every real run of `kitchen.sh check` appends one **receipt** to `<checkout>/.claude/check.log`:
the tree it ran on, when it started and ended, the exact command, its exit code, a sha256 of
its output, the station and the config's `check:` line. `kitchen.sh check --receipt [<tree>]`
prints the newest receipt for the current (or given) tree. The taster reads that receipt
instead of running the check; `open-pr` will not push a tree without a green one; the budget
and the Window count receipts. Contract 8 says a check's proof is its receipt.

Verified by: the new cases in `tests/kitchen.test.sh` and `tests/window-live.mjs`, and
`scripts/check.sh` green.

## Not doing

- A hook that refuses an Edit or Write on `check.log`. **Limitation:** "no model writes or edits
  a receipt" is prose until a guard enforces it. Today `.claude/check.log` is writable by the
  cook's own Edit and Write, and the digest only shows a line was made by a run, not that nobody
  forged one. The guard refusal belongs with #91 (positive authorization, `guard.sh`); the sous
  carries it into #91's brief. Contract 4 still says only `kitchen.sh check` writes the log.
- `kitchen.sh ship` (CI is its receipt, as the ticket says).
- Moving the paperwork out of the hashed tree (#78). This plan lives with it: see How, last bullet.
- Keeping `check.out` past the next run. The digest is of that run's output; the file itself is
  still overwritten by the next run.

## Approach

Reuse #66's log and its single-line, space-separated shape, and add fields. One function finds
the receipt for a tree, and both `cmd_check`'s "already green" skip and `--receipt` use it, so
what `check` trusts and what the taster is shown cannot drift apart. New code goes in new
functions after `tree_hash`; the existing lines changed are named in Phase 1.

The receipt line (one line, fields in this order):

```
<ended, UTC> tree=<40 hex> rc=<n> secs=<n> cmd=<12 hex> start=<started, UTC> out=<64 hex sha256 of the output> station=<checkout folder name>[ moved] check=<the config's check: line, to the end of the line>
```

`check=` is last so the command may hold spaces. `cmd=` stays: it is #66's id and the readers
already know it.

## Decisions

### Changes the ticket

None.

### How

- **One field for "the exact command" and "the config's `check:` value".** At write time they are
  the same string (`cmd_check` runs `bash -c "$cmd"` where `cmd="$(cfg check)"`), so the receipt
  carries it once as `check=`. A receipt is stale when its `check=` differs from the config's
  today: that is the ticket's "the check changed under this tree".
- **A receipt is a new line, and older lines are not receipts.** Lines written before this change
  (no `start=`, `out=`, `station=`, `check=`) stay readable by the Window and the budget, which
  keeps counting them as runs, but `--receipt` and the skip ignore them. Cost: one extra real
  run per tree after an upgrade.
- **A ` moved` line is never a receipt.** It records a run that changed its own tree; its `tree=`
  names the tree after the run, which the check never saw. `--receipt` skips it, so a moved run
  reads as "no receipt for this tree".
- **Newest receipt wins.** `check` skips the run only when the newest receipt for the tree is
  green and current (#66 skipped on any green line; a `--force` run that came back red now
  counts against the tree). Receipts for other trees do not matter.
- **`--receipt` prints the raw line on stdout and exits:** `0` the newest receipt is green and
  current; `1` there is none ("no receipt for this tree" on stderr); `2` there is one that cannot
  be relied on, with the reason on stderr: "the check changed under this tree" (stale, tested
  first) or "the check was red on this tree (rc <n>)". The ticket fixes the `1`; `2` is what
  lets the taster and `open-pr` tell "run the check" from "fix the code" without parsing.
  `--receipt` takes an optional 40-hex tree; the flag consumes it, so a hash starting with a digit
  is not read as a PR number.
- **sha256** comes from `shasum -a 256`, else `sha256sum` (macOS has the first, most Linux the
  second; both run under bash 3.2). If neither exists `check` stops with a message before it runs.
- **The Window and the budget drop a receipt that names another station** (its `station=` is not the
  folder it was read from): a copied or misfiled line is not a run that happened there. Legacy lines
  carry no station and are kept.
- **The taster's verdicts.** Green and current receipt: proceed, `CHECK: receipt <ended>`. No receipt
  or stale: `VERDICT: blocked`, and the reason says the cook's last act before `[handoff]` is
  `kitchen.sh check`; the taster never runs it. Red receipt: `findings`, with the rc as finding 1.
  The old "the check changed tracked files" finding goes: a run that moved the tree has no receipt.
- **`tree_hash` keeps the real index's mtime on its copy** (added in Phase 1, signed by the sous
  after the fact: a receipt has to name the right tree). `tree_hash` copies the index to a temp
  file, and the copy's fresh mtime made git trust a file's stat, so a same-size edit in the same
  second as the index write hashed as the old content (the receipt test failed about 1 run in 3).
  `touch -r "$real" "$idx"` after the `cp` makes git re-check racy entries by content.
  Regression test: 24 same-size edits right after `git add -A`, each a distinct tree; red 4 of 4
  without the line.
- **The pass's findings, signed by the sous (added after the pass).** `open-pr` pushes `HEAD`, so it
  commits what `index` changed and, right before the push, requires a clean `git status --porcelain`
  and `kitchen.sh check --receipt "$(git rev-parse 'HEAD^{tree}')"` to exit 0: only then does the
  receipt name the commit pushed. The `station=` field is encoded (`%` as `%25`, space as `%20`) on
  write and decoded by `checklog.js`, so a folder with a space keeps its receipts. `--receipt` with
  anything that is not a full 40-hex tree id exits 64 ("--receipt takes a full 40-hex tree id."),
  never answered for the current tree. Each has a test that goes red when its fix is reverted.
- **The tests' sealed PATH gets `shasum` and `sha256sum`**, because `kitchen.sh check` now
  needs one of them.
- **Where the paperwork sits (#78).** The journal, checklist and INDEX are inside the hashed tree,
  so any write after the last check leaves the tree with no receipt. Each skill that writes
  paperwork now runs `kitchen.sh check` after its last write and before the handoff: `review-task`
  (after the checklist and INDEX), and `line-cook` step 7 says nothing in the tree may change
  between that check and `[handoff]` (journal the handoff first). That moves the real run from the
  taster to the cook, so the number of runs per ticket does not grow.

## Phase 1: the receipt in kitchen.sh

**Status:** Done — kitchen.sh (header, `RECEIPT` flag and parse, section comment, `sha256_of`, `receipt_line`, `receipt_field`, `receipt_check`, `cmd_receipt`, `cmd_check` edits, `tree_hash` mtime line) and 19 new cases (and 3 changed) in tests/kitchen.test.sh (sealed PATH gets shasum, sha256sum)

### Changes

#### `plugins/bk/skills/kitchen/kitchen.sh:73-82` (edit) — the usage header

Rewrite the `check` entry: every real run appends a receipt (list the fields in one sentence),
`--receipt [<tree>]` prints the newest receipt for the tree and exits 0, 1 or 2 as above, `--force`
runs anyway. Keep the "both files are kept out of git" sentence.

#### `plugins/bk/skills/kitchen/kitchen.sh:327` (edit) — one more flag variable

```bash
FORCE=false       # --force, for check
RECEIPT=false; RECEIPT_TREE=""   # --receipt [<tree>], for check
```

#### `plugins/bk/skills/kitchen/kitchen.sh:368` (edit) — parse the flag, right after `--force`

```bash
    --receipt) RECEIPT=true; shift; if [[ "${1:-}" =~ ^[0-9a-f]{40}$ ]]; then RECEIPT_TREE="$1"; shift; fi ;;
```

#### `plugins/bk/skills/kitchen/kitchen.sh` `tree_hash` (`:~2710`, one line) (edit)

After `cp "$real" "$idx"` add `touch -r "$real" "$idx"` (with a two-line comment saying why).

#### `plugins/bk/skills/kitchen/kitchen.sh:2674-2681` (edit) — the section comment

Say the log holds receipts (the line above), that a skipped call writes nothing, and that older
lines are readable by the Window and the budget but are not receipts.

#### `plugins/bk/skills/kitchen/kitchen.sh` after `tree_hash` (`:2694`) (new functions)

```bash
# sha256_of <file> → the file's sha256, hex
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else return 1; fi
}

# receipt_line <log> <tree> → the newest receipt for <tree>: a full receipt line that is not
# " moved" (a moved run never saw the tree it names). Older lines are not receipts.
receipt_line() {
  grep -E "^[^ ]+ tree=$2 rc=[0-9]+ secs=[0-9]+ cmd=[0-9a-f]{12} start=[^ ]+ out=[0-9a-f]{64} station=[^ ]+ check=" "$1" 2>/dev/null \
    | grep -v -E ' station=[^ ]+ moved check=' | tail -1
}

# receipt_field <line> <key> → the value of rc, secs, start, out or station; read only from the
# part before check=, so the config line cannot be mistaken for a field
receipt_field() { local head="${1%% check=*}"; printf '%s\n' "$head" | sed -E "s/^.* $2=([^ ]*).*$/\\1/"; }

# receipt_check <line> → the config's check: line the run used (everything after the first check=)
receipt_check() { printf '%s\n' "${1#* check=}"; }
```

```bash
# cmd_receipt: kitchen.sh check --receipt [<tree>]
cmd_receipt() {
  local dir="$HERE" tree="$RECEIPT_TREE" cmd line rc have
  tree="${tree:-$(tree_hash "$dir")}" || { echo "check: couldn't hash the tree in $dir." >&2; return 1; }
  line="$(receipt_line "$dir/.claude/check.log" "$tree")"
  [[ -n "$line" ]] || { echo "no receipt for this tree" >&2; return 1; }
  printf '%s\n' "$line"
  have="$(receipt_check "$line")"; cmd="$(cfg check)"
  [[ "$have" == "$cmd" ]] || { echo "receipt is stale: the check changed under this tree" >&2; return 2; }
  rc="$(receipt_field "$line" rc)"
  (( rc == 0 )) || { echo "receipt is red: the check failed on this tree (rc $rc)" >&2; return 2; }
}
```

#### `plugins/bk/skills/kitchen/kitchen.sh:2696-2725` (edit) — `cmd_check`

Existing lines changed, and only these:

- `:2697` locals: add `startiso outsha station`.
- `:2698-2699` unchanged. Right after it (new): `$RECEIPT && { cmd_receipt; return; }` and a
  `sha256_of` availability check (`sha256_of /dev/null >/dev/null || { echo "check: needs shasum or
  sha256sum on PATH." >&2; return 1; }`).
- `:2702` unchanged (`cmdid` stays: it is the `cmd=` field).
- `:2704-2710` the skip: replace the `grep` on `:2705` with `rec="$(receipt_line "$log" "$before")"`
  and trust only when `[[ -n $rec ]]`, its `rc` is 0 and its `check=` equals `$cmd`; the
  "not re-run" message on `:2707` reads `secs` with `receipt_field "$rec" secs`.
- `:2711` start: also `startiso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"`.
- `:2714` after the run: `outsha="$(sha256_of "$out")"; station="$(basename "$(cd "$dir" && pwd -P)")"`.
- `:2715-2717` the line: `line="$(date -u +%Y-%m-%dT%H:%M:%SZ) tree=$after rc=$rc secs=$secs cmd=$cmdid start=$startiso out=$outsha station=$station"`;
  `[[ "$after" == "$before" ]] || line="$line moved"`; then `echo "$line check=$cmd" >> "$log"`.
- Messages at `:2718-2724` unchanged.

### Success criteria

- [x] `scripts/check.sh` passes (it runs `bash -n`, shellcheck, the whole test suite).
- [x] In a scratch repo: `kitchen.sh check` then `kitchen.sh check --receipt` prints one line with every field and exits 0; with a hand-edited `check=` it exits 2; on a tree never checked it exits 1 and says "no receipt for this tree".
- [ ] Manual: `tail -1 .claude/check.log` in this station after a run shows `start=`, `out=<64 hex>`, `station=station-3` and `check=scripts/check.sh`.

## Phase 2: the Window and the budget read receipts

**Status:** Done — checklog.js (receipt fields, station filter), comments in budget.js and index.js, 4 new cases in tests/window-live.mjs

### Changes

#### `plugins/bk/window/server/live/checklog.js:1-21` (edit)

Update the header comment to the receipt line. Widen `LINE` (`:8`) so the receipt fields are
optional and the line may end in `check=…`:

```js
const LINE = /^(\S+) tree=(\S+) rc=(\d+) secs=(\d+) cmd=(\S+)(?: start=(\S+) out=([0-9a-f]{64}) station=(\S+))?( moved)?(?: check=(.*))?$/;
```

`parseCheckLog` (`:10-17`) returns `{ at, tree, rc, ok, secs, moved }` as today and, when the
receipt fields are there, `receipt: true, start, out, station, check`. `readCheckLog(dir)`
(`:19-21`) drops a receipt whose `station` is not `path.basename(dir)`; a legacy line stays.

#### `plugins/bk/window/server/live/budget.js:340-341` and `live/index.js:84-86` (edit, comments only)

Say "receipt" where they say "line"; no logic changes, they already read through `readCheckLog`.

#### `tests/window-live.mjs` after `:120` (edit, new cases)

A receipt line parses with its fields; a receipt naming `station-9` read from `station-1` is not
counted; a legacy line in the same log still is; a moved receipt is counted as a moved run, as before.

### Success criteria

- [x] `tests/window.test.sh` passes with the new cases, and `tests/budget.test.sh` is unchanged and green.
- [x] `scripts/check.sh` passes.

## Phase 3: contract, skills and the changelog fragment

**Status:** Done — Contract 1 Taster row, Contract 4 log row, a Contract 8 paragraph, taster.md, sous-chef, open-pr, review-task, implement, line-cook, PLAYBOOK, changelog fragment

### Changes

#### `plugins/bk/skills/README.md:299` (edit) — the log row

Describe the receipt line and `kitchen.sh check --receipt` and the three exits; say a green for the
same tree and command is trusted only as the newest receipt, and a red, stale or moved one never.

#### `plugins/bk/skills/README.md:35` (edit) — the Taster's row

"reads the receipt (`kitchen.sh check --receipt`) for the exact tree it reads instead of running the check".

#### `plugins/bk/skills/README.md:716` (edit) — Contract 8 (new paragraph after "The sous reads stations")

**A check's proof is its receipt.** "`kitchen.sh check` writes a receipt for every real run; a phase,
a handoff and a push are done when the receipt for the exact tree is green, not when a session says
so. The taster reads it and never re-runs the check; a tree with no green receipt (or a stale one,
because the config's `check:` line changed) is not reviewable and not pushable. Paperwork inside
the tree (journal, checklist, INDEX) moves the tree, so the cook runs the check after its last write."

#### `plugins/bk/agents/taster.md:3,20,38-46,68` (edit)

Step 2 becomes "The receipt": run `cd <station> && "<Check>"` where `Check:` is now
`kitchen.sh check --receipt`; map exit 0 to proceed, 1 and "stale" to `blocked`, red to a finding;
never run `kitchen.sh check` (the Bash allowance names the receipt, the leak check and git reads).
The report line (`:68`) becomes
`CHECK: receipt <ended> rc=<n> | none | stale | red — <one line>`.
Frontmatter `description` (`:3`) and the `Check:` input line (`:20`) follow.

#### `plugins/bk/skills/sous-chef/SKILL.md:483` (edit)

`Check: <abs path of kitchen.sh> check --receipt.`

#### `plugins/bk/skills/open-pr/SKILL.md:3,74-88,124-127` (edit)

Step 4 keeps `kitchen.sh check` (it makes the receipt) and adds "a check that does not exit 0 stops
here". Step 6 starts with `kitchen.sh check --receipt` run immediately before `git push`: a non-zero
exit means do not push, say which reason it gave; the push is of the tree the receipt names.

#### `plugins/bk/skills/review-task/SKILL.md:54,90` (edit)

Step 4 stays; a step after the checklist and INDEX are written runs `kitchen.sh check` again so the
receipt names the tree the taster will read; the `[handoff]` paragraph (`:90`) says the taster reads
that receipt and does not run the check.

#### `plugins/bk/skills/implement/SKILL.md:91` (edit)

"A phase is done when `kitchen.sh check` is green for its tree: that run's receipt, not the cook's
word."

#### `plugins/bk/skills/line-cook/SKILL.md:182-187,193` (edit)

Step 7: journal the handoff first, then the last `kitchen.sh check` in the station, then send
`[handoff]`; nothing in the tree changes in between. Step 8 re-runs the check (as now) and hands off again.

#### `PLAYBOOK.md:464` (edit) — the taster's row, same wording as the contract's

#### `changelog.d/90-gate-receipts.md` (new)

```
level: minor

Every run of the check now leaves a receipt in the station's check log: which tree, which
command, how it ended and a digest of what it printed. The taster reads the receipt instead of
running the check, and `open-pr` will not push a tree without a green one. For you: nothing to
set up. A cook's last act before `[handoff]` is now `kitchen.sh check`, so the taster has a
receipt for the exact tree it reads.
```

### Success criteria

- [x] `scripts/check.sh` passes (frontmatter check, release check: the fragment is the only release file touched).
- [x] `grep -rn "re-runs the check\|runs the check there" plugins/bk PLAYBOOK.md` finds no taster text that still says it runs the check. (the only hits are the generic setup and line-cook lines about re-running the check before a PR, which are the cook's check)
- [x] A read-only sub-agent comparing the edited skills with Contract 8 and the taster lists no contradiction (it found 3 real and 2 loose ones, all fixed: see the journal).

## Testing

`tests/kitchen.test.sh`, section "check: the config's check runs once per tree" (`:1184-1250`):

Existing lines that change: `:1196` (the log-line regex gains the new fields), `:1217` (the
"another command" case rewrites `check=` instead of `cmd=`, since trust now compares the config
line), `:1233` (`" moved$"` becomes `" moved check="`).

New cases, in that section:

- a receipt carries every field: `start=`, `out=` equals `shasum -a 256 .claude/check.out`, `station=`
  is the folder name (also in the worktree station case), `check=` is the config line;
- `--receipt` prints the newest receipt for the current tree and exits 0; for a given older tree
  (taken from the log) prints that tree's;
- a hand-edited `check=` makes `--receipt` exit 2 with "the check changed under this tree", and the
  next `check` runs again;
- a red receipt makes `--receipt` exit 2 and say red; a ` moved` line is not a receipt (exit 1);
- a tree with no receipt exits 1 with "no receipt for this tree"; so does a log holding only a
  pre-receipt line, and `check` runs again over it;
- a tree hash starting with a digit is read by `--receipt`, not taken as a PR number.

`tests/window-live.mjs`: the Phase 2 cases. Each new test is run red once: remove the receipt
write from `cmd_check` (and, for the Window, revert `LINE`) and watch the cases fail, then restore.
The full gate (`tests/kitchen.test.sh`, `scripts/check.sh`) runs only after telling the sous: four
stations share the machine.

## References

- Ticket: GitHub issue #90 (the head chef's WHAT, 2026-11-03).
- #66: `docs/plans/66-check-tree-hash.md:105-114` (the line and the trust rule), `docs/checklists/66-check-tree-hash.md:32-34,59`.
- Contract 8 `skills/README.md:672` (the paragraph at `:716`); the log row `:299`.
- `agents/taster.md`, `skills/open-pr/SKILL.md`, `window/server/live/checklog.js`.
- Overlap: #86 (taster, kitchen.sh, tests/kitchen.test.sh), #85 (`kitchen.sh done` clears `check.log`
  per ticket; no conflict with receipts, which are per-ticket), #92 (the taster). Bring `main` in
  before Phase 1 and re-check the line refs above (done once, after #85).
