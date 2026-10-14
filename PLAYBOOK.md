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
- [The three sub-agents](#the-three-sub-agents)
- [When something looks wrong](#when-something-looks-wrong)
- [Command cheat sheet](#command-cheat-sheet)

## The idea in one paragraph

You are the **head chef**. You talk to one Claude Code session, the **sous chef**, usually
on the biggest model, in the repo's main checkout. The sous runs the **line cooks**: one
session per **station** (a separate copy of the repo), each working one ticket from plan to
pull request. Cooks can be smaller models, or big ones for hard tickets. You don't watch
the cooks' terminals. Everything they need decided reaches you through the sous, with a
recommendation, and you approve plans and merge.

## Setting up

**How do I set it up in a repo?** Run `/bk:setup` in the repo's main checkout. It reads the
repo, asks one round of questions, and writes:

- `.claude/brigade.md`: the config every skill reads (trunk, check command, install
  command, stations, where tickets live);
- the rail folders under `docs/` (specs, backlog, plans, checklists, journal), each with an
  `INDEX.md`;
- a short section in `CLAUDE.md` saying the repo runs on the Brigade, and that a session
  inside a station is a line cook.

Nothing is committed until you say so. Stations are created from `origin/<trunk>`, so the
setup must be pushed before `/bk:kitchen setup` can build them.

**Do I need several stations?** No. One station works: you get the sous plus one cook.
Add more later with `/bk:kitchen setup -n 3`; existing stations are left alone.

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
| `item` (default, also when missing) | a capability, a change in behaviour, a chore | `/bk:grill-me` → `/bk:spec` → `/bk:file-tickets`. The spec's tickets get built; the item is closed with `spec: SNNN` |
| `bug` | something that exists and works wrong against what was already decided | the item is its own ticket: `/bk:create-plan`, then build |

Bug or item is a fact about the work, not its size. A small new behaviour is still an item.

**The three lanes** say where a ticket came from:

| Lane | Source | Ids |
|---|---|---|
| A | a spec, sliced into tickets | `SNNN-NN` |
| B | bugs from the backlog | `BKLG-NNN` with `kind: bug` |
| C | hygiene work the kitchen finds itself (`/bk:clean`) | `HYG-NNN` |

**Statuses:** `backlog` → `todo` (a plan exists) → `in-progress` → `rfr` (ready for
review) → `done`, plus `blocked`. `backlog` and `blocked` are free; anything else is
somebody's claim.

## Starting a shift

Two commands, in either order:

1. **`/bk:kitchen open`** in the main checkout opens one terminal per station, each already
   running `/bk:line-cook`. It only opens sessions. It assigns nothing.
2. **`/bk:sous-chef`** in the main checkout makes that session the sous. It pulls trunk,
   reads its last handoff note, collects unanswered questions from the cooks' journals,
   builds the board, records its session name for the cooks (`kitchen.sh sous`), says
   `[hello]` to cooks that were already waiting, and then assigns work.

So the sous is what picks tickets, not `kitchen open`. You don't need to ask it to.

## How work gets assigned

The sous assigns the next ready ticket to each **free** cook without asking, and tells you
in one line what it assigned and why. (Set `gates.assign: head-chef` in the config if you
want it to propose and wait for a yes instead.)

**A cook is free** when its check-in says: no ticket, a clean station, and a fresh session.
A cook that has just served a ticket or held a grilling is *spent* and is not free until
you clear it.

**A ticket is ready** when its status is `backlog` or `blocked`, every ticket in its
`blocked_by` is `done`, and it isn't a backlog item that still needs a spec. The rail board
works this out; its `RDY` column says:

| `RDY` | Means |
|---|---|
| `yes` | can be assigned |
| `no` | a blocker is still open; the open blockers are printed after the title |
| `spec` | a backlog item that isn't a bug: it has to become a spec and tickets first |
| `-` | already claimed |

**Order among ready tickets:**

1. what you said to do first, or to hold;
2. `priority:` `high`, then normal, then `low`;
3. the ticket that more other tickets are blocked by;
4. lane A before B before C; within a spec, ticket-number order; otherwise the lowest id.

So spec tickets go before backlog bugs, and a backlog item that isn't a bug is never
assigned at all. When nothing is ready, the sous says what is blocked and on what, and
offers a grilling for the highest-priority item waiting for a spec.

Two hard rules can skip a pick: tickets touching the same files go to one cook in sequence,
and only one station carries a database migration at a time.

## Who you talk to

**The sous, and only the sous.** A cook never asks you anything and never opens a question
dialog; nobody is watching its terminal. What a cook needs goes to the sous as a message:

| The cook needs | It sends | Who answers |
|---|---|---|
| a routine confirmation (scope, "continue?", which helper) | `[gate]` | the sous |
| a real design fork | `[gate]` | you, in the sous's terminal; the sous adds a recommendation and relays your answer marked `(head chef)` |
| the plan approved | `[plan]` | you, in the sous's terminal; the sous relays `[approved]` with your words |
| a ticket changed | `[rail]` | the sous (the only writer of tickets) |
| a destructive command on a shared resource | `[walk-in]` | the sous |
| a login for testing | `[gate] … need a test account` | the sous, with an account name |
| a write on production | `[gate] … production write` | you, for that exact action |
| merge or deploy | nothing | you do these yourself; no session does, and a relayed "go" is refused |

The sous never approves a plan itself. Every plan needs your own yes, in the sous's current
session, after seeing that plan. A changed plan needs a new yes.

If you do type in a cook's terminal, the cook does as told and tells the sous in one line.

## One ticket, start to PR

1. The sous sends the cook a `[brief]`: the ticket's path, why it matters, constraints.
2. The cook branches (`<id>-<slug>`), runs `/bk:pick-ticket`, and asks the sous to claim
   the ticket (`todo`).
3. `/bk:create-plan` writes the plan. The cook sends `[plan]` and waits.
4. The sous reads the plan, checks it against the other stations, and shows you a short
   summary with a recommendation. You approve, change something, or ask to grill it first.
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

Lane C (hygiene) skips the plan and the checklist; you approve the ticket itself before the
sous assigns it.

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

## Grilling and brainstorming

**Grilling** (`/bk:grill-me`) questions an idea until there is one shared picture. It needs
you.

- The sous can grill you itself, or **hand the grilling to a free cook**. A long grilling
  fills the context the sous needs for the passes, and the cook has the code in front of
  it. The sous tells you which station is waiting; you answer the questions there. This is
  the one planned time you use a cook's terminal.
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
| the main checkout (sous) | `.claude/sous-handoff.md`, gitignored, overwritten each time: your standing instructions, what it meant to assign next, walk-in holds, which session is which cook | when you say "handoff" before clearing the sous |

A cook cleared before `[go]` without being asked for a handoff leaves none. The journal
still has its questions, answers and decisions, and the station still has the files.

**What do I type after clearing the sous?** `/bk:sous-chef`. Nothing else. It reads the
handoff note first, then checks it against the rail, the stations and the journals, and
reality wins over the note. Its `[hello]` asks every cook to re-send whatever it was
waiting on. `/bk:pick-ticket` is not the way back in: that is a cook's step for one ticket.

**How does a cleared cook know it is a cook?** By where it is. Every lifecycle skill starts
with the station check, `kitchen.sh role`, which prints `cook <station> <main checkout>`
inside a station. So any session in a station behaves as a cook whether or not
`/bk:line-cook` was typed. Type `/bk:line-cook` after a `/clear` so that it checks in:

- on a ticket branch with work in flight, it reads the journal's last handoff and resumes;
- on a ticket that is already served (PR open, station clean), it goes back to trunk and
  checks in as a fresh, free cook.

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

## The three sub-agents

Sub-agents are short-lived helpers a session spawns. None is started by hand.

| Sub-agent | Spawned by | Does | Can't |
|---|---|---|---|
| **inspector** | a cook, through `/bk:clean check` and `/bk:review-task` | reads the branch's diff and reports what a reviewer would reject, plus dead code in the diff | write anything: it holds no tool that can |
| **taster** | the sous, at the pass, on a cook's `[handoff]` | reads the station's diff, re-runs the check there, walks the ticket's "Done when" boxes, runs the leak check, returns a verdict with numbered findings | edit, commit or message anyone |
| **runner** | anyone | runs one noisy command (the check, a test suite, a scan) and returns pass or fail plus the lines that matter | decide or edit anything |

The point of all three is to keep long output out of the session that has to keep thinking.

## When something looks wrong

**The sous picked a backlog item instead of a ticket.** It shouldn't, unless the item is
`kind: bug` and no spec ticket is ready. Check the rail board: a non-bug backlog item shows
`spec` under `RDY` and is never assignable.

**Tickets I just wrote show `RDY no`.** Read what follows the title. An open blocker is
listed by id. An id with `?` is not a ticket on this rail (an older id scheme, or a typo);
it holds the ticket because nothing proves that work is done. Tell the sous the work is
finished and it removes the id from `blocked_by`. A chain of tickets all waiting on one
blocked ticket will all show `no` until that one is cleared.

**A backlog item I think is a bug shows `spec`.** It has no `kind: bug`. Tell the sous; it
sets `kind:` as a rail change with one line of why.

**A cook left no handoff.** It was cleared before `[go]` and nobody asked for one. Ask for
`/bk:handoff` before clearing a cook mid-ticket.

**A station is dirty and no cook did it.** Usually the install step or a project hook wrote
into it. See [Setting up](#setting-up).

**A cook is waiting and nothing is happening.** Look at "waiting on" in the board. A plan
sign-off waits for you; the sous won't approve it for you.

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
| set the repo up | `/bk:setup` | main checkout |
| create or add stations | `/bk:kitchen setup -n N` | main checkout |
| open the cooks | `/bk:kitchen open` | main checkout |
| start or restart the sous | `/bk:sous-chef` | main checkout |
| restart a cleared cook | `/bk:line-cook` | its station |
| see everything | open `.claude/board.md`, or `/bk:kitchen board` | main checkout |
| capture an idea or a bug | tell the sous; it files a backlog item | sous |
| turn an item into tickets | `/bk:grill-me` → `/bk:spec` → `/bk:file-tickets` | sous, or a cook the sous briefs for the grilling |
| clear a session safely | "handoff", then `/clear` | that session |
| work alone, no kitchen | any skill in the main checkout without `/bk:sous-chef`: you answer every gate | main checkout |
