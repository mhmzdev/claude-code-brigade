---
ticket: "#65"
title: route routine message kinds to script; measure the sous's turns per ticket by kind (and take #59: ticket ids from the rail's own form)
plan: docs/plans/65-routine-kinds-script.md
last_verified: 2026-11-03
---

# Acceptance — #65 route routine message kinds to script (Closes #65, #59)

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

### A briefed cook claims and moves its ticket without a message

1. The sous (main checkout) runs `kitchen.sh rail brief 7 station-1` → `#7 briefed to station-1.`, a line in `.claude/briefs`.
2. The cook (station-1) runs `kitchen.sh rail claim 7 todo` → `#7 → todo (station-1)`; the ticket is `Todo` on the board, assigned to the logged-in account, with a comment naming the station. Markdown rail: one `rail: <ID> → todo` commit on `origin/main`, the main checkout untouched.
3. `kitchen.sh rail move 7 in-progress`, then `… rfr` → each lands; `kitchen.sh board` shows "The cooks" with the station's last state.
4. `kitchen.sh here --spent --waiting "the pass"` → the board line changes; the sous is sent no message.

### The budget shows what the sous spent its turns on

1. `kitchen.sh budget --ticket '#13'` (or `13`) on a github rail → the ticket's cost, phases and a `sous turns  N (kind n, …) · R relays` line.
2. `kitchen.sh debrief` → `relay-heavy` and `ship-rounds` rows with their fixes.

## Edge cases

- A cook with no brief on record, or a ticket someone else holds → refused, nothing written, "send the sous `[rail]`" → the old message still works.
- A push refused once → rebuilt from the new tip and lands; refused twice → exit 1, nothing pushed.
- `rail.commit: daily-pr`, a jira rail, or a missing `gh` → refused before writing.
- A PR number in a message (`PR #76`) or a number inside a URL names no ticket; a `[brief]` starts its ticket even after a stray mention of another.
- A free cook still sends one `[check-in]` line (the one change to the ticket, A3).

## Acceptance criteria

### #65 Done when

- [x] budget: sous turns by message kind per ticket (`--ticket`, the ledger row, `--json`) — `tests/budget.test.sh` "the sous's turns on #13, by kind", "the ticket report prints them", "the ledger row carries them"; `budget.js:145` `sousTurnsOf`, `:525` `sousLine`
- [x] `relay-heavy` (more than half the sous's turns, from eight up) — "relay-heavy trips on the ticket whose sous turns were mostly relays", "…not on seven relays"; `budget.js:469`; red with the rule renamed, the floor at 1, or `gate` counted as routine (broken on purpose)
- [x] `ship-rounds` (pushed again after its first `[served]`) — "ship-rounds is DUE on two tickets…"; `budget.js:472`, counted at `:292` and in `spans()`; red when it never trips, and when findings-after-served is not counted (broken on purpose)
- [x] routine kinds go to script: rail claim and move — `tests/kitchen.test.sh` section "rail brief | claim | move" (clone, worktree and github, 90 cases); `kitchen.sh:1205` `rail_write`, `:1190` `rail_check` (Contract 3: a claim is never overwritten), `:1107` `md_write`, `:1161` `gh_write`
- [x] `[status]` and `[check-in]` → a station status file `kitchen.sh board` reads — "here ($label): a cook's state by script", "the board lists the cooks…"; `kitchen.sh:1270` `cmd_here`, `:1294` `cmd_here_board_lines`
- [x] the sous is sent only `[gate]`, `[plan]`, `[handoff]`, `[walk-in]`, `[served]` (and the free `[check-in]`, A3) — `README.md:600-630` Contract 6's Route column and paragraph; `line-cook/SKILL.md` Check in step 4 and the loop; `sous-chef/SKILL.md` brief step 6 and "Writing the rail"
- [x] Contract 6's table marks each kind sous, script or cook, and `line-cook`/`sous-chef` follow it — `README.md:600`; a fresh read-only consistency read listed 12 stale spots, all fixed; `git grep` for `[rail] claim` / `[status]` in skills leaves only the refusal fallbacks and the sous's own broadcast
- [x] tests: `tests/budget.test.sh` for the two rules (red with the rule removed) and `tests/kitchen.test.sh` for the script-side claim and the status file — ten rail/here breaks and six budget breaks each went red (journal, phases 2 and 3)
- [x] the markdown claim never touches the main checkout (the sous's finding 1) — "the main checkout is untouched: same status, HEAD, file and staged change" and "a push refused once is rebuilt…; main's own file did not fool it", clone and worktree

### #59 Done when

- [x] ticket ids from the rail's own form (github `#N` and `issue-N-`, jira keys, the markdown ids) — `live/ticket-id.js:14,26,36`; `budget.js` and `stations.js` use it, the adapter coming from the config
- [x] a github-rail budget test attributes spend to `#N` and goes red with the old regex — `tests/budget.test.sh:403` section; "a github rail attributes spend to #13" and 8 more red with the tracker forms off
- [x] `kitchen.sh budget --ticket 13` / `'#13'` shows that ticket's spend — "--ticket 13 shows that ticket's spend", "--ticket '#13' shows the same"

### The gate and the release

- [x] the full gate is green — `kitchen.sh check` after the pass's six findings, on the tree before #50 merged: green, ran 213s; kitchen 507 · guard 27 · bk 82 · budget 115 · window 22 · release 45. Main (#50) was brought in afterwards (no conflict): shellcheck clean, the new kitchen section 98/98, budget 115; the taster's or open-pr's `check` covers the merged tree
- [x] the board shows a cook's claim before the sous has pulled — "the board shows the cook's claim before the sous has pulled" (clone, worktree); `kitchen.sh rail_origin_tree`, `cmd_board`; red with the origin read removed
- [x] a claim by the claim's own station at a later status is a no-op — "the claim's own station asking again…", "github: the claim's own station asking again at a later status"; `rail_check`
- [x] every gh failure path carries gh's words and ends with "send the sous [rail]" — "github: a refused gh edit…", "github: a field-list failure…"
- [x] `shellcheck -S warning` clean on `kitchen.sh`, `tests/kitchen.test.sh`, `tests/budget.test.sh`; `claude plugin validate` passes for the marketplace and the plugin
- [x] release by fragment, no bump (#64 merged) — `changelog.d/65-routine-kinds-script.md`, level minor
- [?] live walk on this repo's own GitHub project — after merge: brief #N, claim it from a cook, and see the Project 4 item move to Todo with the assignee and comment. Needs the `project` scope on `gh`; the stub tests cover the call shapes, not GitHub's answer
- [?] a real `gh project item-list --jq` against project 4 returns `<count>|<id>|<status>` — run `gh project item-list 4 --owner mhmzdev --format json --limit 500 --jq '(.items|length) as $len | …'` (the expression at `kitchen.sh:1144`) once and compare with the board

## Known limitations

- `fire`, `close`, `link` and body edits stay the sous's; jira and `rail.commit: daily-pr` stay `[rail]` messages.
- The first match in a message names its ticket, as before: a message that mentions another ticket's `#N` before its own can still attribute to it (a stray mention creates an extra open ticket; the brief rule keeps the real one).
- The Window does not draw `here` files yet.
- `AGENTS.md` still lists the old kitchen.sh command set (it is #64's file in flight).
