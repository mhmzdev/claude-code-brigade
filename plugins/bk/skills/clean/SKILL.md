---
name: clean
description: Lane C, "clean as you go", in three scopes. `check` runs the report-only inspector on your own branch's diff before every handoff (findings fixed in the same PR); `around` finds old mess in the files your branch touched, at the end of a cook's shift; `scan` counts the whole kitchen's mess with the repo's counters. `around` and `scan` draft PR-sized HYG tickets and hand them to the sous, who numbers and fires them. Run by cooks as part of their loop, or by anyone. Use when the user says "clean", "hygiene", "run the hygiene scan", "what's the slop count", "clean check", "clean around", "/bk:clean".
argument-hint: "check | around | scan [--post]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, SendMessage, ListAgents, ToolSearch
---

# /bk:clean — clean as you go

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md` (in an installed plugin that's `…/plugins/cache/claude-code-brigade/bk/<version>/skills/README.md`, never a file in this repo). Read `.claude/brigade.md` first.

**Station check first** (Contract 1): run `"${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" role`. If it prints `cook …`, you are a line cook even if nobody typed `/bk:line-cook` (e.g. after a `/clear`): read and follow `${CLAUDE_SKILL_DIR}/../line-cook/SKILL.md` for where questions go, the journal, and what a cook never does.

In a real kitchen you don't wait for closing to clean, or service grinds to a halt. Lane C is that rule: the kitchen measures its own mess **mechanically** and files it as ordinary tickets, worked alongside the other two lanes.

Cooks run this skill themselves as part of their loop (Contract 9), so it is **not**
human-only. It never writes the rail: `around` and `scan` only **draft** tickets, and the sous
(or a solo session) fires them.

## Contents

- [Modes](#modes)
- [around](#around)
- [scan](#scan)
- [Working a HYG ticket](#working-a-hyg-ticket)
- [The plateau rule](#the-plateau-rule)
- [check](#check)

## Modes

| Mode | Scope | Who runs it, when | Outcome |
|---|---|---|---|
| `check` | your own new code (the branch's diff) | a cook before every handoff; anyone | a report; findings **fixed** in the same PR |
| `around` | old mess in the files your branch touched | a cook at the end of its shift, on `[go]`, before `open-pr` | `HYG` drafts → the sous |
| `scan` | the whole kitchen | a cook when the sous asks (lane C empty); a solo session | a snapshot + `HYG` drafts → the sous |
| `scan --post` | same | same | also posts the snapshot to `clean.umbrella` |

**Where drafts go.** A cook sends all its drafts in **one** `[rail] fire` message to the sous,
with the draft bodies written into its journal (the message is the doorbell). The sous drops
any draft that duplicates an open `HYG` ticket, numbers the rest and fires them. In a solo
session, running the mode is the go: fire the drafts through `/bk:rail`. **One `scan` at a
time** across the kitchen; the sous schedules it.

**The one rule that keeps scopes honest:** a finding in a line **your branch added** is
fixed now, never filed. Only pre-existing mess becomes a ticket.

## around

End of shift, after the sous's `[go]` and before `open-pr`. Your station is where you
cooked; this reports the mess you worked next to, without widening your PR.

1. The files your branch touched: `git diff --name-only origin/<trunk>` plus untracked files.
2. Run each `clean.counters` command and keep only findings in those files.
3. Drop findings in lines your branch added (`git diff -U0 origin/<trunk> -- <file>` gives
   the added ranges). Those should already be fixed by `check`; if one isn't, fix it now and
   tell the sous, since it changes what the pass approved.
4. What's left is pre-existing. Cluster it into PR-sized drafts exactly as in `scan` step 3,
   write them into your journal under `## Clean around`, and send the sous one
   `[rail] fire HYG ×N, see journal`. Nothing found → one line in the journal, no message.

Run it through the `runner` sub-agent when the counters are noisy, so the raw output stays out
of your context.

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

Skip any finding already covered by an open HYG ticket. Then hand them over as in [Modes](#modes): a cook writes the drafts into its journal and sends the sous one `[rail] fire` batch; a solo session fires them through `/bk:rail` (running `scan` was the go). A cook never fires them itself.

A cook running `scan` does it on a clean, detached copy of trunk, not its ticket branch, so
the counts describe trunk: `git stash push -m "<station>: before scan"` if needed, `git switch --detach origin/<trunk>`, scan, then switch back.

## Working a HYG ticket

Lane C skips `create-plan` and `review-task` (Contract 9): the ticket body is already the plan, and "the counter moved" is the proof.

`pick-ticket` → `implement` straight off the ticket body → `clean check` → hand off to the sous → on `[go]`: `clean around` → `handoff` → `open-pr`. The PR's Test plan names the counter before and after. Remove only what the finding names. A "cleanup" that changes behaviour is a lane B ticket, not this one.

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
