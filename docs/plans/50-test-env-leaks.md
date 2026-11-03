---
ticket: "#50"
title: tests/kitchen.test.sh is safe inside a kitchen: seal the env, pick a free port for the Window test
status: done
approved: 2026-11-03
lane: B
created: 2026-11-03
open_questions: none
migration: false
files:
  - tests/kitchen.test.sh
  - tests/bk.test.sh
  - changelog.d/50-test-env-leaks.md
  - docs/journal/50-test-env-leaks.md
  - docs/plans/50-test-env-leaks.md
  - docs/checklists/50-test-env-leaks.md
---

# #50 — tests/kitchen.test.sh is safe inside a kitchen

## Why

`scripts/check.sh` fails 7 tests of `tests/kitchen.test.sh` when run from any session `bk open`
started, because `bin/bk:252` exports `BRIGADE_CLAUDE_ARGS` and `BRIGADE_VIA_BK` into the
kitchen's sessions, which run inside tmux (`TMUX`, `TMUX_PANE`), and the suite doesn't unset them.
Its Window test also binds a fixed port (47471), so two gates at once collide. Every gate in
this kitchen is relayed by hand with `env -u …` until both are fixed.

## Current state

At `origin/main` 70e1d1c:

- `tests/kitchen.test.sh:27-28` unsets `CLAUDE_CONFIG_DIR` and the `BRIGADE_*` config vars, but not
  `BRIGADE_CLAUDE_ARGS`, `BRIGADE_VIA_BK`, `TMUX`, `TMUX_PANE`. `kitchen.sh` reads three of them:
  `extra_args()` at `kitchen.sh:378` (`BRIGADE_CLAUDE_ARGS`, added to every launch line),
  `kitchen.sh:849,852` (`BRIGADE_VIA_BK`, picks the `bk …` hints) and `kitchen.sh:850` (`TMUX`, picks
  `tmux switch-client` over `tmux attach`). `TMUX_PANE` isn't read by any script here; it goes with
  `TMUX` because tmux sets both.
- `tests/bk.test.sh:27-28` unsets `BRIGADE_CLAUDE_ARGS` and `TMUX`, not `BRIGADE_VIA_BK` or
  `TMUX_PANE`. `bin/bk:184` reads `TMUX`; `bin/bk:252` sets `BRIGADE_VIA_BK` itself for `open`.
- `tests/budget.test.sh:24`, `tests/guard.test.sh`, `tests/release.test.sh`, `tests/window.test.sh`
  unset none of the four, and no code they run reads them (`kitchen.sh budget`, `guard.sh`,
  `release*.sh` and the Window's reader never touch them: grepped).
- `tests/kitchen.test.sh:346-362`, the `live (the Window)` section, starts `live --demo --port
  47471` and uses 47471 in six places (lines 346, 348, 350, 352-354, 362). The server binds
  `127.0.0.1` (`plugins/bk/window/server/index.js:84`); `kitchen.sh live` records the port in
  `.claude/window.pid` (`kitchen.sh:2044`) and `live status` reads it back (`kitchen.sh:2021-2023`).

## Desired end state

`scripts/check.sh` is green when run from inside a `bk open` session, and two of them at once
don't collide on a port. Proof: the 7 tests (59, 60, 107, 109, 115, 116, 123) fail in such a
session with the new unset block removed, pass with it; two `tests/kitchen.test.sh` running at
once both pass.

## Not doing

- No new env guard in `kitchen.sh` itself: the leak is the tests' (a real `open` inside tmux is
  supposed to read `TMUX`).
- No unsets in `budget`, `guard`, `release`, `window` suites: no code they run reads these vars,
  so nothing can fail there (checked, above). If one starts to, that test adds its own.
- No change to any other section of `tests/kitchen.test.sh`: station-2 (#65) edits it too.

## Approach

Follow the precedent the commis found: each suite seals itself at the top (`tests/bk.test.sh:24-28`
is the fullest). Add the four names to `kitchen.test.sh`'s unset line, and top up `bk.test.sh`'s.

For the port, ask the OS for a free one once per run, in the Window section, and use it in place
of the literal: `node -e 'const s=require("net").createServer();s.listen(0,"127.0.0.1",()=>{console.log(s.address().port);s.close()})'`.
That block only runs when `node` exists (`kitchen.test.sh:344`), and the Window needs node, so
this adds no dependency. Two runs ask at nearly the same time and the OS hands out different
ports; the gap between `close` and the server's bind is tiny and a collision there fails
loudly, not wrongly.

## Decisions

### Changes the ticket

None.

### How

- **Where the free port comes from: the OS, via node, not a port derived from the temp dir.**
  A derived port (a hash of `$TMP` into a range) can still hit a port something else holds;
  asking the OS (`listen(0)`) can't. The ticket allows either ("a free port, or one derived
  from the temp dir"). The commis found nothing recorded on it.
- **Which names: `BRIGADE_CLAUDE_ARGS BRIGADE_VIA_BK TMUX TMUX_PANE`**, the ticket's four, appended
  to the existing line-wrapped `unset`.
- **The port variable is `WPORT`**, set at the top of the Window section, inside the
  `command -v node` branch, so a machine without node never calls node.
- **`bk.test.sh` gets `BRIGADE_VIA_BK` and `TMUX_PANE` added** to its existing unset; it has the
  other two already. No behaviour changes there today (`bin/bk` sets `BRIGADE_VIA_BK` itself), it
  just closes the gap the ticket asks to check.

## Phase 1: Seal the env

**Status:** Done

### Changes

#### `tests/kitchen.test.sh:27-28` (edit)

```bash
unset CLAUDE_CONFIG_DIR BRIGADE_TRUNK BRIGADE_KITCHEN BRIGADE_KITCHEN_MODE BRIGADE_STATIONS \
  BRIGADE_MODEL BRIGADE_PERMISSION_MODE BRIGADE_TERMINAL BRIGADE_OS \
  BRIGADE_CLAUDE_ARGS BRIGADE_VIA_BK TMUX TMUX_PANE
```

#### `tests/bk.test.sh:27-28` (edit)

```bash
unset CLAUDE_CONFIG_DIR BRIGADE_TRUNK BRIGADE_KITCHEN BRIGADE_KITCHEN_MODE BRIGADE_STATIONS \
  BRIGADE_MODEL BRIGADE_PERMISSION_MODE BRIGADE_TERMINAL BRIGADE_OS BRIGADE_CLAUDE_ARGS \
  BRIGADE_VIA_BK TMUX TMUX_PANE BK_PLUGIN_DIR
```

### Success criteria

- [x] `bash -n tests/kitchen.test.sh tests/bk.test.sh` and `shellcheck -S warning` (the gate's level) pass; plain `shellcheck` info notes: 105 on main, 106 now, the gate ignores them
- [x] In this `bk open` session (the four set), `tests/kitchen.test.sh` and `tests/bk.test.sh` pass (via `kitchen.sh check`, cleared by the sous): 409 and 82
- [x] Proved able to fail: with the kitchen.test.sh unset line reverted on a COPY of the file outside the checkout (the lesson from #64), the same run goes red on 59, 60, 107, 109, 115, 116, 123

## Phase 2: A free port for the Window test

**Status:** Done

### Changes

#### `tests/kitchen.test.sh:343-362` (edit, the `live (the Window)` section only)

At the top of the node branch (after `if command -v node …; then`, line 344), pick the port:

```bash
  # a free port from the OS, so two suites running at once (two stations' checks) don't collide
  WPORT=$(node -e 'const s=require("net").createServer();s.listen(0,"127.0.0.1",()=>{console.log(s.address().port);s.close()})')
```

Then replace the literal `47471` with `$WPORT` at lines 346, 348, 350, 352, 353, 354 and 362. Lines
that sit in single quotes or a `bash -c` string pass it as an argument instead:

```bash
  out=$("$K" live --demo --port "$WPORT" --no-launch 2>&1); rc=$?
  ok "…and prints its URL" has "$out" "http://localhost:$WPORT"
  read -r wpid wport < "$C/.claude/window.pid"
  ok "…and records a live pid and the port" bash -c 'kill -0 "$1" && test "$2" = "$3"' _ "$wpid" "$wport" "$WPORT"
  for _ in $(seq 1 30); do curl -sf "http://localhost:$WPORT/api/state" >/dev/null 2>&1 && break; sleep 0.5; done
  ok "…and it serves the kitchen's state" bash -c 'curl -sf "http://localhost:$1/api/state" | grep -q "\"stations\""' _ "$WPORT"
  ok "live status says open" has "$("$K" live status)" "open: http://localhost:$WPORT"
  ...
  echo "99999999 $WPORT" > "$C/.claude/window.pid"
```

### Success criteria

- [x] `grep -n 47471 tests/kitchen.test.sh` prints nothing
- [x] `shellcheck tests/kitchen.test.sh` passes
- [x] The Window section's 12 tests pass alone: `tests/kitchen.test.sh` filtered to it, or the full run
- [x] Two `tests/kitchen.test.sh` at once, started within a second (`& wait`), both pass (the sous clears it: a full run twice) (batch 2: 409/409 and 408/409, the one red being the known flake #84 in the tmux stubs, test 124; batch 2b: both 409/409)
- [x] Proved able to fail: put the literal 47471 back on a COPY and run two copies at once: one fails on "live --demo opens the Window" (as station-1 saw on 2026-10-25)

## Phase 3: The fragment

**Status:** Done

### Changes

#### `changelog.d/50-test-env-leaks.md` (new)

```
level: patch

The test suite now runs green from inside a kitchen (a session `bk open` started): it no longer
picks up `bk`'s launch flags or tmux's variables, and its Window test asks the OS for a free port,
so two stations' checks at once don't collide. You don't need to run the gate with `env -u …` any
more. Nothing else changes for you.
```

### Success criteria

- [x] `scripts/check.sh` passes (the release check wants exactly this fragment and no version bump)

## Testing

The change is the tests. `tests/kitchen.test.sh` is run (a) in this kitchen session unmodified
by env, (b) with the unset removed on a copy (red), (c) twice at once (both green), (d) twice
at once with the literal port on a copy (one red). Each full run is cleared with the sous first.

## References

- Ticket: GitHub issue #50 (its three comments: triage 2026-10-25, the 2026-11-03 collision evidence)
- Precedent: `tests/bk.test.sh:24-28`
- `bin/bk:184,252`; `plugins/bk/skills/kitchen/kitchen.sh:378,849-852,2021-2044`
- Lesson from #64: mutate a COPY outside the checkout, never the live file
