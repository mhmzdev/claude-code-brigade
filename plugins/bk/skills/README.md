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
- [The skills](#the-skills)

---

## Contract 1 — The cast

| Role | Who | Does | Never does |
|---|---|---|---|
| **Head Chef** | the human | talks to **one** session, the sous: approves plans and answers real forks there; merges, deploys | relays messages between sessions, or watches the cooks' terminals |
| **Sous Chef** | one Claude Code session in the **main checkout**, running `/bk:sous-chef` | assigns tickets, answers routine gates, brings plans and real forks to the head chef with a recommendation and relays the answer, reviews every diff before commit, **is the only writer of the rail** | writes code in a station, merges, deploys, speaks for the head chef |
| **Line Cook** | one Claude Code session per **station** (started by `kitchen open`, or any session in a station) | works one ticket from plan to PR | edits ticket files, touches another station, empties the walk-in without asking |
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
kitchen: stations                        # stations dir, relative to repo root (worktree default: ../<repo>-stations)
stations: 2                              # how many a fresh setup creates; setup -n N grows it
migrations: none                         # path, or none

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
  plan_approval: head-chef
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
docs:
  specs: docs/specs
  backlog: docs/backlog
  plans: docs/plans
  checklists: docs/checklists
  journal: docs/journal
  research: docs/research
  brainstorm: docs/brainstorm
---
Free-text repo notes the skills should respect.
```

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
(Contract 4: every `BKLG` item that isn't `kind: bug`). `kitchen.sh rail` works all of
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
   stations, files in flight, the rail and open questions in one go, and from the main
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
| Promoted lessons | `docs/lessons.md` | — (one row per promoted key) |
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

**Ticket frontmatter (markdown rail):**

```yaml
---
id: BKLG-004
title: One line
lane: B                  # A | B | C
status: backlog          # backlog | todo | in-progress | rfr | done | blocked
cook: null               # station name once claimed
kind: item               # BKLG only: item (becomes a spec and tickets) | bug (planned and built directly)
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

**Bug or item is a fact about the work, not a size.** A "small" new behaviour is still an
item. A fix that turns out to need a decision about *what* the behaviour should be was
never a bug: say so, and it becomes an item. The sous sets or corrects `kind:` as a rail
change, with one line of why. The one way an item is built without a spec is the head chef
saying so for that item; the plan then notes that it has none.

On a github or jira rail a backlog item is an issue labelled `lane:B` (plus `bug` for a
bug), and "closed into a spec" shows as its closing comment (`Became spec SNNN: <path>`)
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

Templates for spec, ticket, plan, checklist, journal and `brigade.local.md` ship with the plugin at
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
is watching its terminal.
Everything a cook needs decided goes to the sous as a `[gate]`. The sous answers what is
routine, and takes the rest to the head chef in its own terminal, with a recommendation,
then relays the answer marked `(head chef)`. The one planned exception is a grilling the
sous hands to a cook (the table below): the questions are for the human, so the human
answers them in that station. If the human does type in a cook's terminal,
the cook does as told and sends the sous one `[status]` line, so the sous's picture stays whole.

**The sous assigns the work.** With `gates.assign: sous-chef` (the default), the sous puts
each free cook on the next ready ticket (Contract 3) without asking, and tells the head
chef what it assigned and why in one line. The head chef steers by saying what comes first
or what to hold, and still signs off every plan. With `gates.assign: head-chef`, the sous
proposes and waits for a yes. Either way a cook only gets a ticket when it is **free**: it
has checked in with no ticket, a clean station, and a fresh session. A cook that has just
served is not free until its session has been cleared.

**The chef's sign-off is what starts `/bk:implement`.** It approves the plan and authorises
every commit made under it (after the sous's pass). No separate "approve?" question exists.

- **Solo:** the human types `/bk:implement`, or says in plain words to build the plan.
  A solo session never chains into `implement` from `create-plan` by itself.
- **In a kitchen:** the cook sends `[plan] <ID> ready: <path>`. The sous reads the plan,
  shows the head chef a short summary with its recommendation, and on their yes sends the
  cook `[approved]`, quoting them. The cook records it in the journal and starts
  `/bk:implement` itself. `implement` refuses to start in a station without that record
  (the one other way in: the head chef typing `/bk:implement` in that station themselves).
- **The sous never approves a plan itself.** Every plan needs the head chef's own yes, in
  the sous's current session, after seeing that plan. A changed plan needs a new yes. A
  handoff note, a standing remark or an earlier ticket's approval is not one.
- **Lane C has no plan**, so the sign-off is on the ticket itself: before assigning a
  `HYG` ticket the sous shows it to the head chef, and on their yes the brief carries the
  `[approved]` line.

Only `setup` has `disable-model-invocation: true` (it changes a repo's layout). Every
other skill is model-invocable, or cooks would stall waiting for a human to type it.

**Who** answers a decision depends on where the skill runs.

| Gate | Solo session | Line cook |
|---|---|---|
| Plan approval (the **chef's sign-off**) | human types `/bk:implement`, or says to build the plan | **human, in the sous's terminal**; the sous relays `[approved]` and the cook starts `/bk:implement`. That authorises every commit made under the plan |
| Which ticket a free cook takes next | human | the sous (`gates.assign`), from the ready tickets in Contract 3's order |
| Design fork, contradiction between ticket and code | human | cook sends `[gate]`; the sous takes it to the human with a recommendation and relays the answer |
| Grilling (`/bk:grill-me`) | human | a cook never starts one unasked: it sends `[gate] <ID> needs grilling`. The sous grills the human itself, or **hands the grilling to a free cook** with a `[brief]` and tells the human which station is waiting. The human may also type `/bk:grill-me` in a station. The cook then grills the human in its own terminal, logs every decision (a backlog item that needs a spec: in the spec draft it writes; an existing spec or ticket: sent to the sous, who writes them in), tells the sous, and is cleared before it takes a ticket |
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
and every cook must run under the same `CLAUDE_CONFIG_DIR`.

Cooks are named `<repo>-cook-N` by `kitchen open`; the sous keeps whatever name its session
has. So the sous records it: on start, `kitchen.sh sous --set <its ListAgents name>`. A cook
reads it with `kitchen.sh sous` and checks in straight away if `ListAgents` still lists that
name; otherwise it waits for the `[hello]`.

Keep messages short and typed. The first line is the kind, in brackets:

| Kind | From → to | Carries |
|---|---|---|
| `[hello]` | sous → cook | "I'm the sous, check in": sent at start-up to cooks that were already waiting |
| `[brief]` | sous → cook | the ticket's absolute path, why it matters, constraints from other stations, the loop. Or a **grilling brief**: the item to grill the head chef on, and where its decisions go |
| `[check-in]` | cook → sous | station, model, branch, dirty or clean, ticket, whether the session is **fresh or spent** (it has already served a ticket or held a grilling, so it needs clearing), and **what it's waiting on** (a question id, the plan's sign-off, the pass, a walk-in clearance, or nothing) |
| `[gate]` | cook → sous | the question, the options, the cook's recommendation |
| `[rail]` | cook → sous | a rail change request: `claim BKLG-004 todo`, `BKLG-004 → rfr`. Also a file for the sous to record in the main checkout, by absolute path: a spec draft, grilling decisions, a brainstorm doc |
| `[walk-in]` | cook → sous | "about to run `<command>` on `<resource>`, OK?" |
| `[status]` | anyone | a state change that needs no answer: "the head chef told me directly to …", "implement started (signed off)", a lane-C counter before/after |
| `[handoff]` | cook → sous | "ready for the pass": branch, files, check result, inspector result, absolute checklist path |
| `[findings]` | sous → cook | numbered items, each with file and why |
| `[plan]` | cook → sous | the plan is ready for the sign-off: its absolute path. The cook waits for `[approved]` or `[findings]` |
| `[approved]` | sous → cook | the head chef approved this plan, in their words: start `/bk:implement`. Never the sous's own approval |
| `[go]` | sous → cook | commit approval after the pass |
| `[served]` | cook → sous | the PR is open: its URL |
| `[heard]` | anyone | acknowledgement, one line; also the sous's **answer** to a `[gate]` (`[heard] Q3: <answer>, because …`), which the cook copies into its journal as `A3` |

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
| **B** | À la carte | bugs: backlog items marked `kind: bug`. Every backlog item is filed `lane: B`; one that isn't a bug leaves for lane A through a spec | pick-ticket → (grill-me) → create-plan → implement → review-task → open-pr |
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

An **unanswered question** is a `Qn:` with no matching `An`. That's how a fresh sous finds
what cooks are waiting on: `grep` across `<kitchen>/*/docs/journal/`.

**Handoffs.** `/bk:handoff` works out its role from the station check.
- **Cook:** appends a `## Handoff — <datetime> · <session>` section to the journal: stage,
  what's uncommitted, the next step, what's pending, follow-ups (drafted as tickets and sent
  to the sous), and lessons. It runs automatically on `[go]`, before `open-pr`, so the closing
  handoff is in the reviewed PR (the journal is the one file allowed to change after the
  pass). The human can also run it any time, e.g. before clearing a cook between plan and
  implement. A fresh cook reads its ticket's journal and resumes from the last handoff.
- **Sous:** overwrites the gitignored `.claude/sous-handoff.md` with only what lives nowhere
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

- **When:** only at the **sous's handoff**, the one checkpoint for it.
- **Count:** `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" lessons` counts distinct tickets per key
  across trunk's and every station's journals, and marks each key `watch`, `DUE` or `promoted`.
- **Threshold:** a `repo` lesson is due at **2 tickets**; a `plugin` lesson at **1**.
- **Action for `repo`:** fire a normal `BKLG` ticket, "promote lesson `<key>` into
  CLAUDE.md / the config notes". It goes through a cook, the pass, and the head chef's
  merge. Add the key to `docs/lessons.md` (`` | `<key>` | repo | <ticket> | ``) so it's
  never promoted twice.
- **Action for `plugin`:** run `/bk:feedback` with the lesson lines as the note. It drafts an
  issue for https://github.com/mhmzdev/claude-code-brigade with repo-specific detail removed,
  and **files it only on the head chef's yes**: it's public. Record the key in
  `docs/lessons.md` once filed (or declined).

## The skills

| Skill | Lane | Does |
|---|---|---|
| `/bk:setup [--worktree \| --clone]` | — | set up the Brigade in a repo: config, rail folders, `CLAUDE.md` section. Refuses a workspace root |
| `/bk:kitchen` | — | stations: setup, open, sync, status, files, rail board, `board` (all of it in one snapshot, also written to `.claude/board.md`), `sous` (the sous's session name, for cooks), and `leaks` (test-account secrets copied into a checkout) |
| `/bk:sous-chef` | — | take the lead role for the rest of the session |
| `/bk:line-cook` | — | take a station's worker role for the rest of the session |
| `/bk:rail` | — | the six rail operations on any adapter |
| `/bk:brainstorm` | A | explore what to build and why |
| `/bk:grill-me` | A, B | question a plan or idea until there's one shared picture |
| `/bk:spec` | A | write the numbered spec, and close the backlog item it came from |
| `/bk:file-tickets` | A, B | slice a spec into tickets, or add one backlog item (an item or a bug) |
| `/bk:pick-ticket` | A, B, C | pick a ticket up cold: context, staleness, whether a backlog item is a bug or still needs a spec, claim |
| `/bk:create-plan` | A, B | write the plan for one ticket |
| `/bk:implement` | A, B, C | carry out the plan, phase by phase, check after each |
| `/bk:review-task` | A, B | acceptance checklist from intent plus diff, with evidence |
| `/bk:open-pr` | A, B, C | commit, pull trunk, re-check, push, open the PR |
| `/bk:clean` | C (+ every ticket) | `check` your own diff, `around` your station, `scan` the kitchen; drafts go to the sous |
| `/bk:handoff` | — | write the handoff for this session's role (cook: journal section; sous: local note) |
| `/bk:feedback` | — | draft a scrubbed issue for the Brigade's own repo, with session context only if the human agrees; file it on their yes |
