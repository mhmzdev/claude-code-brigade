# Changelog

What changed in each version of the Brigade (`bk@claude-code-brigade`), newest first.

Every merge to `main` is a release. It bumps `version` in
[`plugins/bk/.claude-plugin/plugin.json`](plugins/bk/.claude-plugin/plugin.json), adds an
entry here, and is tagged `vX.Y.Z` with a [GitHub release](https://github.com/mhmzdev/claude-code-brigade/releases)
that carries the entry as its notes. To get a new version, see
[Update](README.md#update), then restart every session.

Versions follow [semver](https://semver.org) loosely while the Brigade is `0.x`: the minor
number moves for a change in how a kitchen runs, the patch number for fixes and changes
that don't touch the plugin's behaviour. A **breaking** change is called out in bold.

## [0.15.1] - 2026-10-14

Lesson promotion works when journals move or the docs folder has rules.
`kitchen.sh lessons` reads journals at any depth under `docs.journal`, so lessons from
finished tickets still count when their journal moves (for example, inside a plan moved to
`completed/`). The register of promoted lessons now has its own key, `docs.lessons`
(default `docs/lessons.md`): set it if the repo doesn't allow that file.
([#18](https://github.com/mhmzdev/claude-code-brigade/issues/18))

## [0.15.0] - 2026-10-14

Restart a cook by hand without losing the sous. `kitchen open` now leaves each station a
`.claude/cook` launcher (kept out of git) with the cook's `CLAUDE_CONFIG_DIR`, name, model
and permission mode in it. After `/exit`, run `.claude/cook` in that station to resume the
session, or `.claude/cook "/bk:line-cook"` for a fresh one. No retyping the profile; plain
`claude` would pick up whatever profile the terminal has, and then the cook can't see the
sous. Stations get the launcher the next time `kitchen open` opens them.
([#16](https://github.com/mhmzdev/claude-code-brigade/issues/16))

## [0.14.1] - 2026-10-14

The sous trusts a cook's `[check-in]`. A cook that checks in with no ticket, a clean
station and a fresh session gets its brief straight away; the sous no longer asks it to
confirm it was cleared. ([#12](https://github.com/mhmzdev/claude-code-brigade/issues/12))

## [0.14.0] - 2026-10-14

A cook that's restarted or cleared can find the sous by itself. When `/bk:sous-chef`
starts, it records its session name with the new `kitchen.sh sous --set`, in
`.claude/sous` (kept out of git). `/bk:line-cook` reads it with `kitchen.sh sous` and checks
in straight away, as long as `ListAgents` still lists that name; otherwise it waits for the
sous's `[hello]` as before. Restart the sous once after updating so it records its name.
([#15](https://github.com/mhmzdev/claude-code-brigade/issues/15))

## [0.13.1] - 2026-10-14

This changelog. The version history moved here from the README's Status section. Every
merge to `main` is now a release: CI refuses a pull request that doesn't bump the version
and add its entry here, and each merge is tagged `vX.Y.Z` with a GitHub release. No change
to the plugin itself.

## [0.13.0] - 2026-10-10

A backlog item is work that still has to become tickets. Only a bug (`kind: bug`) is
planned and built straight from the backlog; every other item goes through a spec first,
however small. The old "small enough to build" judgement is gone. The rail board now says
so itself: `RDY` is `yes`, `no` (a blocker is open) or `spec` (a backlog item waiting for
its spec). It also resolves blockers itself, listing only the open ones and marking an id
that is no ticket on the rail with `?`, which holds the ticket; before, the sous was told a
blocker missing from the board was done. **Existing backlog items have no `kind:` and now
read as items:** mark the real bugs `kind: bug`.

## [0.12.0] - 2026-10-10

The sous assigns work itself: each free cook gets the next ready ticket, by `priority` (a
new optional ticket field, shown on the rail board), then by what unblocks the most, then
oldest first. It tells you what it assigned; `gates.assign: head-chef` makes it ask first.
The sous can hand a grilling to a free cook: it tells you which station is waiting, the
cook grills you there, logs the decisions in the spec, and reports back. Brainstorming
stays between you and the sous.

## [0.11.0] - 2026-10-10

Test accounts: logins for local, stage and production live in the gitignored
`.claude/brigade.local.md`, so you share them once. Cooks ask the sous for an account by
name and read it from the file; secrets never go into messages, journals or PRs, and the
new `kitchen.sh leaks` checks for them at the pass and again before the commit and the
push. A write on production needs your yes for that one action.

## [0.10.0] - 2026-10-10

You now talk to the sous only. Cooks never ask the human: every question goes to the sous,
which brings plans and real design forks to you with a recommendation and relays your
answer. The plan sign-off moved from typing `/bk:implement` in each cook's terminal to a
yes in the sous's; the sous sends `[approved]` and the cook starts. So `implement` is now
model-invocable, and checks the sign-off itself. `kitchen.sh board` prints the whole state
in one go and keeps `.claude/board.md` current for you to leave open.

## [0.9.0] - 2026-10-10

The backlog is now where un-specced work waits. A `BKLG` item can be anything not yet
grilled or specced, a whole capability included, and `/bk:file-tickets` no longer asks for
a spec first. `/bk:pick-ticket` says whether an item is small enough to build directly or
needs a spec; `/bk:spec` then closes the item into the spec it became (`spec: SNNN`), and
the spec's tickets carry the work.

## [0.8.0] - 2026-09-30

`/bk:feedback` sends feedback to the maintainers as a GitHub issue: scrubbed of anything
from your repo, session context only if you agree, filed only on your yes. The sous's
handoff files due plugin lessons through it. `kitchen.sh sessions` lists the saved session
transcripts for a checkout or a station, from `$CLAUDE_CONFIG_DIR`.

## [0.7.0] - 2026-09-29

`kitchen open` without Warp now opens the machine's own terminal (Terminal.app, Windows
Terminal or mintty, or the Linux desktop's) instead of tmux, and prints the commands only
when there is none. Warp is also found in `~/Applications` and on Linux. tmux is still
there with `--terminal tmux`. To grow a kitchen, run `kitchen setup -n 4`: existing
stations stay put, and `open` now opens every station, not just the configured count,
skipping any station where a cook is already running.

## [0.6.0] - 2026-09-29

Long services: ticket journals, `/bk:handoff` for cooks and the sous, lessons promoted by
count, the `taster` and `runner` sub-agents, and cleaning in three scopes. A session inside
a station is a cook even after `/clear`. `clean` is no longer human-only, so cooks run it
in their loop.

## [0.5.2] - 2026-09-28

Cooks start in Claude Code's `auto` permission mode (set `permission_mode:` in the config
to change it), and `kitchen open` names each one `<repo>-cook-N`.

## [0.5.1] - 2026-09-28

`kitchen open` names cook sessions, and `INDEX` files merge with git's union driver so two
cooks adding rows don't conflict.

## [0.5.0] - 2026-09-28

Skills no longer ask for approval they already have; **`review` is now `review-task`**;
cooks start themselves and check in in either order.

## [0.4.0] - 2026-09-28

`/bk:setup --worktree` and `--clone` pick the station kind, and setup refuses to run at a
workspace root.

## [0.3.0] - 2026-09-28

Tried on a real repo (a Flutter package): setup, stations, `kitchen open`, and the sous ↔
cook check-in all work. Adds worktree stations (`kitchen_mode: worktree`), tested in a
nested workspace layout; clone mode is unchanged.

## [0.2.0] - 2026-09-28

**The plugin is renamed `brigade` → `bk`**, so skills are `/bk:<skill>`. Uninstall
`brigade@claude-code-brigade` and install `bk@claude-code-brigade`. Setup now pushes before
it creates stations, since a station is a fresh clone of `origin/<trunk>`.

## [0.1.0] - 2026-09-28

The first Brigade: the sous chef, line cooks, the rail, and the lifecycle skills.
