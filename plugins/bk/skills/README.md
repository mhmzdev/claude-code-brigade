# The Brigade — plugin contract

Every skill in this plugin honours this file. A skill says *how* to do its step; this file
says what every step shares: who does what, where things live, what the names mean, and
which gate belongs to whom. When a skill and this file disagree, this file wins, and the
skill has a bug.

## Contents

- [Contract 1 — The cast](#contract-1--the-cast)
- [Contract 2 — The config](#contract-2--the-config)
- [Contract 3 — The rail](#contract-3--the-rail)
- [Contract 4 — Names and ids](#contract-4--names-and-ids)
- [Contract 5 — Gates: who answers each stop](#contract-5--gates-who-answers-each-stop)
- [Contract 6 — Messages between sessions](#contract-6--messages-between-sessions)
- [Contract 7 — The walk-in](#contract-7--the-walk-in)
- [Contract 8 — Stations](#contract-8--stations)
- [Contract 9 — The three lanes](#contract-9--the-three-lanes)
- [Contract 10 — Talk like a human](#contract-10--talk-like-a-human)
- [Contract 11 — Journals, handoffs and lessons](#contract-11--journals-handoffs-and-lessons)
- [Contract 12 — The record: what the kitchen remembers](#contract-12--the-record-what-the-kitchen-remembers)
- [The skills](#the-skills)

---

## Contract 1 — The cast

| Role | Who | Does | Never does |
|---|---|---|---|
| **Head Chef** | the human | talks to **one** session, the sous: makes the decisions nobody has made yet (new features and flows, real forks), merges, deploys | relays messages between sessions, watches the cooks' terminals, or answers what the record already answers |
| **Sous Chef** | one Claude Code session in the **main checkout**, running `/bk:sous-chef` | assigns tickets, answers every gate the record or routine can settle, signs off bug, chore and hygiene plans, brings feature plans and real forks to the head chef with a recommendation and relays the answer, keeps the record (Contract 12), reviews every diff before commit, **is the only writer of the rail** | writes code in a station, merges, deploys, decides a fork the record doesn't settle |
| **Line Cook** | one Claude Code session per **station** (started by `kitchen open`, or any session in a station) | works one ticket from plan to PR; sends the commis before it sends a question | edits ticket files, touches another station, empties the walk-in without asking, settles a design fork on its own |
| **Commis** | the `commis` sub-agent, spawned by a cook or the sous before any question goes up | searches the record for a decision already made or a fact already written, and returns a short verdict with its sources (the junior who fetches for the line) | holds any tool that can write; decides anything |
| **Inspector** | the `inspector` sub-agent | reads a diff and reports what shouldn't be there (the health inspector: looks, never cooks) | holds any tool that can write |
| **Taster** | the `taster` sub-agent, spawned by the sous at the pass | reads a cook's diff, re-runs the check, walks "Done when", returns a verdict and numbered findings, so the sous doesn't read whole diffs | edits, commits, or messages anyone |
| **Runner** | the `runner` sub-agent, anyone may spawn it | runs one noisy command (the check, a test suite, a scan) and returns only pass/fail plus the failing lines | decides anything, or edits |

**A session inside a station is a line cook, whether or not `/bk:line-cook` was typed.**
After a `/clear`, the next skill may run straight away: it must still
behave as a cook. So every lifecycle skill starts with the **station check**:
`"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" role` prints `cook <station> <main checkout>`
inside a station and `main <main checkout>` elsewhere. On `cook`, read and follow
`${CLAUDE_SKILL_DIR}/../line-cook/SKILL.md` for where questions go and what a cook never does.

A session in the main checkout that is not running `/bk:sous-chef` is a **solo**
session: the head chef working alone. Every skill still works solo. The human is then both
chef and sous, and every gate goes to them.

## Contract 2 — The config

Every skill reads **`.claude/brigade.md`** at the repo root before doing anything
repo-specific. Never guess a trunk, a check command or a path that the config names. If
the file is missing, say so and offer `/bk:setup`.

The frontmatter has two parts. **Flat keys** are read by `kitchen.sh` as well as by the
skills, so they stay one line each. **Nested blocks** are read only by the skills.

```yaml
---
# flat — read by kitchen.sh too
trunk: main
check: "npm run check"
install: "npm install"
copy_into_stations: ".env .env.local"   # space-separated; names only
kitchen_mode: clone                      # clone (default) | worktree — see Contract 8
permission_mode: auto                    # cook sessions' Claude Code permission mode (default auto)
sous_model: opus                         # the sous's model when `kitchen open` starts it in tmux (default opus)
kitchen: stations                        # stations dir, relative to repo root (worktree default: ../<repo>-stations)
stations: 2                              # how many a fresh setup creates; setup -n N grows it
migrations: none                         # path, or none
commis_model: opus                       # the commis sub-agent's model (Contract 12); opus by default, sonnet to trade accuracy for cost

# nested — read by skills
rail:
  adapter: markdown                      # markdown | github | jira | mixed
  commit: direct                         # direct (sous commits rail changes to trunk) | daily-pr
  # github: { owner: <org-or-user>, project: <number>, status_field: Status }
  # jira:   { site: <x.atlassian.net>, project: <KEY> }
walk_in:
  - name: local-db
    destructive: ["make reset", "docker compose down -v"]
    safe: ["make migrate"]
gates:
  assign: sous-chef                      # sous-chef (assigns the next ticket itself) | head-chef (proposes, waits for a yes)
  plan_approval:                         # who signs off a plan, by what the ticket is (Contract 5)
    feature: head-chef                   # lane A tickets, and items built without a spec: always head-chef
    bug: sous-chef                       # kind: bug
    chore: sous-chef                     # kind: chore
    hygiene: sous-chef                   # HYG tickets (the ticket is the plan)
  pre_commit: sous-chef
  merge: head-chef
  deploy: head-chef
clean:                                   # lane C counters; each command prints one finding per line
  counters:
    - name: unused-code
      command: "npx knip --no-progress --reporter compact"
    - name: todo-comments
      command: "git grep -n -E 'TODO|FIXME' -- ':!docs'"
  umbrella: null                         # optional: a tracker id, or a markdown ticket path whose ## Snapshots gets a row per scan
prices:                                  # the budget's price table, USD per million tokens; a key is any part of a model id
  # opus: { in: 4, out: 20, read: 0.20 } # overrides the built-in list prices (cache writes: 1.25x in, 2x for the 1-hour kind)
budget:                                  # the scale the Ledger draws spend against; a meter, not a limit (nothing stops)
  # shift_usd: 60                        # the shift's bar: spend of this
  # ticket_usd: 12                       # each dish's bar
docs:                                    # the map of everything the kitchen keeps (Contract 12)
  specs: docs/specs
  backlog: docs/backlog
  plans: docs/plans
  checklists: docs/checklists
  journal: docs/journal                  # any depth: a journal moved to a subfolder still counts
  lessons: docs/lessons.md               # the register: promoted lessons and handled decisions (a file)
  research: docs/research
  brainstorm: docs/brainstorm
  decisions: docs/decisions              # ADRs: decisions the head chef made that outlive one ticket
  conventions: docs/conventions          # how code here is written
  knowledge: docs/domains                # how the product works, by area
  questions: docs/questions              # open questions nobody has answered yet
  # any other key is one more place the commis searches; the sous adds one when no type fits
---
Free-text repo notes the skills should respect.
```

`gates.plan_approval` may also be the one word `head-chef`, which brings every plan to the
head chef. A missing block means `feature: head-chef` and the rest `sous-chef`. `feature`
is always `head-chef`: a config that says otherwise is read as the default. A `docs`
key set to `none` means the repo keeps no such store; `.claude/inbox.md` (Contract 12) is
not under `docs` because it never reaches git.

**The budget.** The kitchen knows what it spends: tokens (input, output, cache read, cache
write), money, time and CI minutes, per session and per ticket, read from the transcripts
Claude Code keeps for every session and sub-agent. `kitchen.sh budget` prints it, the
Window shows it (a chip at the foot that opens **the Ledger**, a page of dishes and sessions
over the shift, today or the week, each dish split into prep, cook, check and serve with
every step and what a red check cost in rework; and rows on each figure's page), and nothing
in the kitchen records it by hand. A `budget:` block gives the Ledger a scale to draw spend
against. Money is tokens times the model's list price on a dated
built-in table; `prices:` overrides any entry. Served tickets and CI results are kept in
`.claude/budget.jsonl` (out of git) because Claude Code deletes transcripts after its
cleanup period. It is a meter, not a limit: nothing stops because of it. A dish's stages
follow its messages: prep from the brief to the sign-off, cook to `[handoff]`, check to
`[go]`, serve to `[served]`; a hygiene ticket cooks from the brief.

**Where each artifact lands.** Rail artifacts (specs and tickets) are written by the sous in
the main checkout and reach trunk straight away (`rail.commit`). Work artifacts (a ticket's
plan and checklist) are written by its cook in the station and reach trunk **with the
cook's PR**, alongside the code. Until then the plan exists only in that station: the sous
reads it by absolute path, `kitchen.sh files` marks it `(plan)`, and the ticket's `todo`
status on the rail is the only sign elsewhere that it exists.

Machine-only notes (credentials, local ports) live in **`.claude/brigade.local.md`**,
which is gitignored. Skills may read it and never copy from it into a committed file.

**Test accounts.** That file's `## Test accounts` section is where the head chef leaves the
logins sessions may use to test a flow, so nobody is asked for the same credentials twice.
It has one block per environment, `local`, `stage` and `production`, and each account has
a short **name** (`stage-builder`), its login details and what it's for. The shape ships
as `${CLAUDE_SKILL_DIR}/../../templates/brigade.local.md`.

- **Getting one.** A cook sends `[gate] <ID> need a test account: <environment>, <role>`.
  The sous answers with the account's **name**, and the cook reads that entry itself from
  the main checkout's file by absolute path. A solo session reads the file directly.
- **A missing account.** The sous (or a solo session) asks the head chef once, shows the
  block to fill, and the head chef types it into the file themselves, so the secret never
  passes through a chat. If they paste it in chat anyway, the session writes it to the
  file. An empty section means "ask", never "guess" and never "create one".
- **Secrets never travel.** A secret is the value of a `password:`, `code:`, `token:` or
  `secret:` line. None goes into a message, a journal, a plan, a checklist, a ticket, a
  test, the board, a handoff note, a commit, a PR or a feedback issue. Those name the
  account ("walked as `stage-builder`") and nothing else: a journal is committed with its
  PR, and a value passed around in messages ends up copied into one. An automated test
  that needs a secret reads it from an environment variable at run time. A login the repo
  already commits (local seed users) is not a secret; the entry can just point at it.
- **The leak check is mechanical.** `kitchen.sh leaks` searches a checkout's changed files
  and its branch's commit messages for every secret in the file and prints `file:line`,
  never the value. The taster runs it at the pass, `/bk:open-pr` runs it again before it
  commits and before it pushes (the journal's closing handoff and the PR body are written
  after the pass), and `/bk:feedback` runs it on its draft. It is a literal search: it
  can't see a secret that was encoded, split or reworded, and it skips values under six
  characters, saying so.
- **Reading the file leaves its contents in that session's local transcript.** That is as
  private as the file itself. The rules above are about what leaves the machine.
- **Production is read-only by default.** Only accounts listed under `production` are
  used there, and they are test accounts, never a real user's. Looking is fine. Any action
  that **writes** (creates, edits, deletes, pays, sends) needs the head chef's yes for that
  exact action: a cook sends `[gate] <ID> production write: <the action, as which account>`,
  the sous asks the head chef in its own session and relays the answer marked
  `(head chef)`. One yes covers one action; it is never standing.

## Contract 3 — The rail

The rail is wherever tickets live. It is an **adapter**: every skill talks to it in six
operations and never assumes which backend is behind them. `/bk:rail` is the one
place that knows how each backend does each operation.

| Operation | markdown | github | jira |
|---|---|---|---|
| **list** | frontmatter of every ticket file | `gh project item-list` | JQL search |
| **read** | the file | `gh issue view` | get issue |
| **claim** (status + cook) | edit `status:`, `cook:` | Status field + assignee | transition + assignee |
| **fire** (create) | write a new file | `gh issue create` + add to project | create issue |
| **link** (blocked by) | `blocked_by:` | native blocked-by / sub-issue | issue link |
| **close** | `status: done` (plus `spec:` for a backlog item that became a spec) | close the issue (same case: with a comment naming the spec) | transition to Done (same case: comment first) |

**Statuses, the same on every backend:** `backlog` → `todo` → `in-progress` → `rfr` →
`done`, plus `blocked`.

- `backlog` and `blocked` are **free**. Anything else is **somebody's claim**. Never
  plan, start or overwrite a ticket in `todo`, `in-progress` or `rfr` unless you are that
  ticket's cook.
- `todo` means a plan exists, even if you can't see it. The plan is an uncommitted file in
  another station.

**Priority** is optional: `priority: high | normal | low` in a markdown ticket's
frontmatter (absent means `normal`), the tracker's own priority field or a
`priority:high` label on github or jira. It is set by the head chef's word, when the
ticket is fired or later, and written by the sous like any other rail change.
`kitchen.sh rail` shows it in the `PRI` column.

**What's next.** A ticket is **ready** when its status is `backlog` or `blocked`, every
ticket in its `blocked_by` is `done`, and it isn't a backlog item that still needs a spec
(Contract 4: every `BKLG` item that isn't `kind: bug` or `kind: chore`). `kitchen.sh rail` works all of
that out itself: the `RDY` column says `yes`, `no` (a blocker is open) or `spec` (a backlog
item that has to become a spec and tickets first), and a ticket's still-open blockers are
printed after its title. A blocker id that
is no ticket on the rail (an id from an older scheme, or a typo) is printed with `?` and
**holds** the ticket: nothing proves it's done. The sous removes it from `blocked_by` once
the head chef says that work is finished.
Among ready tickets the next one is picked in this order:

1. what the head chef has said to do first, or to hold;
2. `priority`: `high` before `normal` before `low`;
3. the ticket more other tickets are blocked by;
4. lane A before lane B before lane C; within a spec, ticket-number order; otherwise the
   lowest id (the oldest) first.

**Two rules that keep any rail honest:**

1. **Only the sous chef writes the rail.** That covers every edit to a ticket: status,
   cook, links, *and* body edits such as a `## Decisions` section. Cooks ask by message. In
   a solo session the human is the sous, so solo skills write the rail directly.
2. **No hand-kept summary page.** The board view is computed each time (`kitchen.sh rail`,
   or the tracker's own board). A hand-kept roll-up drifts. `kitchen.sh board` prints
   stations, files in flight, the rail, open questions and the record's counts in one go, and from the main
   checkout also writes them to `.claude/board.md` for a human to keep open. That file is
   generated, never edited and never committed (it's listed in `.git/info/exclude`).

**Markdown rail commits.** With `rail.commit: direct` the sous commits each rail change to
trunk on its own (`rail: BKLG-004 → in-progress`) and pushes. With `daily-pr` it
accumulates them on a `rail/YYYY-MM-DD` branch and opens one PR. Cooks read ticket files by
**absolute path in the main checkout**, so they never wait for either.

**Closing.** A tracker usually closes the ticket on merge. A markdown rail has nothing to
do that, so the sous closes the ticket (`status: done`) through `/bk:rail` once the
head chef has merged.

**A backlog item that became a spec closes when the spec is written**, not when the code
merges. `close` then also records the spec: `spec: SNNN` on a markdown rail, a closing
comment naming the spec on github or jira. From there the spec's tickets carry the work
(Contract 4).

## Contract 4 — Names and ids

**Things the rail tracks get numbers. Everything else gets a date.** Numbers are safe
because only one session (the sous) hands them out. They are zero-padded and never reused.

| Kind | Path (markdown rail) | Id |
|---|---|---|
| Spec | `docs/specs/NNN-<slug>.md` | `SNNN` |
| Spec's ticket (lane A) | `docs/specs/NNN-<slug>/NN-<slug>.md` | `SNNN-NN` |
| Backlog item (lane B) | `docs/backlog/BKLG-NNN-<slug>.md` | `BKLG-NNN` |
| Hygiene ticket (lane C) | `docs/backlog/HYG-NNN-<slug>.md` | `HYG-NNN` |
| Plan | `docs/plans/<id>-<slug>.md` | the ticket's id |
| Checklist | `docs/checklists/<id>-<slug>.md` | the ticket's id |
| Journal | `docs/journal/<id>-<slug>.md` | the ticket's id |
| The register: promoted lessons and handled decisions | `docs/lessons.md` (`docs.lessons`) | — (one row per promoted key or kept answer) |
| Sous handoff | `.claude/sous-handoff.md`, **gitignored** | — (overwritten each handoff) |
| Sous's session name | `.claude/sous`, kept out of git (`.git/info/exclude`) | — (written by `kitchen.sh sous --set` when the sous starts) |
| Research | `docs/research/YYYY-MM-DD-<slug>.md` | — |
| Brainstorm | `docs/brainstorm/YYYY-MM-DD-<slug>.md` | — |
| Branch | `<lowercase id>-<slug>` e.g. `bklg-004-fix-login` | — |
| PR title and commit subject | `[<ID>] <imperative summary>` | — |
| Draft spec (a cook's, before it has a number) | `docs/specs/draft-<slug>.md` | — the sous numbers it |

On a github or jira rail, ticket ids come from the tracker (`#123`, `ABC-123`) and plans,
checklists and branches use them the same way (`gh-123-<slug>`, `abc-123-<slug>`). Specs
stay in `docs/specs/` on every rail.

`<slug>` is lowercase-kebab, 2–5 words. Every docs folder has an `INDEX.md` with one
row per file; the skill that writes a file adds its row.

Beyond the rail, the record (Contract 12) adds:

| Kind | Path | Id |
|---|---|---|
| Decision (ADR) | `docs/decisions/NNN-<slug>.md` (`docs.decisions`) | `NNN`, handed out by the sous |
| Open question | `docs/questions/YYYY-MM-DD-<slug>.md` (`docs.questions`) | — |
| Inbox | `.claude/inbox.md`, kept out of git | — (one line per thing heard, cleared as it's filed) |

A repo with its own doc schema keeps its own names and frontmatter for these; `brigade.md`'s
notes say so, and the sous follows them.

**Ticket frontmatter (markdown rail):**

```yaml
---
id: BKLG-004
title: One line
lane: B                  # A | B | C
status: backlog          # backlog | todo | in-progress | rfr | done | blocked
cook: null               # station name once claimed
kind: item               # BKLG only: item (becomes a spec and tickets) | bug | chore (both planned and built directly)
spec: null               # lane A: the parent spec. BKLG: the spec it became
priority: normal         # high | normal | low (optional; Contract 3)
blocked_by: []
files: []                # paths it will likely touch
created: YYYY-MM-DD
---
```

**A backlog item is work that still has to become tickets.** `BKLG-NNN` is where anything
lands first, and capturing one is cheap. A **ticket** (`SNNN-NN`) is what a cook plans and
builds: it has been grilled, specced and sliced, so it is one step from a plan. A backlog
item is further back. Its `kind:` says which way it leaves the backlog:

- **`kind: item`** (the default, and what a missing `kind:` means): a capability, a change
  in behaviour, a chore, a follow-up. It goes `grill-me` → `spec` → `file-tickets`, and the
  spec's `SNNN-NN` tickets are what gets built. The item is closed with `spec: SNNN`, and
  the spec lists it under `backlog:`. It is never planned, built or claimed directly: it
  stays `backlog` until its spec closes it.
- **`kind: bug`**: something that already exists and works wrong, measured against how it
  is meant to work. It needs no spec, because the intended behaviour is already decided.
  The item is its own ticket: `create-plan`, then build.
- **`kind: chore`**: work whose outcome is already fixed and nobody would argue about: a
  dependency bump, a rename, a missing checklist item, a follow-up a reviewer asked for, a
  doc that has to say what the code already does. No behaviour changes. Like a bug, it is
  its own ticket: `create-plan`, then build.

**Bug, chore or item is a fact about the work, not a size.** A "small" new behaviour is
still an item. A fix that turns out to need a decision about *what* the behaviour should be
was never a bug, and a chore that turns out to need one was never a chore: say so, and it
becomes an item. The sous sets or corrects `kind:` as a rail change, with one line of why.
The one way an item is built without a spec is the head chef saying so for that item; the
plan then notes that it has none, and its sign-off is the head chef's (Contract 5).

On a github or jira rail a backlog item is an issue labelled `lane:B` (plus `bug` or
`chore`), and "closed into a spec" shows as its closing comment (`Became spec SNNN: <path>`)
rather than a `spec:` field.

**Plans don't move between folders.** A plan's lifecycle is its `status:` field,
`draft → approved → active → done`. Plan frontmatter:

```yaml
---
ticket: BKLG-004
title: One line
lane: B
status: draft            # draft | approved | active | done
open_questions: none     # must be `none` before implement will start
migration: false
files: []
created: YYYY-MM-DD
---
```

Templates for spec, ticket, plan, checklist, journal, decision, question, `SCHEMA.md` and `brigade.local.md` ship with the plugin at
`${CLAUDE_SKILL_DIR}/../../templates/` (from inside any skill).

**Research.** v0 ships no research skill. `brainstorm` and `create-plan` research with `Explore`
sub-agents; if the repo has its own research skill (e.g. `/research-codebase`), prefer it.
Research that's worth keeping goes to `docs/research/YYYY-MM-DD-<slug>.md`.

## Contract 5 — Gates: who answers each stop

**Invoking a skill is the approval for that skill's whole job.** `/bk:create-plan` doesn't
ask "does this look right?" before or after writing: being asked to plan was the go. It
presents the plan and stops. `/bk:implement` doesn't ask "phase 1 done, go on?": it runs
every phase. `/bk:review-task` and `/bk:open-pr` do their whole job. A skill stops only
for a **decision** it can't settle from the ticket, the plan or the code (a design fork, a
contradiction, a failure it can't fix), never for ceremony.

**The head chef talks to one session.** In a kitchen that is the sous: it sees every
station, so it can put a recommendation next to each question. A cook never asks the human
anything unasked and never opens an `AskUserQuestion` dialog for its own questions; nobody
is watching its terminal, and the plugin's hook refuses the dialog in a station outside a
grilling.
Everything a cook needs decided goes to the sous as a `[gate]`. The sous answers what the
record or routine settles, and takes the rest to the head chef in its own terminal, with a
recommendation, then relays the answer marked `(head chef)`. The one planned exception is a
grilling the sous hands to a cook (the table below): the questions are for the human, so the
human answers them in that station. If the human does type in a cook's terminal,
the cook does as told and sends the sous one `[status]` line, so the sous's picture stays whole.

**Three kinds of unknown, and only one is the head chef's.** Before any question goes up,
whoever holds it works out which kind it is:

1. **A fact**: how the code or the product works today. It is in the code, the docs or the
   record. Nobody's question but the agent's: look it up. A fact is never stored on its own;
   the code is its source and a copy would rot.
2. **A decision already made**: the head chef (or a spec they approved) has answered this,
   somewhere in the record (Contract 12). Found, it is answered with its source and the
   head chef is never asked twice. The commis exists to find these.
3. **A decision nobody has made**, and that changes what gets built: product behaviour,
   visibility, a metric's meaning, scope, a new flow. The head chef's, however confident
   anyone feels. Once answered it becomes kind 2 and is written down.

**The chain**: a cook with a question spawns the **commis** first. *Settled* with a source
→ the cook logs `An (commis): <answer>, per <source>` and goes on. *A fact* → the cook reads
the `file:line` and goes on. *Blocked* (an open question file already asks this) → the cook
sends `[gate] <ID> Qn, see journal. commis: blocked on <question file>`; the sous may have
the answer by now, else the cook's ticket waits like the file's. *Nothing*, or *conflict*
(two records disagree) → the cook sends the `[gate]`, with the commis's result in it
(`commis: nothing recorded in <places>`, `commis: conflict between <a> and <b>`), so the
sous doesn't search again. The sous answers if it is routine or the record settles it
(it may send the commis once more, wider), and tells the head chef in one line whenever its
answer came from the record. Otherwise it is kind 3: the sous asks the head chef with a
recommendation, relays the answer marked `(head chef)`, and the answer is recorded.
**A commis result settles a question only when it cites a decision.** A related fact never
closes a design fork in a cook's hands; it goes up with the fact attached. When the sous
can't tell which kind a question is, it's kind 3.

**The sous assigns the work.** With `gates.assign: sous-chef` (the default), the sous puts
each free cook on the next ready ticket (Contract 3) without asking, and tells the head
chef what it assigned and why in one line. The head chef steers by saying what comes first
or what to hold. With `gates.assign: head-chef`, the sous
proposes and waits for a yes. Either way a cook only gets a ticket when it is **free**: it
has checked in with no ticket, a clean station, and a fresh session. That `[check-in]` is
enough: the sous never asks the cook to confirm it was cleared. A cook that has just served
is not free until its session has been cleared. Freshness is about the session's own
context, not the station's history: a journal that says the station served a ticket is an
earlier session's work. And when the head chef says they've just cleared a cook, that
outranks a check-in that says spent.

**The sign-off is what starts `/bk:implement`.** It approves the plan and authorises
every commit made under it (after the sous's pass). No separate "approve?" question exists.
**Who signs off depends on what the ticket is** (`gates.plan_approval`, Contract 2):

| The ticket | Default signer | Why |
|---|---|---|
| a lane A ticket (`SNNN-NN`), or an item the head chef said to build without a spec | **head chef** | a feature or a new flow: a decision about what the product does |
| `kind: bug` | sous | the intended behaviour is already decided; the plan only restores it |
| `kind: chore` | sous | the outcome is already fixed; nothing to decide |
| a `HYG` ticket (lane C) | sous | the counter is the whole intent; the ticket is the plan |

Whatever the kind, a plan goes to the **head chef** when it carries a migration, touches a
`walk_in:` resource, needs a production write, or makes a decision the record doesn't hold
(the sous asks the commis before signing off: a bug plan that settles something unrecorded
was a feature in disguise). The head chef can also say "show me every plan" for a while, and
the sous does.

- **Solo:** the human types `/bk:implement`, or says in plain words to build the plan.
  A solo session never chains into `implement` from `create-plan` by itself.
- **In a kitchen:** the cook sends `[plan] <ID> ready: <path>`. The sous reads the plan and
  checks it against the other stations. A plain defect goes back as `[findings]` first.
  Then, by the table: the sous sends `[approved] <ID>: <path> · sous, per
  gates.plan_approval.<kind>` and tells the head chef in one line; or it shows the head chef
  a short summary with its recommendation and on their yes sends `[approved]`, quoting
  them. The cook records it in the journal and starts `/bk:implement` itself. `implement`
  refuses to start in a station without that record (the one other way in: the head chef
  typing `/bk:implement` in that station themselves).
- **A feature plan is never approved by the sous.** It needs the head chef's own yes, in the
  sous's current session, after seeing that plan. A changed plan needs a new yes. A handoff
  note, a standing remark or an earlier ticket's approval is not one.
- **Lane C has no plan**, so the sign-off is on the ticket itself: the sous reads the
  ticket's findings list before the brief, and the brief carries the `[approved]` line.

Only `setup` has `disable-model-invocation: true` (it changes a repo's layout). Every
other skill is model-invocable, or cooks would stall waiting for a human to type it.

**Who** answers a decision depends on where the skill runs.

| Gate | Solo session | Line cook |
|---|---|---|
| Plan approval (the **sign-off**) | human types `/bk:implement`, or says to build the plan | by `gates.plan_approval`: **the sous** for a bug, chore or hygiene plan (it tells the head chef); **the head chef, in the sous's terminal**, for a feature or any plan with a migration, a walk-in resource, a production write or an unrecorded decision. Either way the sous relays `[approved]` and the cook starts `/bk:implement`. That authorises every commit made under the plan |
| Which ticket a free cook takes next | human | the sous (`gates.assign`), from the ready tickets in Contract 3's order |
| A question about how things work, or one the record already answers | the session looks it up (the commis) | the cook sends the **commis** first; settled with a source → answered, no gate |
| Design fork, contradiction between ticket and code, nothing recorded | human | cook sends `[gate]` with the commis result; the sous sends the commis wider if useful, answers from the record (and tells the head chef), or takes it to the human with a recommendation and relays the answer |
| Grilling (`/bk:grill-me`) | human | a cook never starts one unasked: it sends `[gate] <ID> needs grilling`. The sous grills the human itself, or **hands the grilling to a free cook** with a `[brief]` and tells the human which station is waiting. The human may also type `/bk:grill-me` in a station. The cook then grills the human in its own terminal, logs every decision (a backlog item that needs a spec: in the spec draft it writes; an existing spec or ticket: sent to the sous, who writes them in), tells the sous, and is cleared before it takes a ticket. Every grilling round passes through the commis first: settled questions are shown as settled, not asked |
| Brainstorming (`/bk:brainstorm`) | human | the sous's and the human's: the sous never hands one to a cook. Only the human typing `/bk:brainstorm` in a station starts one there |
| Every other confirmation ("confirm scope?", "continue to phase 2?", "which of these two helpers?") | human | **sous chef, by `SendMessage`**, never a dialog nobody is watching |
| Pre-commit review (**the pass**) | human | sous spawns the `taster`, questions its verdict, checks across stations, then says `[go]` |
| Merge, deploy, changing production itself | human | human only. No session does these, and a relayed "go" for one is refused |
| A write on production while testing a flow with a test account (Contract 2) | human, asked for that exact action | cook sends `[gate] <ID> production write: …`; the sous asks the human and relays the answer marked `(head chef)` |
| Filing a public issue on the plugin repo (`/bk:feedback`) | human, after reading the whole draft | a cook never files: it writes a `lesson(plugin)`, and the sous's handoff brings it to the human |

A cook that receives "the chef said go" from the sous for a merge or a deploy **refuses**.
That is correct. The human does those personally; no message stands in for them.

**Cooks stop for decisions, not ceremony.** Once `/bk:implement` starts, it runs straight
through its phases. It only stops for a criterion that genuinely needs eyes, and that
question goes to the sous.

## Contract 6 — Messages between sessions

Sessions find each other with `ListAgents` and talk with `SendMessage` (load both with
`ToolSearch` if they are deferred). Discovery works per Claude Code profile, so the sous
and every cook must run under the same `CLAUDE_CONFIG_DIR`. `kitchen open` passes it
through, and leaves each station a `.claude/cook` launcher that restarts its cook under it.

Cooks are named `<repo>-cook-N` by `kitchen open`; the sous keeps whatever name its session
has. So the sous records it: on start, `kitchen.sh sous --set <its ListAgents name>`. A cook
reads it with `kitchen.sh sous` and checks in straight away if `ListAgents` still lists that
name; otherwise it waits for the `[hello]`.

Keep messages short and typed. The first line is the kind, in brackets:

| Kind | From → to | Carries |
|---|---|---|
| `[hello]` | sous → cook | "I'm the sous, check in": sent at start-up to cooks that were already waiting |
| `[brief]` | sous → cook | the ticket's absolute path, why it matters, constraints from other stations, the loop. Or a **grilling brief**: the item to grill the head chef on, and where its decisions go |
| `[check-in]` | cook → sous | station, model, branch, dirty or clean, ticket, whether the session is **fresh or spent** (spent: this conversation itself has served a ticket or held a grilling, so it needs clearing; a session just started or just cleared is fresh, whatever the station's journal or branch says), and **what it's waiting on** (a question id, the plan's sign-off, the pass, a walk-in clearance, or nothing) |
| `[gate]` | cook → sous | the question, the options, the cook's recommendation, and the commis's result (`commis: nothing recorded in <places>`, `commis: conflict between <a> and <b>`, or `commis: blocked on <question file>`) |
| `[rail]` | cook → sous | a rail change request: `claim BKLG-004 todo`, `BKLG-004 → rfr`. Also a file for the sous to record in the main checkout, by absolute path: a spec draft, grilling decisions, a brainstorm doc |
| `[walk-in]` | cook → sous | "about to run `<command>` on `<resource>`, OK?" |
| `[status]` | anyone | a state change that needs no answer: "the head chef told me directly to …", "implement started (signed off)", a lane-C counter before/after |
| `[handoff]` | cook → sous | "ready for the pass": branch, files, check result, inspector result, absolute checklist path |
| `[findings]` | sous → cook | numbered items, each with file and why |
| `[plan]` | cook → sous | the plan is ready for the sign-off: its absolute path. The cook waits for `[approved]` or `[findings]` |
| `[approved]` | sous → cook | the sign-off: start `/bk:implement`. Either the sous's own, naming its rule (`[approved] <ID>: <path> · sous, per gates.plan_approval.<kind>`), or the head chef's yes in their words (`[approved] <ID>: <path> · head chef: "<words>"`). A feature plan only ever gets the second |
| `[go]` | sous → cook | commit approval after the pass |
| `[served]` | cook → sous | the PR is open: its URL |
| `[heard]` | anyone | acknowledgement, one line; also the sous's **answer** to a `[gate]`: its own (`[heard] Q3: <answer>, because …`, copied in as `A3 (sous)`), from the record (`[heard] Q3: <answer>, settled in <path> (<date>)`, copied in as `A3 (sous)` with the source), or relayed (`[heard] Q3: <answer> (head chef), because …`, copied in as `A3 (head chef)`, the tag the record is built from) |

**The message is the doorbell; the journal is the letter.** Anything a cook would send that's
longer than a line (a question with options, ticket drafts, a handoff) is written into the
ticket's journal first, and the message points at it. The sous's answers and findings go by
message, and the cook copies them into the journal; the sous never writes journals: `[gate] BKLG-004 Q3, see journal`. Messages vanish when
a session is cleared; the journal doesn't. When a sous starts, its `[hello]` asks every
cook to re-send whatever it's waiting on, so nothing sent during a restart is lost.

**Believe the cook.** When a cook says the sous's picture of its station is wrong, the cook
is standing in the station and wins. The sous re-checks.

## Contract 7 — The walk-in

The walk-in is every shared local resource listed under `walk_in:` in the config: a
database, a docker stack, a fixed port.

- Before a **destructive** command on a walk-in resource, a cook sends `[walk-in]` and waits
  for the sous. The sous checks the other stations (asking them if unsure), then clears
  or sequences it.
- Prefer the resource's **safe** command when one exists. A reset replays only the cooking
  station's own migrations, so it silently drops every other station's unmerged schema.
- **Only one station carries a migration at a time** (`migrations:` in the config) until it
  merges.

## Contract 8 — Stations

A station is where one cook works. `kitchen.sh` creates it, adds the ignore line, copies
`copy_into_stations`, and runs `install`. There are two kinds, picked by `kitchen_mode:`.

| Mode | Where | What it is | Use it for |
|---|---|---|---|
| **`clone`** (default) | `<repo>/stations/station-N`, gitignored | a full clone | one standalone repo: the simplest setup |
| **`worktree`** | `../<repo>-stations/station-N`, next to the repo | a git worktree of the main checkout | big repos, and repos that live inside a workspace repo |

A config without `kitchen_mode:` is clone mode, so existing setups don't change.

### Clone mode

Things this layout needs you to know:

- **`git clean -fdx` in the main checkout deletes every station, uncommitted work
  included.** `-x` removes ignored files. Never run it in a brigade repo. `kitchen.sh`
  prints this warning on setup.
- Tools that don't read `.gitignore` will see the stations: `tsc` include globs, test
  runners, linters, `docker build .` contexts, file watchers. `kitchen.sh setup` adds
  `stations/` to `.dockerignore` when one exists, and lists the configs you should exclude
  it from.
- A session started inside a station also loads the main checkout's `CLAUDE.md`, because
  Claude Code reads `CLAUDE.md` files up the directory tree. Both are the same file at
  possibly different commits. The station's own copy describes the station's branch;
  prefer it where they differ.

### Worktree mode

A worktree is a second working folder backed by the **same** repo: one object store, one
set of branches, one `git fetch` for everyone. Stations cost only their checked-out files.

- **Idle stations are detached at `origin/<trunk>`.** Git lets a branch be checked out in
  one worktree only, and the main checkout already holds trunk. A cook branches off
  `origin/<trunk>` as usual; `kitchen.sh sync` re-detaches idle stations.
- **Stashes are shared across stations.** A cook stashes with
  `git stash push -m "<station>: …"` and applies only its own entry, by name, never a
  bare `git stash pop`. Parking work on a named branch is safer still.
- **Branches are shared too.** That's why branch names carry the ticket id: two cooks
  can't collide. Removing a station keeps its branch and commits.
- **Remove with `kitchen.sh remove`, never `rm -rf`.** It uses `git worktree remove`,
  which refuses a station with uncommitted work, then prunes git's records.
- **Dependencies are per station** (`node_modules`, `.dart_tool`, Pods, virtualenvs): the
  install step still runs in each one.
- **The sibling folder may sit inside another repo**, e.g. a workspace checkout that holds
  several product repos. `kitchen.sh setup` adds the ignore line to **that** repo's
  `.gitignore`, and a cook there loads the workspace's `CLAUDE.md` as well as the repo's.
- Run from anywhere, including inside a station: `kitchen.sh` finds the main checkout
  through git's common directory.

### Both modes

**The sous reads stations and never writes in them.** No edits, resets or branch
switches. Running the check command or the inspector inside a station is fine. A finding
goes to the owning cook.

## Contract 9 — The three lanes

A lane is defined by **where its tickets come from**.

| Lane | Name | Source | Path through the skills |
|---|---|---|---|
| **A** | Specials | a spec, sliced into tickets. The spec starts from a brainstorm or from a backlog item that needs one | (brainstorm or pick-ticket) → grill-me → spec → file-tickets → create-plan → implement → review-task → open-pr |
| **B** | À la carte | bugs and chores: backlog items marked `kind: bug` or `kind: chore`. Every backlog item is filed `lane: B`; one that is neither leaves for lane A through a spec | pick-ticket → (grill-me) → create-plan → implement → review-task → open-pr |
| **C** | Clean as you go | the kitchen generates them: `/bk:clean around` / `scan` | pick-ticket → implement → clean check → the pass → on `[go]`: clean around → handoff → open-pr |

**Lane C skips the plan, the checklist and `review-task`.** Its claim goes straight from
`backlog` to `in-progress`, because nothing sits between picking and cooking. The
inspector pass still runs, as `/bk:clean check`. A plan for "remove 26 unused exports" restates
the ticket, and a checklist saying "the counter is zero" restates the check. Every `HYG-` ticket
body names its counter (from `clean.counters`), the starting count, and the exact findings. The proof of done is the
check passing and the counter going down.

**One ticket per session.** When a cook's PR is open and has passed, the head chef clears
that session (`/clear`) before its next ticket. A second ticket never goes onto a live
context.

**Two tickets that touch the same files go to one cook, in sequence.** The `files:` field and
`kitchen.sh files` are how the sous sees overlap.

**Clean as you go has three scopes**, all run by cooks, none by the sous (scan output is
exactly the noise that fills a sous's context):

| Scope | Mode | When | Outcome |
|---|---|---|---|
| Your own new code | `/bk:clean check` | before every handoff | **fixed** in the same PR |
| Around your station: old mess in files your branch touched | `/bk:clean around` | end of shift, on `[go]`, before `open-pr` | `HYG` drafts sent to the sous as one `[rail]` batch |
| The whole kitchen | `/bk:clean scan` | only when the sous asks (lane C empty) | `HYG` drafts sent to the sous as one `[rail]` batch |

A finding in a line **your branch added** is fixed now, never filed. The sous drops drafts
that duplicate an open `HYG` ticket, then numbers and fires the rest. One `scan` at a time.

## Contract 10 — Talk like a human

Every chat reply is read by one busy human.

- Lead with the point in plain words.
- One idea per sentence.
- Any term of art gets a one-clause gloss the first time it appears.
- `file:line` references support a sentence; they never replace its subject.

## Contract 11 — Journals, handoffs and lessons

Context windows are a cache, not the record. Everything a fresh session needs is on disk,
so any session can be cleared at a quiet point and a new one carries on.

**The ticket journal**, `docs/journal/<id>-<slug>.md`, is the story of one ticket. Its
**only writer is the cook** holding the ticket, in its station, so it never conflicts; it
reaches trunk with the cook's PR, next to the plan and checklist. The sous reads journals
across stations and never writes them: answers it sends by message are copied in by the
cook. Entries are append-only, one line each where possible:

```
- 2026-09-29 14:32 · <session name> · Q3: <question> (options, recommendation)
- 2026-09-29 14:35 · <session name> · A3 (sous): <answer>
- 2026-09-29 15:10 · <session name> · finding 2 (pass): <what> → fixed in <file>
```

The journal's last line, after the closing handoff, is the ticket's **cost line**, printed
by `kitchen.sh budget --ticket <ID> --journal-line [--session <name>]` and appended by
`/bk:open-pr` before it commits: money, tokens, brief→PR with the phases known by then
(plan, wait, build, pass), and the helpers. The ship phase and the CI minutes come later and
live in `.claude/budget.jsonl`, not in the journal. The ticket's spend is what its cook
spent between the brief and `[served]`, across a `/clear` if there was one, plus its
sub-agents and the sous's sub-agents that name it (the taster at the pass); the sous's own
turns are the shift's, not the ticket's.

```
- 2026-09-29 16:40 · <session name> · cost: $4.63 · 1.5M tokens (in 1.0M, out 5k, cache read 450k, cache write 50k) · brief→PR 41m (plan 31m, wait 2m, build 8m, pass 1m) · helpers: runner 1 ($0.05), taster 1 ($2.00)
```

An **unanswered question** is a `Qn:` with no matching `An`. That's how a fresh sous finds
what cooks are waiting on: `grep` across `<kitchen>/*/docs/journal/`.

**Handoffs.** `/bk:handoff` works out its role from the station check.
- **Cook:** appends a `## Handoff — <datetime> · <session>` section to the journal: stage,
  what's uncommitted, the next step, what's pending, follow-ups (drafted as tickets and sent
  to the sous), and lessons. It runs automatically on `[go]`, before `open-pr`, so the closing
  handoff is in the reviewed PR (the journal is the one file allowed to change after the
  pass). The human can also run it any time, e.g. before clearing a cook between plan and
  implement. A fresh cook reads its ticket's journal and resumes from the last handoff.
- **Sous:** files the record, fetches CI minutes for the week's tickets into the budget's
  ledger, then overwrites the gitignored `.claude/sous-handoff.md` with only what lives nowhere
  else: the head chef's standing instructions, what it meant to fire next, walk-in holds it
  granted, and which session is which cook. A fresh `/bk:sous-chef` reads it first, then
  checks it against the rail, stations and journals; **reality wins over the note**.

Neither handoff clears the session: `/clear` stays the human's.

**Lessons are promoted mechanically, never by judgement.** A lesson is one tagged line in a
journal, written at handoff:

```
- lesson(repo): <key> | <one line> | <TICKET-ID>
- lesson(plugin): <key> | <one line about the Brigade itself> | <TICKET-ID>
```

- **When:** only at the **sous's handoff**, the one checkpoint for it (the same pass files
  decisions, questions and the inbox, Contract 12).
- **Count:** `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" lessons` counts distinct tickets per key
  across trunk's and every station's journals, and marks each key `watch`, `DUE` or `promoted`.
  It reads every `*.md` at any depth under `docs.journal`, so a journal that moves when its
  ticket is done (say, inside a plan moved to `completed/`) still counts.
- **Threshold:** a `repo` lesson is due at **2 tickets**; a `plugin` lesson at **1**.
- **Action for `repo`:** fire a normal `BKLG` ticket, "promote lesson `<key>` into
  CLAUDE.md / the config notes". It goes through a cook, the pass, and the head chef's
  merge. Add the key to the register, `docs.lessons` (default `docs/lessons.md`), as
  `` | `<key>` | repo | <ticket> | `` so it's
  never promoted twice. The register also holds the decisions the sous has handled
  (Contract 12); it is one file so there is one place to look.
- **Action for `plugin`:** run `/bk:feedback` with the lesson lines as the note. It drafts an
  issue for https://github.com/mhmzdev/claude-code-brigade with repo-specific detail removed,
  and **files it only on the head chef's yes**: it's public. Record the key in
  the register once filed (or declined).

## Contract 12 — The record: what the kitchen remembers

The record is everything written down that a session can read instead of asking: the
repo's `CLAUDE.md`, every folder under the config's `docs:` map (specs, tickets, plans,
checklists, journals, brainstorms, research, **decisions**, **conventions**, **knowledge**,
**questions**, and any key the sous adds), plus the stations' journals, which hold answers
that haven't reached trunk yet. The `docs:` map is the only index: a key there is a place the
commis searches, and nothing outside the map counts as recorded.

**Four rules.**

1. **Every head-chef answer is written down where it was asked, at once.** A gate answer
   goes into the journal as `An (head chef): …` (the cook copies it in). A grilling's or
   brainstorm's decisions go into the artifact's Decisions section. A plan approval is
   quoted in the journal. This already makes it findable; the rest is promotion.
2. **Capture at utterance, file at handoff.** When the head chef says, in passing, a fact,
   a rule or a reason that the record doesn't hold ("the cache invalidates on every deploy",
   "always go through the pricing service for that"), the sous appends it to the **inbox**
   right then: `kitchen.sh inbox --add "<their words>"`. One line, no judgement, no filing.
   The inbox is `.claude/inbox.md`, kept out of git, so a session cleared without a handoff
   has still written the line down. Cooks don't feed the inbox: what a cook learns, it
   learns from the code, and a cook's gotcha is a `lesson(repo)`.
3. **The sous's handoff is the one checkpoint that files.** Three mechanical lists, one
   pass:
   - `kitchen.sh decisions` lists every `(head chef)` answer across trunk's and the
     stations' journals that no file under the map cites and the register doesn't list.
     For each: it **generalises** (another ticket could hit it) → write it as a decision in
     `docs.decisions` (an ADR, in the repo's own format if it has one) with `source: <ID>
     An` in its frontmatter and its INDEX row, or into the convention or knowledge doc it
     belongs to, citing the same; it **doesn't** → add `` | `<ID> An` | kept | — | `` to
     the register so it isn't listed again. The head chef's words go in verbatim under
     their own heading; the sous's structured version (decision, why, applies to,
     supersedes) goes under it.
   - `kitchen.sh questions` lists the journals' unanswered `Qn` lines and the open question
     files. A question the head chef hasn't answered by this handoff, or that blocks a
     ticket, becomes a file in `docs.questions` (template `question.md`): status `open`,
     asked date, who's blocked, what the commis searched, the options and the
     recommendation; the ticket goes to `blocked` with a link. The commis searches
     `docs.questions`, so the next cook that hits the same wall reports "blocked on
     <question>" instead of asking again. When the head chef answers, the file gets
     `status: answered`, their words verbatim and the structured answer, and it is a
     decision like any other. Grillings are the exception: there the frontier waits.
   - `kitchen.sh inbox` lists the unfiled lines. Each goes into the doc type it belongs to
     (knowledge, convention, decision), then the line is removed. The board shows the
     count, so forgotten knowledge is a number, not a memory.
4. **The map can grow.** When nothing in the map fits what has to be recorded, the sous
   adds a type: through the repo's own extension point if it has a doc schema (never by
   editing a vendored file), else a new folder with an `INDEX.md`; then the key under
   `docs:` so the commis finds it; then the doc; then the repo's docs check. It tells the
   head chef in one line. It doesn't ask: the change is reviewed in the PR that carries it.

**A decision that the domain has moved past** is caught by showing, not hiding: a grilling
lists settled questions as *"already settled: <answer> (<source>), say if that changed"*,
and a sous answering from the record tells the head chef it did. A newer decision cites
the one it supersedes (`supersedes:` in its frontmatter); the commis reports the newest.

**Who writes what.** The sous writes the record in the main checkout, as it writes the
rail (a solo session writes it directly). The commis writes nothing. A cook writes only its
own journal and station files. A repo whose schema names a human as the writer of ADRs
treats the sous recording the head chef's quoted words as that human's writing; the
config's notes say so if the repo wants it otherwise.

**The commis's model.** It runs on Opus by default: its one judgement, "a related decision
is not this decision", is where a smaller model stretches a near miss into a false
*settled*, and that failure is silent. It is also the most-spawned sub-agent in the
kitchen. A repo that wants the trade sets `commis_model: sonnet` in the config; every
skill that spawns the commis passes that value as the `Agent` call's `model`.

**Hooks that back this up.** The plugin ships `hooks/hooks.json`: in a station (a
`station-*` folder in the configured kitchen, the same test `kitchen.sh` uses, so a nested
repo or a `claude --worktree` session is left alone), `AskUserQuestion` is refused unless a
grilling is under way (`.claude/grilling` exists in the station and was touched within
four hours: `grill-me` and `brainstorm` write it when they start there, touch it before
each round so the cap measures idle time, and remove it when they finish; `kitchen.sh
setup` keeps it out of the station's git status), and a `[gate]`
carrying a numbered question is refused when it names no commis result. Both are
guardrails against a slip, not a wall; both stay out of the way in a repo with no
`.claude/brigade.md` and in the main checkout.

## The skills

| Skill | Lane | Does |
|---|---|---|
| `/bk:setup [--worktree \| --clone]` | — | set up the Brigade in a repo: config, rail folders, `CLAUDE.md` section. Refuses a workspace root |
| `/bk:kitchen` | — | stations: setup, open, sync, status, files, rail board, `board` (all of it in one snapshot, also written to `.claude/board.md`), `sous` (the sous's session name, for cooks), `leaks` (test-account secrets copied into a checkout), `questions`, `decisions`, `inbox` (the record's three lists, Contract 12) and `doctor` (tickets and the docs map, checked) |
| `/bk:sous-chef` | — | take the lead role for the rest of the session |
| `/bk:line-cook` | — | take a station's worker role for the rest of the session |
| `/bk:rail` | — | the six rail operations on any adapter |
| `/bk:brainstorm` | A | explore what to build and why |
| `/bk:grill-me` | A, B | question a plan or idea until there's one shared picture |
| `/bk:spec` | A | write the numbered spec, and close the backlog item it came from |
| `/bk:file-tickets` | A, B | slice a spec into tickets, or add one backlog item (an item, a bug or a chore) |
| `/bk:pick-ticket` | A, B, C | pick a ticket up cold: context, staleness, what the record already decided, whether a backlog item is a bug or chore or still needs a spec, claim |
| `/bk:create-plan` | A, B | write the plan for one ticket |
| `/bk:implement` | A, B, C | carry out the plan, phase by phase, check after each |
| `/bk:review-task` | A, B | acceptance checklist from intent plus diff, with evidence |
| `/bk:open-pr` | A, B, C | commit, pull trunk, re-check, push, open the PR |
| `/bk:clean` | C (+ every ticket) | `check` your own diff, `around` your station, `scan` the kitchen; drafts go to the sous |
| `/bk:handoff` | — | write the handoff for this session's role (cook: journal section; sous: local note) |
| `/bk:feedback` | — | draft a scrubbed issue for the Brigade's own repo, with session context only if the human agrees; file it on their yes |
