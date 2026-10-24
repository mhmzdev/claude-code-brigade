# The Brigade

[![check](https://github.com/mhmzdev/claude-code-brigade/actions/workflows/check.yml/badge.svg)](https://github.com/mhmzdev/claude-code-brigade/actions/workflows/check.yml)
[![release](https://img.shields.io/github/v/release/mhmzdev/claude-code-brigade)](CHANGELOG.md)

![The Brigade: a sous chef bot at the pass, line-cook bots at five stations, and the human head chef overseeing](assets/hero.jpeg)

Run a kitchen of Claude Code sessions on one machine. A **sous chef** session leads, a few
**line cook** sessions each work one ticket in their own **station** (a clone or worktree),
and you are the **head chef**: you approve feature plans and you merge. The sessions talk to
each other over `SendMessage`. No daemon, no queue, no database.

> Inspired by Steve Yegge's *[The Shape of Things to Come](https://yegge.ai/essays/the-shape-of-things-to-come/)*
> and *[Model Welfare for Agentic Engineers](https://yegge.ai/essays/model-welfare/)*.
> Gas Town is a city of agents. The Brigade is the same idea at the scale of one engineer
> and one laptop.

## Contents

- [Install](#install)
- [Set up a repo](#set-up-a-repo)
- [Run a service](#run-a-service)
- [The Window](#the-window)
- [Pause and resume](#pause-and-resume)
- [How work flows](#how-work-flows)
- [What's in the box](#whats-in-the-box)
- [Troubleshooting](#troubleshooting)
- [Feedback](#feedback)
- [Honest limits](#honest-limits)

## Install

```bash
brew install mhmzdev/brigade/bk
```

That gives you the `bk` command, with tmux and node behind it. You need
[Claude Code](https://claude.com/claude-code) installed and logged in. Use the full formula
name: Homebrew's own `bk` is an unrelated EPUB reader. macOS and Linux; on Windows use WSL.

Every session `bk` starts loads the plugin that came with it, so there is no marketplace
step. Update with:

```bash
brew upgrade mhmzdev/brigade/bk
```

<details>
<summary>Plugin only, without <code>bk</code></summary>

In Claude Code:

```
/plugin marketplace add mhmzdev/claude-code-brigade
/plugin install bk@claude-code-brigade
```

Or for your whole team, in `.claude/settings.json`:

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

You then open the kitchen with `/bk:kitchen open` from a Claude session and attach with
`tmux attach -t <repo>-brigade:sous`. Update with `/plugin marketplace update claude-code-brigade`
and `claude plugin update bk@claude-code-brigade`, then restart every session.
</details>

## Set up a repo

Once per repo, at its root, inside Claude Code:

```
/bk:setup               # detects the station kind and recommends it
/bk:setup --worktree    # or choose: worktrees next to the repo (big repos, workspaces)
/bk:setup --clone       #            clones inside the repo (the simple default)
```

It asks one round of questions and writes the config (`.claude/brigade.md`), the ticket
folders under `docs/` and a short section in `CLAUDE.md`. Nothing is committed until you
say so. Commit and push it, then create the stations:

```bash
bk setup -n 3           # three stations, three cooks
```

Stations are gitignored (`stations/`) or live next to the repo (`../<repo>-stations/`).
Never run `git clean -fdx` in a repo with clones inside it.

## Run a service

```bash
bk open
```

That starts everything in one tmux session and puts you in front of the sous:

- the sous, already running `/bk:sous-chef`;
- one cook per station, already running `/bk:line-cook`, who find the sous and check in.

The sous picks the next ready ticket for each free cook, briefs it, answers its questions
from the record, reviews its diff before anything is committed, and tells you what it
assigned. You talk to the sous only. It comes to you for two things: a yes on a feature
plan, and the merge.

| You want to | Type |
|---|---|
| leave the kitchen running and get your terminal back | `Ctrl-b d` |
| go back to the sous | `bk attach` |
| watch cook 2 work | `bk peek 2`, then `Ctrl-b d` |
| see what is up | `bk status` |
| the board: stations, files in flight, the rail, open questions | `bk board` |
| the questions waiting on you | `bk questions` |
| watch it all in the browser | `bk live` |
| pause everything for the day | `bk stop` |

Detaching leaves every session running; so does closing the terminal. Only `bk stop`, a
logout or a reboot ends them.

Several Claude Code logins on one machine (`~/.claude`, `~/.claude-work`)? `bk open --profile work`
picks one the first time and records it in `.claude/bk-profile`, out of git. Every later
`bk` command uses the same one, so a kitchen never mixes two accounts.

## The Window

```bash
bk live
```

![The Window: the kitchen drawn as a room, the rail on the left, the line's messages below](assets/window.png)

The Window is the kitchen in your browser, for when you want to see the whole line without
touching a terminal. The sous stands at the pass, each cook at its station with its ticket,
the commis at the record, and every message between them appears as a speech bubble and
in the console below. The rail is down the left. Click a cook or the sous for its page:
what it is doing, its branch, its questions, and controls that type into that session for
you (send a line, change the model, hand off, answer a question). Run `bk live` again to
close it. Try it without a kitchen: `bk live --demo`.

## Pause and resume

```bash
bk stop        # at the end of the day
bk open        # the next morning: everyone carries on where they stopped
```

`bk stop` types `/bk:handoff` into the sous and every cook, waits until each has written
where it is, saves every session's id, exits them and closes tmux and the Window. It
commits nothing. The next `bk open` resumes the same sessions, context and all.
`bk open --fresh` starts new sessions instead.

A single session that has grown too long is cleared, not paused: say "handoff", then
`/clear`, then `/bk:sous-chef` or `/bk:line-cook`. Everything a fresh session needs is on
disk: tickets on the rail, plans and checklists, each ticket's journal, the record of
decisions, and the sous's own note.

## How work flows

Three lanes, one loop:

| Lane | Starts from | Path |
|---|---|---|
| **A, Specials** | an idea, grilled into a spec, sliced into tickets | brainstorm → grill-me → spec → file-tickets → create-plan → implement → review-task → open-pr |
| **B, À la carte** | a bug or chore on the backlog | pick-ticket → create-plan → implement → review-task → open-pr |
| **C, Clean as you go** | mess the kitchen finds itself (`/bk:clean scan`) | pick-ticket → implement → open-pr |

The rules the kitchen runs on:

1. **One cook, one ticket, one shift.** Clear the session before the next ticket.
2. **If it's on the rail, it's taken.** The plan is in another station.
3. **Nobody empties the walk-in without calling it.** Shared resources (a database, a docker stack) go through the sous.
4. **The chef signs the specials, the sous checks every plate.** Feature plans need your yes; bugs, chores and hygiene the sous signs and tells you. Every diff is reviewed before it is committed.
5. **Call for decisions, not ceremony.** Before any question reaches you, the `commis` has searched the record. Answer once and it is written down; you are never asked twice.

Test logins live in `.claude/brigade.local.md`, gitignored; a cook gets an account's name
from the sous, never its password, and `bk leaks` checks every diff for them. The full cast
and names are in [`docs/the-names.md`](docs/the-names.md); every flow, question by
question, is in [`PLAYBOOK.md`](PLAYBOOK.md).

## What's in the box

| | |
|---|---|
| `bk` | `open`, `attach`, `peek`, `stop`, `status`, `live`, profiles, and every `kitchen.sh` word (`board`, `rail`, `questions`, `doctor`, `sync`, …) |
| `setup` · `kitchen` | set up a repo; manage stations and print the boards |
| `sous-chef` · `line-cook` | the lead and worker roles |
| `brainstorm` · `grill-me` · `spec` · `file-tickets` | from idea to tickets |
| `pick-ticket` · `create-plan` · `implement` · `review-task` · `open-pr` | from ticket to PR |
| `clean` | `check` your diff, `around` your station, `scan` the kitchen |
| `rail` | tickets on markdown (default), GitHub Projects or Jira |
| `handoff` · `feedback` · `live` | hand a session off; file an issue here; the Window |
| agents `commis` · `taster` · `runner` · `inspector` | search the record · review at the pass · run noisy commands · flag what a reviewer would reject |

Every skill works solo too: without a sous, you are both chef and sous. The rules every
skill follows are in [`plugins/bk/skills/README.md`](plugins/bk/skills/README.md).

## Troubleshooting

| You see | Why | Do |
|---|---|---|
| `bk open`: "No stations yet" | the setup isn't pushed, or `bk setup` hasn't run | commit and push the setup, then `bk setup -n N` |
| `bk: several Claude Code profiles on this machine and none recorded` | more than one `~/.claude*` folder and this repo hasn't picked one | `bk open --profile NAME` once (`default` is `~/.claude`) |
| `bk version` prints `init error: No such file or directory` | a bare `brew install bk` installed Homebrew's `bk`, an EPUB reader | `brew uninstall bk && brew install mhmzdev/brigade/bk` |
| `bk stop` says a session is still busy after the timeout | its handoff didn't finish | it was saved and stopped anyway; `bk open` resumes it. `bk stop --timeout 1200` waits longer |
| the sous can't find a cook, or the reverse | they run under different Claude Code profiles | open everything with `bk open`; to restart one cook by hand, run `.claude/cook` in its station, which keeps the profile |
| a station is dirty right after setup | the install step wrote into it | `git -C stations/station-N diff`, fix the cause in the main checkout, then `git -C stations/station-N checkout -- .` |

## Feedback

```
/bk:feedback the sous asked me a routine question instead of answering it
```

It drafts a GitHub issue for this repo with your plugin version and setup, scrubbed of your
repo's names, paths and secrets, and files nothing until you have read it and said yes. Or
[open an issue](https://github.com/mhmzdev/claude-code-brigade/issues/new?template=feedback.yml) by hand.

## Honest limits

- One machine. Two to five cooks, not a fleet.
- The sous is a second fence, not a replacement for your review. You still merge.
- It costs more tokens than one session. Use it when the work is really parallel.

Every merge to `main` is a release, tagged and listed in [`CHANGELOG.md`](CHANGELOG.md).

MIT © Muhammad Hamza
