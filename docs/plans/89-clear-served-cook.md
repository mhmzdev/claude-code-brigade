---
ticket: "#89"
title: kitchen.sh clear passes a served cook on trunk, and no longer trusts a journal's mtime alone
status: done
approved: 2026-11-03
lane: B
created: 2026-11-03
open_questions: none
migration: false
files:
  - plugins/bk/skills/kitchen/kitchen.sh
  - tests/kitchen.test.sh
  - plugins/bk/skills/README.md
  - plugins/bk/skills/kitchen/SKILL.md
  - plugins/bk/skills/sous-chef/SKILL.md
  - plugins/bk/skills/line-cook/SKILL.md
  - PLAYBOOK.md
  - changelog.d/89-clear-served-cook.md
---

# #89 — `clear` passes a served cook on trunk

## Contents

- [Why](#why)
- [Current state](#current-state)
- [Desired end state](#desired-end-state)
- [Not doing](#not-doing)
- [Approach](#approach)
- [Decisions](#decisions)
- [Phase 1: done leaves a marker, clear reads it](#phase-1-done-leaves-a-marker-clear-reads-it)
- [Phase 2: the mid-ticket proof is more than an mtime](#phase-2-the-mid-ticket-proof-is-more-than-an-mtime)
- [Phase 3: the tests](#phase-3-the-tests)
- [Phase 4: the contract, the skills and the fragment](#phase-4-the-contract-the-skills-and-the-fragment)
- [Testing](#testing)
- [References](#references)

## Why

`kitchen.sh clear <station>` refuses a cook whose handoff is "older than its last turn". A
cook that has been served and merged has nothing left to hand off: its closing handoff is
already on trunk. But the cook answers the sous's ack, and that answer is a new turn, so the
check can never pass again. The check also reads only a file's mtime, which a `git checkout`
refreshes. Hit twice on station-2 on 2026-11-03 (after #65 and #85).

## Current state

- `cmd_clear` step 2 (`plugins/bk/skills/kitchen/kitchen.sh:2481-2487`) takes `newest_handoff
  "$dir"` and refuses unless `mtime_ms(handoff) >= lastTurnStart`.
- `newest_handoff` (`kitchen.sh:2383-2391`) scans **every** journal in the station with a
  `## Handoff`, newest mtime wins. On trunk that is every ticket's journal ever merged, and a
  checkout/reset gives them all a fresh mtime.
- Step 3 (`kitchen.sh:2489-2495`) refuses an `open` `[gate]`/`[plan]`/`[handoff]`/`[walk-in]`
  (from `session-state.js`, `WAITS`). `[served]` is not one: a served cook is not "waiting".
- `cmd_done` (`kitchen.sh:2574-2634`) verifies the PR merged into trunk, detaches the station
  at `origin/<trunk>` (`:2301`) and deletes the branch. After it nothing in the station says
  which ticket was served: `.claude/here` says `ticket: -` once the cook reruns `here`, and
  the branch is gone.
- `branch_ticket` (`kitchen.sh:1549`) maps a branch to its ticket id (`issue-89-…` → `#89`).
  Journals are `<docs.journal>/<id-without-#>-<slug>.md` (`89-clear-served-cook.md`,
  `BKLG-001-open.md`).

## Desired end state

- A cook that is **served** passes the handoff check whatever its last turn: its station is
  clean, detached at (or behind) `origin/<trunk>`, `done` recorded the ticket and PR it
  served, and that ticket's journal **committed at HEAD** carries a `## Handoff`. The proof
  is git's, not an mtime.
- A mid-ticket cook still needs a handoff newer than its last turn, now proved twice: the
  newest `## Handoff — YYYY-MM-DD HH:MM` heading's own stamp. The file's mtime counts only
  as the fallback for a handoff with no stamp (an older journal). A checkout that refreshes
  an old journal's mtime no longer passes.
- Unchanged: busy → refused; an open `[gate]`/`[plan]`/`[handoff]`/`[walk-in]` → refused, for
  a served cook too; the sous's own clear.
- Verify: `tests/kitchen.test.sh` (new cases red on `origin/main`, green here), `scripts/check.sh`.

## Not doing

- No change to `session-state.js`, to what counts as a turn or as `open`.
- No `gh` call in `clear` (it stays script-local; `done` already proved the merge).
- Not clearing the marker when a cook starts its next ticket: `clear` only trusts it while
  the station is detached, clean and at trunk, and the next `done` overwrites it.
- The sous's own `clear sous` path (`.claude/sous-handoff.md`) is untouched.

## Approach

`cmd_done` is the one place that knows a ticket was served and merged, so it leaves a small
marker, `<station>/.claude/served` (kept out of git through `exclude_locally`, like
`.claude/here`): `ticket:`, `branch:`, `pr:`, `at:`. `clear` reads it for a cook:

```
served  ⇔  marker present
         ∧ station detached ∧ clean
         ∧ HEAD is an ancestor of (or equal to) origin/<trunk>
         ∧ the marker's ticket has a journal at HEAD (git ls-tree) whose blob has "## Handoff"
```

When that holds the handoff step passes (no mtime, no last turn); step 3 (nothing waiting) and
the idle check still apply. When it does not, the existing mtime check runs, now stricter
(Phase 2). This follows the issue's own suggestion ("the trunk copy"), reuses `branch_ticket`,
`exclude_locally`, `cfg_docs` and the `mtime_ms` GNU-then-BSD trick.

## Decisions

### Changes the ticket

None.

### How

- **A marker written by `done`, not a reflog or `gh` lookup.** The branch is gone after `done`;
  the reflog is per-worktree and brittle; `done` already holds the ticket, branch and PR.
- **The marker's name is `.claude/served`**, beside `here`, `go`, `check.log`; machine-local.
- **The journal is found by the ticket id** (`<id-without-#>-*.md`, case-insensitive) in
  `git ls-tree HEAD <docs.journal>/`, so the proof is the committed blob, not a file in the
  working tree.
- **Stamp slack of 59 s** in the mid-ticket stamp check: the heading is minute-precision, and
  the handoff is written *during* the last turn, so `stamp + 59 s >= lastTurnStart` is a
  necessary condition for "written in the last turn". Stricter would refuse real handoffs.
- **The stamp is the proof; the mtime is only the fallback** (the sous's amendment, 2026-11-03):
  a `## Handoff` heading with a parseable stamp is compared against the last turn and the mtime
  is not read; only a handoff with no stamp (an older journal) falls back to the mtime check,
  because a `git checkout` refreshes the mtime, which is the case this ticket names.
- **Mid-ticket, the ticket's own journal is preferred** to the newest journal anywhere
  (`newest_handoff` keeps its scan as the fallback when the branch carries no ticket).

## Phase 1: done leaves a marker, clear reads it

**Status:** Done

### Changes

#### `plugins/bk/skills/kitchen/kitchen.sh:2601` (edit) — `cmd_done` writes the marker (after #91: next to `rm -f "$(grant_file …)"` at :2630, not before it)

After the `switch --detach` succeeds, before `lstate=deleted`:

```bash
  # what was served, for `clear`: the branch is about to be gone (#89). Kept out of git like .claude/here.
  mkdir -p "$dir/.claude"; exclude_locally .claude/served "$dir"
  printf 'ticket: %s\nbranch: %s\npr: %s\nat: %s\n' "$(branch_ticket "$branch")" "$branch" "$pr" "$(date +%s)" > "$dir/.claude/served"
```

#### `plugins/bk/skills/kitchen/kitchen.sh:2383` (edit) — add `served_handoff` next to `newest_handoff`

```bash
served_handoff() {  # served_handoff <station> → the journal path at HEAD holding the served ticket's "## Handoff", or exit 1
  local dir="$1" f ticket id jdir path want
  f="$dir/.claude/served"; [[ -f "$f" ]] || return 1
  ticket="$(sed -n 's/^ticket: //p' "$f" | head -1)"; id="${ticket#\#}"
  [[ -n "$id" && "$id" != - ]] || return 1
  [[ -z "$(git -C "$dir" branch --show-current)" ]] || return 1             # on a ticket branch: mid-ticket
  [[ -z "$(git -C "$dir" status --porcelain)" ]] || return 1                # unfinished work
  git -C "$dir" merge-base --is-ancestor HEAD "origin/$TRUNK" 2>/dev/null || return 1
  want="$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')"
  jdir="$(cfg_docs journal docs/journal)"
  while IFS= read -r path; do
    case "$(basename "$path" | tr '[:upper:]' '[:lower:]')" in "$want"-*.md) ;; *) continue ;; esac
    git -C "$dir" show "HEAD:$path" 2>/dev/null | grep -q '^## Handoff' && { echo "$path"; return 0; }
  done < <(git -C "$dir" ls-tree --name-only HEAD "$jdir/")
  return 1
}
```

#### `plugins/bk/skills/kitchen/kitchen.sh:2460-2487` (edit) — `cmd_clear` step 2

Declare `served` in the `local` line. Replace step 2's handoff block (for a cook) with:

```bash
  tr="$(transcript_of "$reg")" || …            # unchanged: the transcript is still needed for step 3
  state="$(session_state "$tr")" || …
  last_turn=…
  if [[ "$who" != sous ]] && served="$(served_handoff "$dir")"; then
    :   # served and merged, clean on trunk, handoff committed: nothing to hand off, whatever the last turn
  else
    <the existing no-handoff / mtime check, then the stamp check from Phase 2>
  fi
```

Also update the `clear` header comment (`kitchen.sh:99-103 (check)`) and the block comment at `:2093`.

### Success criteria

- [x] `bash -n plugins/bk/skills/kitchen/kitchen.sh` and `shellcheck` clean
- [x] Manual: `done` in a throwaway station leaves `.claude/served` with `ticket: #N`

## Phase 2: the mid-ticket proof is more than an mtime

**Status:** Done

### Changes

#### `plugins/bk/skills/kitchen/kitchen.sh:2383` (edit) — `newest_handoff` prefers the ticket's journal

```bash
newest_handoff() {  # newest_handoff <station> → the station's journal with a "## Handoff": its ticket's, else the newest
  local f best="" best_t=0 t id jdir; jdir="$1/$(cfg_docs journal docs/journal)"
  id="$(branch_ticket "$(git -C "$1" branch --show-current 2>/dev/null)")"
  if [[ "$id" != - ]]; then
    for f in "$jdir/${id#\#}"-*.md; do [[ -f "$f" ]] && grep -q '^## Handoff' "$f" && { echo "$f"; return 0; }; done
  fi
  … existing scan over "$jdir"/*.md …
}
```

#### `plugins/bk/skills/kitchen/kitchen.sh:2383` (edit) — `handoff_stamp`

```bash
handoff_stamp() {  # handoff_stamp <journal> → epoch seconds of its newest "## Handoff — YYYY-MM-DD HH:MM" heading (local time, as /bk:handoff stamps it), or exit 1
  local s
  s="$(sed -nE 's/^## Handoff[^0-9]*([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}).*/\1/p' "$1" | tail -1)"
  [[ -n "$s" ]] || return 1
  date -d "$s:00" +%s 2>/dev/null || date -j -f '%Y-%m-%d %H:%M:%S' "$s:00" +%s 2>/dev/null   # GNU first, then BSD
}
```

#### `plugins/bk/skills/kitchen/kitchen.sh:2486-2487` (edit) — the stamp first, the mtime as fallback (a cook)

```bash
    stamp=""; [[ "$who" != sous ]] && stamp="$(handoff_stamp "$handoff")"
    if [[ -n "$stamp" ]]; then
      (( stamp * 1000 + 59999 >= last_turn )) || { echo "Not cleared: $who's newest handoff section is stamped before its last turn (the file may only have been touched since, e.g. by a checkout). Ask it for /bk:handoff first." >&2; return 1; }
    else   # no dated heading (an older journal), and the sous's note: the mtime is all there is
      hmtime="$(mtime_ms "$handoff")"
      (( hmtime >= last_turn )) || { echo "Not cleared: $who's handoff ($handoff) is older than its last turn. Ask it for /bk:handoff first." >&2; return 1; }
    fi
```

### Success criteria

- [x] `shellcheck -S info` on `kitchen.sh` adds no finding (the `shellcheck-info` counter does not rise)
- [x] the existing clear tests, updated for the stamp (Phase 3), pass

## Phase 3: the tests

**Status:** Done

### Changes

#### `tests/kitchen.test.sh:902-941` (edit) — the existing clear section carries stamps

Run the clear calls with `TZ=UTC` (transcript times are `Z`). The fixture handoff heading becomes
`## Handoff — 2026-01-01 10:05 · app-cook-1` for the passing cases (the refusal case keeps 09:00,
refused as "stamped before its last turn"). New cases: a journal **checked out after the last
turn** (fresh mtime) with a 09:00 stamp → refused (the case the ticket names); a heading with no
stamp and a fresh mtime → clears (fallback); a heading with no stamp and an old mtime → refused,
"older than its last turn".

#### `tests/kitchen.test.sh` after the `done` section (new) — `section "clear: a served cook on trunk"`

Guarded by `command -v node`, reusing `reg`, `tline`, `txt`, `snd`, `slug`, `$TB`, `$REG` from
the clear section and the `done` fixture (`$D`, `$DS`, `$D2`, `$DG`, `done_`):

1. In station-2: branch `issue-5-served`, commit `docs/journal/5-served.md` with a `## Handoff`,
   push, `update-ref` origin's `main` to the tip, `done_ "9 MERGED $tip main" station-2`.
   Register an idle cook there, transcript with a last turn at `2099-01-01` (after the journal's mtime).
2. Cases (each runs `clear station-2`):
   - served, last turn newer than the journal's mtime → **clears** (typed `/clear` then `/bk:line-cook` into its pane). Red on `origin/main`: "older than its last turn".
   - …with a `[gate]` sent and unanswered → refused, "waiting on an answer".
   - marker removed (a cook that never went through `done`) → refused, "older than its last turn".
   - marker names a ticket with no journal on trunk (`ticket: #6`) → refused.
   - an untracked file in the station → refused.
   - the cook back on a ticket branch with the marker still there (`issue-6-wip`) → refused.
3. Clean up the sessions and `$REG`.

### Success criteria

- [x] `tests/kitchen.test.sh` passes
- [x] On `origin/main`'s `kitchen.sh` (copied into place for one run): 11 tests fail (the served case, the stamp cases, the marker); breaking `served_handoff`'s dirty or branch check turns the dirty and new-branch cases red

## Phase 4: the contract, the skills and the fragment

**Status:** Done

### Changes

#### `plugins/bk/skills/README.md:756-761` and `:840-844` (edit) — Contract 5/11 wording

"refuses unless the cook is idle, its handoff is newer than its last turn and nothing it sent
still waits" gains: *"(a cook that is served and merged, back on trunk, clean, with its closing
handoff committed there needs no newer one: `kitchen.sh done` records what it served, and `clear`
reads the handoff from trunk, so an ack after the handoff doesn't undo it)"*; and the proof of a
handoff is its own dated heading as well as the file's mtime.

#### `plugins/bk/skills/kitchen/SKILL.md:36`, `sous-chef/SKILL.md:552-554` (and `:282`), `PLAYBOOK.md:330-332`, `line-cook/SKILL.md:196` (edit) — same sentence

Each says "handoff newer than its last turn": add the served-on-trunk case; the sous-chef step
says the order is `ship`, `done`, then `clear`.

#### `changelog.d/89-clear-served-cook.md` (new)

```
level: patch

`kitchen.sh clear` now clears a cook that has been served and merged ...
```

### Success criteria

- [x] `git grep -n "newer than its last turn" -- ':!docs' ':!tests'` lists only places that carry the served case
- [x] `scripts/check.sh` passes (the release check wants the fragment): `kitchen.sh check` green

## Testing

`tests/kitchen.test.sh` is the only suite touched: the clear section (stamps) and the new served
section. They reach `served_handoff`, `handoff_stamp`, `newest_handoff`'s ticket preference and the
`done` marker through the real `kitchen.sh` with a stub `tmux`, a fake registry and handmade
transcripts; no runner is added. Each new case is made to fail once (Phase 3 criteria).

## References

- Issue #89; #58 (`clear`) `docs/journal` / `docs/plans/58-*` if present; #85 (`done`), `docs/plans/85-worktrees-only.md`
- `kitchen.sh`: `cmd_clear:2161`, `newest_handoff:2139`, `mtime_ms:2104`, `cmd_done:2273`, `branch_ticket:1305`, `exclude_locally:629`
- `plugins/bk/window/server/live/session-state.js:20-47` (`lastTurnStart`, `open`)
