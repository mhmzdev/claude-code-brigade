---
ticket: "#85"
title: worktrees only; drop clone mode; `kitchen.sh done` deletes a merged ticket's branch and resets the station
status: done
approved: 2026-11-03
lane: B
created: 2026-11-03
open_questions: none
migration: false
files:
  - plugins/bk/skills/kitchen/kitchen.sh
  - plugins/bk/hooks/guard.sh
  - bin/bk
  - plugins/bk/window/server/live/config.js
  - plugins/bk/window/server/state.js
  - plugins/bk/window/server/demo.js
  - plugins/bk/window/web/main.js
  - tests/kitchen.test.sh
  - tests/guard.test.sh
  - tests/bk.test.sh
  - tests/budget.test.sh
  - plugins/bk/skills/README.md
  - plugins/bk/skills/setup/SKILL.md
  - plugins/bk/skills/kitchen/SKILL.md
  - plugins/bk/skills/line-cook/SKILL.md
  - plugins/bk/skills/sous-chef/SKILL.md
  - plugins/bk/skills/open-pr/SKILL.md
  - plugins/bk/skills/feedback/SKILL.md
  - .github/ISSUE_TEMPLATE/feedback.yml
  - README.md
  - PLAYBOOK.md
  - AGENTS.md
  - changelog.d/85-worktrees-only.md
---

# #85 — worktrees only; drop clone mode; `kitchen.sh done`

## Contents

- [Why](#why)
- [Current state](#current-state)
- [Desired end state](#desired-end-state)
- [Not doing](#not-doing)
- [Approach](#approach)
- [Decisions](#decisions)
- [Refs after #86](#refs-after-86-main-025fb38)
- [Phase 1: kitchen.sh is worktree-only](#phase-1-kitchensh-is-worktree-only)
- [Phase 2: kitchen.sh done](#phase-2-kitchensh-done)
- [Phase 3: the hook, bk and the Window](#phase-3-the-hook-bk-and-the-window)
- [Phase 4: the tests](#phase-4-the-tests)
- [Phase 5: the contract, the skills and the docs](#phase-5-the-contract-the-skills-and-the-docs)
- [Testing](#testing)
- [References](#references)

## Why

Every path, test and contract section exists twice for a mode nobody runs: clone costs a second
copy of the repo and a second `install`, and gives nothing a worktree lacks. The head chef decided
on 2026-11-03 (issue #85): worktrees only, and a station's work is ephemeral: when its ticket is
merged the ticket branch goes (local and remote), the station is reset to trunk, detached, and the
folder stays because the cook's session lives in it.

## Current state

Line numbers are `origin/main` at `6ce2f0d`; #86 (station-1) lands first and moves them, so they
are re-read at implement time.

- `kitchen.sh` picks a mode: header comment `:5-15`; env `BRIGADE_KITCHEN_MODE` listed `:182`;
  root detection has a clone branch (`elif basename ROOT == station-*`) `:206-210`; `MODE` read,
  validated and used for the default kitchen `:254-259`; `setup` clones or adds a worktree
  `:645-680`, prints the stash warning only for worktrees `:742-748`; `sync` has a clone branch
  (checkout trunk, hard reset) `:911-923`; `status` prints the mode `:929`; `remove` has an
  `rm -rf` branch `:2402-2420`; the dispatcher is the last `case "$CMD"` `:2432-2439`.
- Nothing deletes a ticket branch or resets a served station: `ship` ends at `gh pr merge`
  (`:2229`), `sync` skips dirty stations, and `remove` keeps branches. End of shift is `ship` →
  one line to the head chef → `kitchen.sh clear` (`sous-chef/SKILL.md:500-522`).
- `guard.sh:38-61` finds the main checkout twice: by walking up from the kitchen (clone), then by
  git's common dir (worktree); the default-kitchen test accepts `$main/stations` or the sibling.
- `window/server/live/config.js:40-41` reads `kitchen_mode` (default `clone`) to choose the folder;
  `state.js:10`, `demo.js:7` carry `mode: 'clone'`; `web/main.js:52` prints it.
- `tests/kitchen.test.sh` is one big clone-mode suite (`section "clone mode (the default)"`
  `:64-245`, 26 `$C/stations` paths) with a workspace worktree section (`:1013-1065`), a
  `rail_suite "clone"` and `"worktree"` pair (`:1268,1280`), `remove (clone)` (`:1006`).
  `bk.test.sh:66-77` sets up "two clone stations"; `budget.test.sh` writes `kitchen_mode: clone`
  into seven configs (`:63,384,387,390,393,408`); `guard.test.sh:33-66` has a clone section.

## Desired end state

- `kitchen_mode` is gone. A station is a worktree of the main checkout at
  `<kitchen>`/station-N, the kitchen being `../<repo>-stations`, or `kitchen:` in the config
  (absolute, or relative to the main checkout). `grep -rn -i clone` finds no station-clone text
  outside `CHANGELOG.md`, `changelog.d/` and `docs/` history.
- A config that says `kitchen_mode: clone` (or `BRIGADE_KITCHEN_MODE=clone`) makes every
  `kitchen.sh` command but `remove` print one line and exit 1: stations are worktrees now; run
  `kitchen.sh remove` (it deletes the old `stations/` after confirming), drop the `kitchen_mode`
  line, run `kitchen.sh setup`. `kitchen_mode: worktree` is ignored.
- `kitchen.sh done <station-N>` after a merged PR: station detached at `origin/<trunk>`, ticket
  branch deleted locally and on origin (only a merged one, never forced), per-ticket state
  files gone, folder and session untouched. Verify: the new tests; `scripts/check.sh` green.
- End of shift reads `ship` → `done` → `procs --reap` (#86) → `clear`.

## Not doing

- #89 (`clear` vs a served cook on trunk): not taken in. `done` is written so it does not worsen
  it (see Approach).
- Auto-running `done` from `ship` or from `bk stop`; the sous runs it in End of shift.
- Deleting the worktree folder, or a station's `.claude/cook`, `cook-session`, `here`,
  `settings.local.json`.
- Editing `docs/the-names.md` (hand-written, outside the map: `.claude/brigade.md`), though it
  still says a station is "one gitignored clone".
- `gates.merge: head-chef` kitchens: `done` works the same after the head chef merges.
- A migration tool for clone kitchens beyond the exit-1 line and `remove`.

## Approach

Collapse the two modes into the worktree one in `kitchen.sh`, `guard.sh` and the Window, then add
`done` next to `ship`, then move the tests onto the worktree layout (the existing worktree
sections are the template), then the contract and the docs.

`done` follows `ship`'s shape (a `cmd_` function, a gh stub in the tests, refusals that name the
condition) and `clear`'s safety checks (`registry_of` for a live session). It never asks for
anything: the sous runs it (Contract 5's "invoking is approval" does not apply to a human; the
refusals are the safety).

#89: `done` leaves the station clean on trunk and does not touch the journal's `## Handoff` (the
merged PR carried it; `git switch --detach origin/<trunk>` rewrites only files that differ), and
it runs before `clear`, so `clear`'s "handoff newer than last turn" check sees what it saw before.
`done` neither adds a turn nor changes a journal mtime that passed before.

AGENTS.md is edited last (its `CLAUDE.md` symlink is a protected path; AGENTS.md itself is not,
but if the tool refuses, the cook sends `[gate] #85 edit denied: AGENTS.md …` and waits).

## Decisions

### Changes the ticket

None.

### How

- **`done` is its own command, not a part of `ship`.** The ticket allows either. Separate
  because a head-chef-merged PR (`gates.merge: head-chef`) and a PR the cook merged elsewhere
  need the same cleanup, and `done` can be re-run if the remote delete failed. `ship` only prints
  one more line: "then `kitchen.sh done <station>`".
- **`done` proves the merge through gh, four ways** (the pass added the last three). The branch's
  PR must be `MERGED` (not just closed) and its `baseRefName` must be trunk (a stacked PR's work has
  not reached trunk); the station must not be on trunk's own name; the origin branch is deleted only
  while `git ls-remote origin refs/heads/<branch>` (the exact ref) still equals the PR's head, else
  it is kept and named (`NOT deleted (it moved past PR #N: <sha>)`, exit 1). And the station's local tip must equal that PR's `headRefOid`: a commit made after the
  PR was opened is lost on deletion, so `done` refuses with both shas. Squash and rebase merges
  pass (the tip is the PR head, not on trunk), which is why `git branch -d` is not the test (the local delete is `-D`, only behind that tip check).
- **`done` refuses a dirty station and a busy session** (same registry reading as `clear`); no
  live session is fine. It exits 0 with "already on trunk, nothing to do" for a detached,
  clean station.
- **Per-ticket state removed:** `.claude/go` (the ticket names it; nothing writes it today, `rm -f`
  is harmless), `.claude/check.log`, `.claude/check.out`, `.claude/grilling`. Kept: `.claude/cook`,
  `cook-session` (the session lives on), `settings.local.json`, and `here`/`here.log` (the cook's
  own report; its next `[check-in]` replaces it, and the board shows the station spent until then).
- **The remote branch** is deleted with `git push origin --delete <branch>` only if
  `git ls-remote --exit-code --heads origin <branch>` finds it (GitHub may have auto-deleted it);
  a failed delete is reported and exits 1 after the rest is done. Never `--force`.
- **`remove` keeps one legacy branch.** The ticket's migration line says "`kitchen.sh remove`,
  then `setup`", so with `kitchen_mode: clone` in the config `remove` still runs and deletes the
  old `<repo>/stations/` (after the same `delete` confirmation); every other command exits 1.
  This is the only clone text left in `kitchen.sh`.
- **`kitchen_mode: worktree` is ignored**, not an error: the dogfood config and every existing
  worktree kitchen carries it, and breaking them for a no-op line would be noise.
- **The Window** drops `mode`: the header shows `trunk <name>`.
- **Order in End of shift:** ship → done → reap → clear. `done` follows `ship` (the ticket) and
  precedes `clear`; the reap goes between `done` and `clear` (the brief, matching #86). `done`
  does not need the reap first: it refuses only a dirty tree and a busy session, and a leftover
  process holds no git state. Nothing in either ticket argues for another order.
- **Tests:** the clone section becomes the worktree suite (stations at `$TMP/…/app-stations`,
  variable `CS`), the workspace-repo section stays as its own case, `rail_suite "clone"` goes,
  `budget.test.sh` drops the `kitchen_mode: clone` line from its configs, `guard.test.sh`'s clone
  section goes and its "not a station" cases become worktrees.

## Refs after #86 (main `025fb38`)

#86 merged (PR #93) before this started; main was brought in (a fast-forward) and every ref
re-read. The `Current state` and phase line numbers above are the old ones; these replace them:

- `kitchen.sh` (2783 lines): header `:5-20` (usage block grew, `procs` added); `BRIGADE_KITCHEN_MODE`
  `:208`; clone root `elif` `:233`; `MODE` `:280-284`; `ignore_kitchen` comment `:635`; `cmd_setup`
  `:662` (clone branch `:687-708`, warnings `:771`); `cmd_sync` `:933` (`:940`); `cmd_status` `:956`
  (`:958`); `cmd_clear` `:2163`; `cmd_ship` `:2232`; `seed_sous_permissions` `:2265`; `cmd_procs`
  `:2548`; `cmd_remove` `:2741-2760`; dispatcher `:2769-2783`. `cmd_done` goes after `cmd_ship`,
  before `seed_sous_permissions`. `registry_of` `:2109`, `json_str` `:2104`.
- End of shift (`sous-chef/SKILL.md:517`) is now 1 ship, 2 reap (`procs --reap`, then `--scan`),
  3 clear, 4 next ticket, 5 assign. `done` is inserted as step 2, so: ship, **done**, reap, clear.
  The reap reads `<station>/.claude/procs`, which `done` leaves alone (it never touches `procs` or
  `procs.log`).
- Tests: the clone section `tests/kitchen.test.sh:72`; `BRIGADE_KITCHEN_MODE=bogus` `:237`; ship's
  configs `:998,1001`; `remove (clone)` `:1014`; `rail_suite "clone"` `:1276`; and a new
  `procs_suite "clone"` `:1571` (#86 runs its procs tests per mode: the clone call goes, the worktree
  call stays). `bk.test.sh` has #86's stop/reap tests on the stations the file sets up.
- Docs: Contract 8 `README.md:676-709` (config line `:65`, skill table `:1033`); `PLAYBOOK.md:82-93`;
  `README.md:9,93-103,271`; `AGENTS.md:141`; `feedback/SKILL.md:43,102`; `kitchen/SKILL.md:3,25`;
  `line-cook/SKILL.md:3`; `setup/SKILL.md` lines as grep shows at edit time.

## Phase 1: kitchen.sh is worktree-only

**Status:** Done — `kitchen.sh` has no mode: root detection, `LEGACY_CLONE` (`:283`), setup/sync/status worktree-only, `remove` keeps the one legacy path (`:2772`), the one-line refusal (`:2801`).

### Changes

#### `plugins/bk/skills/kitchen/kitchen.sh:5-15,182` (edit)
Header: one kind of station (worktrees, `../<repo>-stations/station-N`, or `kitchen:`), no
`kitchen_mode`, no `BRIGADE_KITCHEN_MODE`. Add `done` to the usage block (Phase 2).

#### `plugins/bk/skills/kitchen/kitchen.sh:202-211` (edit)
Drop the clone `elif`; keep the common-dir test:
```bash
if [[ -n "$COMMON_DIR" && "$COMMON_DIR" != "$GIT_DIR_ABS" && "$(basename "$COMMON_DIR")" == .git ]]; then
  ROOT="$(dirname "$COMMON_DIR")"
fi
```

#### `plugins/bk/skills/kitchen/kitchen.sh:254-262` (edit)
```bash
LEGACY_CLONE=false
[[ "${BRIGADE_KITCHEN_MODE:-$(cfg kitchen_mode)}" == clone ]] && LEGACY_CLONE=true
KITCHEN_REL="${BRIGADE_KITCHEN:-$(cfg kitchen)}"
$LEGACY_CLONE && KITCHEN_REL="stations"   # only `remove` reads it: the old clone folder
[[ -z "$KITCHEN_REL" ]] && KITCHEN_REL="../${REPO_NAME}-stations"
```
and just before the dispatcher (`:2432`), after the `REC=` block:
```bash
if $LEGACY_CLONE && [[ "$CMD" != remove ]]; then
  echo "kitchen_mode: clone is gone: stations are worktrees now. Run 'kitchen.sh remove' (it asks before it deletes <repo>/stations/; push or park unpushed work first), delete the kitchen_mode line from .claude/brigade.md, then run 'kitchen.sh setup'." >&2
  exit 1
fi
```

#### `plugins/bk/skills/kitchen/kitchen.sh:606-607,633-760` (edit)
`ignore_kitchen` comment loses "(clone mode)". `cmd_setup`: no `remote` clone variable (the
"No 'origin' remote" check stays, a worktree needs `origin/<trunk>`); header text says "a
worktree detached there"; the `if worktree/else clone` at `:658-680` keeps only the
`git worktree add --detach` branch; the stash/`remove` warning block at `:742-748` is
unconditional (the `git clean -fdx` warning at `:729-736` stays: it is keyed on the kitchen being
inside the repo, which `kitchen:` can still do).

#### `plugins/bk/skills/kitchen/kitchen.sh:904-939` (edit)
`cmd_sync` keeps the detach branch only; `cmd_status` heading `Stations ($KITCHEN_REL/, trunk $TRUNK):`.

#### `plugins/bk/skills/kitchen/kitchen.sh:2398-2423` (edit)
`cmd_remove`: worktree path unconditional; the `rm -rf "$KITCHEN"` branch runs only when
`$LEGACY_CLONE` (message: "This deletes stations/ — every clone, including unpushed branches and
uncommitted work."; after it, "Now delete the kitchen_mode line and run kitchen.sh setup.").

### Success criteria
- [x] `bash -n plugins/bk/skills/kitchen/kitchen.sh` and `shellcheck` pass
- [x] `git grep -n -i -E 'clone|kitchen_mode|MODE' plugins/bk/skills/kitchen/kitchen.sh` shows only the legacy `remove` path, the refusal line, `git clone` in none, and the word "permission mode"
- [x] Manual: in a throwaway repo with `kitchen_mode: clone`, `kitchen.sh status` prints the one line and exits 1; `kitchen.sh setup` in a repo with no mode line creates `../<repo>-stations/station-N`

## Phase 2: kitchen.sh done

**Status:** Done — `cmd_done` (`kitchen.sh:2256`), usage block, dispatcher entry, `ship`'s last line points at it.

### Changes

#### `plugins/bk/skills/kitchen/kitchen.sh` after `cmd_ship` (new function `cmd_done`), `:2302` (edit dispatcher)
The parser already puts `station-*` into `CLEAR_WHO` (`:342`); `done` reads it.
```bash
cmd_done() {
  local who="$CLEAR_WHO" dir branch rows pr state tip pretip reg f rc=0
  [[ "$who" == station-* ]] || { echo "Usage: kitchen.sh done <station-N>" >&2; return 1; }
  dir="$KITCHEN/$who"; [[ -e "$dir/.git" ]] || { echo "No such station: $who" >&2; return 1; }
  command -v gh >/dev/null 2>&1 || { echo "done needs the gh CLI on your PATH, logged in." >&2; return 1; }
  branch="$(git -C "$dir" branch --show-current)"
  [[ -n "$branch" ]] || { echo "$who is already detached ($(git -C "$dir" rev-parse --short HEAD)): nothing to do."; return 0; }
  [[ -z "$(git -C "$dir" status --porcelain)" ]] || { echo "Not done: $who has uncommitted work on $branch." >&2; return 1; }
  reg="$(registry_of "$dir")"
  if [[ -n "$reg" && "$(json_str "$reg" status)" != idle ]]; then echo "Not done: $who ($(json_str "$reg" name)) is busy. Wait for its turn to end." >&2; return 1; fi
  rows="$(cd "$ROOT" && gh pr list --head "$branch" --state all --json number,state,headRefOid --jq '.[] | "\(.number) \(.state) \(.headRefOid)"' 2>/dev/null)" \
    || { echo "Not done: gh could not list PRs for $branch." >&2; return 1; }
  pr=""; while read -r n state tip; do [[ "$state" == MERGED ]] && { pr="$n"; pretip="$tip"; break; }; done <<<"$rows"
  [[ -n "$pr" ]] || { echo "Not done: no merged PR for $branch (${rows:-none found}). Only a merged ticket's branch is deleted." >&2; return 1; }
  [[ "$(git -C "$dir" rev-parse HEAD)" == "$pretip" ]] || { echo "Not done: $branch is at $(git -C "$dir" rev-parse --short HEAD), but merged PR #$pr ended at ${pretip:0:7}: the station has commits the PR does not. Push or park them first." >&2; return 1; }
  git -C "$dir" fetch --quiet origin "$TRUNK" && git -C "$dir" switch --quiet --detach "origin/$TRUNK" \
    || { echo "Not done: could not detach $who at origin/$TRUNK." >&2; return 1; }
  lstate=deleted; rstate="already gone"
  git -C "$dir" branch -D "$branch" >/dev/null 2>&1 || { lstate="NOT deleted"; rc=1; }
  if git -C "$dir" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    if git -C "$dir" push --quiet origin --delete "$branch" 2>/dev/null; then rstate=deleted
    else rstate="NOT deleted"; rc=1; echo "The remote delete of $branch did not happen (refused or failed); run: git push origin --delete $branch" >&2; fi
  fi
  for f in go check.log check.out grilling; do rm -f "$dir/.claude/$f"; done
  echo "$who: PR #$pr merged. detached at origin/$TRUNK ($(git -C "$dir" rev-parse --short HEAD)); local branch $branch: ${lstate}; origin branch: ${rstate}; per-ticket state cleared."
  return $rc
}
```
A re-run of a half-done `done` finds the station detached and says nothing to do, so a failed
remote delete prints the exact `git push origin --delete <branch>` for the sous to run. Dispatcher: add `done) cmd_done ;;`. Usage block: `done <station-N>`.
`cmd_ship`'s last echo gains "Then `kitchen.sh done <station>`."

### Success criteria
- [x] `scripts/check.sh` steps 1–3 pass
- [x] Manual (throwaway repo, stub gh): merged → branch gone locally and in the bare origin, `git -C station status` clean and detached; unmerged → refused, branch still there

### Limitations

- Auto mode has refused a `git push origin --delete` in the sous's session (classed "Git
  Destructive"). `done` therefore reports each step on its one summary line: `local branch …:
  deleted | NOT deleted`, `origin branch: deleted | already gone | NOT deleted`, and exits 1 with
  the exact command when the remote delete did not happen, so a refusal is visible, never silent.
  The station is already reset by then; only the remote branch is left, for the head chef or a
  permission rule. A test stubs a refused push and checks the line and the exit code.

## Phase 3: the hook, bk and the Window

**Status:** Done — `guard.sh`, `bin/bk`, the Window (`config.js`, `state.js`, `demo.js`, `web/main.js`, and two the plan missed that the inspector found: `live/index.js`, `web/ledger.js`).

### Changes

#### `plugins/bk/hooks/guard.sh:30-61` (edit)
Comment: the kitchen is the config's `kitchen:` or `../<repo>-stations`. Delete the clone walk
(`:41-47`); keep the common-dir block unconditional; the default test becomes
`[[ -n "$sibling" && "$kitchen" == "$sibling" ]] || exit 0`.

#### `bin/bk:246` (edit)
`for s in $(git -C "$ROOT" worktree list --porcelain … ) "$ROOT"/stations/station-*; do` loses
the `"$ROOT"/stations/station-*` glob (worktree list already names the stations).

#### `plugins/bk/window/server/live/config.js:40-41` (edit)
Drop `mode`: `kitchenRel = BRIGADE_KITCHEN || flat.kitchen || \`../${repo}-stations\``; remove `mode` from the returned object. `state.js:10`, `demo.js:7`: drop `mode`. `web/main.js:52`: `$('#mode').textContent = \`trunk ${s.kitchen.trunk}\`;`.

### Success criteria
- [x] `node --check` on the three Window files; `tests/window.test.sh` passes
- [x] `bash -n` + `shellcheck` on `guard.sh` and `bin/bk`

## Phase 4: the tests

**Status:** Done — `kitchen.test.sh` (569), `guard.test.sh` (27), `bk.test.sh` (85), `budget.test.sh` (115), `window-live.mjs` (+3, a config reader test the plan did not list).

### Changes

#### `tests/kitchen.test.sh:64-245` (edit)
Rename the section "worktree stations (the suite)"; `CS="$TMP/clone/app-stations"` (the repo stays
`$TMP/clone/app`); replace every `$C/stations` with `$CS`; swap clone-only assertions: stations
are worktrees (`.git` is a file), the `/stations/` gitignore line goes (a sibling folder outside any
repo needs none), the `git clean -fdx` warning is absent, the grilling line is in `$C/.git/info/exclude`,
`BRIGADE_KITCHEN_MODE=bogus` (`:229`) becomes `kitchen_mode: clone` refused with the one line.
`:990,993` configs drop `kitchen_mode: clone`; `:1006` becomes "remove with a legacy clone config"
(a made-up `stations/` folder is deleted, `status` refuses); `:1268` drops `rail_suite "clone"`.

#### `tests/kitchen.test.sh` new `section "done: a merged ticket's station is reset"` after ship (`:1004`)
Stub gh (`pr list --head`) answering `$GH_LIST`; a station on `issue-1-x` with a commit pushed to
the bare origin. Cases (each red without its check):
1. merged PR, tip equal → branch gone locally and on origin, station detached at `origin/main`, `check.log` and `grilling` gone, `.claude/cook` and `settings.local.json` kept;
2. PR `OPEN` → refused, branch survives local and remote;
3. PR `CLOSED` (not merged) → refused;
4. no PR → refused;
5. merged PR, local tip ahead of its head sha → refused, names both shas, branch survives;
6. dirty station → refused; busy session (fake registry as the `clear` tests) → refused;
7. detached station → "nothing to do", exit 0;
8. squash-style (PR head sha not on trunk) still passes;
9. no `station-N` argument → usage; unknown station → refused;
10. a refused `git push origin --delete` (a pre-push hook that fails): the summary says `origin branch: NOT deleted`, prints the command, exit 1, the station still reset.

#### `tests/guard.test.sh:33-66,84-86` (edit)
Remove the clone-mode station and its section; "a clone in the kitchen folder not named
station-*" and "named station-* outside the kitchen" become worktrees; keep the worktree section.

#### `tests/bk.test.sh:5,66-77` (edit) and `tests/budget.test.sh:63,384-408` (edit)
`bk.test.sh`: comment "two worktree stations"; `S1="$TMP/app-stations/station-1"`.
`budget.test.sh`: drop `kitchen_mode: clone\n` from the seven config writes.

### Success criteria
- [x] `tests/kitchen.test.sh`, `guard.test.sh`, `bk.test.sh`, `budget.test.sh` pass
- [x] Each new `done` test goes red when its check is removed (merged check, tip check, dirty check, busy check, remote delete), watched on a copy; the legacy-clone refusal test goes red without the refusal

## Phase 5: the contract, the skills and the docs

**Status:** Done — Contract 8, the sous-chef's End of shift (ship, done, reap, clear), line-cook, setup, kitchen, open-pr, feedback (+ issue template), README, PLAYBOOK, AGENTS.md, the fragment.

### Changes

#### `plugins/bk/skills/README.md:65,657-709` (edit), `:1012` (edit)
Contract 8 has one kind: drop the mode table, "Clone mode", the "Worktree mode" heading (its
bullets become the contract's body), "A config without `kitchen_mode:` is clone mode"; the config
example loses line 65; the skill table drops `[--worktree | --clone]`. "Both modes" becomes plain
text; add: "the sous reads stations and never writes in them, except `kitchen.sh done`, which
detaches a served station at trunk and deletes its merged branch"; "Removing a station keeps its
branch and commits" stays (it is about `remove`) and one sentence says what `done` deletes. A
sentence on End of shift order `ship → done → clear` lands in Contract 5 next to `clear`.

#### `plugins/bk/skills/sous-chef/SKILL.md:500-522` (edit)
End of shift: after the merge, step "Reset the station: `kitchen.sh done <station>`" (it refuses,
saying why, unless the PR is merged, the station is clean and its cook idle; a refusal is an
instruction), then (#86's reap), then `clear`. `:190` "Sync to `origin/<trunk>` and branch off it" stays.

#### `plugins/bk/skills/line-cook/SKILL.md:3,82-86,185-195` (edit)
Description and the "In a worktree station" paragraph: every station is a worktree; step 10 says
the sous runs `done` and then `clear`, and that after the merge the station is reset under you
(your branch is deleted: don't be on it).

#### `plugins/bk/skills/setup/SKILL.md`, `kitchen/SKILL.md`, `open-pr/SKILL.md`, `feedback/SKILL.md`, `.github/ISSUE_TEMPLATE/feedback.yml`, `README.md`, `PLAYBOOK.md`, `AGENTS.md` (edit)
`setup`: no `--clone`/`--worktree`, no clone/worktree detection, no `kitchen_mode` written, no
"stations/ clone-mode only" notes. `kitchen/SKILL.md`: the `setup`, `sync`, `remove` rows, a `done` row. `feedback`:
drop `kitchen_mode` from the gathered setup and the issue's version line; the issue template's
placeholder loses "clone". `README.md:9,93-103,271`, `PLAYBOOK.md:82-98`: one kind. `AGENTS.md:66,140-141`: test descriptions.

#### `changelog.d/85-worktrees-only.md` (new)
```
level: minor

**Breaking for kitchens on `kitchen_mode: clone`: stations are worktrees only.** ...
```
what changed (one kind of station; `done` after `ship`), what to do (clone kitchens: push or park
work, `kitchen.sh remove`, delete the `kitchen_mode` line, `kitchen.sh setup`; worktree kitchens:
nothing, the `kitchen_mode: worktree` line is ignored).

### Success criteria
- [x] `git grep -n -i -E 'kitchen_mode|clone mode|--clone|full clone' -- . ':!CHANGELOG.md' ':!changelog.d' ':!docs' ':!tests'` shows only the legacy refusal in `kitchen.sh` and its test
- [x] a fresh read-only sub-agent's consistency read of the contract against every skill lists no disagreement
- [x] `scripts/check.sh` is green (release check wants the fragment and no version bump)

## Testing

`tests/kitchen.test.sh` reaches `done` (ten cases above), the refusal for a clone config, `setup`
and `sync` as worktrees; `guard.test.sh` the one detection path; `bk.test.sh` that `bk` still opens
and pauses worktree stations; `budget.test.sh` that configs without a mode line still read. Each
new behaviour test is made red once on a copy before it is trusted.

## References

- Ticket #85, `docs/journal/85-worktrees-only.md`
- `kitchen.sh:2202-2230` (`cmd_ship`: the shape), `:2133-2200` (`cmd_clear`: `registry_of`), `:658-680` (the worktree add)
- `tests/kitchen.test.sh:968-1004` (ship's gh stub), `:1013-1065` (the worktree/workspace section to follow)
- #86 (station-1, `docs/plans/86-kitchen-procs.md`): shares `kitchen.sh`, `tests/kitchen.test.sh`, the contract, line-cook, sous-chef, handoff; adds `procs --reap` after `ship`
- #89 (`clear` vs a served cook on trunk): see Approach
