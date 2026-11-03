---
ticket: "#50"
title: tests/kitchen.test.sh is safe inside a kitchen: seal the env, pick a free port for the Window test
plan: docs/plans/50-test-env-leaks.md
last_verified: 2026-11-03
---

# Acceptance — #50 tests/kitchen.test.sh is safe inside a kitchen

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

### The gate, run from inside a `bk open` session

1. Session has `BRIGADE_CLAUDE_ARGS`, `BRIGADE_VIA_BK`, `TMUX`, `TMUX_PANE` set → `kitchen.sh check` runs `scripts/check.sh` → all six suites green (kitchen 409, guard 27, bk 82, budget 92, window 22, release 45).

### Two checks at once

1. Two `tests/kitchen.test.sh` started together → each asks the OS for its own port → both finish, no port collision.

## Edge cases

- A machine without `node` → the Window section is skipped as before, and `WPORT` is never read (the node call sits inside the `command -v node` branch, `tests/kitchen.test.sh:345-347`).
- The OS-picked port is closed before the Window binds it, so a collision in that gap is possible but not seen in 6 concurrent runs → it would show as EADDRINUSE in the journal, not a wrong pass.

## Acceptance criteria

- [x] `tests/kitchen.test.sh` unsets `BRIGADE_CLAUDE_ARGS`, `BRIGADE_VIA_BK`, `TMUX`, `TMUX_PANE` — `tests/kitchen.test.sh:28-29`
- [x] `tests/bk.test.sh` has the same four — `tests/bk.test.sh:27-29` (it had two of them)
- [x] `tests/budget.test.sh`, `guard`, `release`, `window` checked and left alone: no code they run reads these variables (grep of `plugins/bk/hooks/guard.sh`, `scripts/`, `plugins/bk/window/` found only `control.js` looking for a tmux binary, not the variables) — journal, plan "Not doing"
- [x] The gate is green inside a `bk open` session — `kitchen.sh check` ran green (168s) in this session with all four set: 409/27/82/92/22/45, v0.33.0. The tree has only docs edits since (plan ticks, journal, checklist, INDEX rows), so the sous's taster re-runs for the exact tree
- [x] Proven able to fail (env): the unset block removed on a COPY outside the checkout, run in this session, goes red on exactly 59, 60, 107, 109, 115, 116, 123 (402/409) — journal, batch 1
- [x] The Window test picks a free port, not 47471 — `tests/kitchen.test.sh:347` (`WPORT`), used at 349, 351, 353, 355, 356, 357, 365; `grep -c 47471 tests/kitchen.test.sh` prints 0
- [x] Two suites at once don't collide — 6 concurrent runs of the real suite, 0 Window failures (batch 2: 409/409 and 408/409; batch 2b: 409/409 ×2); the one red, test 124 in the tmux stubs, is the known flake #84
- [x] Proven able to fail (port): the literal 47471 back on a COPY, two at once, one run red on 131 "live --demo opens the Window" and 132 "…and prints its URL" and aborted at `wpid: unbound variable` — journal, batch 3
- [x] A `level: patch` fragment and no version bump — `changelog.d/50-test-env-leaks.md`; the gate's release check passes (step 5: "1 change(s) on main wait for a release", v0.33.0)
- [?] After merge, a gate run from a station (no `env -u …`) is green — run `kitchen.sh check` in the next station that opens after the release; expect green. Post-merge observation.
- [?] Test 124 flakes under load again — if so it is #84, not this ticket. Post-merge observation.

## Known limitations

- Test 124 ("…without a second sous window") flaked once in 4 runs of the real suite (batch 2 run A, two at once); filed as #84 (`list-windows | grep -qx` under pipefail, `kitchen.sh:831/:840`). Not caused by this change and not fixed here.
- `TMUX_PANE` is unset with `TMUX` because tmux sets both; no script here reads it.
- The OS-picked port has a small window between close and bind (the sous noted it); no collision was seen.
