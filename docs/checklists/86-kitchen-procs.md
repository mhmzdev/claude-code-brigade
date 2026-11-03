---
ticket: "#86"
title: "kitchen.sh procs: the kitchen registers, reaps and scans the processes it started; never a system or unknown process"
plan: docs/plans/86-kitchen-procs.md
last_verified: 2026-11-03
---

# Acceptance — #86 kitchen.sh procs: register, reap, scan

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

### A cook starts a dev server and the ticket ends

1. The cook starts it and runs `kitchen.sh procs --add <pid> "dev server"` → `<station>/.claude/procs` holds the pid, start time, command line, purpose and the ticket from the branch; the file is out of git.
2. The cook finishes, runs `kill <pid>` and `procs --prune` → the line is gone; its handoff says `Processes: none`.
3. A cook forgets: after `ship` the sous runs `procs --reap station-1` → the registered process gets TERM (KILL after 5 s), the reap is logged in `.claude/procs.log`, and the sous sends the cook `[findings]` for whatever `procs --scan` still lists.

### The head chef stops for the day

1. `bk stop` → handoffs are typed and awaited, session ids saved, `/exit` typed, then `procs --reap all` runs for every station, then the tmux session is closed.

## Edge cases

- A pid that now belongs to another process (start time or command differs) → listed `reused`, never signalled, left in the register by `--reap`, dropped by `--prune`.
- A registered `claude`, `tmux`, login shell or pane shell, pid 1, someone else's process, the caller's own tree → refused by `--add`; skipped (and printed) by `--reap` even if a line was written by hand.
- A process ignoring TERM → KILLed after the 5 s grace.
- A registered wrapper's child → not registered, so not killed; the scan reports it with its registered parent.
- An unregistered process in a station → reported by `--scan`, never signalled.
- `procs --prune` / the list run in a station touch that station only; from the main checkout, every station.

## Acceptance criteria

- [x] **A register.** `procs --add <pid> "<what>"` (from a station, or `--station N` from the main checkout) writes `<station>/.claude/procs` out of git with pid, start, command, what, ticket — `procs: … --add registers a pid from a station`, `…the register holds the pid, a start time, the command line and what it is for`, `…kept out of git`, `…the sous registers into a station with --station N`, `…the ticket comes from the station's branch` pass in clone and worktree mode (`tests/kitchen.test.sh`, `procs_suite`, `kitchen.sh:2370` `procs_add`)
- [x] `procs` lists every station's registered processes with alive/dead (and reused) and `--prune` drops the dead lines — `…the list shows every station's register with the state`, `…and counts them`, `--prune drops the dead line`, `…leaves the other stations' registers alone`, `--prune from the main checkout covers every station` pass
- [x] **The rule for cooks.** line-cook (`Processes you start`, `plugins/bk/skills/line-cook/SKILL.md:211`), implement (item 2 of the phase loop and Step 4, `implement/SKILL.md:90,119`), the taster (`taster.md`) and the runner (`runner.md`) say to register at the start, register the process that holds the port or the CPU, stop your own before `[handoff]`, and list what stays up in the handoff — read in this run; consistency read by a fresh read-only sub-agent found no disagreement after its five findings were fixed
- [x] **The reap.** `procs --reap <station>` kills a registered, still-identical, non-session pid (TERM then KILL) and records it — `…a registered process is gone, by TERM`, `…one that ignores TERM is killed`, `…the reap is logged`; an identity mismatch is skipped and survives (`…a pid whose start time does not match is skipped, and survives`); a kitchen session in the register is skipped (`…a kitchen session in the register is skipped, and survives`); `bk stop` runs it for every station (`tests/bk.test.sh`: `stop reaps a process a cook registered in a station`, `…but not a process nobody registered`, `bin/bk:348`)
- [x] The sous runs the reap after `ship` and before `clear` (End of shift step 2, `sous-chef/SKILL.md`, the section "End of shift") — read in this run
- [x] **The scan, report-only.** `procs --scan` lists unregistered processes standing in a station, not registered ones, not kitchen sessions, and signals nothing — `…--scan lists an unregistered process standing in a station`, `…not a registered one`, `…not a kitchen session`, `…and it signals nothing`, `…the scan names a leftover child's registered parent`; the board shows both counts — `…the board counts the registered-alive and the unregistered` (`kitchen.sh:1371`)
- [x] **Handoffs.** The cook's handoff has a `Processes` line (`handoff/SKILL.md:52`, `templates/journal.md`); the sous's handoff lists every registered-alive process and every suspect, and a fresh sous reads it before its first brief (`handoff/SKILL.md:189,202`, `sous-chef/SKILL.md` Step 0) — read in this run
- [x] **Contract 7** gains the rule in one paragraph (`plugins/bk/skills/README.md:654`), Contract 11's handoffs mention it, and Contract 6's `[findings]` row covers an unregistered process
- [x] **Tests red with the checks removed**, on copies outside the checkout: identity check off (10 red), protected check off (red from the refusals; the run reaps its own shell and aborts), reap kills the whole station (12 red), the `bk stop` line removed (2 red), list/prune not scoped to the cook's station (6 red); the controls are green
- [x] **Pass finding 1 (scope).** A cook works on its own station: `--reap` (any argument), `--station` naming another station or `all`, and `--add … --station 2` are refused from a station and change nothing; its own station by name passes — `a cook cannot name another station`, `…and that station's register is untouched`, `…nor all of them`, `…but its own station, by name, passes`, `a cook cannot reap (all)`, `…nor its own station`, `…and nothing was reaped`, `…nor register into another station`, `…and nothing was written there` (`cmd_procs`, `kitchen.sh` "a cook's scope is its own station"); red with the check removed (mutation f)
- [x] **Pass finding 2 (a pid must belong to the station).** `--add` refuses a pid whose cwd is not inside the target station; the reap re-checks the cwd and leaves a process that moved out alone, printed — `--add refuses a pid whose cwd is not inside the station`, `…and wrote nothing`, `a process inside the station registers`, `the reap leaves a process whose cwd moved out of the station alone, and says so`, `…it still runs` (`procs_in_station`, used by `procs_add` and `procs_reap`); red with either check removed (mutations g, h)
- [x] **Pass finding 3 + the note.** PLAYBOOK flow step 9, the `/bk:handoff` table (cook's `Processes`, the sous note's process list) and `bk stop` carry the reap; the board reads the cwds once per call (`procs_scan_rows`, one `lsof`/`/proc` read) — read in this run
- [x] The check is green on this tree — `kitchen.sh check`: green (ran, 293s) — kitchen 647, guard 27, bk 85, budget 115, window 22, release 45, v0.33.0, no process left behind
- [?] A real cook session registers its dev server and the sous's reap kills it end to end (a live kitchen with `claude` sessions) — after merge: in a Brigade session start `sleep 600 &`, `procs --add $! "test"`, then as the sous `procs --reap station-N`; expect "reaped … (test, term)" and the sleeper gone, `claude` and `tmux` untouched
- [?] Linux: the scan reads `/proc/*/cwd` and the identity check reads `ps -ww -o lstart=,command=` of procps — CI on Linux (bash 5) runs the same tests; confirm the check job is green there

## Known limitations

- The reap kills only the registered pid, never its group or children (the head chef's "never a process the sous doesn't know about"): a cook must register the process that holds the port; a leftover child is only reported by the scan, with its registered parent.
- The scan skips a shell that is a direct child of a claude session (the tool call's own shell), so a polling loop run as that very shell is not reported; and a process that changed its cwd is not seen.
- `bk stop` reaps after the handoffs and `/exit`, so a cook that had left a process running on purpose loses it on a pause; its handoff's `Processes` line says what to restart.
- A test run killed with SIGKILL can leave its sleepers behind; they exit by themselves after 120 s (the trap handles TERM, HUP and INT).
