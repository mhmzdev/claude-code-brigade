---
name: handoff
description: Write this session's handoff so it can be cleared and a fresh session carries on — the role comes from where it runs. In a station (a line cook) it appends a Handoff section to the ticket's journal (stage, what's uncommitted, next step, pending questions, follow-ups, lessons). In the main checkout (the sous chef) it runs the lesson count, files the record (head-chef decisions into ADRs, unanswered questions into question files, the inbox into the docs), and overwrites the gitignored .claude/sous-handoff.md with what lives nowhere else. Cooks run it on [go] before open-pr; anyone can run it before a /clear. Use when the user says "handoff", "hand over", "write a handoff", "I'm going to clear you", "/bk:handoff".
argument-hint: "(none: the role comes from the station check)"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, SendMessage, ListAgents, ToolSearch
---

# /bk:handoff

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md` (in an installed plugin that's `…/plugins/cache/claude-code-brigade/bk/<version>/skills/README.md`, never a file in this repo). Contracts 11 and 12 are the ones this skill implements. Read `.claude/brigade.md` first.

A context window is a cache, not the record. A handoff writes down the few things a fresh
session couldn't rebuild from the rail, the stations, the journals and the PRs, so that the
human can `/clear` this session and nothing is lost. **This skill never clears the session
itself**: `/clear` is the human's. End by saying *"Handoff written: `<path>`. Ready to clear, then `/bk:sous-chef`"* (in a station: *"then `/bk:line-cook`"*), so the human knows the one command that picks the work back up.

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
     `[rail] fire <n> ticket(s), see journal`. Never create ticket files yourself.
   - **Lessons**: only things a future session would get wrong again. One line each, tagged
     `lesson(repo)` (this codebase, its tools, its tests) or `lesson(plugin)` (the Brigade
     itself: a gate asked the wrong person, a skill stopped for nothing, a rule that didn't
     fit). Reuse an existing key when it's the same lesson (`grep -rh 'lesson(' <docs.journal> <docs.lessons>`
     shows the keys in use) so the count works. Reading keys isn't counting: only the sous's handoff counts. No lesson is fine; don't invent one.
5. **Tell the sous** in one line: `[status] <ID> handoff written, see journal`.
6. **On `[go]`** (the automatic case), this runs after `/bk:clean around` and before
   `/bk:open-pr`, so the closing handoff is inside the reviewed PR. The journal is the only
   file allowed to change after the pass.

## Sous handoff

This is the one checkpoint that files the record (Contract 12), so steps 1 to 4 come before
the note. They're mechanical lists; the judgement is only *where* each item goes.

1. **The lesson count** (Contract 11, the only time it runs):
   ```bash
   "${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" lessons
   ```
   For each `DUE` row: a `repo` lesson → fire a `BKLG` ticket "promote lesson `<key>` into
   CLAUDE.md (or the config notes)" with the lesson lines as evidence, and add
   `` | `<key>` | repo | <ticket> | `` to the register, `docs.lessons` (default `docs/lessons.md`; create it with a header row if
   missing; commit per `rail.commit`). A `plugin` lesson → run `/bk:feedback` with the
   lesson lines as the note: it removes every repo-specific name, path and snippet, shows the
   head chef the draft, and **files it only on their yes**. Then add the key to
   the register either way (`filed #n` or `declined`).
2. **Decisions to file**:
   ```bash
   "${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" decisions
   ```
   Every `DUE` row is a `(head chef)` answer in some journal that nothing cites yet. Read
   the question and answer in that journal. **It generalises** (another ticket could hit
   it: a rule, a product behaviour, a reason that outlives this fix) → write it as a
   decision in `docs.decisions` from `${CLAUDE_SKILL_DIR}/../../templates/decision.md`
   (next free number; the repo's own ADR format and frontmatter if it has one), with
   `source: <ID> An`, the head chef's words verbatim under *Head chef said*, your structured
   version under *Decision*, and its INDEX row. If it belongs in an existing convention or
   knowledge doc instead, add it there, citing `<ID> An` in the text. **It doesn't** (it
   only settled this ticket's own detail) → add `` | `<ID> An` | kept | — | `` to the
   register, `docs.lessons`, so it isn't listed again. Several answers that together make
   one decision → one file, several sources. Commit per `rail.commit`.
3. **Open questions**:
   ```bash
   "${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" questions
   ```
   A journal `Qn` that is the head chef's to answer and still open, or whose ticket you've
   had to mark `blocked` → write it as a file in `docs.questions` from
   `${CLAUDE_SKILL_DIR}/../../templates/question.md`: `status: open`, the date, `blocks:
   [<ID>]`, `source: <ID> Qn`, the options, your recommendation, and what the commis
   searched (from the journal's `commis:` line). Add its INDEX row; set the ticket
   `blocked` through `/bk:rail` if it isn't. Tell the head chef in one line what's waiting on
   them. A question the head chef **has** answered since the file was written → `status:
   answered`, their words under *Head chef said*, the structured answer under *Answer*,
   `answered: <date>`; it now counts as a decision (promote it as in step 2 if it
   generalises), and the ticket it blocked goes back to `backlog`. Routine questions that
   are yours stay in the journal: answer them.
4. **The inbox**:
   ```bash
   "${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" inbox
   ```
   Each line is something the head chef said that the record didn't hold. File it where it
   belongs: how the product works → `docs.knowledge` (the area's doc, or a new one with its
   INDEX row); how code is written here → `docs.conventions`; a decision with a reason →
   `docs.decisions`; already in the record after all → nowhere. No type fits → add one
   (Contract 12, rule 4) and say so. Then delete the line from `.claude/inbox.md`. The
   inbox should be empty when you finish.
5. **Overwrite** `.claude/sous-handoff.md` (make sure `.gitignore` lists it) with only what
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
6. **Tell the cooks** in one line each: `[status] sous restarting; re-send anything pending
   after my [hello]`.

## Reading a handoff on start

- **A fresh cook** (station check says `cook`, a ticket branch exists): read the ticket's
  journal, take the **last** handoff section as the starting point, and verify it against
  `git status` and the plan. The station wins where they disagree. Then carry on from
  "Next step".
- **A fresh sous**: `/bk:sous-chef` reads `.claude/sous-handoff.md` first (Step 0), checks it
  against the rail, stations and journals, and treats it as history once read: **reality
  wins over the note**. What the last sous filed into the record needs no note: the commis
  finds it.
