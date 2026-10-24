---
name: live
description: Open or close the Window, a live view of this kitchen in your browser on localhost — the cooks at their stations, the sous at the pass, the commis running to the record, tickets flying between sessions, and a panel with what needs you, the line, the rail and the message log. Click a cook or the sous for its page and controls (model, a line to send, handoff, end of shift). Running it again closes it. Use when the user says "live", "open the window", "show me the kitchen", "watch the kitchen", "close the window", "/bk:live".
argument-hint: "[stop|status] [--port P] [--demo [-n N]]"
allowed-tools: Bash, Read
---

# /bk:live

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md`. Invoking this skill is its approval (Contract 5): open or close the Window and report, ask nothing.

The Window reads what the kitchen already writes (the session registry, each session's transcript, the stations' git state, the rail, the record, the budget) and draws it as a room; it changes nothing by itself beyond the budget's local ledger (`.claude/budget.jsonl`, where it keeps served tickets and the CI minutes it fetches every ten minutes). The chip at the foot is the shift's spend (money, tokens, working time, CI minutes); it opens the Ledger (`$`, `Esc` back), a page of dishes and sessions over the shift, today or the week, each dish split into prep, cook, check and serve with every step and what a red check cost in rework. The line shows what each session has spent today, and a figure's page has its spend rows. Its controls type into a session's terminal when that session runs inside tmux, which is how `/bk:kitchen open` starts the kitchen; a session opened in Warp or the OS's terminal gets the command to paste instead.

## Contents

- [Run it](#run-it)
- [Report](#report)
- [When it won't open](#when-it-wont-open)

## Run it

One command, with whatever the user passed after `/bk:live`:

```bash
"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" live $ARGUMENTS
```

- No word: **toggle**. Opens the Window (and the browser) when it is closed, closes it when it is open.
- `stop`: close it. `status`: say whether it is open, and where.
- `--port P`: serve on another port (default 4747). `--demo [-n N]`: a scripted service with N stations instead of the live kitchen, for a look at the room without cooks running.

It works from the main checkout or a station: either way it shows the whole kitchen. Its pid and log live in `.claude/window.pid` and `.claude/window.log`, kept out of git.

## Report

Repeat the script's line as it printed it, for example *"The Window is open: http://localhost:4747"* or *"The Window is closed."* Add nothing else, unless the user asked something.

## When it won't open

- **"needs node 20 or newer"**: the Window is one Node process with no dependencies. Say what the script said; on a Mac `brew install node` is the usual route.
- **"didn't start"**: the script printed the tail of `.claude/window.log`. Pass it on. The common cause is the port already in use: try `/bk:live --port 4748`.
- **The controls say the session runs outside tmux**: that session was opened in Warp or the OS's terminal. Close it and run `/bk:kitchen open`, which starts the kitchen in tmux; the panel's `peek`/`attach` line on each page shows where each one lives.
- **A stale pid**: a Window killed from outside leaves `.claude/window.pid` behind; the script notices and treats it as closed, so just run `/bk:live` again.
