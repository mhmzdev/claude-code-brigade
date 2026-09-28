---
name: rail
description: The Brigade's ticket store, behind one interface — list, read, claim, fire, link and close tickets on a markdown rail in docs/, GitHub Projects, or Jira, as .claude/brigade.md's rail.adapter says. Other brigade skills call this instead of talking to a tracker directly. Enforces the rail's two rules — only the sous chef (or a solo session) writes, and a claim is never overwritten. Use when the user says "show the rail", "claim BKLG-4", "move S001-02 to rfr", "fire a ticket", "close HYG-3", "/brigade:rail".
argument-hint: "list | read <id> | claim <id> <status> [cook] | fire <lane> <title> | link <id> blocked-by <id> | close <id>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# /brigade:rail

Honour `${CLAUDE_SKILL_DIR}/../README.md` (the plugin contract): Contract 3 (the rail) and
Contract 4 (names and ids).

The rail is wherever tickets live. This skill is the only place that knows *how* each
backend does each operation. Everything else asks for the operation.

## Contents

- [Who may write](#who-may-write)
- [The operations](#the-operations)
- [markdown adapter](#markdown-adapter)
- [github adapter](#github-adapter)
- [jira adapter](#jira-adapter)
- [mixed](#mixed)

## Who may write

`list` and `read` are open to everyone. `claim`, `fire`, `link` and `close` are **writes**:

- **Sous chef or solo session**: do it.
- **Line cook**: don't. Draft the change and send it to the sous as `[rail] …`, then stop.

Before any `claim`, check the current status. `backlog` and `blocked` are free. `todo`,
`in-progress` and `rfr` belong to the ticket's `cook`, and only a request from that cook
may move them. Refuse anything else and say whose claim it is.

## The operations

| Operation | Input | Output |
|---|---|---|
| `list` | optional lane / status filter | table: id · lane · status · cook · title (done hidden unless asked) |
| `read` | id | the ticket's full body plus status fields |
| `claim` | id, new status, cook | status and cook updated |
| `fire` | lane, title, body, optional spec, `blocked_by`, `files` | the new id and where it lives |
| `link` | id, blocked-by id | the edge recorded |
| `close` | id | status `done` |

## markdown adapter

Tickets are files (Contract 4). **The frontmatter is the rail.**

- **list**: `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" rail`, then filter.
- **read**: find the file by id: `docs/backlog/<ID>-*.md`, or for `SNNN-NN` the
  `NN-*.md` inside `docs/specs/NNN-*/`.
- **claim / link / close**: edit only the frontmatter fields (`status`, `cook`,
  `blocked_by`). Never rewrite the body in a status change.
- **fire**: next number = highest existing number in that family + 1, zero-padded
  (`BKLG-007`, `HYG-003`, `S002-04`). Write from `${CLAUDE_SKILL_DIR}/../../templates/ticket.md`
  with `status: backlog` and `created:` today. Add the row to the folder's `INDEX.md`.
  Lane-A tickets go in their spec's folder; create it if it's the spec's first ticket.
- **commit**: per `rail.commit`. `direct` means `git commit -m "rail: <ID> → <status>"`
  (or `rail: fire <ID>`) on trunk, then push. `daily-pr` means the same on `rail/YYYY-MM-DD`,
  with one PR opened or updated. If the push is rejected because trunk moved, pull
  (rebase) and push again; never force.

## github adapter

Config: `rail.github.owner`, `rail.github.project`, `rail.github.status_field`. Needs
`gh` with the `project` scope (`gh auth refresh -s project` if a call says so).

- **list**: `gh project item-list <project> --owner <owner> --format json --limit 500`.
  Fail loudly if you hit the limit, rather than pretend the list is complete.
- **read**: `gh issue view <n> --json title,body,state,labels,assignees,comments`.
- **claim**: set the Status field to the mapped column (`gh project item-edit`), and
  assign the head chef's login (a cook has no GitHub identity). Put the station name in a
  short issue comment.
- **fire**: `gh issue create`, then `gh project item-add`. Lane goes in a label
  (`lane:A`/`lane:B`/`lane:C`), and lane A adds the spec id to the body.
- **link**: native sub-issue or blocked-by where the repo supports it; otherwise a
  `Blocked by #n` line in the body.
- **close**: `gh issue close <n>` (the board's own workflow usually moves it to Done).

Map the six statuses onto the board's real column names once, and record the mapping in
the config's free-text section so every session uses the same one.

## jira adapter

Config: `rail.jira.site`, `rail.jira.project`. Use a Jira MCP server if the session has
one, else the `jira` CLI. If neither is available, say so and stop.

- **list**: JQL `project = <KEY> AND statusCategory != Done ORDER BY rank`.
- **claim**: a transition to the mapped status, plus the assignee.
- **fire**: create the issue in `<KEY>`, with the lane as a label.
- **link**: an "is blocked by" issue link.
- **close**: transition to the done status.

As with GitHub, record the status → transition mapping in the config once.

## mixed

Specs, plans, checklists, research and brainstorms stay in `docs/` on every rail. `mixed`
means tickets live in a tracker (github or jira block present) while everything else is
markdown. Use the tracker adapter for the six operations, and put the tracker id in each
plan's and checklist's filename.
