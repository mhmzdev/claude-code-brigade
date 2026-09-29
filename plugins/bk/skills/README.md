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
| **Head Chef** | the human | approves plans, answers real forks, merges, deploys | relays messages between sessions |
| **Sous Chef** | one Claude Code session in the **main checkout**, running `/bk:sous-chef` | assigns tickets, answers routine gates, reviews every diff before commit, **is the only writer of the rail** | writes code in a station, merges, deploys, speaks for the head chef |
| **Line Cook** | one Claude Code session per **station** (started by `kitchen open`, or any session in a station) | works one ticket from plan to PR | edits ticket files, touches another station, empties the walk-in without asking |
| **Inspector** | the `inspector` sub-agent | reads a diff and reports what shouldn't be there (the health inspector: looks, never cooks) | holds any tool that can write |
| **Taster** | the `taster` sub-agent, spawned by the sous at the pass | reads a cook's diff, re-runs the check, walks "Done when", returns a verdict and numbered findings, so the sous doesn't read whole diffs | edits, commits, or messages anyone |
| **Runner** | the `runner` sub-agent, anyone may spawn it | runs one noisy command (the check, a test suite, a scan) and returns only pass/fail plus the failing lines | decides anything, or edits |

**A session inside a station is a line cook, whether or not `/bk:line-cook` was typed.**
After a `/clear`, the human may type `/bk:implement` straight away: the skill must still
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
| **close** | `status: done` | close the issue | transition to Done |

**Statuses, the same on every backend:** `backlog` → `todo` → `in-progress` → `rfr` →
`done`, plus `blocked`.

- `backlog` and `blocked` are **free**. Anything else is **somebody's claim**. Never
  plan, start or overwrite a ticket in `todo`, `in-progress` or `rfr` unless you are that
  ticket's cook.
- `todo` means a plan exists, even if you can't see it. The plan is an uncommitted file in
  another station.

**Two rules that keep any rail honest:**

1. **Only the sous chef writes the rail.** That covers every edit to a ticket: status,
   cook, links, *and* body edits such as a `## Decisions` section. Cooks ask by message. In
   a solo session the human is the sous, so solo skills write the rail directly.
2. **No summary page.** The board view is computed each time (`kitchen.sh rail`, or the
   tracker's own board). A hand-kept roll-up drifts.

**Markdown rail commits.** With `rail.commit: direct` the sous commits each rail change to
trunk on its own (`rail: BKLG-004 → in-progress`) and pushes. With `daily-pr` it
accumulates them on a `rail/YYYY-MM-DD` branch and opens one PR. Cooks read ticket files by
**absolute path in the main checkout**, so they never wait for either.

**Closing.** A tracker usually closes the ticket on merge. A markdown rail has nothing to
do that, so the sous closes the ticket (`status: done`) through `/bk:rail` once the
head chef has merged.

## Contract 4 — Names and ids

**Things the rail tracks get numbers. Everything else gets a date.** Numbers are safe
because only one session (the sous) hands them out. They are zero-padded and never reused.

| Kind | Path (markdown rail) | Id |
|---|---|---|
| Spec | `docs/specs/NNN-<slug>.md` | `SNNN` |
| Spec's ticket (lane A) | `docs/specs/NNN-<slug>/NN-<slug>.md` | `SNNN-NN` |
| Standalone ticket (lane B) | `docs/backlog/BKLG-NNN-<slug>.md` | `BKLG-NNN` |
| Hygiene ticket (lane C) | `docs/backlog/HYG-NNN-<slug>.md` | `HYG-NNN` |
| Plan | `docs/plans/<id>-<slug>.md` | the ticket's id |
| Checklist | `docs/checklists/<id>-<slug>.md` | the ticket's id |
| Journal | `docs/journal/<id>-<slug>.md` | the ticket's id |
| Promoted lessons | `docs/lessons.md` | — (one row per promoted key) |
| Sous handoff | `.claude/sous-handoff.md`, **gitignored** | — (overwritten each handoff) |
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
spec: null               # SNNN for lane A
blocked_by: []
files: []                # paths it will likely touch
created: YYYY-MM-DD
---
```

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

Templates for spec, ticket, plan and checklist ship with the plugin at
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

**The chef's sign-off is typing `/bk:implement`.** `implement` has
`disable-model-invocation: true` (as does `setup`; every other skill is model-invocable), so only a human can start it; a cook can't chain into it
by itself. Typing it, in the cook's own terminal, approves the plan and authorises every
commit made under it (after the sous's pass). No separate "approve?" question exists.

**Who** answers a decision depends on where the skill runs.

| Gate | Solo session | Line cook |
|---|---|---|
| Plan approval (the **chef's sign-off**) | human types `/bk:implement` | **human types `/bk:implement` in the cook's own terminal**. That authorises every commit made under the plan |
| Design fork, contradiction between ticket and code, anything that needs grilling | human | human (the cook asks with `AskUserQuestion`) |
| Every other confirmation ("confirm scope?", "continue to phase 2?", "which of these two helpers?") | human | **sous chef, by `SendMessage`**, never a dialog nobody is watching |
| Pre-commit review (**the pass**) | human | sous spawns the `taster`, questions its verdict, checks across stations, then says `[go]` |
| Merge, deploy, anything touching production | human | human only, never relayed |

A cook that receives "the chef said go" from the sous for a merge or a deploy **refuses**.
That is correct. Those approvals are given in person.

**Cooks stop for decisions, not ceremony.** Once `/bk:implement` is typed, it runs straight
through its phases. It only stops for a criterion that genuinely needs eyes, and that
question goes to the sous.

## Contract 6 — Messages between sessions

Sessions find each other with `ListAgents` and talk with `SendMessage` (load both with
`ToolSearch` if they are deferred). Discovery works per Claude Code profile, so the sous
and every cook must run under the same `CLAUDE_CONFIG_DIR`.

Keep messages short and typed. The first line is the kind, in brackets:

| Kind | From → to | Carries |
|---|---|---|
| `[hello]` | sous → cook | "I'm the sous, check in": sent at start-up to cooks that were already waiting |
| `[brief]` | sous → cook | the ticket's absolute path, why it matters, constraints from other stations, the loop |
| `[check-in]` | cook → sous | station, model, branch, dirty or clean, ticket, and **what it's waiting on** (a question id, the pass, a walk-in clearance, or nothing) |
| `[gate]` | cook → sous | the question, the options, the cook's recommendation |
| `[rail]` | cook → sous | a rail change request: `claim BKLG-004 todo`, `BKLG-004 → rfr` |
| `[walk-in]` | cook → sous | "about to run `<command>` on `<resource>`, OK?" |
| `[status]` | anyone | a state change that needs no answer: "in a design conversation with the head chef", "plan ready: `<path>`", "implement started (signed off)", a lane-C counter before/after |
| `[handoff]` | cook → sous | "ready for the pass": branch, files, check result, inspector result, absolute checklist path |
| `[findings]` | sous → cook | numbered items, each with file and why |
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
| **A** | Specials | a spec, sliced into tickets | brainstorm → grill-me → spec → file-tickets → create-plan → implement → review-task → open-pr |
| **B** | À la carte | standalone tickets already on the rail | pick-ticket → (grill-me) → create-plan → implement → review-task → open-pr |
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
- **Action for `plugin`:** draft an issue for https://github.com/mhmzdev/claude-code-brigade
  with repo-specific detail removed, and **ask the head chef before filing**: it's public.
  Record the key in `docs/lessons.md` once filed (or declined).

## The skills

| Skill | Lane | Does |
|---|---|---|
| `/bk:setup [--worktree \| --clone]` | — | set up the Brigade in a repo: config, rail folders, `CLAUDE.md` section. Refuses a workspace root |
| `/bk:kitchen` | — | stations: setup, open, sync, status, files, rail board |
| `/bk:sous-chef` | — | take the lead role for the rest of the session |
| `/bk:line-cook` | — | take a station's worker role for the rest of the session |
| `/bk:rail` | — | the six rail operations on any adapter |
| `/bk:brainstorm` | A | explore what to build and why |
| `/bk:grill-me` | A, B | question a plan or idea until there's one shared picture |
| `/bk:spec` | A | write the numbered spec |
| `/bk:file-tickets` | A | slice a spec into tickets, or fire one standalone ticket |
| `/bk:pick-ticket` | B, C | pick a ticket up cold: context, staleness, claim |
| `/bk:create-plan` | A, B | write the plan for one ticket |
| `/bk:implement` | A, B, C | carry out the plan, phase by phase, check after each |
| `/bk:review-task` | A, B | acceptance checklist from intent plus diff, with evidence |
| `/bk:open-pr` | A, B, C | commit, pull trunk, re-check, push, open the PR |
| `/bk:clean` | C (+ every ticket) | `check` your own diff, `around` your station, `scan` the kitchen; drafts go to the sous |
| `/bk:handoff` | — | write the handoff for this session's role (cook: journal section; sous: local note) |
