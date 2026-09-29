---
name: handoff
description: Write this session's handoff so it can be cleared and a fresh session carries on — the role comes from where it runs. In a station (a line cook) it appends a Handoff section to the ticket's journal (stage, what's uncommitted, next step, pending questions, follow-ups, lessons). In the main checkout (the sous chef) it overwrites the gitignored .claude/sous-handoff.md with what lives nowhere else, and runs the lesson count. Cooks run it on [go] before open-pr; anyone can run it before a /clear. Use when the user says "handoff", "hand over", "write a handoff", "I'm going to clear you", "/bk:handoff".
argument-hint: "(none: the role comes from the station check)"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, SendMessage, ListAgents, ToolSearch
---

# /bk:handoff

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md` (in an installed plugin that's `…/plugins/cache/claude-code-brigade/bk/<version>/skills/README.md`, never a file in this repo). Contract 11 is the one this skill implements. Read `.claude/brigade.md` first.

A context window is a cache, not the record. A handoff writes down the few things a fresh
session couldn't rebuild from the rail, the stations, the journals and the PRs, so that the
human can `/clear` this session and nothing is lost. **This skill never clears the session
itself**: `/clear` is the human's. End by saying *"Handoff written: `<path>`. Ready to clear."*

## Contents

- [Which handoff](#which-handoff)
- [Cook handoff](#cook-handoff)
- [Sous handoff](#sous-handoff)
- [Reading a handoff on start](#reading-a-handoff-on-start)

## Which handoff

Run `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" role`.

- `cook <station> <main>` → [Cook handoff](#cook-handoff).
- `main <main>` and this session is running `/bk:sous-chef` → [Sous handoff](#sous-handoff).
- `main` in a solo session → a cook-style handoff into the current ticket's journal if there
  is one; otherwise say there's nothing to hand off (the rail and git already hold it).

## Cook handoff

1. **Find the ticket**: the id in the branch name (`bklg-004-…` → `BKLG-004`). No ticket →
   say so and stop.
2. **Find or create the journal** at `<docs.journal>/<ID>-<slug>.md` in this station, from
   `${CLAUDE_SKILL_DIR}/../../templates/journal.md`. Add its row to `<docs.journal>/INDEX.md`.
3. **Work out the stage from the files, not memory**: plan `status:` and phases marked Done,
   whether a checklist exists, whether a PR exists (`gh pr list --head <branch>`), whether the
   sous has sent `[go]` (the journal says).
4. **Append** a `## Handoff — <YYYY-MM-DD HH:MM> · <session name>` section with the fields in
   the template: stage, uncommitted files (`git status --short`), the next step, pending items
   (unanswered `Qn`, unfixed findings), follow-ups, and lessons.
   - **Follow-ups** are drafted as tickets: write them under the handoff and send the sous one
     `[rail] fire ×N, see journal`. Never create ticket files yourself.
   - **Lessons**: only things a future session would get wrong again. One line each, tagged
     `lesson(repo)` (this codebase, its tools, its tests) or `lesson(plugin)` (the Brigade
     itself: a gate asked the wrong person, a skill stopped for nothing, a rule that didn't
     fit). Reuse an existing key when it's the same lesson (`grep -h 'lesson(' <docs.journal>/*.md docs/lessons.md`
     shows the keys in use) so the count works. Reading keys isn't counting: only the sous's handoff counts. No lesson is fine; don't invent one.
5. **Tell the sous** in one line: `[status] <ID> handoff written, see journal`.
6. **On `[go]`** (the automatic case), this runs after `/bk:clean around` and before
   `/bk:open-pr`, so the closing handoff is inside the reviewed PR. The journal is the only
   file allowed to change after the pass.

## Sous handoff

1. **The lesson count** (Contract 11, the only time it runs):
   ```bash
   "${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" lessons
   ```
   For each `DUE` row: a `repo` lesson → fire a `BKLG` ticket "promote lesson `<key>` into
   CLAUDE.md (or the config notes)" with the lesson lines as evidence, and add
   `` | `<key>` | repo | <ticket> | `` to `docs/lessons.md` (create it with a header row if
   missing; commit per `rail.commit`). A `plugin` lesson → draft an issue for
   `mhmzdev/claude-code-brigade` with every repo-specific name, path and snippet removed,
   show it to the head chef, and **file it only on their yes** (`gh issue create --repo
   mhmzdev/claude-code-brigade`); then add the key to `docs/lessons.md` either way
   (`filed #n` or `declined`).
2. **Overwrite** `.claude/sous-handoff.md` (make sure `.gitignore` lists it) with only what
   lives nowhere else:
   ```markdown
   # Sous handoff — <YYYY-MM-DD HH:MM> · <session name>

   ## Standing instructions from the head chef
   - <e.g. "don't touch lib/auth today", "lane C paused this week">

   ## Next up
   - <what I meant to fire next, and why>

   ## Walk-in holds I granted
   - <station, resource, until when — or "none">

   ## Cooks
   | session | station | model | ticket |

   ## Notes
   - <anything a fresh sous would otherwise get wrong, at most five lines>
   ```
   Don't copy the rail, the station status or the PR list into it: a fresh sous reads those
   live, and a copy would only drift.
3. **Tell the cooks** in one line each: `[status] sous restarting; re-send anything pending
   after my [hello]`.

## Reading a handoff on start

- **A fresh cook** (station check says `cook`, a ticket branch exists): read the ticket's
  journal, take the **last** handoff section as the starting point, and verify it against
  `git status` and the plan. The station wins where they disagree. Then carry on from
  "Next step".
- **A fresh sous**: `/bk:sous-chef` reads `.claude/sous-handoff.md` first (Step 0), checks it
  against the rail, stations and journals, and treats it as history once read: **reality
  wins over the note**.
