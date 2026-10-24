# The Window

A live view of a Brigade kitchen on localhost: the cooks at their stations, the sous at
the pass, the head chef at the window, the commis running to the record, tickets flying
between sessions. The right-hand panel holds what needs you, the line, the rail and the
message log.

![The Window: a six-station demo service](assets/window.png)

From a kitchen, `/bk:live` opens it and `/bk:live` again closes it (`kitchen.sh live` does
the same from a shell). It needs node 20 or newer and nothing else: PixiJS is vendored under
`web/vendor/`, so there is no install step. To run it by hand from this folder:

```bash
node server/index.js --root /path/to/the/repo     # the live kitchen (default: the cwd's repo)
node server/index.js --demo                       # a scripted service, to see the room move
node server/index.js --demo --stations 6          # the same service with a longer line
```

Open http://localhost:4747. Options: `--port N`, `--root <repo>`.

Click a cook, the sous or the head chef and the panel turns into that one's page: session,
model, ticket, branch, what it said, and the controls (change model, send a line, handoff, `/clear`). The
`/clear` button stays dim until the sous's handoff is written, or a cook's ticket is served.
Hover anyone for their role. Click the floor or press Esc to go back.

## How the controls reach a session

Claude Code has no outside switch for a session's model or prompt. The only honest route
is typing into the terminal the session runs in, which tmux allows. Open the kitchen with
`kitchen.sh open --terminal tmux` and the Window types `/model sonnet`, `/clear`, a chat
line, or a question's answer straight into the right pane; you see it land in the
terminal. Without tmux (Warp, Terminal.app) the Window shows you the command to paste.
A question's answer is typed as its option number, then Enter.

## What it reads

- `~/.claude/sessions/*.json` (or `$CLAUDE_CONFIG_DIR`): who is running where, busy or idle.
- each session's transcript under `~/.claude/projects/`, tailed: edits, commands, sub-agent
  spawns, SendMessage calls, AskUserQuestion, your own prompts to the sous.
- each station's git state every five seconds, and the markdown rail's frontmatter.
- the record: one book per markdown page under each folder of the config's `docs` map
  (INDEX files excluded), counted every twenty seconds. The shelf against the left wall
  fills a row per six pages, three rows a cupboard, and opens a second cupboard beneath; hover it for the count by kind.

How it stays cheap: one Node process with no dependencies, watching files Claude Code
already writes; one Server-Sent Events stream; PixiJS draws vector shapes (no assets),
capped at 30 fps, 10 fps when the room is still, paused when the tab is hidden.
