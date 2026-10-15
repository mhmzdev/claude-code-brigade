# Open question: what should be mechanical instead of judgement?

**Status:** partly built; see [Taken on](#taken-on). The rest still waits on a choice.
**Asked:** 2026-10-11. **Updated:** 2026-10-15.
**Scope read:** all 17 skills, the sub-agents (three then, four now), the contract,
`kitchen.sh`, and the current Claude Code docs on hooks (re-verified 2026-10-15).

## Taken on

Built on `feat/knowledge-chain` (v0.16.0), the "knowledge chain" change: the kitchen
remembers what the head chef decided and stops asking twice.

| Row | What was built | Where |
|---|---|---|
| 2 | `AskUserQuestion` is refused in a station unless `<station>/.claude/grilling` exists; `grill-me` and `brainstorm` write it when they start in a station and remove it after | `plugins/bk/hooks/hooks.json`, `hooks/guard.sh`, `tests/guard.test.sh` |
| new 13 | A `[gate]` carrying a numbered question is refused when it has no `commis:` line, so "look it up before you ask" is enforced, not hoped for. This also corrects the limit below: `SendMessage` is a tool call, so `PreToolUse` does fire on it | `hooks/guard.sh` |
| 11 | `kitchen.sh doctor`: required fields, known statuses, blockers that exist, unique ids, a `kind` on every backlog item; plus the docs map (every mapped folder indexed, nothing under `docs/` unmapped) | `kitchen.sh` |
| 6 (part) | The record's writes are counted and listed by script: `kitchen.sh decisions` (head-chef answers nothing cites), `questions` (journals and open question files), `inbox --add` / `inbox`. The sous still files by hand; the lists are what make the handoff mechanical. Rail writes (`claim`, `fire`, `close`, `link`) are still hand edits | `kitchen.sh` |
| new 14 | Who signs off a plan is read from the ticket's kind (`gates.plan_approval`), not judged: features to the head chef, bug / chore / hygiene to the sous, with hard overrides (migration, walk-in, production write, unrecorded decision) | contract, Contract 5 |

Still open from the table below: rows 1, 3, 4, 5 (now narrower: a human-only approve
record for **feature** plans only), 6 (rail writes), 7, 8, 9, 10, 12.

Next up, as its own PR: the idle prep pass (no ready ticket → the sous drafts tickets from
the counters, `[?]` checklist items, due lessons, open questions and stale docs, under a
per-shift budget, each marked with its source). It feeds on the lists built here.

## The question

Which rules of the Brigade should be enforced by a hook, a script, a permission rule or
CI, so they no longer depend on an agent choosing to obey them? And which to build first?

## Already mechanical

- **Role:** `kitchen.sh role` decides cook or main checkout from the directory.
- **Ready tickets:** the rail board's `RDY` column and blocker resolution.
- **Secrets:** `kitchen.sh leaks`.
- **Lessons and open questions:** counted by script.
- **Open questions in a plan:** `implement` greps for them and refuses.
- **The inspector can't write:** it holds no tool that can.

## Rests on judgement today

Most replacements need a hook that runs before a tool call and can block it.

| # | Rule today | Mechanical replacement | Docs confirmed? |
|---|---|---|---|
| 1 | A cleared cook remembers it is a cook | A session-start hook runs `kitchen.sh role` and injects "you are the cook in station-N, run `/bk:line-cook`" | Yes; fires after `/clear`, but can only add context, not run a skill |
| 2 | A cook never opens a dialog to ask the human | Block `AskUserQuestion` inside a station, unless a grilling is under way | Yes |
| 3 | A cook never edits ticket files, the main checkout or another station; the sous never edits inside a station | Block `Edit`/`Write` when the path is outside what that role may touch | Yes for those tools; shell commands can still write anywhere |
| 4 | No session merges; no force-push; no push to trunk from a station; no `git clean -fdx`; no commit before `[go]` | Block shell commands matching those patterns | Yes, as a guard against mistakes, not a security boundary |
| 5 | The sous relays the plan approval and never invents one | A human-only `/bk:approve <ID>` typed in the sous's terminal writes the approval where cooks can't write; `implement` checks that record | Yes: a typed command with model invocation disabled |
| 6 | The sous edits ticket frontmatter by hand: status, cook, numbers, INDEX rows | `kitchen.sh` does the rail writes (`claim`, `fire`, `close`, `link`) and refuses an illegal move or a reused number | No hook needed |
| 7 | The sous applies the ordering rules by reading the board | `kitchen.sh next` prints the ready tickets already in order | No hook needed |
| 8 | Sessions remember to run the leak check | Run it automatically on every commit, push and PR creation | Yes |
| 9 | A cook asks before a destructive command on a shared resource | A lock file the sous sets; a hook blocks the listed commands without it | Yes; needs the config's command list parsed |
| 10 | The sous refreshes `.claude/board.md` when state changes | A hook at the end of every sous turn runs `kitchen.sh board` | Yes |
| 11 | Ticket files are well-formed | `kitchen.sh doctor`: required fields, valid status, blockers that exist, unique ids, a `kind` on every backlog item | No hook needed |
| 12 | Project hooks that write into stations | `/bk:setup` lists the repo's session-end hooks and flags them; it can also add deny rules to the project's settings | Yes; a plugin can't ship permission rules, so setup must write them |

## Suggested first build

1. **Row 5, the approval.** Restores the technical guarantee given up in v0.10, and the
   head chef still only uses the sous's terminal.
2. **Row 6, rail writes by script.** Hand-edited frontmatter caused a stale blocker, a
   status nobody moved, and two sessions colliding on a commit.
3. **Rows 2 to 4, the "never" list.** One small hook script covers them all.
4. **Row 1, the role hook.** Removes the last thing typed after a `/clear`.
5. **Row 7, `kitchen.sh next`.** Closes the ordering gap from v0.12.

## Should stay judgement

- Whether something is a bug or an item (the answer is recorded in `kind:`).
- Whether a plan is good, and whether a question is a real design fork.
- The review verdict before commit.
- How to slice a spec into tickets.
- Whether an action writes on production: no reliable mechanical test.

## Limits

- **Messages between sessions can be hooked after all**, because `SendMessage` is a tool
  call and `PreToolUse` fires on it (confirmed 2026-10-15 against the hooks reference, and
  tested in `tests/guard.test.sh`). The guard uses it for the commis rule. What a hook can
  check is the message's text, so message kinds and "no secret in a message" could follow;
  "the sous quotes the head chef's words" can't be checked mechanically.
- **Shell pattern-matching is a guardrail.** It stops mistakes, not a determined
  workaround.
- **Plugin hooks run in every project where the plugin is enabled.** Each must exit at
  once when there is no `.claude/brigade.md`, and leave solo sessions alone.
- **Confirmed 2026-10-15:** hooks fire for sub-agents' tool calls too (the stdin JSON then
  carries `agent_id` and `agent_type`); a plugin ships hooks in `hooks/hooks.json` under a
  top-level `hooks` key; blocking is exit 2 with the reason on stderr, or a JSON
  `permissionDecision: deny`. **Still unconfirmed:** whether a hook can tell which skill is
  being invoked. Row 5 avoids that by using a typed command.
- **Hooks add a little time to every tool call.**

## To decide

- Which rows to build, and whether the five above go in one release.
- Whether the "never" hooks should block, or only warn, in a solo session.
