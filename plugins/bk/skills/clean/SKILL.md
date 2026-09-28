---
name: clean
description: Lane C, "clean as you go". `scan` runs the repo's hygiene counters from .claude/brigade.md (unused code, TODOs, whatever the repo declares), posts a snapshot, and drafts PR-sized HYG tickets from the findings; `check` runs the report-only inspector sub-agent on the current branch's diff before review. Use when the user says "clean", "hygiene", "run the hygiene scan", "what's the slop count", "clean check", "/bk:clean".
argument-hint: "scan [--post] | check"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, SendMessage, ListAgents, ToolSearch
disable-model-invocation: true
---

# /bk:clean — clean as you go

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md` (in an installed plugin that's `…/plugins/cache/claude-code-brigade/bk/<version>/skills/README.md`, never a file in this repo). Read `.claude/brigade.md` first.

In a real kitchen you don't wait for closing to clean, or service grinds to a halt. Lane C is that rule: the kitchen measures its own mess **mechanically** and files it as ordinary tickets, worked alongside the other two lanes.

> **User-invoked only.** `scan` fires tickets onto the rail, so Claude never runs it on its own.

## Contents

- [Modes](#modes)
- [scan](#scan)
- [Working a HYG ticket](#working-a-hyg-ticket)
- [The plateau rule](#the-plateau-rule)
- [check](#check)

## Modes

| Mode | Who runs it | Writes |
|---|---|---|
| `scan` | the sous chef, or a solo session | a snapshot (and HYG tickets once the human agrees) |
| `scan --post` | same | also posts the snapshot to `clean.umbrella` |
| `check` | anyone, including a line cook in its station | nothing: a report |

## scan

### 1. Run the counters

Each entry in `clean.counters` is a command that prints **one finding per line**. The count is the line count. Run each from the repo root on an up-to-date trunk:

```bash
git fetch origin && git status --short     # a dirty tree or an old trunk → say so; counts would lie
<command> > /tmp/brigade-clean-<name>.txt 2>/dev/null; wc -l < /tmp/brigade-clean-<name>.txt
```

A non-zero exit usually means "there are findings", not "the tool broke". A command that isn't installed → report that counter as `unavailable` and carry on. No `clean:` block in the config → stop and offer to add one, suggesting counters that fit this stack (a dead-code tool, `git grep` for TODO/FIXME, a lint rule count).

### 2. The snapshot

Print one table, and compare with the previous snapshot if one exists (`docs/backlog/INDEX.md` notes, or the umbrella's last comment):

```
Clean scan — <date> — trunk <sha>
| counter      | now | last | Δ  |
| unused-code  |  26 |   31 | −5 |
| todo-comments|  12 |   12 |  0 |
```

With `--post` and a `clean.umbrella` set, post the same table there: a comment on a github/jira umbrella ticket, or an appended `## Snapshots` row in the umbrella's markdown file.

### 3. Draft the tickets

Cluster the findings into **PR-sized** tickets: one directory, one module, or one kind of finding, small enough that a reviewer reads it in one go (rough guide: ≤ 20 findings, ≤ ~10 files). For each draft:

- id `HYG-NNN` (next free number), `lane: C`, `status: backlog`
- `## Why`: the counter and what cleaning this cluster makes easier
- `## Done when`: the **exact findings list** (file:line per finding), plus "`<counter>` drops by N" and "`<check>` passes"
- `files:` filled from the findings

Show the drafts. **Fire them only on the human's say-so.** Filing goes through `/bk:rail`, which respects the writer rule: the sous or a solo session fires; a line cook never does. Skip any finding already covered by an open HYG ticket.

## Working a HYG ticket

Lane C skips `create-plan` and `review` (Contract 9): the ticket body is already the plan, and "the counter moved" is the proof.

`pick-ticket` → `implement` straight off the ticket body → `clean check` → hand off to the sous → `open-pr`. The PR's Test plan names the counter before and after. Remove only what the finding names. A "cleanup" that changes behaviour is a lane B ticket, not this one.

## The plateau rule

Stop filing new HYG tickets when every counter is **zero, or unchanged for two scans running** while no HYG ticket is open. A flat counter with nothing in flight means what's left is deliberate (a public API, a generated file). Say so, and suggest adding those to the tool's ignore config with a one-line reason each. Don't file tickets to chase them.

## check

A pre-review hygiene pass on the current branch. Report-only: it never edits.

1. Build the inputs. Use the **two-dot** diff: in a station nothing is committed before the sous's `[go]`, so a three-dot diff would read empty and pass by accident.
   ```bash
   git fetch origin --quiet
   DIFF=$(mktemp); FILES=$(mktemp)
   { git diff origin/<trunk> --
     git ls-files --others --exclude-standard | while read -r f; do git diff --no-index /dev/null "$f"; done
   } > "$DIFF"
   { git diff origin/<trunk> --name-only; git ls-files --others --exclude-standard; } > "$FILES"
   ```
2. Find the repo's own "what not to add" list. First match wins: `.claude/rules/*.md`, then conventions docs under `docs/`, then the root `CLAUDE.md`. None → the inspector uses its bundled list.
3. Optionally, run the first `clean.counters` command that is a dead-code tool into a tempfile, so the inspector can keep only findings in changed files.
4. Spawn the inspector by its **namespaced** name, so a repo-local agent with the same name isn't picked by mistake:
   ```
   Agent(subagent_type: "bk:inspector",
         description: "inspect branch vs <trunk>",
         prompt: "Trunk: origin/<trunk>. Diff: <DIFF>. Changed files: <FILES>.
                  Dead-code report: <path, and the command> — or: none.
                  Repo list: <path> — or: none, use your bundled list.")
   ```
5. Print its report verbatim. Findings get fixed before the handoff to the sous; they aren't acceptance criteria.
