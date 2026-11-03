---
ticket: "#65"
title: route routine message kinds to script; measure the sous's turns per ticket by kind (and take #59: ticket ids from the rail's own form)
status: active
approved: 2026-11-03
lane: B
created: 2026-11-03
open_questions: none
migration: false
files:
  - plugins/bk/window/server/live/ticket-id.js
  - plugins/bk/window/server/live/budget.js
  - plugins/bk/window/server/live/stations.js
  - plugins/bk/skills/kitchen/kitchen.sh
  - tests/budget.test.sh
  - tests/kitchen.test.sh
  - plugins/bk/skills/README.md
  - plugins/bk/skills/line-cook/SKILL.md
  - plugins/bk/skills/sous-chef/SKILL.md
  - plugins/bk/skills/pick-ticket/SKILL.md
  - plugins/bk/skills/create-plan/SKILL.md
  - plugins/bk/skills/implement/SKILL.md
  - plugins/bk/skills/review-task/SKILL.md
  - plugins/bk/skills/grill-me/SKILL.md
  - plugins/bk/skills/handoff/SKILL.md
  - plugins/bk/skills/rail/SKILL.md
  - PLAYBOOK.md
  - docs/questions/mechanical-enforcement.md
  - plugins/bk/.claude-plugin/plugin.json   # or a changelog.d fragment, per #64's rule at open-pr
  - Formula/bk.rb
  - CHANGELOG.md
---

# #65 — route routine message kinds to script; measure the sous's turns per ticket by kind

**Closes #65 and #59.** The sous signs this plan (a chore); one line below is the head
chef's, already answered.

## Why

Every message a cook sends wakes the sous for a full turn, and most need no judgement:
`[check-in]`, `[status]`, `[rail] claim` and moves, `[heard]` back, a re-sent `[served]` after
main moved. On 2026-10-25 the sous ran 58 minutes and $7.35 for two docs-only tickets, 50
turns past the context line, mostly relays. The budget cannot show this: it counts turns
over the line, not what they were for. #59 is the prerequisite: the budget's ticket regex
(`budget.js:72`) matches only `S…`, `BKLG-…` and `HYG-…`, so on this repo's GitHub rail
(`#65`, `issue-65-…`) no spend is attributed to any ticket, and a per-ticket count of the
sous's turns has nothing to attach to.

## Current state

- `budget.js:72` `TICKET` and `stations.js:7` `TICKET` know only the markdown ids. `budget.js:89`
  `scanTranscript` makes one mark per `SendMessage` out (`:116`) and one per message in (`:128`),
  each with `kind`, `ticket`, `text`, but no sender, and the sous's turns are never grouped by
  them. `budget.js:413` `DEBRIEF_RULES` has six rules; none about relays or re-serves.
  `budget.js:255` `spans()` records `servedAt` once, not how many times `[served]` was sent.
- `kitchen.sh:894` `cmd_rail` only reads (markdown only: it says "isn't markdown" on a tracker).
  The dispatcher is `kitchen.sh:1803`; the flag parser rejects any bare word (`:282`).
  `kitchen.sh:955` `cmd_board` prints stations, files, rail, questions and the record's counts.
  `kitchen.sh:1022` `cmd_role` is how a script knows it runs in a station.
- Contract 3 rule 1 (`README.md:245`): only the sous writes the rail. Contract 6's table
  (`README.md:583-598`) has no routing column. A cook's claim, `→ in-progress` and `→ rfr` are
  `[rail]` messages (`pick-ticket:140`, `create-plan:37`, `implement:80`, `line-cook:160,168,172`,
  `review-task:88`); every `[status]` is a message (`grill-me:39,45`, `handoff:59`,
  `implement:43,73`, `line-cook:135`, `README.md:416`); the check-in is a message
  (`line-cook` Check in, step 4).
- `docs/questions/mechanical-enforcement.md` row 6 (rail writes by script) is still "hand edits".
- `/bk:rail`'s GitHub claim today (`rail/SKILL.md` github adapter): Status field by
  `gh project item-edit`, the head chef's login as assignee, a short comment naming the station.

## Desired end state

- `kitchen.sh budget --ticket 13` and `--ticket '#13'` show #13's spend on a GitHub rail; the
  ledger, the journal line, the debrief's ticket rules and the sous-turn counts all key on it.
- Per ticket: the sous's turns by the kind of message that woke it, in `--ticket`, the `--json`
  and the ledger row; debrief rules `relay-heavy` and `ship-rounds`.
- A cook claims and moves its own briefed ticket with `kitchen.sh rail claim|move`, on a
  markdown or a GitHub rail, with no message. It reports state with `kitchen.sh here`, which
  the sous reads in `kitchen.sh board`. The sous is sent `[gate]`, `[plan]`, `[handoff]`,
  `[walk-in]`, `[served]`, and the one free-cook `[check-in]`.
- Contract 6's table marks each kind **sous** or **script**; the skills follow it.

## Not doing

- `fire`, `close`, `link` stay with the sous (row 6 stays open for them); jira stays a `[rail]`
  message. A cook still never moves a ticket to `done`, `blocked`, `backlog` or `todo` by script.
- No hook that refuses a `[rail] claim` message (a later ticket can add it to `hooks/guard.sh`).
- `AGENTS.md` and `scripts/check.sh` are #64's: no layout edit there; the new commands are
  documented in `kitchen.sh`'s header and Contracts 3 and 6.
- The Window does not draw `here` files yet.
- `kitchen.sh next` (row 7) is not part of this.

## Approach

Four moves, in this order so each leaves `check` green: (1) ticket ids from the rail's form
(#59), the base the rest keys on; (2) the sous's turns by kind and the two rules, in
`budget.js`; (3) `kitchen.sh rail brief|claim|move` and `kitchen.sh here`, as new functions
plus one dispatcher line, one parser branch and one board section (#64 edits the readers
around them); (4) the contract and skills, then the release. The briefing is made
mechanical by a record the sous writes in the same turn as the `[brief]`, so "the brief is the
authorisation" is something a script can check; a claim is allowed only on a free ticket, so
Contract 3's "never overwritten" is a precondition in code, not a promise.

## Decisions

### Changes the ticket

- The ticket says "the sous is sent only `[gate]`, `[plan]`, `[handoff]`, `[walk-in]`,
  `[served]`"; the plan also keeps a **free-cook `[check-in]`** as a message (no ticket, clean,
  fresh), because a status file cannot wake an idle sous and a free cook must never sit
  unbriefed. Every other check-in and every `[status]` goes to the file. **Answered:** A3
  (head chef, relayed by the sous 2026-11-03), journal `docs/journal/65-routine-kinds-script.md`.
- #59 is taken whole into this PR, so the PR says "Closes #59" (the sous's call, A in the journal).

### How

- **Ticket ids from the rail's form (#59).** One new module `live/ticket-id.js`:
  `idPattern(adapter)` always matches the markdown ids; `github` and `mixed` add `#N`; `jira` adds
  keys `[A-Z][A-Z0-9]+-\d+`. `idOf(text, adapter)` returns the canonical id (`#13`, upper-cased);
  `idOfBranch(branch, adapter)` reads `issue-13-…` as `#13` and `proj-123-…` as `PROJ-123`;
  `canon(arg, adapter)` turns `13`, `#13` into `#13` for `--ticket`. `\b` fails before `#`, so the
  GitHub pattern is `(?<![\w/&])#(\d+)\b` (not inside a URL or an HTML entity). The adapter comes
  from `readConfig(...).railAdapter` (`config.js`), passed into `createBudget` and `scanTranscript`
  (a new third argument; the default keeps the markdown ids, so no caller breaks). First match in the
  message wins, as today.
- **Sous turns by kind.** A sous assistant turn belongs to the **latest incoming message before it**
  (`dir: 'in'`); that message's `kind` is the turn's kind, and its ticket is the id in the text, else
  the last ticket that sender (the new `from` on in-marks, read from the `from-name` attribute) named,
  else none. A turn with no incoming message before it, or one typed by the head chef (no kind), is
  `other`. Output on each ticket: `sousTurns: { total, byKind: { gate: 4, heard: 2, … }, routine }`,
  where `routine` counts `heard`, `status`, `check-in` and `rail`. It rides `strip(sp)`, so the ledger row
  and `--json` carry it; `report(…, { ticket })` gets one line: `sous turns  14 (gate 4, rail 3, check-in 3, …)`.
- **`relay-heavy`** (scope `plugin`, unit `ticket`): `routine / total > 1/2` and `total >= 8`
  (below eight, a ratio is noise). Fix: "make the kind mechanical: a station status file for `[status]`
  and `[check-in]`, `kitchen.sh rail` for claim and move".
- **`ship-rounds`** (scope `plugin`, unit `ticket`): `rounds = max(findings the cook received after its
  first [served], [served] messages sent after the first)`; trips at `rounds >= 1`; DUE at two tickets
  as every rule. Fix: "merge sooner, and assign the version at merge (a changelog fragment, #64)".
  `spans()` gains `served` (count of out-`served` marks) and `findingsAfterServed`; `merge()` sums them.
- **The brief record.** `kitchen.sh rail brief <ID> station-N`, main checkout only, writes
  `.claude/briefs` (`<ID><TAB>station-N<TAB>epoch`, one line per ticket, out of git through
  `exclude_locally`). It refuses when the ticket is already somebody's claim (`todo`, `in-progress`,
  `rfr`) unless that claim is the same station's (a re-brief after a restart). The sous runs it in the
  turn it sends the `[brief]`: one tool call, no extra turn. A claim with no brief on record refuses
  with "no brief for station-N on #65: send [rail] claim to the sous", so a forgetful sous costs one
  message, not a wrong claim.
- **`kitchen.sh rail claim <ID> <todo|in-progress>` and `rail move <ID> <in-progress|rfr>`.**
  Run in a station (`cmd_role` says so). Allowed only when `.claude/briefs` names this station for
  the ID. `claim`: the ticket is free (`backlog`/`blocked`), or already this station's at that status
  (idempotent: no write, exit 0). `move`: `todo→in-progress`, `in-progress→rfr`, `rfr→in-progress`
  only, and only on this station's own claim. Every refusal names the current status and whose claim
  it is, exit 1, nothing written. Run from the main checkout, `claim <ID> <status> <station>` and
  `move` skip the brief check (the sous is the writer, Contract 3) and share the code.
  Who holds a claim: markdown, the ticket's `cook:`; GitHub, the briefs record plus the claim
  comment (`claimed by station-N`), since a GitHub issue has no cook field.
- **Markdown adapter, and the main checkout is never touched** (the sous's finding 1). A station never
  edits, stages, commits in or pulls into the main checkout's working tree or index: the sous's tree is
  usually dirty and mid-operation. The write is built with plumbing against `origin/<trunk>` only:
  `git fetch origin <trunk>`; read the ticket's current `status:`/`cook:` from `origin/<trunk>:<path>`
  (`git show`), never from main's file; edit the frontmatter `status:` and `cook:` lines of that text with
  awk; `blob=$(git hash-object -w --stdin)`; a temporary `GIT_INDEX_FILE` primed with `git read-tree
  origin/<trunk>`; `git update-index --cacheinfo 100644,$blob,<path>`; `tree=$(git write-tree)`;
  `commit=$(git commit-tree $tree -p origin/<trunk> -m "rail: <ID> → <status>")`; `git push origin
  $commit:refs/heads/<trunk>`. A rejected push (trunk moved) re-fetches and rebuilds from the new tip once;
  still rejected → exit 1, nothing pushed, "send [rail]". No force, no lock (the push is the lock: two
  writers can't both fast-forward). The sous's checkout picks the commit up at its next pull. Finding the
  file: `git ls-tree -r --name-only origin/<trunk>` filtered by the id (`BKLG-nnn-*.md`, `HYG-nnn-*.md`
  under `docs.backlog`; `NN-*.md` under `docs.specs/NNN-*/` for `SNNN-NN`). `rail.commit: daily-pr`
  → refuses before writing ("this rail commits through a daily PR: send the sous `[rail]`"). Run from
  the main checkout the same code runs (it never needs the working tree either).
- **GitHub adapter.** Config from `rail.github` (`owner`, `project`, `status_field`; the inline-map and
  block forms). `gh project item-list` finds the item for issue N and its current Status (fails loudly
  at the 500 limit, as the rail skill says); `gh project field-list` gives the field id and option ids;
  `gh project view` the project id; `gh project item-edit` sets it. Status names to try, in order:
  backlog `Backlog`; todo `Todo`, `To do`; in-progress `In Progress`, `In progress`; rfr
  `Ready for review`, `In review`; blocked `Blocked`; done `Done`. On a claim: `gh issue edit N
  --add-assignee <gh api user login>` and `gh issue comment N --body "claimed by station-N"`. All
  through `--jq` of `gh`, so no `jq` dependency. A `gh` or `project`-scope failure exits 1 with gh's
  words and "send [rail]".
- **`kitchen.sh here [--fresh|--spent] [--waiting "<what>"] [--note "<text>"] [--model <m>]`.** Run in a
  station; writes `<station>/.claude/here` (key: value lines: `at`, `station`, `branch`, `dirty`,
  `ticket` read from the branch with `idOfBranch`'s shell twin, `session` fresh|spent, `waiting`, `model`)
  and appends `--note` to `<station>/.claude/here.log` (last 20 lines kept). It is station-local (no
  write into the main checkout, which is protected territory for a cook), out of git through
  `exclude_locally`'s station twin. Fresh/spent are the cook's own knowledge, so they are flags;
  everything else the script reads itself.
- **`board`** gains a **Cooks** section from each station's `here` file: station, age, branch,
  dirty/clean, fresh/spent, waiting on, model, last note. A station with no `here` file is "no
  check-in yet".
- **Flag parser.** A bare word is collected into `POS` only when `CMD` is `rail`; every other command
  keeps "Unknown argument". New value flags `--fresh --spent --waiting --note` and `--cook`.
- **Messages after this change** (Contract 6 gets a `Route` column): `[hello]` `[brief]` `[findings]`
  `[approved]` `[go]` `[heard]` (sous → cook) are the sous's; cook → sous `[gate]` `[plan]` `[handoff]`
  `[walk-in]` `[served]` and a free `[check-in]` reach the sous; `[rail] claim|move` and `[status]` and a
  non-free `[check-in]` are **script**; `[rail]` for anything else (decisions, a spec draft, fire,
  close) stays **sous**. The cook sends no `[heard]` back (script kinds need no ack).

## Protected paths

None. `docs/questions/mechanical-enforcement.md` and `docs/plans/…` are not under `.claude/`.

## Phase 1: ticket ids from the rail's form (#59)

**Status:** Done. `ticket-id.js` (new), `budget.js`, `index.js`, `stations.js`; `tests/budget.test.sh` 99 cases. Also: a `[brief]` now starts its own span even after a stray mention, and `PR #76` names no ticket (found by running the budget on this repo: #76 and #80 showed up as tickets).

### Changes

#### `plugins/bk/window/server/live/ticket-id.js` (new)
```js
// A ticket's id in the form the rail uses (Contract 3/4): the markdown ids on every rail, plus
// #N on github and mixed, plus PROJ-123 keys on jira. One place, so budget and the Window agree.
const MD = 'S\\d{3}-\\d{2}|BKLG-\\d{3}|HYG-\\d{3}';
export function idPattern(adapter = 'markdown') {
  const parts = [MD];
  if (adapter === 'jira') parts.push('[A-Z][A-Z0-9]+-\\d+');
  const md = new RegExp(`\\b(${parts.join('|')})\\b`, 'i');
  return adapter === 'github' || adapter === 'mixed' ? new RegExp(`${md.source}|(?<![\\w/&])#(\\d+)\\b`, 'i') : md;
}
export function idOf(text, adapter) { const m = String(text || '').match(idPattern(adapter)); return m ? canon(m[1] || `#${m[2]}`) : null; }
export function idOfBranch(branch, adapter) { /* issue-N-… → #N (github, mixed); <key>-N-… → KEY-N (jira); else the markdown prefix */ }
export function canon(id, adapter) { /* '13' | '#13' → '#13' on github/mixed; others upper-cased */ }
```
(`idOfBranch` and `canon` written out fully in the build, with the cases below as tests.)

#### `plugins/bk/window/server/live/budget.js:72` (edit)
Drop the module `TICKET`; `scanTranscript(file, st, adapter)` (`:89`) uses `idOf(text, adapter)` at `:116`,
`:128` and for `pendingAgents` notes (`:114`, `:134`); `createBudget` (`:209`) takes `adapter`,
passes it to every `scanTranscript`; the CLI (`:~533`) passes `cfg.railAdapter` and runs `--ticket`
through `canon`; `ci(ticket, …)` (`:379`) and `report`/`journalLine` take the canonical id.
`/\bS\d…/` stays the markdown default, so the existing 92 budget cases do not move.

#### `plugins/bk/window/server/live/stations.js:7,22` (edit)
`ticket: idOfBranch(branch, cfg.railAdapter)` replaces the regex.

#### `plugins/bk/skills/kitchen/kitchen.sh:1692` (edit, `cmd_budget`)
No code change expected; `--ticket 13` and `--ticket '#13'` reach the CLI as typed. Check.

#### `tests/budget.test.sh` (edit)
A second kitchen `APPG` with `rail:\n  adapter: github` and a cook transcript briefed on `#13`
(`[brief] #13 …`, `[plan] #13 …`, `[served] #13 https://…/pull/9`, the branch `issue-13-x`):
`--ticket 13` and `--ticket '#13'` show the ticket; `Tickets` lists `#13`; a jira kitchen with
`PROJ-7`; the markdown kitchen still attributes `BKLG-001`; `(?<![\w/&])`: `https://x/issues/13`
and `#x13` name no ticket.

### Success criteria
- [x] `tests/budget.test.sh` passes
- [x] Break it on purpose: put the old regex back in `ticket-id.js` → the new github, jira and `--ticket 13` cases go red; restore
- [x] Manual: in this repo, `plugins/bk/skills/kitchen/kitchen.sh budget --since 7d` lists `#66` or another #N ticket instead of `Tickets (none)`
- [ ] `scripts/check.sh` steps 1–3 (manifests, shellcheck, frontmatter) pass; the full gate waits for the sous's slot (run at the end, with the sous's slot)

## Phase 2: the sous's turns by kind, `relay-heavy`, `ship-rounds`

**Status:** Done. `budget.js`: `wakes` per transcript, `sousTurnsOf`, `sousTurns` on every ticket (ledger, `--json`, the `--ticket` report), `relay-heavy`, `ship-rounds`; `tests/budget.test.sh` 115 cases with main (0.33.0) merged in.

### Changes

#### `plugins/bk/window/server/live/budget.js:128` (edit)
In-marks gain `from` (the `from-name="…"` attribute of the wrapper, read before it is stripped).

#### `plugins/bk/window/server/live/budget.js:255` (edit, `spans`)
`cur.served` (count of out-`served` marks), `cur.findingsAfterServed` (in-`findings` after the first
`served`); `merge()` (`:~290`) adds both; `finish()` (`:300`) leaves them on the span; `strip` keeps them.

#### `plugins/bk/window/server/live/budget.js:346` (edit, `compute`)
After the cook spans are built: for each sous session, walk its turns and in-marks in time order,
give every turn its kind and ticket as in Decisions, and fold into `byId.get(ticket).sousTurns`
(`{ total, byKind, routine }`). Tickets with no sous turns get `{ total: 0, byKind: {}, routine: 0 }`.

#### `plugins/bk/window/server/live/budget.js:413` (edit, `DEBRIEF_RULES`)
```js
const ROUTINE = new Set(['heard', 'status', 'check-in', 'rail']);
{ key: 'relay-heavy', scope: 'plugin', unit: 'ticket',
  about: 'more than half the sous\'s turns on a ticket were relays ([heard], [status], [check-in], [rail])',
  fix: 'make the kind mechanical: a station status file for [status] and [check-in], kitchen.sh rail claim|move for the rail',
  test: (t) => { const s = t.sousTurns; return s && s.total >= 8 && s.routine / s.total > 0.5 ? `${s.routine} of ${s.total} sous turns were relays` : null; } },
{ key: 'ship-rounds', scope: 'plugin', unit: 'ticket',
  about: 'a ticket was pushed again after its first [served] (trunk moved under it)',
  fix: 'merge sooner, and assign the version at merge (a changelog fragment) so a moved main does not cost a round',
  test: (t) => { const n = Math.max(t.findingsAfterServed || 0, (t.served || 0) - 1); return n >= 1 ? `${n} round${n > 1 ? 's' : ''} after the first [served]` : null; } },
```

#### `plugins/bk/window/server/live/budget.js:491` (edit, `report`) and `:471` (`journalLine`)
`--ticket` report: `sous turns  N (kind n, …)`; the journal line stays as is (a cook writes it; the
sous's count is known only at the end).

#### `tests/budget.test.sh` (edit)
In the existing fixture the sous gets turns after known inbound messages for `BKLG-001` (a `[check-in]`,
a `[rail]`, a `[gate]`, a `[heard]`), so `--ticket BKLG-001 --json` has `sousTurns.byKind` of the exact
counts; a ticket with seven relay turns is not `relay-heavy` (the floor), one with ten of twelve is; a cook
transcript that sends `[served]` twice, and one that receives `[findings]` after `[served]`, trip `ship-rounds`
(2 tickets → `DUE`); `debrief` lists neither rule on the existing tickets. Ledger row carries `sousTurns`.

### Success criteria
- [x] `tests/budget.test.sh` passes
- [x] Break it: remove `relay-heavy` from `DEBRIEF_RULES` → its cases red; remove `ship-rounds` → red; make `routine` count `gate` → the byKind and rule cases red; restore each
- [x] Manual: `kitchen.sh budget --ticket '#66' --since 7d` in this repo prints a `sous turns` line

## Phase 3: `kitchen.sh rail brief|claim|move` and `kitchen.sh here`

**Status:** Done. `kitchen.sh`: `cfg_rail`, `rail_*`, `md_*` (plumbing on origin/<trunk>), `gh_*`, `cmd_rail_dispatch`, `cmd_here`, the board section, parser and header; `tests/kitchen.test.sh` +90 cases (both modes, github stub). The full run waits for the sous's slot.

### Changes

#### `plugins/bk/skills/kitchen/kitchen.sh:~252` (edit, parser) and `:1803` (dispatcher)
```bash
POS=()   # bare words, for rail
…
    --fresh) HERE_SESSION=fresh; shift ;;
    --spent) HERE_SESSION=spent; shift ;;
    --waiting) HERE_WAITING="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
    --note) HERE_NOTE="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
    *) if [[ "$CMD" == rail ]]; then POS+=("$1"); shift; else echo "Unknown argument: $1"; usage; fi ;;
```
Dispatcher: `rail) cmd_rail_dispatch ;;` where `cmd_rail_dispatch` runs `rail_write` for `brief|claim|move`
and `cmd_rail` otherwise; `here) cmd_here ;;`. The header usage block (`:34–:143`) documents both.

#### `plugins/bk/skills/kitchen/kitchen.sh` after `cmd_rail` (new functions)
`rail_ticket_path <ID>` (the path at `origin/<trunk>`, or empty), `rail_status <ID>` → `status cook` for
either adapter (markdown from `origin/<trunk>:<path>`), `rail_set <ID> <status> <cook>` per adapter,
`rail_brief_of <ID>`, `rail_write`, `cmd_here`, `cmd_here_board_lines` (used by `board`). The adapters are written as two
function families (`rail_md_*`, `rail_gh_*`) so #64's reader edits do not touch them.

#### `plugins/bk/skills/kitchen/kitchen.sh:955` (edit, `cmd_board`)
After `cmd_files`: `echo ""; echo "The cooks:"; cmd_here_board_lines`.

#### `tests/kitchen.test.sh` (edit, new section "rail: briefs, claims and moves by script" and "here")
Both kitchen modes where the existing sections run both. Markdown: brief refuses from a station and
on a claimed ticket; a claim with no brief refuses; a claim on the briefed free ticket lands on
`origin/<trunk>` as one commit touching only that ticket's `status:`/`cook:` lines (`git log`/`git diff`
on origin), with the main checkout's working tree, index and HEAD byte-for-byte unchanged, **including when
main is dirty with another change to the same ticket file** (that change stays, unstaged, and the claim
still lands); the status read comes from `origin/<trunk>` (main's file edited to say `todo` does not fool
it); a push rejected once because trunk moved is rebuilt and lands; rejected twice exits 1 with nothing
pushed; a second claim by another station refuses and writes nothing (Contract 3); the same station's
repeat is a no-op; `move` follows the legal table, `rfr → done` refuses; `daily-pr` refuses without
writing. GitHub (stub `gh` in `$TMP/ghbin` that logs calls and answers `item-list`,
`field-list`, `view`, `api user`): claim edits the right item with the right option id, assigns, comments;
`In Progress` and `Ready for review` resolve; an unknown column fails loudly; a claimed item refuses.
`here`: writes the file with branch/dirty/ticket/session/waiting; `--note` appends and is capped at 20
lines; refuses in the main checkout; `board` shows the Cooks section, and "no check-in yet" for a bare station.

### Success criteria
- [x] `bash -n` and `shellcheck` on `kitchen.sh` and the tests pass
- [ ] `tests/kitchen.test.sh` passes in full (the new section passes alone, 90/90; the full run waits for the sous's slot)
- [x] Break it: drop the free-ticket check in `claim` → the "second claim refuses" case red; drop the briefs check → the "no brief" case red; make `move` accept `done` → red; make the markdown write edit main's file (a `sed -i` on the working tree) → the "main untouched" case red; read the status from main's file → the "edited main" case red; make `here` write into the main checkout → the station-local case red; restore each
- [x] Manual (demo kitchen, nothing on port 4747): in a throwaway markdown repo with one station, `kitchen.sh rail brief BKLG-001 station-1` from main, `kitchen.sh rail claim BKLG-001 todo` from the station, then `kitchen.sh board` shows the claim and the cook

## Phase 4: the contract and the skills

**Status:** Done. Contract 1, 3, 5, 6 (a Route column and its paragraph), `PLAYBOOK.md`, the question file, and brainstorm, create-plan, grill-me, handoff, implement, line-cook, pick-ticket, rail, review-task, setup, sous-chef; a fresh read-only consistency read found 12 spots, all fixed (it also made `[rail] <ID> grilled` the grilling-done message, noted in Contract 6 and the sous-chef skill).

### Changes

#### `plugins/bk/skills/README.md` (edit)
- Contract 3 (`:206`, `:245`): rule 1 becomes "the sous chef writes the rail; a cook writes only its own briefed
  ticket's claim and moves, through `kitchen.sh rail`, which refuses anything else"; the `brief`, `claim` and
  `move` operations and the `.claude/briefs` record are described once, here.
- Contract 6 (`:583-598`): the table gets a **Route** column (`sous` or `script`) and a paragraph under it:
  the rule for a free `[check-in]` (the one routine message that wakes the sous to assign), the `here` file,
  and that a script kind needs no `[heard]`. `[status]` keeps its meaning but its route is script.
- Contract 5 (`:416`): "sends the sous one `[status]` line" becomes `kitchen.sh here --note "…"`.
- Contract 11/Contract 12 mention nothing else to change; grep proves it (below).

#### Skills (edit, the lines named in Current state)
`line-cook/SKILL.md` (Check in step 4: `kitchen.sh here` unless free; the loop's claim, in-progress and rfr
as `kitchen.sh rail`), `sous-chef/SKILL.md` (Step 0 reads `board`'s Cooks section; Assigning runs
`kitchen.sh rail brief <ID> station-N` with the `[brief]`; "Writing the rail" no longer answers a
claim/move with `[heard]`; the `[hello]` asks cooks to run `here` again), `pick-ticket`, `create-plan`,
`implement`, `review-task`, `grill-me`, `handoff` (each line named above), `rail/SKILL.md` (a note: a cook's
claim/move is `kitchen.sh rail`, the same writes), `PLAYBOOK.md` (the two rows that say "sends `[rail]`").

#### `docs/questions/mechanical-enforcement.md:18-22` (edit)
"Taken on" gets a row: `6 (claim, move)`: built by #65 (`kitchen.sh rail brief|claim|move`); fire, close and
link still hand edits. The "Still open" list keeps 6 for fire/close/link.

### Success criteria
- [x] `git grep -n '\[rail\] claim\|\[rail\] <ID> →\|send the sous .\[status\]\|\[status\] ' -- plugins/bk/skills` lists only the intended remaining uses (decisions, spec drafts, the sous's own `[status] sous restarting`)
- [x] A fresh read-only sub-agent does the consistency read of Contracts 3, 5, 6 against every skill named and lists any file that still disagrees; none left
- [x] `scripts/check.sh` step 3 (frontmatter, Contents lists) passes

## Phase 5: release

**Status:** Done up to the gate. #64 has merged (main 0.33.0 with changelog fragments), so the release is `changelog.d/65-routine-kinds-script.md` (level minor), no version bump. The full gate (`scripts/check.sh`) waits for the sous's slot.

### Changes
- Per #64's release rule **at open-pr time**: if #64 has merged by then, a `changelog.d/` fragment (level
  `minor`) and no edit to `plugin.json`, `Formula/bk.rb` or `CHANGELOG.md`; if not, one minor above main
  (0.33.0 after #80's 0.32.0) in `plugins/bk/.claude-plugin/plugin.json`, the `Formula/bk.rb:9` `url`, and
  `CHANGELOG.md` (`## [0.33.0] - 2026-11-03`). Either way the text is a paragraph for the busy human: cooks
  and the sous now use `kitchen.sh rail brief|claim|move` and `kitchen.sh here`; a running kitchen picks it up
  after a restart; "Closes #59 and #65".

### Success criteria
- [ ] `scripts/check.sh` green (the sous gives the slot), including its release check
- [ ] PR body says "Closes #65" and "Closes #59", and lists the `Done when` boxes below

## Done when (carried from the tickets)

#65: [ ] budget sous turns by kind (`--ticket`, ledger, `--json`) + `relay-heavy` · [ ] `ship-rounds` ·
[ ] routine kinds to script (rail claim/move, status file, sous sent only the named kinds, plus the
free check-in) · [ ] Contract 6 marks each kind; line-cook and sous-chef follow · [ ] tests red without the rules,
and for the script claim and the status file.
#59: [ ] ids from the rail's own form (github `#N` and `issue-N-`, jira keys, markdown) · [ ] a github-rail
`tests/budget.test.sh` case goes red with the old regex · [ ] `kitchen.sh budget --ticket 13` / `#13` shows spend.

## Testing

`tests/budget.test.sh` reaches phases 1 and 2 (handmade transcripts, `node`); `tests/kitchen.test.sh` reaches
phase 3 in clone and worktree mode with a stub `gh`; phase 4 is prose with the grep and the read-only
consistency read; phase 5 is the gate. Each new test is broken on purpose first (listed above).

## References

Tickets #65, #59, EPIC #71; `docs/questions/mechanical-enforcement.md` rows 6–7; Contracts 3, 5, 6; the
journal `docs/journal/65-routine-kinds-script.md` (A1–A3); `budget.js` (`:72`, `:89`, `:255`, `:413`);
`kitchen.sh` (`:894`, `:955`, `:1022`, `:1803`); `rail/SKILL.md` github adapter.
