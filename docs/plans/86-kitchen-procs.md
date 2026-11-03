---
ticket: "#86"
title: "kitchen.sh procs: the kitchen registers, reaps and scans the processes it started; never a system or unknown process"
lane: B
status: done
approved: 2026-11-03
open_questions: none
migration: false
files:
  - plugins/bk/skills/kitchen/kitchen.sh
  - bin/bk
  - tests/kitchen.test.sh
  - tests/bk.test.sh
  - plugins/bk/skills/README.md
  - plugins/bk/skills/line-cook/SKILL.md
  - plugins/bk/skills/implement/SKILL.md
  - plugins/bk/skills/handoff/SKILL.md
  - plugins/bk/skills/sous-chef/SKILL.md
  - plugins/bk/skills/kitchen/SKILL.md
  - plugins/bk/agents/taster.md
  - plugins/bk/agents/runner.md
  - plugins/bk/templates/journal.md
  - PLAYBOOK.md
  - changelog.d/86-kitchen-procs.md
created: 2026-11-03
---

# Plan — #86 kitchen.sh procs: register, reap, scan

## Contents

- [Goal](#goal)
- [Current state](#current-state)
- [Approach](#approach)
- [Decisions](#decisions)
- [Phases](#phases)
- [Success criteria](#success-criteria)
- [Risks](#risks)

## Goal

A cook that starts a dev server, a watcher or a poll registers it the moment it starts, and
stops it before `[handoff]`. The sous reaps whatever is still registered after `ship` and
before `clear`, `bk stop` reaps every station before the pause, and `kitchen.sh procs --scan`
reports (never kills) processes standing in a station that nobody registered. The reap kills
only a registered pid that is still the same process (start time and command line match) and
is not a kitchen session; it never touches a system or an unknown process. Handoffs carry
what is still running.

## Current state

- Nothing in the kitchen knows a background process exists. `git grep -i 'procs|orphan|reap'`
  at `origin/main` (be9c13a) finds nothing in `plugins/`, `bin/`, `tests/` or `docs/`; the
  commis found no recorded decision on it (journal `86-kitchen-procs.md`, A1).
- The pieces to reuse:
  - `claude_cwds` (`kitchen.sh:535`) finds a process's cwd from `/proc/<pid>/cwd`, else
    `lsof -a -p <pid> -d cwd -Fn`, and tells a claude session by its program or its
    interpreter's script (`${a1##*/} == claude`).
  - `busy` (`kitchen.sh:545`) tests a cwd against a station dir.
  - `exclude_locally <path> [checkout]` (`kitchen.sh:556`) keeps a machine-local file out of
    git; `.claude/cook-session` and `.claude/window.pid` already use it.
  - `stations` (`kitchen.sh:331`) lists the station dirs; `KITCHEN` is their folder.
  - The Window's pid file (`cmd_live`, `kitchen.sh:2018-2047`) is the one pid-file pattern, and
    it kills with no identity check (`kill "$pid"`): not a precedent to copy.
- Parser: the `while` loop at `kitchen.sh:289-322` owns `--add`, `--ticket`, `--ci`, `--check`,
  `stop|status`, and rejects an unknown flag. A second `--add <pid> "<what>"` would clash with
  `--add <text>` (inbox, asks), so `procs` takes its own arguments before that loop.
- Dispatcher: the last `case "$CMD"` (`kitchen.sh:2092-2100`). Board: `cmd_board`
  (`kitchen.sh:999-1015`), one line per record count.
- `bk stop` (`bin/bk:273-348`): handoff typed into every pane (1), wait for idle (2), save
  session ids (3), `/exit` and wait (4), kill the tmux session, close the Window.
- Skills: the line-cook loop (`line-cook/SKILL.md:158-190`, step 7 is the `[handoff]`),
  `implement` step 2 (`implement/SKILL.md:84-93`, the walk-in at item 2), the cook handoff
  (`handoff/SKILL.md:40-62`) and sous handoff (`:64-`), the sous's End of shift
  (`sous-chef/SKILL.md:491-513`), Contract 7 (`README.md:613-624`) and the handoffs in
  Contract 11 (`README.md:775-790`).

## Approach

One new command, `kitchen.sh procs`, in new functions; the skills say when to call it.

**The register** is `<station>/.claude/procs`, kept out of git with `exclude_locally`. One
line per process, tab-separated: `pid · start · command · what · ticket · added`. `start` is
`ps -ww -o lstart= -p <pid>` (the same text on macOS and Linux, whitespace squeezed) and
`command` is `ps -ww -o command= -p <pid>`, both read at `--add` time. A process whose start
time or command `ps` cannot print is refused: if we cannot identify it, we do not register it.

**The identity check** (reap, and the state shown in the list) compares a line against
`ps` now: no such pid → `dead`; pid alive but a different start time or command → `reused`
(the pid went to someone else); the same → `alive`.

**What is never registered or reaped** (`procs_protected <pid> <command>`): pid 1 or below
2; not owned by the caller; the caller or one of its ancestors (the shell running the
command, the claude session above it); a kitchen session, by command: a program or an
interpreter script named `claude`, `tmux`, or a login shell (argv0 starts with `-`) or a shell whose
parent is `tmux` (the pane's shell). `--add` refuses these with the reason; `--reap` leaves
them alone and prints them.

**The reap** (`procs --reap <station-N|all>`) walks the station's register: `alive` and not
protected → `kill -TERM`, poll `kill -0` for 5 s, then `kill -KILL`; the line moves to
`<station>/.claude/procs.log` as `<date> reaped <pid> <what> (term|kill)`. `dead` lines
are dropped with a note; `reused` and protected lines are left in the register and printed
as `skipped`. It kills **only the registered pid**: a child the registered process started
(the `node` behind `npm run dev`) was not registered, so it is not killed; the scan then
reports it. The cook rule says to register the pid that holds the port, and every process it
starts.

**The scan** (`procs --scan`) lists every process whose cwd is inside a station dir that is
not registered and not a kitchen session (`procs_protected`'s command rules), one row per
process: station, pid, parent pid, age, command. One `lsof -d cwd -Fpn` call (macOS), or a loop over
`/proc/*/cwd` (Linux), so the board stays cheap. It never signals anything. Two documented
blind spots, both on the report-only side: a shell that is a direct child of a claude session
(the tool call's own shell) is skipped so a cook mid-call is not a "suspect", which also hides
a loop run as that very shell; and a process that changed its cwd.

**Board and list.** `procs` with no argument prints every station's register with
`alive|dead|reused` and a count line. The board gets one line:
`Processes: <n> registered alive · <m> unregistered in stations`.

**`bk stop`** runs `"$KITCHEN" procs --reap all` after the wait for the handoffs (step 2) and
before `/exit` (step 4): the cooks have listed what they leave running in their handoffs by
then, and the pause saves the ids. It prints the reap's output with the rest of its progress.

**Skills.** Line-cook: register at start (`--add $! "<what>"`, or the pid from `lsof -ti
:<port>`), stop your own before `[handoff]`, list the ones left running (and why) in the
handoff's `Processes` line. Implement: the same, per phase. Runner and taster: register what
they start in the background. Sous: after `ship`, before `clear`: `procs --reap station-N`;
`procs --scan` at each pass and at its handoff; a suspect is a `[status]` line to that cook
("register or stop `<pid>`") or, with the cook gone, a line to the head chef. The sous's
handoff lists every registered-alive process and every suspect; a fresh sous reads that list
before its first brief. Contract 7 gains the rule in one paragraph.

**The alternative it beat:** killing the registered pid's whole process group or
descendants. It is wider than the ticket's hard line ("a process the sous doesn't know about
is reported, not killed"), and a group can include the cook's own shell. Rejected.

## Decisions

### Changes the ticket

None. Every choice below fills in what the ticket's Done when leaves open.

### How

- `procs` takes its own arguments: one line after `CMD="${1:-}"; shift` hands the rest to
  `PROCS_ARGS` and empties `$@`, so the global parser (`--add`, `--ticket`) is untouched and
  one parser line is all #65's merge sees. `--add` here is `--add <pid> "<what>"`; `--ticket ID`
  and `--station N` follow it. Without `--ticket` the ticket column is `-`.
- The register is tab-separated text, not JSON: `awk -F'\t'` reads it, bash 3.2 has no
  arrays to fight, and every other `.claude/*` file here is plain lines. Tabs and newlines in
  the command are squeezed to spaces before writing.
- The time grace is 5 s TERM then KILL, as `bk stop` uses fixed waits (`bin/bk:340`); no config key.
- `reused` lines are dropped by `--prune` like `dead` ones (our process is gone either way);
  `--reap` leaves them in the register and prints them, so the sous sees the mismatch once.
- `--reap all` exists for `bk stop`; the sous uses `--reap station-N`. `--station N` accepts `N` or
  `station-N`, as `clear` accepts `station-*`.
- The reap's record is `.claude/procs.log` in the station (out of git), not the journal: the
  journal is the cook's alone (Contract 11).
- (Sous amendment a, 2026-11-03) The cook rule says to register the process that actually
  holds the port or the CPU: the server itself, not only the `npm`/`make` wrapper (`$!` of an
  `exec`'d command, or each child found with `pgrep -P` right after the start). The scan's row
  for a leftover child names its registered parent when its ppid is a registered pid.
- (Sous amendment b, 2026-11-03) The sous's message to a cook, "register or stop pid N", is
  decided after #65 merges: if `[status]` has a script route in Contract 6's Route column
  (a cook's status file), use `[findings]` instead; the journal says which and why.
- A new section in the existing `tests/kitchen.test.sh` (as the ticket says), appended after the
  last `section`, so #65's edits and this one don't touch the same lines.
- Sleepers in tests are only ones the test started, in the test's own temp dir, killed by
  pid in its `cleanup` trap (the sous's rule: never kill anything by hand).
- The sous's plain message to a cook is a `[status]` (Contract 6: "anyone", needs no answer).
  No new message kind.

## Phases

### Phase 1 — `kitchen.sh procs`

**Status:** Done — `procs` block (cmd_procs and nine helpers) after `seed_sous_permissions`; one parser line (`kitchen.sh:317`), `PROCS_ARGS` global, one dispatcher entry, one board line, usage block. shellcheck -S info clean for the new lines.

- `cmd_procs` and helpers in a new block after `cmd_ship`/`seed_sous_permissions` (before `cmd_budget`, `kitchen.sh:1924`): `procs_ps`, `procs_state`, `procs_protected`, `procs_add`, `procs_list`, `procs_prune`, `procs_reap`, `procs_scan`, `procs_summary` — `plugins/bk/skills/kitchen/kitchen.sh`
- One parser line after `CMD="${1:-}"; shift || true` (`kitchen.sh:291`): `if [[ "$CMD" == procs ]]; then PROCS_ARGS=("$@"); set --; fi`, and `PROCS_ARGS=()` with the other globals (`:285`) — same file
- One dispatcher entry `procs) cmd_procs ;;` (`kitchen.sh:2094`), one board line (after `kitchen.sh:1008`), and the usage block in the header — same file
- Check: `bash -n`, `shellcheck`, and a by-hand run in a throwaway repo (the test below) pass

### Phase 2 — `bk stop` reaps

**Status:** Done — `bin/bk` step 5 before the tmux session is killed, so it also covers a kitchen with no live session.

- After the wait loop (ends `bin/bk:321`) and before step 3 (`bin/bk:322`), the saves, run `"$KITCHEN" procs --reap all 2>&1` and print what it says; a failure never stops the pause — `bin/bk`
- Check: `shellcheck bin/bk` clean

### Phase 3 — tests (each proved red by mutating a COPY, outside the checkout)

**Status:** Done — kitchen.test.sh `procs` section 53 tests per mode (106 in a trimmed copy), bk.test.sh +3 (85). Mutations on copies: a (identity check off) 10 red, b (protected check off) red from #12 and the run aborts (it reaps its own shell), c (reap kills everything in the station) 12 red, d (bk stop line removed) 2 red; control green. The test sleepers now sleep 120 s and the run traps TERM/HUP/INT into its EXIT cleanup.

- `tests/kitchen.test.sh`, a `section "procs: …"` for both modes through the existing structure: add (writes the line, out of git, refuses a bad pid, a non-number, `claude`, `tmux`, a login shell, itself); list (alive/dead/reused); prune (drops dead and reused, keeps alive); reap (a registered sleeper dies; an unregistered sleeper in the station survives and the scan reports it; a pid whose recorded start time is wrong is skipped and survives; a protected process is left; a grace test with a sleeper that ignores TERM dies by KILL); scan (never kills, doesn't list a registered one, doesn't list a `claude`-named one); the board line
- `tests/bk.test.sh`, in "stop (a pause) and the resume": a registered sleeper in a station is dead after `bk stop`, an unregistered one is alive, and the output says what it reaped
- Mutations on copies: (a) the identity check removed → the "wrong start time survives" test goes red; (b) the protected check removed → the claude/tmux refusals go red; (c) the register filter removed so the reap kills every station-cwd process → the "unregistered survives" test goes red; (d) the `bk stop` line removed → the bk test goes red
- Check: `tests/kitchen.test.sh`, `tests/bk.test.sh` green (the sous clears each full run)

### Phase 4 — the rules in prose (contract first)

**Status:** Done — Contract 7 (Processes paragraph) and 11, line-cook (Processes you start), implement, handoff (+ journal template `Processes`), sous-chef (Step 0, The walk-in, End of shift 2, handoff), kitchen skill, taster, runner, PLAYBOOK, fragment. `[findings]` is the sous → cook message (Contract 6: `[status]` is a script kind).

- Contract 7: one paragraph — the kitchen manages the processes it registers and only those; the register, the reap and its identity check, the scan report-only — `plugins/bk/skills/README.md:613-624`; Contract 11: the cook's `Processes` line and the sous handoff's list — `README.md:775-790`
- line-cook: the rule in the loop (before step 7) and in "Things you never do" — `plugins/bk/skills/line-cook/SKILL.md`
- implement: register in the phase loop — `plugins/bk/skills/implement/SKILL.md:88-93`
- handoff: the cook's `Processes` field (step 4) and the sous handoff's list — `plugins/bk/skills/handoff/SKILL.md`
- sous-chef: End of shift (reap between `ship` and `clear`), the scan, a fresh sous reads the list — `plugins/bk/skills/sous-chef/SKILL.md:491-513`
- kitchen skill: the subcommand — `plugins/bk/skills/kitchen/SKILL.md`; taster and runner: register what they start — `plugins/bk/agents/taster.md`, `runner.md`
- PLAYBOOK: `bk stop` and End of shift, one line each — `PLAYBOOK.md:154,342`
- Fragment `changelog.d/86-kitchen-procs.md` (`level: minor`)
- Check: a fresh read-only sub-agent greps every skill for wording that disagrees with Contract 7 and 11; `scripts/check.sh` green (the sous clears the full run)

## Success criteria

- [ ] `kitchen.sh procs --add <pid> "<what>"` writes `<station>/.claude/procs`, out of git; `procs` lists every station's lines as alive/dead/reused; `--prune` drops the dead (test)
- [ ] `--reap station-N` kills a registered sleeper (TERM, then KILL for one that ignores TERM), logs it, and leaves an unregistered sleeper, a pid with a mismatched start time, and a `claude`/`tmux`/login-shell process alone, printing each skipped (tests)
- [ ] `--scan` reports an unregistered sleeper in a station, omits registered and kitchen-session ones, and signals nothing (test)
- [ ] The board prints the registered-alive and unregistered counts (test)
- [ ] `bk stop` reaps every station before the pause (`tests/bk.test.sh`)
- [ ] Each test goes red with its check removed (mutations a–d on copies)
- [ ] Contract 7 and 11, line-cook, implement, handoff, sous-chef, kitchen, taster, runner and PLAYBOOK carry the rule and agree (a read-only consistency read finds no disagreement)
- [ ] `scripts/check.sh` green on both OS shapes (bash 3.2 syntax only: no `mapfile`, no associative arrays); CI green on Linux and macOS

## Risks

- PID reuse between the identity check and the `kill` → start time and command compared at the moment of the kill, in the same function, with no sleep between.
- `ps -o lstart` text differs between macOS and procps → the test registers and checks on whatever the platform prints; the only comparison is register-time vs reap-time on the same machine.
- `lsof` is slow or absent → one `lsof -d cwd` call, and if neither `/proc` nor `lsof` can be read the scan says so instead of reporting nothing.
- A test sleeper outliving a failed test → every sleeper pid goes in an array that `cleanup` kills; none is found by name or cwd.
- #65 merges first and moves `kitchen.sh`, `kitchen.test.sh` and the skills → implement waits for the sous's "#65 merged", then brings main in and re-checks every `file:line` above before touching a file.
- The scan's blind spots (a loop run as the tool shell; a process that moved its cwd) → documented in the sous-chef skill, and the scan is only a report.
