# The Brigade

Run a kitchen of Claude Code sessions. One **sous chef** leads, a few **line cooks** work
one ticket each at their own **station**, and you are the **head chef**: you approve
plans and you merge. The sessions talk to each other with `SendMessage`. There is no
daemon, no queue, and no database.

> Inspired by Steve Yegge's *[The Shape of Things to Come](https://yegge.ai/essays/the-shape-of-things-to-come/)*
> and *[Model Welfare for Agentic Engineers](https://yegge.ai/essays/model-welfare/)*.
> Gas Town is a city of agents. The Brigade is the same idea at the scale of one engineer
> and one laptop.

## Contents

- [Why a kitchen](#why-a-kitchen)
- [The cast](#the-cast)
- [The three lanes](#the-three-lanes)
- [The rules](#the-rules)
- [Install](#install)
- [Set up a repo](#set-up-a-repo)
- [Run a service](#run-a-service)
- [What's in the box](#whats-in-the-box)
- [Honest limits](#honest-limits)
- [Status](#status)

## Why a kitchen

A professional kitchen already solved this problem: several people working in parallel,
in one shared room, under time pressure, with one person checking every plate before it
goes out. Escoffier's *brigade de cuisine* gives every station one owner, turns every order
into a ticket, and puts one gate between the kitchen and the customer: **the pass**.

## The cast

| Kitchen | In the harness |
|---|---|
| **Head Chef** | you: sign off plans, answer real forks, merge, deploy |
| **Sous Chef** | the lead session: assigns tickets, answers routine questions, is the only one who writes the rail, reviews every diff at the pass |
| **Line Cook** | a worker session: one ticket, plan to PR |
| **Station** | a gitignored clone at `stations/station-N` |
| **The Walk-in** | shared local resources (a database, a docker stack) that one cook could break for everyone |
| **The Rail** | where tickets live: markdown in `docs/` (default), GitHub Projects, or Jira |
| **Health Inspector** | a report-only sub-agent that reviews diffs |

The full table, plus an Urdu alternate (Qafila), is in [`docs/the-names.md`](docs/the-names.md).

## The three lanes

| Lane | Source | Path |
|---|---|---|
| **A — Specials** | a spec, sliced into tickets | brainstorm → grill-me → spec → file-tickets → create-plan → implement → review → open-pr |
| **B — À la carte** | tickets already on the rail | pick-ticket → (grill-me) → create-plan → implement → review → open-pr |
| **C — Clean as you go** | the kitchen finds its own mess: `/bk:clean scan` | pick-ticket → implement → open-pr |

## The rules

1. **One cook, one ticket, one shift.** Clear the session before its next ticket.
2. **If it's on the rail, it's taken**, even if you can't see the plan: it's in another station.
3. **Nobody empties the walk-in without calling it.** Ask the sous before a reset.
4. **One migration in flight at a time.**
5. **Two tickets on the same files go to the same cook**, in sequence.
6. **The chef signs the recipe, the sous checks the plate.** The sous never speaks for the chef on merge or deploy.
7. **Call for decisions, not ceremony.** Routine questions go to the sous; only real forks reach you.
8. **Trust the cook at the station.** When a cook says the sous is wrong about its station, the cook wins.

## Install

In Claude Code:

```
/plugin marketplace add mhmzdev/claude-code-brigade
/plugin install bk@claude-code-brigade
```

Or commit it for your whole team in `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "claude-code-brigade": {
      "source": { "source": "github", "repo": "mhmzdev/claude-code-brigade" }
    }
  },
  "enabledPlugins": { "bk@claude-code-brigade": true }
}
```

You need a Claude Code version where sessions on one machine can see each other
(`ListAgents`) and message each other (`SendMessage`). All sessions must run under the
same `CLAUDE_CONFIG_DIR`.

## Set up a repo

At the repo root, with a clean working tree:

```
/bk:setup
```

It reads the repo, asks one round of questions, and writes:

```
.claude/brigade.md          # config: trunk, check command, walk-in, rail adapter
docs/specs/001-<slug>.md    # specs; their tickets in docs/specs/001-<slug>/01-<slug>.md
docs/backlog/BKLG-001-*.md  # standalone tickets;  HYG-001-*.md for hygiene
docs/plans/  docs/checklists/  docs/research/  docs/brainstorm/
stations/station-1 …        # gitignored clones, one per cook
```

Tickets carry their status in frontmatter. There is no summary page to keep in sync:
`kitchen.sh rail` computes the board each time.

## Run a service

1. `/bk:kitchen open` opens one bare Claude session per station.
2. In the main checkout: `/bk:sous-chef`.
3. In each station: `/bk:line-cook`.
4. Tell the sous which ticket to fire, or ask it to propose one per lane.

## What's in the box

| Skill | Does |
|---|---|
| `setup` | set up a repo |
| `kitchen` | stations: setup, open, sync, status, files in flight, the rail board |
| `sous-chef` / `line-cook` | take the lead or worker role |
| `rail` | list, read, claim, fire, link, close: markdown, GitHub or Jira |
| `brainstorm` · `grill-me` · `spec` · `file-tickets` | lane A, from idea to tickets |
| `pick-ticket` · `create-plan` · `implement` · `review` · `open-pr` | from ticket to PR |
| `clean` | lane C: count the mess, file hygiene tickets, pre-review inspection |

Every skill works **solo** too: without a sous, you are both chef and sous.
The shared rules every skill follows are in [`plugins/bk/skills/README.md`](plugins/bk/skills/README.md).

## Honest limits

- One machine. Two to five cooks, not a fleet.
- The sous is a second fence, not a replacement for your review. You still merge.
- It costs more tokens than one session. Use it when the work is really parallel.
- Stations live inside the repo, gitignored. **Never run `git clean -fdx`** there, and
  exclude `stations/` from tools that don't read `.gitignore` (setup helps with this).

## Status

v0.1: the skills are written and `kitchen.sh` is tested; a full end-to-end service on a
real repo hasn't been run yet. Issues and PRs welcome.

MIT © Muhammad Hamza
