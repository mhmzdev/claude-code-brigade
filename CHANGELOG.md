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

## [0.19.1] - 2026-10-24

**Install `bk` by its full name: `brew install mhmzdev/brigade/bk`.** Homebrew's own
formula called `bk` is an unrelated EPUB reader, and a bare `brew install bk` installs that
one, after which `bk version` prints `init error: No such file or directory`. The README,
the formula's caveats and the troubleshooting table now say the full name, and the formula
declares the conflict so Homebrew explains it instead of linking over it.

What you must do, if you installed with the short name: `brew uninstall bk && brew install
mhmzdev/brigade/bk`. Upgrades are `brew upgrade mhmzdev/brigade/bk`.

## [0.19.0] - 2026-10-24

**`bk`, the Brigade's command on your machine.** `brew tap mhmzdev/brigade && brew install bk`
puts `bk` on your PATH, with tmux and node behind it (macOS and Linux; Windows through WSL).
In a repo set up for the Brigade: `bk open` starts the kitchen in tmux and sits you with the
sous; `Ctrl-b d` leaves it running; `bk attach` goes back to the sous; `bk peek 2` shows cook
2; `bk live` opens the Window; `bk status` says what is up; any other word (`board`, `rail`,
`questions`, `doctor`, …) goes to `kitchen.sh`. **`bk stop` is a pause, not an end:** it types
`/bk:handoff` into the sous and every cook, waits until each has finished (ten minutes at
most, then it says who is still busy and goes on), saves every session's id, exits them and
closes the tmux session and the Window. The next `bk open` resumes each session where it
stopped; `bk open --fresh` starts new ones instead. Every session `bk` starts loads the plugin
installed next to it (`claude --plugin-dir`), so there is no marketplace step and nothing to
keep in step; `brew upgrade bk` is the update. With several Claude Code logins on one machine
(`~/.claude`, `~/.claude-work`, …), `bk open --profile work` picks one, and the choice is
recorded in `.claude/bk-profile` (kept out of git) so every later command, and the resume
after a stop, uses the same account; with several profiles and nothing recorded, `bk open`
asks once.

Also: when the `sous` window is still there but the sous has left it (an `/exit` by hand),
opening the kitchen again starts the sous in that window instead of leaving an empty shell.

What you must do: nothing. The marketplace plugin keeps working as before for sessions you
open by hand, and `/bk:kitchen open` still works. To use `bk`, install it with Homebrew and
run `bk open` where you ran `/bk:kitchen open`. For maintainers: the tap is
`mhmzdev/homebrew-brigade`; the release workflow pushes `Formula/bk.rb` there with the
tarball's checksum on each release and needs a `TAP_TOKEN` secret with write access to it.

## [0.18.0] - 2026-10-24

**The kitchen runs in tmux.** `/bk:kitchen open` now starts everything in one tmux session,
`<repo>-brigade`: a `sous` window in the main checkout already running `/bk:sous-chef`, and
one window per station already running `/bk:line-cook`. Nothing opens on your screen. You
attach to the sous to talk to it (`tmux attach -t <repo>-brigade:sous`, the command it
prints), peek at a cook's window when you want to see it work, and detach with `Ctrl-b d`;
the sessions keep running. Opening again joins the session: it adds windows for new or
dead cooks and leaves the running ones alone. The sous's model comes from `sous_model` in
the config (default opus); the cooks' from `-m` as before.

What you must do: nothing on a Mac with Homebrew, where `kitchen open` installs tmux if it is
missing. On Linux it prints the one package line to run. Windows works through WSL. Your
current cooks and sous, if they were opened in Warp, keep working; the next `kitchen open`
starts the new way. Warp and the OS's terminal remain available with `--terminal warp` or
`--terminal native`, in which case you start the sous yourself as before.

For the Window (`/bk:live`): because every session now lives in tmux, its controls (change
model, send a line, handoff, end of shift, answer a question) type straight into the right
pane, and each page shows the `tmux attach` line for that session. The layout is rearranged
the way an IDE is: the line as chips in a top bar, the rail down the left, the room in the
middle with questions as a banner over it, the message log as a full-width console at the
bottom with the prompt at its foot, and an inspector that floats over the room while a
figure is selected. Selecting a figure filters the console instead of replacing it. Bubbles
in the room are cut at three lines; hover the figure for the whole message. The Window
re-checks for tmux every few seconds, so installing it mid-service is noticed.

## [0.17.0] - 2026-10-24

**The Window: watch the kitchen in your browser.** `/bk:live` opens a live view of the
service on localhost: the sous at the pass, each cook at its station with what it is doing
(reading, editing, running the check, waiting on a gate), the commis running to the record
before a question goes up, tickets flying between sessions, plates going out at a `[served]`,
and the head chef at the window. The right-hand panel holds what needs you (open questions,
with their options clickable), the line, the rail, and the message log; click a cook or the
sous for its own page: session, model, ticket, branch, and the controls. The record on the
wall grows a book per page written under the config's `docs` map, so a kitchen that
remembers more looks like it. Run `/bk:live` again to close it; `/bk:live --demo -n 6` shows
a scripted service with six stations.

What you must know: it needs **node 20 or newer** on your PATH, nothing else (its one library
is vendored). It reads what the kitchen already writes and changes nothing by itself. The
controls (change model, send a line, handoff, `/clear`) type into a session's terminal only
when that session runs in tmux (`/bk:kitchen open --terminal tmux`); in Warp or Terminal.app
the panel shows you the command to paste. The sous's "end of shift" button stays dim until
its handoff is written, and a cook's until its ticket is served. The Jira and GitHub rails
show an empty rail card in this version; the markdown rail shows the board.

## [0.16.1] - 2026-10-18

A cook you've just cleared now checks in as fresh. Before, a cleared cook in a station whose
last ticket had shipped read that ticket's journal, took the earlier session's work as its
own, and checked in as spent. The sous then held its brief and asked you to clear a session
that was already clear. Now "fresh or spent" is about the session's own conversation, never
the station's journal, and a served ticket counts whether its PR is open or merged. If a cook
still checks in spent after you clear it, tell the sous: your word wins and it briefs the
cook. Nothing to do but update ([#29](https://github.com/mhmzdev/claude-code-brigade/issues/29)).

## [0.16.0] - 2026-10-15

The kitchen remembers what you decided, and stops asking twice. Four things change for the
head chef:

- **You sign off features, not everything.** A plan for a `kind: bug`, the new `kind: chore`
  (work whose outcome is already fixed: a bump, a rename, a missing checklist item) or a
  `HYG` ticket is signed off by the sous, which tells you in one line. A lane A ticket, an
  item built without a spec, or any plan with a migration, a shared resource, a production
  write or a decision nobody has recorded still comes to you. `gates.plan_approval` in
  `.claude/brigade.md` can now be a map by kind; the one-word form still works, and
  `head-chef` brings every plan back to you.
- **The commis.** A new read-only sub-agent on Opus. Before a cook sends any question, it
  searches the record (the config's `docs:` map, `CLAUDE.md`, the stations' journals) and
  returns `settled` with a source, `fact`, `blocked`, `conflict` or `nothing`. Settled
  questions never leave the station; the rest go up carrying what was searched. The sous
  does the same before asking you, and tells you when it answered from the record. Grillings
  show already-settled questions instead of asking them.
- **The record.** The `docs:` map gains `decisions` (ADRs), `conventions`, `knowledge` and
  `questions`, pointed at the folders your repo already keeps if it has them (`none` if it
  doesn't want one); any other key you add is one more place the commis searches. Every
  answer you give is marked `(head chef)` in a journal; at the sous's handoff
  `kitchen.sh decisions` lists the ones nothing cites and the sous files those that outlive
  their ticket, your words verbatim plus a structured version. A question you haven't
  answered becomes a file in `docs.questions` that blocks its ticket, so it's asked once.
  Things you say in passing go to a local inbox (`kitchen.sh inbox --add`, `.claude/inbox.md`,
  never committed) and are filed at handoff. The board shows both counts.
- **Two hooks.** The plugin now ships `hooks/hooks.json`: in a station, a dialog to the human
  is refused unless a grilling is under way, and a `[gate]` with a numbered question is
  refused when it carries no commis result. A station is what `kitchen.sh` calls one (a
  `station-*` folder in the configured kitchen), so nested repos, submodules and
  `claude --worktree` sessions are left alone, as are the main checkout and other repos.

The commis runs on Opus: it is spawned before every question and every grilling round, and
its one judgement ("a related decision is not this decision") is where a smaller model fails
silently. Large kitchens can set `commis_model: sonnet` in the config to trade that for
cost.

Also: `kitchen.sh doctor` checks ticket files (fields, statuses, blockers, unique ids, a
`kind` on every backlog item) as errors, and the docs map (a mapped folder without an
`INDEX.md`, a folder under `docs/` that no key names) as warnings that don't fail it;
`kitchen.sh questions` lists open question files too, and reads journals at any depth; `/bk:setup` maps
the docs a repo already keeps, respects an existing doc schema, and writes a `docs/SCHEMA.md`
where there is none. Templates for a decision, a question and the schema ship with the plugin.

**What you must do:** restart every session after updating. Existing configs keep working:
with no `plan_approval` map, bugs and hygiene go to the sous and features to you, so if you
want every plan for a while, set `gates.plan_approval: head-chef`. Run `/bk:kitchen doctor`
once: a backlog item with no `kind:` is now reported.

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
