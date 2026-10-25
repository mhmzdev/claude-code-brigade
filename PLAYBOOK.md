# The Brigade playbook

How the kitchen actually runs, written as the questions people ask when they first use it.
The rules themselves live in the contract,
[`plugins/bk/skills/README.md`](plugins/bk/skills/README.md); when this file and the
contract disagree, the contract wins. The names are in
[`docs/the-names.md`](docs/the-names.md).

## Contents

- [The idea in one paragraph](#the-idea-in-one-paragraph)
- [Setting up](#setting-up)
- [Stations](#stations)
- [Backlog items, tickets and lanes](#backlog-items-tickets-and-lanes)
- [Starting a shift](#starting-a-shift)
- [How work gets assigned](#how-work-gets-assigned)
- [Who you talk to](#who-you-talk-to)
- [One ticket, start to PR](#one-ticket-start-to-pr)
- [Seeing progress](#seeing-progress)
- [Grilling and brainstorming](#grilling-and-brainstorming)
- [Handoffs and clearing sessions](#handoffs-and-clearing-sessions)
- [Test accounts](#test-accounts)
- [The record: never asked twice](#the-record-never-asked-twice)
- [The four sub-agents](#the-four-sub-agents)
- [When something looks wrong](#when-something-looks-wrong)
- [Command cheat sheet](#command-cheat-sheet)

## The idea in one paragraph

You are the **head chef**. You talk to one Claude Code session, the **sous chef**, usually
on the biggest model, in the repo's main checkout. The sous runs the **line cooks**: one
session per **station** (a separate copy of the repo), each working one ticket from plan to
pull request. Cooks can be smaller models, or big ones for hard tickets. You don't watch
the cooks' terminals. Everything they need decided that nobody has decided yet reaches you
through the sous, with a recommendation; everything already decided is found in the record
by the **commis** before anyone asks. You sign off feature plans, answer real forks, and
merge. The sous signs off bug, chore, precedent and hygiene plans itself and tells you.

## Setting up

**How do I set it up in a repo?** Run `bk setup` in the repo's main checkout (it starts a
Claude session there already running `/bk:setup`; inside Claude Code, type that). It reads the
repo, asks one round of questions, and writes:

- `.claude/brigade.md`: the config every skill reads (trunk, check command, install
  command, stations, where tickets live);
- the rail folders under `docs/` (specs, backlog, plans, checklists, journal) and the
  record's (decisions, conventions, domains, questions), each with an `INDEX.md`, or the
  `docs:` map pointed at the folders the repo already keeps; a `docs/SCHEMA.md` saying what
  each type is, unless the repo has its own;
- a short section in `CLAUDE.md` saying the repo runs on the Brigade, and that a session
  inside a station is a line cook.

Nothing is committed until you say so. Stations are created from `origin/<trunk>`, so the
setup must be pushed before `/bk:kitchen setup` can build them.

**Do I need several stations?** No. One station works: you get the sous plus one cook.
Add more later with `bk stations -n 3` (or `/bk:kitchen setup -n 3`); existing stations are
left alone.

**Do I need a board like GitHub Projects or Jira?** No. The default rail is markdown: each
ticket is a file under `docs/` with frontmatter. GitHub Projects and Jira are optional
adapters.

**The repo already has its own harness (hooks, make targets, docs). What happens to it?**
It stays. The Brigade reads the config, so point the config at what exists: your check
command in `check:`, your docs folders under `docs:`, your shared database or docker stack
under `walk_in:`. Setup merges into `CLAUDE.md`, `.gitignore` and `.claude/settings.json`
and shows each change first. Two things to look at yourself:

- **Old ticket ids.** A blocker id from an older scheme is not a ticket on the new rail, so
  it holds the ticket it blocks until it is removed (see
  [When something looks wrong](#when-something-looks-wrong)).
- **Project hooks that write into the repo** (for example a session-end hook that saves a
  transcript). Stations are copies of the repo, so the hook fires there too and leaves the
  station dirty. Make such a hook exit early inside a station. These hooks belong to the
  project, not to the plugin.

## Stations

A station is where one cook works. There are two kinds, set by `kitchen_mode:` in the
config.

| Mode | Where | What it is | Use it for |
|---|---|---|---|
| `clone` (default) | `<repo>/stations/station-N`, gitignored | a full clone | one standalone repo |
| `worktree` | `../<repo>-stations/station-N`, next to the repo | a git worktree | big repos, and repos inside a workspace repo |

**Why are worktree stations outside the repo?** A git worktree placed inside its own repo
would be seen by every tool that walks the repo: the type checker, the test runner, the
linter, file watchers, docker builds. Next to the repo, none of them see it. Clone stations
sit inside `stations/` because a clone is self-contained and the folder is gitignored; the
price is that tools ignoring `.gitignore` must be told to skip it, and
**`git clean -fdx` in the main checkout deletes every station**.

In a worktree station, an idle cook sits detached at `origin/<trunk>` (trunk itself is
checked out in the main checkout), and stashes and branches are shared across stations.

## Backlog items, tickets and lanes

**What is the difference between a backlog item and a ticket?**

- A **backlog item** (`BKLG-NNN`) is where anything lands first. It has not been grilled or
  specced. Capturing one is cheap.
- A **ticket** (`SNNN-NN`) is one slice of a spec. It has been grilled, specced and sliced,
  so it is one step from a plan. Tickets are what cooks build.

A backlog item carries `kind:`, and that decides how it leaves the backlog:

| `kind:` | Means | Path |
|---|---|---|
| `item` (default, also when missing) | a capability, a change in behaviour | `/bk:grill-me` → `/bk:spec` → `/bk:file-tickets`. The spec's tickets get built; the item is closed with `spec: SNNN`. Its plans need your sign-off |
| `bug` | something that exists and works wrong against what was already decided | the item is its own ticket: `/bk:create-plan`, then build. The sous signs off the plan |
| `chore` | work whose outcome is already fixed: a bump, a rename, a missing checklist item, a doc catching up with the code | the same as a bug |
| `precedent` | another instance of something the code already does twice or more the same way, where the record says why: a third provider, one more report, a new adapter behind an existing interface | the same as a bug. The commis finds the precedent; the sous sets the kind, lists the instances, and tells you before anyone is briefed, so you can say "that one is new" |

Bug, chore, precedent or item is a fact about the work, not its size. A small new behaviour
is still an item, a "chore" that turns out to need a decision was an item all along, and a
precedent whose instances disagree on the very point the new one raises was never one. The
first of its kind (the first provider; a bus operator in a kitchen that only knows airlines)
has no precedent, and that is exactly the decision that is yours.

**The three lanes** say where a ticket came from:

| Lane | Source | Ids |
|---|---|---|
| A | a spec, sliced into tickets | `SNNN-NN` |
| B | bugs, chores and precedents from the backlog | `BKLG-NNN` with `kind: bug`, `kind: chore` or `kind: precedent` |
| C | hygiene work the kitchen finds itself (`/bk:clean`) | `HYG-NNN` |

**Statuses:** `backlog` → `todo` (a plan exists) → `in-progress` → `rfr` (ready for
review) → `done`, plus `blocked`. `backlog` and `blocked` are free; anything else is
somebody's claim.

## Starting a shift

One command: **`bk open`** in the main checkout (or `/bk:kitchen open` from a Claude session,
if you installed the plugin alone). It starts the whole kitchen in a tmux session named
`<repo>-brigade`: a `sous` window already running `/bk:sous-chef`, and one window per station
already running `/bk:line-cook`. Nothing opens on your screen. `bk open` then attaches you to
the sous; `kitchen open` prints the line to attach.

**Where do I type?** With the sous: `bk attach` (or `tmux attach -t <repo>-brigade:sous`). That
is the one session you talk to. `Ctrl-b d` detaches and leaves everything running; `bk peek 2`
(or `Ctrl-b w` inside tmux) shows a cook. `bk live` (or `/bk:live`) shows the whole kitchen in
your browser, and its controls type into these sessions for you.

**Which Claude account?** If you keep several Claude Code profiles (`~/.claude`,
`~/.claude-work`, …), `bk open --profile work` picks one the first time, or it asks; the
choice is recorded in `.claude/bk-profile` (kept out of git) and every later `bk` command
uses it. A `CLAUDE_CONFIG_DIR` already exported in your shell wins over the recorded one.

**Stopping for the day: `bk stop`.** It is a pause. It types `/bk:handoff` into the sous and
every cook, waits until each has finished and gone idle (ten minutes at most, then it says
who is still busy and goes on), saves each session's id, types `/exit`, and closes the tmux
session and the Window. It commits nothing. The next `bk open` resumes every session where
it stopped; `bk open --fresh` starts new ones.

**Do I run `/bk:sous-chef` myself?** Not when tmux opened the kitchen: the sous starts with it,
pulls trunk, reads its last handoff note, collects unanswered questions from the cooks'
journals, builds the board, records its session name for the cooks (`kitchen.sh sous`), says
`[hello]` to cooks that were already waiting, and assigns work. Only with `--terminal warp`
or `native` do you start the sous yourself, in your own terminal.

So the sous is what picks tickets, not `kitchen open`. You don't need to ask it to.

## How work gets assigned

The sous assigns the next ready ticket to each **free** cook without asking, and tells you
in one line what it assigned and why. (Set `gates.assign: head-chef` in the config if you
want it to propose and wait for a yes instead.)

**A cook is free** when its check-in says: no ticket, a clean station, and a fresh session.
A cook that has just served a ticket or held a grilling is *spent* and is not free until
you clear it. Spent means that session's own conversation did the work: a session you've
just cleared or opened is fresh, even in a station whose journal shows a served ticket. If
a cook you've just cleared still checks in spent, tell the sous you cleared it, and it
briefs the cook.

**A ticket is ready** when its status is `backlog` or `blocked`, every ticket in its
`blocked_by` is `done`, and it isn't a backlog item that still needs a spec. The rail board
works this out; its `RDY` column says:

| `RDY` | Means |
|---|---|
| `yes` | can be assigned |
| `no` | a blocker is still open; the open blockers are printed after the title |
| `spec` | a backlog item that is none of a bug, a chore or a precedent: it has to become a spec and tickets first |
| `-` | already claimed |

**Order among ready tickets:**

1. what you said to do first, or to hold;
2. `priority:` `high`, then normal, then `low`;
3. the ticket that more other tickets are blocked by;
4. lane A before B before C; within a spec, ticket-number order; otherwise the lowest id.

So spec tickets go before backlog bugs, chores and precedents, and any other backlog item is
never assigned at all. When nothing is ready, the sous says what is blocked and on what, and
offers a grilling for the highest-priority item waiting for a spec.

Two hard rules can skip a pick: tickets touching the same files go to one cook in sequence,
and only one station carries a database migration at a time.

## Who you talk to

**The sous, and only the sous.** A cook never asks you anything and never opens a question
dialog; nobody is watching its terminal. What a cook needs goes to the sous as a message:

| The cook needs | It sends | Who answers |
|---|---|---|
| how something works, or whether it was decided before | nothing: it spawns the **commis**, which searches the record and answers with a source | the record |
| a routine confirmation (scope, "continue?", which helper) | `[gate]`, with what the commis found | the sous |
| a real design fork the record doesn't settle | `[gate]`, with what the commis searched | you, in the sous's terminal; the sous adds a recommendation and relays your answer marked `(head chef)`, and it's written down |
| a bug, chore or precedent plan approved | `[plan]` | the sous, which tells you in one line (a precedent plan has to follow its precedent) |
| a hygiene ticket approved | nothing: it has no plan; the sous's `[approved]` rides in the `[brief]` | the sous, which tells you in one line |
| a feature plan approved, or any plan with a migration, a shared resource, a production write or an unrecorded decision | `[plan]` | you, in the sous's terminal; the sous relays `[approved]` with your words |
| a ticket changed | `[rail]` | the sous (the only writer of tickets) |
| a destructive command on a shared resource | `[walk-in]` | the sous |
| a login for testing | `[gate] … need a test account` | the sous, with an account name |
| a write on production | `[gate] … production write` | you, for that exact action |
| merge or deploy | nothing | you do these yourself; no session does, and a relayed "go" is refused |

The sous never approves a **feature** plan itself. Those need your own yes, in the sous's
current session, after seeing that plan; a changed plan needs a new yes. Bug, chore,
precedent and hygiene plans the sous signs on its own, naming the rule, and tells you in one line. Want
every plan for a while? Say so, or set `gates.plan_approval: head-chef` in the config.

If you do type in a cook's terminal, the cook does as told and tells the sous in one line.

## One ticket, start to PR

1. The sous sends the cook a `[brief]`: the ticket's path, why it matters, constraints.
2. The cook branches (`<id>-<slug>`), runs `/bk:pick-ticket`, and asks the sous to claim
   the ticket (`todo`).
3. `/bk:create-plan` writes the plan. The cook sends `[plan]` and waits.
4. The sous reads the plan and checks it against the other stations. A bug, chore or
   precedent plan it signs itself and tells you in one line. A feature plan (or one with a migration, a shared
   resource, a production write or a decision the record doesn't hold) it shows you in a
   short summary with a recommendation: you approve, change something, or ask to grill it
   first.
5. On `[approved]`, the cook starts `/bk:implement` itself. It runs every phase, running
   the check after each, without "continue?" questions.
6. `/bk:clean check` (the inspector reads the diff), then `/bk:review-task` (the acceptance
   checklist). Status goes to `rfr`.
7. The cook sends `[handoff]` and **does not commit**. This is **the pass**: the sous
   spawns the taster, questions its verdict, checks across stations, and sends `[findings]`
   or `[go]`.
8. On `[go]`: `/bk:clean around` (old mess nearby, drafted as hygiene tickets),
   `/bk:handoff` (the journal's closing section), `/bk:open-pr`. The cook sends `[served]`
   with the PR link.
9. You merge. The sous closes the ticket. You clear the cook's session before its next
   ticket: one ticket per session.

Lane C (hygiene) skips the plan and the checklist; the ticket is the plan, and the sous
signs it before assigning (or you do, if the config says `hygiene: head-chef`).

## Seeing progress

The sous prints one table after it walks the kitchen, and again when things change:

```
cook           station    model  lane  ticket    stage         files in flight   migration  waiting on
my_app-cook-1  station-1  Sonnet A     S002-01   implementing  src/app/shell/*   no         nothing
my_app-cook-2  station-2  Opus   B     BKLG-031  plan ready    src/lib/auth.ts   no         plan sign-off
```

**Is there one file I can keep open?** Yes: **`.claude/board.md`** in the main checkout.
`kitchen.sh board` writes it: station status, files in flight, the rail and open questions
in one snapshot. The sous refreshes it whenever a message changes a station's state. It is
generated, never edited and never committed. Open it in your editor; a terminal `watch`
loop is not the way (stock macOS has no `watch`, and the script is not on your `PATH`).

**Can I watch it instead of reading it?** Yes: **`/bk:live`** opens the Window, a live view
of the service in your browser on localhost. Each cook stands at its station doing what it
is doing, the commis runs to the record before a question goes up, tickets fly between
sessions, and the panel holds what needs you, the line, the rail and the message log. Click a
cook or the sous for its page: session, model, ticket, branch, and controls (model, a line
to send, handoff, end of shift). It reads what the kitchen writes and changes nothing by
itself beyond the budget's local ledger; it needs node 20 or newer. `/bk:live` again closes it.

**What is it costing me?** `bk budget` (or `/bk:kitchen budget`) prints the shift: money,
tokens by kind, working time and CI minutes, then a row per session and a row per ticket
with brief→served and each phase (plan, wait for the sign-off, build, pass, ship). `--ticket
ID` is one ticket's page, `--since 7d` widens the window to a week, as far as it looks, `--ci` asks `gh`
for the CI minutes of each ticket's PR branch. The Window shows the same at its foot, and
the chip opens the Ledger: a page of dishes and sessions over the shift, today or the week,
each dish split into prep, cook, check and serve, with every step and what a red check cost
in rework; a `budget:` block in the config (`shift_usd`, `ticket_usd`) gives it a scale. It is
read from the transcripts Claude Code keeps, priced on a dated list (`prices:` in the config
overrides it), and it is a meter: nothing stops because of it. Each ticket's journal gets a
cost line when its PR opens; the sous's handoff and the open Window (every ten minutes)
fetch CI minutes into `.claude/budget.jsonl`.

## Grilling and brainstorming

**Grilling** (`/bk:grill-me`) questions an idea until there is one shared picture. It needs
you.

- The sous can grill you itself, or **hand the grilling to a free cook**. A long grilling
  fills the context the sous needs for the passes, and the cook has the code in front of
  it. The sous tells you which station is waiting; you answer the questions there. This is
  the one planned time you use a cook's terminal.
- Before every round, the commis checks the record. Questions you already answered, in a
  spec, a decision file or an earlier grilling, are shown as *already settled* with their
  source, not asked; you only say so if one has changed.
- The cook logs every decision. For a backlog item that needs a spec, it goes straight on
  to `/bk:spec` and writes a draft with the decisions in it; the sous numbers and files the
  spec and closes the backlog item into it. For an existing spec or ticket, the cook sends
  the decisions to the sous, who writes them in.
- The cook tells the sous it is done, and is spent: clear it before it takes a ticket.

**Brainstorming** (`/bk:brainstorm`) stays between you and the sous. The sous never hands
one to a cook.

## Handoffs and clearing sessions

**Is a handoff a hook or a skill?** A skill: `/bk:handoff`. Nothing runs automatically
before `/clear`, and no skill ever clears a session; `/clear` is always yours.

`/bk:handoff` works out its role from the directory it runs in:

| Where | Writes | When |
|---|---|---|
| a station (cook) | a `## Handoff` section appended to the ticket's journal: stage, uncommitted files, next step, pending questions, follow-ups, lessons | automatically on `[go]`, before the PR. Any other time, you ask for it, for example before clearing a cook that is waiting on a sign-off |
| the main checkout (sous) | first it files the record (decisions you made into ADRs, questions you haven't answered into question files, the inbox into the docs) and fetches CI minutes into the budget, then `.claude/sous-handoff.md`, gitignored, overwritten each time: your standing instructions, what it meant to assign next, walk-in holds, which session is which cook | when you say "handoff" before clearing the sous |

A cook cleared before `[go]` without being asked for a handoff leaves none. The journal
still has its questions, answers and decisions, and the station still has the files.

**And the whole kitchen at once?** `bk stop`. It asks every session for its handoff the same
way (it types `/bk:handoff` into each), waits for them, saves each session's id and exits
them. `bk open` later resumes the very same sessions, context and all, so this is a pause
rather than a clear; clear a session when its context is the problem, stop the kitchen when
you are leaving.

**What do I type after clearing the sous?** `/bk:sous-chef`. Nothing else. It reads the
handoff note first, then checks it against the rail, the stations and the journals, and
reality wins over the note. Its `[hello]` asks every cook to re-send whatever it was
waiting on. `/bk:pick-ticket` is not the way back in: that is a cook's step for one ticket.

**How does a cleared cook know it is a cook?** By where it is. Every lifecycle skill starts
with the station check, `kitchen.sh role`, which prints `cook <station> <main checkout>`
inside a station. So any session in a station behaves as a cook whether or not
`/bk:line-cook` was typed. Type `/bk:line-cook` after a `/clear` so that it checks in:

- on a ticket branch with work in flight, it reads the journal's last handoff and resumes;
- on a ticket that is already served (PR open or merged, station clean), it goes back to
  trunk and checks in as a fresh, free cook.

## Test accounts

Logins for testing a flow live in **`.claude/brigade.local.md`**, in the main checkout,
gitignored. Its `## Test accounts` section has a block each for `local`, `stage` and
`production`. Each account has a short name (`stage-builder`), its login details and what
it is for.

- **Getting one.** The cook asks the sous. The sous answers with the account's *name*; the
  cook reads that entry from the file itself. The secret never travels in a message.
- **A missing account.** The sous asks you once and shows the block to fill. You type it
  into the file. An empty section means "ask", never "guess" and never "create one".
- **Secrets stay in the file.** Journals, plans, tickets, commits and PRs name the account
  and nothing else. `kitchen.sh leaks` searches a checkout's changed files and commit
  messages for every secret in the file; the taster runs it at the pass and `/bk:open-pr`
  runs it before committing and before pushing. It is a literal search: it can't see a
  secret that was encoded or reworded, and it skips values under six characters.
- **Production is read-only by default.** Only the test accounts listed under `production`
  are used there. Any action that writes needs your yes for that exact action, asked in the
  sous's session. One yes covers one action.

## The record: never asked twice

**Why do I keep getting asked things I already answered?** You shouldn't, from this version
on. Everything you decide is written down, and a sub-agent searches it before any question
reaches you.

- **Where it lives.** The `docs:` map in `.claude/brigade.md` names every place: specs,
  tickets, plans, journals, and the record proper: `decisions` (ADRs), `conventions`,
  `knowledge` (how the product works, by area), `questions` (what nobody has answered yet).
  A repo that already keeps ADRs or a doc schema points the map at its own folders; the
  Brigade doesn't add a second home. Any other key the sous adds is one more place searched.
- **How it fills.** Every answer you give lands in the cook's journal marked `(head chef)`.
  Anything you say in passing that nothing records ("the cache invalidates on every deploy") the
  sous drops into the **inbox** right then, one line. At the sous's handoff three lists run:
  `kitchen.sh decisions` (your answers nothing cites yet: the sous writes the ones that
  outlive their ticket as decisions, your words verbatim plus a structured version),
  `kitchen.sh questions` (what you haven't answered: parked as a question file that blocks
  its ticket, so nobody asks it again while it waits), `kitchen.sh inbox` (filed into the
  right doc). The board shows the counts.
- **How it's read.** Before a cook sends any question, it spawns the **commis**, which
  searches all of it and returns `settled` with a source, `fact` with a `file:line`,
  `blocked` (an open question already asks this), `conflict` (two records disagree) or
  `nothing`. Settled questions never leave the station. The sous does the same before
  asking you, and when it answers from the record it tells you in one line, with the source,
  so you can say "that changed".
- **A chore is not a decision.** `kind: chore` on a backlog item means the outcome is
  already fixed; its plan is the sous's to sign, like a bug's.
- **A precedent is a decision already made about how.** When the code does the same kind
  of thing in two or more places and the record says why, "how do we add the third" is
  settled; the commis reports the instances, and a cook follows them. It never settles
  *whether*: the first of its kind is yours.
- **Two hooks back it up.** In a station, a dialog to the human is refused (unless a
  grilling is under way), and a question sent up without the commis's result is refused.
  Guardrails against a slip, not walls.
- **Grillings are the exception.** There you answer in the moment; settled questions are
  shown, not asked.

**What if I don't answer?** The ticket goes to `blocked`, the question becomes a file at
the sous's handoff with the options and its recommendation, and the cook takes another
ticket. When you answer, the file records your words, the ticket comes back, and the
answer is a decision like any other.

**Can the sous add a doc type?** Yes, when nothing in the map fits: through the repo's own
extension point if it has a doc schema, else a folder with an `INDEX.md`, then the key under
`docs:`. It tells you in one line; the PR that carries the doc is where you review it.
`kitchen.sh doctor` checks the map against `docs/` and the ticket files against the contract.

## The four sub-agents

Sub-agents are short-lived helpers a session spawns. None is started by hand.

| Sub-agent | Spawned by | Does | Can't |
|---|---|---|---|
| **commis** | a cook before any question, the sous before asking you, `grill-me` before every round | searches the record (the `docs:` map, `CLAUDE.md`, the stations' journals) and returns a verdict with sources: settled, fact, blocked, conflict or nothing. Runs on Opus | write anything, or decide anything |
| **inspector** | a cook, through `/bk:clean check` and `/bk:review-task` | reads the branch's diff and reports what a reviewer would reject, plus dead code in the diff | write anything: it holds no tool that can |
| **taster** | the sous, at the pass, on a cook's `[handoff]` | reads the station's diff, re-runs the check there, walks the ticket's "Done when" boxes, runs the leak check, returns a verdict with numbered findings | edit, commit or message anyone |
| **runner** | anyone | runs one noisy command (the check, a test suite, a scan) and returns pass or fail plus the lines that matter | decide or edit anything |

The point of all four is to keep long output, and long searches, out of the session that has to keep thinking.

## When something looks wrong

**The sous picked a backlog item instead of a ticket.** It shouldn't, unless the item is
`kind: bug`, `kind: chore` or `kind: precedent` and no spec ticket is ready. Check the rail board: any other
backlog item shows `spec` under `RDY` and is never assignable.

**Tickets I just wrote show `RDY no`.** Read what follows the title. An open blocker is
listed by id. An id with `?` is not a ticket on this rail (an older id scheme, or a typo);
it holds the ticket because nothing proves that work is done. Tell the sous the work is
finished and it removes the id from `blocked_by`. A chain of tickets all waiting on one
blocked ticket will all show `no` until that one is cleared.

**A backlog item I think is a bug, a chore or a precedent shows `spec`.** It has no `kind: bug`, `kind: chore` or `kind: precedent`. Tell the sous; it
sets `kind:` as a rail change with one line of why.

**The sous marked an item `precedent` and I think it's new.** Say so: it goes back to `item`
and gets its grilling. The sous tells you before it briefs anyone for exactly this reason.

**A cook left no handoff.** It was cleared before `[go]` and nobody asked for one. Ask for
`/bk:handoff` before clearing a cook mid-ticket.

**A station is dirty and no cook did it.** Usually the install step or a project hook wrote
into it. See [Setting up](#setting-up).

**A cook is waiting and nothing is happening.** Look at "waiting on" in the board. A feature
plan's sign-off waits for you; the sous won't approve that for you. A question nobody has
answered waits for you too: `kitchen.sh questions` lists it.

**The sous and a cook can't see each other.** Both must run under the same
`CLAUDE_CONFIG_DIR`. `kitchen open` passes the current one through.

**How do I restart one cook by hand?** For example after `/exit`, to load a new agent or
MCP server. In its station, run `.claude/cook`: it resumes the last session there
(`claude --continue`) with the same profile, name and model `kitchen open` used, so it
still sees the sous. `.claude/cook "/bk:line-cook"` starts a fresh session instead. Plain
`claude` would use whatever profile that terminal has.

## Command cheat sheet

| You want to | Type, in | |
|---|---|---|
| set the repo up | `bk setup` (or `/bk:setup`) | main checkout |
| create or add stations | `bk stations -n N` (or `/bk:kitchen setup -n N`) | main checkout |
| run one skill yourself, solo | `bk run SKILL words…` (or `/bk:SKILL words…`) | main checkout |
| tell the maintainers something | `bk feedback words…` (or `/bk:feedback`) | anywhere |
| open the kitchen (sous and cooks, in tmux) and sit with the sous | `bk open` (or `/bk:kitchen open`) | main checkout |
| talk to the sous | `bk attach` (or `tmux attach -t <repo>-brigade:sous`) | any terminal |
| peek at a cook | `bk peek N` (or `tmux attach -t <repo>-brigade:station-N`), `Ctrl-b d` to leave | any terminal |
| pause the whole kitchen, resumable | `bk stop`, later `bk open` | any terminal |
| pick the Claude account a kitchen runs under | `bk open --profile NAME` (recorded in `.claude/bk-profile`) | main checkout |
| start or restart the sous | `/bk:sous-chef` | main checkout |
| restart a cleared cook | `/bk:line-cook` | its station |
| see everything | open `.claude/board.md`, or `/bk:kitchen board` | main checkout |
| watch the kitchen in a browser | `bk live` or `/bk:live` (again to close) | main checkout or a station |
| see what the kitchen is waiting on you for | `/bk:kitchen questions` | main checkout |
| tell the kitchen something it should remember | just say it to the sous; it goes in the inbox and is filed at handoff | sous |
| check the rail and the docs map | `/bk:kitchen doctor` | main checkout |
| see what the shift costs | `bk budget` or `/bk:kitchen budget` (`--ticket ID`, `--since 7d`, `--ci`) | main checkout or a station |
| capture an idea or a bug | tell the sous; it files a backlog item | sous |
| turn an item into tickets | `/bk:grill-me` → `/bk:spec` → `/bk:file-tickets` | sous, or a cook the sous briefs for the grilling |
| clear a session safely | "handoff", then `/clear` | that session |
| work alone, no kitchen | any skill in the main checkout without `/bk:sous-chef`: you answer every gate | main checkout |
