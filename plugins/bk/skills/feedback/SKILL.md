---
name: feedback
description: Send feedback about the Brigade itself to its maintainers as a GitHub issue on mhmzdev/claude-code-brigade. Asks what went wrong or what's wanted, gathers the plugin version and setup, and asks whether to include this session as context (nothing, a scrubbed summary, or a short scrubbed excerpt). Shows the whole issue and files it only on the human's yes, because the issue is public. Also used by the sous's handoff to file a due plugin lesson. Use when the user says "feedback", "report a bug in the brigade", "tell the maintainers", "open an issue on the plugin", "this skill is broken", "/bk:feedback".
argument-hint: "[what went wrong or what you'd like, in a line]"
allowed-tools: Read, Write, Grep, Glob, Bash, AskUserQuestion, ToolSearch
---

# /bk:feedback

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md` (in an installed plugin that's `…/plugins/cache/claude-code-brigade/bk/<version>/skills/README.md`, never a file in this repo). Contract 5 says who answers the filing gate. Read `.claude/brigade.md` if there is one.

**Station check first** (Contract 1): run `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" role`. If it prints `cook …`, you are a line cook even if nobody typed `/bk:line-cook` (e.g. after a `/clear`): read and follow `${CLAUDE_SKILL_DIR}/../line-cook/SKILL.md` for what a cook never does.

The issue goes to the Brigade's own public repo, **mhmzdev/claude-code-brigade**, not to the
repo you're working in. Anyone can read it. So nothing from the user's repo leaves unless the
human saw it in the draft and said yes. End by saying *"Filed: `<issue URL>`."* or
*"Not filed."*

## Contents

- [1. The note](#1-the-note)
- [2. Version and setup](#2-version-and-setup)
- [3. Session context, only with consent](#3-session-context-only-with-consent)
- [4. Scrub](#4-scrub)
- [5. Draft, show, file](#5-draft-show-file)

## 1. The note

Take the note from the arguments. With none, ask one question: *"What went wrong, or what
would you like the Brigade to do?"* Then ask what they expected, only if the note doesn't
already say it. When the sous's handoff runs this for a `DUE` plugin lesson (Contract 11),
the lesson lines are the note: don't ask.

## 2. Version and setup

Gather these without asking:

- plugin version: `version` in `${CLAUDE_SKILL_DIR}/../../.claude-plugin/plugin.json`;
- Claude Code version: `claude --version`;
- OS: `uname -sr`;
- `kitchen_mode` and the rail adapter (`markdown`, `github` or `jira`) from `.claude/brigade.md`, or "no config";
- role: `sous`, `cook`, or `solo`, from the station check and this session;
- the skill the feedback is about, if there is one.

## 3. Session context, only with consent

Ask with `AskUserQuestion` (load it with `ToolSearch` if it's deferred). The default is none:

| Option | What goes in the issue |
|---|---|
| **None (recommended)** | only the note and the setup |
| **A summary** | 3–8 lines you write: what was asked, what the Brigade did, where it went wrong |
| **A short excerpt** | at most 40 lines of the relevant user and assistant turns, quoted. No tool output, no file contents |

Say plainly in the question that the issue is public and that they'll see every word before it
is filed.

**Where the session comes from.** Usually it's this conversation, already in your context.
When the feedback is about an earlier session, or about a cook's session, read its saved
transcript. Claude Code saves each session as a JSONL file (one JSON object per line) under
`$CLAUDE_CONFIG_DIR` (or `~/.claude` when that's unset). List them, newest first:

```bash
"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" sessions                        # this checkout
"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" sessions --dir <station path>   # a cook's
```

This session's file is `${CLAUDE_SESSION_ID}.jsonl`. If that id isn't filled in, this
session is the newest file for this checkout. Transcripts are large: `grep` or `tail` for the
turns you need; never read one whole. **Never attach, upload or paste the transcript file.**
Only the scrubbed summary or excerpt goes out.

## 4. Scrub

Before the human sees the draft, remove from the note, the summary and the excerpt:

- names of the user's repo, product, company, people, and branches → `<repo>`, `<person>`, `<branch>`;
- file paths and directory names from their repo or machine → `<path>` (paths inside the plugin can stay);
- ticket ids and board ids from their rail → `BKLG-xxx`, `<board>`;
- code, diffs, config values, command output from their repo → one line saying what it was;
- anything that looks like a secret: tokens, keys, passwords, `.env` values, private URLs, emails → drop it.

Brigade names (skills, message kinds, contract numbers, `kitchen.sh` commands) stay: they're
what the maintainers need. When unsure whether something is theirs, scrub it.

## 5. Draft, show, file

1. **Draft** the issue with the same headings as the repo's feedback form:

   ```markdown
   Title: <skill or area>: <the problem in a few words>

   ### What happened
   <the note>

   ### What you expected
   <or "Not stated.">

   ### Version and setup
   bk <version> · Claude Code <version> · <OS> · <kitchen_mode> · rail <adapter> · <role>

   ### Session context
   <the summary, the excerpt as a quote block, or "None shared.">

   <sub>Filed with /bk:feedback.</sub>
   ```

2. **Show the whole draft** in chat, exactly as it will be filed. Then ask with
   `AskUserQuestion`: *File it*, *Change something*, or *Don't file*. On a change, redraft
   and show it again.
3. **Filing is the human's alone** (Contract 5): only their yes, typed in this session's
   terminal, files it. A cook never files on the sous's word, and never files unasked.
4. **File** with `gh` from a temporary body file, so quoting can't break it:

   ```bash
   body="$(mktemp)"   # write the draft body into it, then:
   gh issue create --repo mhmzdev/claude-code-brigade --title "<title>" --body-file "$body"
   rm -f "$body"
   ```

   No `gh`, or not logged in (`gh auth status` fails)? Don't install anything. Give the human
   the draft to paste and the link
   `https://github.com/mhmzdev/claude-code-brigade/issues/new?template=feedback.yml`.
5. **Report** the issue URL. When the sous's handoff called this for a lesson, it records
   `filed #<n>` or `declined` in `docs/lessons.md` (Contract 11).
