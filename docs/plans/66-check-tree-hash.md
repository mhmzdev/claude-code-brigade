---
ticket: "#66"
title: kitchen check — run the config's check once per tree, record the result with the tree's hash
status: done
approved: 2026-11-03
lane: B
created: 2026-11-03
open_questions: none
migration: false
files:
  - plugins/bk/skills/kitchen/kitchen.sh
  - tests/kitchen.test.sh
  - plugins/bk/skills/implement/SKILL.md
  - plugins/bk/skills/review-task/SKILL.md
  - plugins/bk/skills/open-pr/SKILL.md
  - plugins/bk/agents/taster.md
  - plugins/bk/skills/sous-chef/SKILL.md
  - plugins/bk/skills/line-cook/SKILL.md
  - plugins/bk/skills/README.md
  - plugins/bk/window/web/scene.js
  - plugins/bk/agents/runner.md
  - PLAYBOOK.md
  - plugins/bk/window/server/live/checklog.js
  - plugins/bk/window/server/live/budget.js
  - plugins/bk/window/server/live/index.js
  - plugins/bk/window/server/state.js
  - tests/budget.test.sh
  - tests/window-live.mjs
  - plugins/bk/.claude-plugin/plugin.json
  - Formula/bk.rb
  - CHANGELOG.md
  - docs/plans/INDEX.md
  - docs/journal/INDEX.md
  - docs/checklists/INDEX.md
---

# #66 — `kitchen.sh check`: the check runs once per tree

## Why

A pass runs the full check three to four times on a tree that hasn't changed: `implement`,
`review-task`, the taster, `open-pr` (and once more per bring-main-in round). Nothing knows the
check already passed on this exact tree. The repeats cost tokens and minutes, and two full runs
overlapping across stations is what collided on #50's fixed port.

## Current state

- The check is run by prose, as `<check>` from `.claude/brigade.md`: `implement/SKILL.md:90`
  (per phase, optionally through the `runner`), `review-task/SKILL.md:54`, `open-pr/SKILL.md:72-84`
  (after `git merge origin/<trunk>`), `agents/taster.md:38-44` (the sous hands it `Check: <check>`,
  `sous-chef/SKILL.md:457`). Nothing is written down: no log, no hash.
- `kitchen.sh` has no `check` command. Its dispatcher is `kitchen.sh:1567-1572`; flags are parsed at
  `kitchen.sh:~236-270`; a machine-local file is kept out of git by `exclude_locally`
  (`kitchen.sh:494-501`, main checkout only) or inline for a station (`kitchen.sh:358-362`).
- The budget reads check results from the **runner sub-agent's reply text** only:
  `budget.js:235` (`ok: verdict(lastText)`), `:324-331` (rework after the first red runner),
  `:414-416` (`check-red-repeat`: three red runner steps). The Window's check machine does the same
  live: `state.js:100-108` (`helperEnd` of a runner → `state.check`). If cooks stop spawning runners
  for the check, both go blind, so they must read the log.
- Contract: `skills/README.md:35` says the taster "re-runs the check"; `:36` the runner runs "the
  check, a test suite, a scan".

## Desired end state

- `kitchen.sh check [--force]` run in any checkout (a station, the main checkout): computes the
  tree hash; if `<checkout>/.claude/check.log` holds a green line for that hash **and** the same
  check command, prints it and exits 0 without running; else runs the config's `check`, appends one
  line, prints green or red, exits with the check's code. Verify: the new `check` tests.
- `implement`, `review-task`, `open-pr` and the taster call `kitchen.sh check`; the taster says
  whether it ran the check or trusted a record.
- The budget's rework/`check-red-repeat` and the Window's check machine count the log's runs (a
  skipped run is never a line, so never a run), falling back to runner replies where no log exists.

## Not doing

- A lock across stations (the sous's "one station at a time" stays; #50's port fix is its own ticket).
- Putting trunk's sha in the key (see Decisions → How); `--force` covers the rare case.
- Caching CI, or changing `scripts/check.sh`, `.claude/brigade.md` or CLAUDE.md.
- Retiring the runner: it stays for other noisy commands (counters, test subsets).
- Trusting a record across checkouts: each checkout has its own log.

## Approach

One new function, `cmd_check`, in `kitchen.sh`, plus a flag and a dispatcher word; it follows
`cmd_budget`/`cmd_leaks` (a command that works on `$HERE`, the checkout it was run from). The log is
one line per **real** run. The Node side gets one small shared reader, `live/checklog.js`, so the
budget and the Window parse the log the same way (as `budget.js:456` already says of `verdict`).

## Decisions

### Changes the ticket

None. (The ticket's Done when 2 itself has the taster trust a green record; the contract lines that
say the taster "re-runs the check" are reworded to match in phase 2. That is the ticket's own ask
carried into the contract, listed here so the sous sees it.)

### How

- **The hash**: a tree object over the working state, made in a **temporary index**, so the real
  index and the tree are never touched: copy `git rev-parse --git-path index` to a temp file (or
  `git read-tree HEAD` when there is none), `GIT_INDEX_FILE=<temp> git add -A`, `git write-tree`.
  It covers tracked changes, deletions and untracked files, and honours `.gitignore` and
  `info/exclude`, so `.claude/check.log` itself is not in it. Why not `git stash create`: it ignores
  untracked files, the thing a new file in a plan would be.
- **The key** is the tree hash **and** the check command (`git hash-object` of the string, 12 hex),
  so editing `check:` in the config invalidates old greens. Trunk's sha is not in it: a merge of
  trunk changes the tree, which is the case the key must catch, and a check that reads trunk
  (this repo's step 5 does) is covered by `open-pr` always merging first.
- **The log**: `<checkout>/.claude/check.log`, one line per real run, space-separated:
  `2026-11-03T12:00:00Z tree=<40 hex> rc=0 secs=41 cmd=<12 hex>` plus a trailing ` moved` when the
  tree after the run differs from the tree before (the check rewrote a file, or wrote an untracked
  non-ignored one). A `moved` line is never trusted; the next call, on the now-stable tree, runs once
  more and then trusts. Red runs are logged (the budget counts them) but never trusted. A skipped
  call writes nothing.
- **Output**: quiet. The full output goes to `<checkout>/.claude/check.out` (last run only); on red
  the last 40 lines are printed with its path. This is what the runner was for, so `implement` no
  longer needs a runner for the check. Both files are excluded via `exclude_locally`, generalised
  with an optional second argument (the checkout, default `$ROOT`).
- **The verdict line** (what the taster quotes): `check: green on this tree, not re-run
  (recorded 2026-11-03T12:00:00Z, 41s)` · `check: green (ran, 41s)` · `check: RED (rc 1, 41s) …`.
- **`--force`** runs regardless and logs as usual. The sous may put it in the taster's `Check:` line
  when it wants an independent run.
- **The taster** runs `kitchen.sh check` as the sous's brief gives it (`Check: <abs kitchen.sh> check`),
  quotes the verdict line, and reports `CHECK: ran` or `CHECK: trusted the record of <time>` (a
  record written by `kitchen.sh` for this exact tree, not the cook's say-so).
- **The Window and the budget**: one rule, "the log wins where it exists". The budget uses log
  lines inside a ticket's span from that cook's station when there are any, else the old runner
  reading. The live machine switches to the log the first time a station's log has a line, and
  `helperEnd` stops feeding it from then on. Neither double-counts a runner that ran `kitchen.sh check`.
- **Version**: 0.31.0 (0.30.0 is #76's, still open); follow #64's rule if it lands first.

## Phase 1: `kitchen.sh check`
**Status:** Done — kitchen.sh (exclude_locally takes a checkout; tree_hash, cmd_check, --force, dispatcher, header) and 28 new cases in tests/kitchen.test.sh (297 pass with the gate's env unset).

### Changes

#### `plugins/bk/skills/kitchen/kitchen.sh` (edit)

- `:494` `exclude_locally`: take an optional checkout (`local repo="${2:-$ROOT}"`) and use it in the
  two `git -C` calls, so a station can exclude its own files.
- New `tree_hash` and `cmd_check`, after `cmd_debrief` (`:~1480`):

```bash
# tree_hash <dir> → a tree object id of <dir>'s working state (tracked, deleted and untracked
# files, minus what git ignores), made in a throwaway index so nothing in <dir> is touched.
tree_hash() {
  local dir="$1" tmp idx rc
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/brigade-tree.XXXXXX")" || return 1
  idx="$tmp/index"
  if [[ -f "$(git -C "$dir" rev-parse --path-format=absolute --git-path index)" ]]; then
    cp "$(git -C "$dir" rev-parse --path-format=absolute --git-path index)" "$idx"
  else
    GIT_INDEX_FILE="$idx" git -C "$dir" read-tree HEAD 2>/dev/null || true
  fi
  GIT_INDEX_FILE="$idx" git -C "$dir" add -A >/dev/null 2>&1 && GIT_INDEX_FILE="$idx" git -C "$dir" write-tree
  rc=$?; rm -rf "$tmp"; return $rc
}

# check — the config's check command, run once per tree (#66). ...
cmd_check() {
  local dir="$HERE" cmd cmdid log out before after start secs rc line rec
  cmd="$(cfg check)"
  [[ -n "$cmd" ]] || { echo "No check: command in $CONFIG." >&2; return 1; }
  mkdir -p "$dir/.claude"; log="$dir/.claude/check.log"; out="$dir/.claude/check.out"
  exclude_locally .claude/check.log "$dir"; exclude_locally .claude/check.out "$dir"
  cmdid="$(printf '%s' "$cmd" | git hash-object --stdin | cut -c1-12)"
  before="$(tree_hash "$dir")" || { echo "check: couldn't hash the tree in $dir." >&2; return 1; }
  if ! $FORCE; then
    rec="$(grep -E " tree=$before rc=0 secs=[0-9]+ cmd=$cmdid\$" "$log" 2>/dev/null | tail -1)"
    if [[ -n "$rec" ]]; then
      echo "check: green on this tree, not re-run (recorded ${rec%% *}, $(echo "$rec" | sed -E 's/.* secs=([0-9]+) .*/\1/')s)"
      return 0
    fi
  fi
  start="$(date +%s)"
  (cd "$dir" && bash -c "$cmd") > "$out" 2>&1; rc=$?
  secs=$(( $(date +%s) - start ))
  after="$(tree_hash "$dir")" || after="unhashable"
  line="$(date -u +%Y-%m-%dT%H:%M:%SZ) tree=$after rc=$rc secs=$secs cmd=$cmdid"
  [[ "$after" == "$before" ]] || line="$line moved"
  echo "$line" >> "$log"
  if (( rc == 0 )); then
    echo "check: green (ran, ${secs}s)"
    [[ "$after" == "$before" ]] || echo "check: the run changed files in the tree, so this green is not trusted; the next call runs once more."
  else
    echo "check: RED (rc $rc, ${secs}s). Last lines of $out:"; tail -40 "$out"
  fi
  return $rc
}
```

- Flags (`:~236`): `FORCE=false` with the other defaults; `--force) FORCE=true; shift ;;` in the parse loop.
- Dispatcher (`:1567-1572`): `check) cmd_check ;;`.
- Header usage block (after `leaks`): the `check [--force]` entry.

#### `tests/kitchen.test.sh` (edit)

New `section "check: once per tree"` before the final summary, on a `new_repo` with
`check: "echo ran >> $T/runs"` (a counter outside the tree): 1) first call runs (counter 1, exit 0,
log line with `rc=0`); 2) second call prints `not re-run` and the counter stays 1; 3) `--force` runs
(counter 2); 4) editing a tracked file runs again; 5) a new untracked file runs again; 6) a red check
exits non-zero, logs `rc=1`, and the next call runs it again; 7) a check that rewrites a tracked file
logs ` moved`, and is not trusted on the next call; 8) changing the `check:` command in the config
invalidates the green; 9) in a worktree station the log lands in the station, `git status` stays
clean, and the main checkout has no log; 10) no `check:` is an error with a message.

### Success criteria
- [x] `bash -n plugins/bk/skills/kitchen/kitchen.sh` and `shellcheck -S warning` on it, clean
- [x] `bash tests/kitchen.test.sh` passes, including the 10 new cases
- [x] Break it: make `tree_hash` print a constant, run `bash tests/kitchen.test.sh`: cases 4, 5 and 7 go red; restore it
- [x] Break it: drop the `cmd=` part of the grep: case 8 goes red; restore it
- [ ] Manual: in this station, `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE plugins/bk/skills/kitchen/kitchen.sh check` is asked of the sous first (one gate at a time); a second call prints `not re-run`

## Phase 2: the skills and the contract call it
**Status:** Done — implement/review-task/open-pr/taster/sous-chef/line-cook/runner/PLAYBOOK/scene.js lines and the contract (taster, runner, paths-table row) now say `kitchen.sh check`; a fresh read-only read found two stale lines (PLAYBOOK taster row, open-pr description), both fixed.

### Changes

Only the lines that run the check; nothing else in these files moves.

- `implement/SKILL.md:90` (edit): "Run `kitchen.sh check` (it runs the config's `check` once per tree and prints one line; the output stays in `.claude/check.out`, so no runner is needed for it) plus anything the phase names. Exit code is the check's."
- `review-task/SKILL.md:54` (edit): "Run `kitchen.sh check` once. A recorded green for this exact tree counts: say which it was. A red check is an `[!]` on its own line."
- `open-pr/SKILL.md:72-84` (edit): the fenced `<check>` becomes `kitchen.sh check`, with one line: the merge changed the tree if trunk moved, so it runs; if trunk added nothing it is a recorded green.
- `agents/taster.md:38-44` (edit): step 2 runs the `Check:` the sous gave (`kitchen.sh check`), keeps the verdict line and the exit code; says `CHECK: ran` or `CHECK: trusted the record of <time>`; `--force` in the sous's line means run it. Add the `CHECK:` line to the report shape.
- `sous-chef/SKILL.md:457` (edit): `Check: <abs path of kitchen.sh> check` instead of `<check>`; one clause: add `--force` for an independent run.
- `line-cook/SKILL.md:187` runner paragraph (edit): the check goes through `kitchen.sh check`; the runner is for other noisy commands.
- `README.md:35` (Taster, edit): "runs the check (`kitchen.sh check`: it trusts a green record for the exact tree it reads, and says so)". `:36` (Runner): "a test suite, a scan". The Contract 4 paths table (`:~284`) gets a row: `.claude/check.log` / `.claude/check.out`, per checkout, kept out of git, written only by `kitchen.sh check`.

### Success criteria
- [ ] `grep -n 'kitchen.sh" check\|kitchen.sh check' plugins/bk/skills/implement/SKILL.md plugins/bk/skills/review-task/SKILL.md plugins/bk/skills/open-pr/SKILL.md plugins/bk/agents/taster.md plugins/bk/skills/sous-chef/SKILL.md` prints one hit per file
- [ ] `git grep -n 're-runs the check' plugins/bk` prints nothing
- [ ] A fresh read-only sub-agent reads the five files and the contract and finds no line that still tells anyone to run the raw `<check>` (the consistency read, CLAUDE.md)
- [ ] `scripts/check.sh` steps 1-3 (frontmatter, Contents lists) stay green

## Phase 3: the budget reads the log
**Status:** Done — live/checklog.js (new), budget.js reads the station's log (log wins where it has lines in the span, runner reading otherwise), tests/budget.test.sh: new BKLG-005 fixture and 5 cases (92 pass).

### Changes

#### `plugins/bk/window/server/live/checklog.js` (new)

```js
// The check log (`kitchen.sh check` writes it): one line per real run in a checkout's
// .claude/check.log. Shared by the budget and the Window so both count the same runs.
import fs from 'node:fs';
import path from 'node:path';
const LINE = /^(\S+) tree=(\S+) rc=(\d+) secs=(\d+) cmd=(\S+)( moved)?$/;
export function parseCheckLog(text) {
  const out = [];
  for (const l of String(text || '').split('\n')) { const m = l.match(LINE); if (m) out.push({ at: Date.parse(m[1]), tree: m[2], rc: +m[3], ok: +m[3] === 0, secs: +m[4], moved: !!m[6] }); }
  return out;
}
export function readCheckLog(dir) {
  try { return parseCheckLog(fs.readFileSync(path.join(dir, '.claude', 'check.log'), 'utf8')); } catch { return []; }
}
```

#### `plugins/bk/window/server/live/budget.js` (edit)

- import `readCheckLog`; in `finish(sp)` (`:297-331`) compute `const log = readCheckLog(stationDir(sp.cook)).filter(r => r.at >= sp.startedAt && (!sp.servedAt || r.at <= sp.servedAt + 60000))` where `stationDir` finds `stations()` entry whose basename is `sp.cook`; push one step per run (`kind: 'check'`, `ok`, `secs`, `cost: 0`); set `sp.checks = { source: log.length ? 'log' : 'runner', runs, reds }`.
- `:324-330`: `red`/`green`/`reds` use `isRun = log.length ? s.kind === 'check' : s.kind === 'runner'`.
- `:416` `check-red-repeat`: `const reds = t.checks ? t.checks.reds : <the old runner count>` (ledger records from before have no `checks`).

#### `tests/budget.test.sh` (edit)
A station `.claude/check.log` fixture with three red lines and one green inside a ticket's span: `check-red-repeat` fires from the log with the runner steps ignored; a ticket without a log still reads runners (existing cases unchanged); a `moved`/green line counts as a green for rework settling.

### Success criteria
- [x] `bash tests/budget.test.sh` passes (existing cases untouched, new cases added)
- [x] Break it: make `finish` ignore the log; the new log case goes red; restore
- [x] `node --check plugins/bk/window/server/live/checklog.js`

## Phase 4: the Window's check machine reads the log
**Status:** Done — state.js `checkResult` + `source`, live/index.js `watchChecks`, tests/window-live.mjs: 6 new cases (22 pass); two deliberate breaks went red. Demo on 4748: the check machine counted 2 runner results, source `runner`.

### Changes

#### `plugins/bk/window/server/state.js:100-108` (edit)
Split the body into `checkResult(r)` (push to history, `runs++`, `failed++` on red, `last`, `emit('check', r)`) and let `helperEnd` call it only while `state.check.source !== 'log'`. Add `source: 'runner'` to the initial `check` (`:18`).

#### `plugins/bk/window/server/live/index.js` (edit)
`watchChecks(cfg, store, every = 5000)` next to `watchHandoff`: every tick, for each of `cfg.stations()`, read `readCheckLog`, remember how many lines per station, and for new lines `store.checkResult({ ok, secs, who: <station>, note: 'check', at })`, setting `source: 'log'` on the first. On start it replays today's lines only. Called from `startLive` after `watchBudget`.

#### `tests/window-live.mjs` (edit)
Cases for `parseCheckLog` (a good line, a `moved` line, a junk line ignored) and for the store: after a log line, a runner `helperEnd` no longer adds to `state.check.runs`.

### Success criteria
- [x] `bash tests/window.test.sh` passes
- [x] Break it: let `helperEnd` keep feeding after `source = 'log'`; the new case goes red; restore
- [x] Manual (demo on 4748, never 4747): `node plugins/bk/window/server/index.js --demo --port 4748` still shows the check machine counting runner results (no log, so runner-fed)

## Phase 5: release
**Status:** Done — 0.31.0 (plugin.json, Formula, CHANGELOG); the full gate passed through `kitchen.sh check` (kitchen 297, guard 27, bk 82, budget 92, window 22); INDEX rows wait for `kitchen.sh index` after main is merged in at open-pr. The version is re-bumped there if #77 lands first.

### Changes
`plugins/bk/.claude-plugin/plugin.json` version 0.31.0; `Formula/bk.rb` url to v0.31.0; `CHANGELOG.md` entry `## [0.31.0] - 2026-11-03` for the busy human (the check runs once per tree and says so; nothing to do; `.claude/check.log` is new and machine-local; the taster may now trust a record); INDEX rows for this plan, journal and checklist: #76 is in main, so they come from `kitchen.sh index` after main is brought in, not by hand.

### Success criteria
- [x] `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh` passes (after asking the sous for the station slot)
- [x] `kitchen.sh leaks` prints nothing

## Testing

`tests/kitchen.test.sh` reaches `cmd_check` and `tree_hash` (both kitchen modes' station layout for case 9);
`tests/budget.test.sh` reaches `finish`'s log reading and the `check-red-repeat` rule;
`tests/window-live.mjs` reaches `parseCheckLog` and the store's `checkResult`/`helperEnd` switch.
Each new case is run red against a deliberate break first.

## References

- Ticket #66 (EPIC #71 section 2); #50 (the port collision); journals `13-merge-base-diff` (the check run at every round) and `62-budget-sous-role` (one gate at a time)
- `kitchen.sh:358-362` (exclude inline for a station), `:494-501` (`exclude_locally`), `:1456-1478` (`cmd_budget`, `cmd_debrief` shape)
- `budget.js:235,324-331,414-416,456`; `state.js:100-108`; `taster.md:38-44`
