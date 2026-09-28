---
name: review-task
description: Close a ticket's inner loop before anything is committed. Runs the inspector on the branch diff, derives the acceptance checklist from intent (ticket + plan) plus the diff, proves each criterion at the cheapest honest layer ([x] passing test or file:line read, [?] runtime proof still owed, [!] fails or missing), writes docs/checklists/<id>-<slug>.md with its INDEX row, and moves the ticket to rfr. In a line-cook session it ends with a [handoff] to the sous chef and waits for [go]. Use when the user says "review this", "is this done", "acceptance checklist", "verify the ticket", "check what we built", "/bk:review-task".
argument-hint: "[<ticket id> | <plan path> | free-text intent] [--no-inspector]"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, Agent, SendMessage, ListAgents, ToolSearch
---

# /bk:review-task — the checklist, then the pass

Honour the plugin contract: the `README.md` in this skill's parent folder, `${CLAUDE_SKILL_DIR}/../README.md` (in an installed plugin that's `…/plugins/cache/claude-code-brigade/bk/<version>/skills/README.md`, never a file in this repo). Read `.claude/brigade.md` first.

Position: `… → implement → **review** → open-pr`. Lane C skips this skill (Contract 9); its proof is the counter moving.

The checklist's real job is an **omission check**: after the work exists, say what must now be true, and find what is missing. Reading code proves absence well ("no guard exists on this route" is a fact). It proves presence badly: an `[x]` that cites a line is the author's hypothesis. So a passing test outranks a static read.

**Invoking this skill is the go** (Contract 5). Derive, verify and write the checklist in
one pass; don't ask whether to write it, or which criteria to include. Stop only when a
criterion can't be verified from here and genuinely needs a human's eyes, and then say
exactly what to look at.

## Contents

- [Inputs](#inputs)
- [Flow](#flow)
- [The evidence ladder](#the-evidence-ladder)
- [The checklist file](#the-checklist-file)
- [Moving the ticket and the handoff](#moving-the-ticket-and-the-handoff)
- [Hard rules](#hard-rules)

## Inputs

| Fact | From | Fallback |
|---|---|---|
| Ticket | the argument, else the branch name's id (`bklg-004-…` → `BKLG-004`), else the plan's frontmatter | ask |
| Plan | `docs.plans/<id>-*.md` | none: criteria come from the ticket alone |
| Checklist dir | `docs.checklists` | `docs/checklists` |
| Check command | `check` | stop and ask; never guess |
| Trunk | `trunk` | stop and ask |

## Flow

1. **Read the whole diff.** Committed, staged, unstaged and untracked work together. In a station nothing is committed until the sous says go, so the three-dot form (`origin/<trunk>...HEAD`) would read empty and look like a clean pass.
   ```bash
   git fetch origin --quiet
   git diff origin/<trunk> --stat
   git diff origin/<trunk>
   git ls-files --others --exclude-standard
   ```
2. **Run the inspector** (skip with `--no-inspector`). Do exactly what `/bk:clean check` does: write the diff and file list to tempfiles, find the repo's own "what not to add" list, spawn `bk:inspector` by its namespaced name, print its report verbatim. Findings are hygiene, not acceptance. They never become `[!]` items. Carry them into the report as work to fix before the handoff.
3. **Seed criteria from the source of truth**: the ticket's `## Done when` boxes, the plan's success criteria, the spec's decisions for lane A. Then add what the diff implies, including anything the intent asked for that the diff **doesn't** contain.
4. **Run the check command** once. A red check is an `[!]` on its own line.
5. **Route every criterion** on the ladder below. Write a test when one is cheap. That is the best `[x]` you can get.
6. **Write or update** `<checklists>/<id>-<slug>.md` (same slug as the plan) and its row in `<checklists>/INDEX.md`. If the file exists, **append and re-verify**: flip every item the diff touches back to `[ ]` and prove it again. Never regenerate it.
7. **Move the ticket and hand off** (below).
8. **Report**: counts of `[x]` / `[?]` / `[!]`, every `[!]` in full, every `[?]` recipe, the inspector's findings, and the next step.

## The evidence ladder

| Rank | Mark | Evidence | Use for |
|---|---|---|---|
| 1 | `[x]` | a **passing test**, named | deterministic logic |
| 2 | `[x]` | a **`file:line` read** plus one line of why | wiring, config, presence of a thing |
| 3 | `[?]` | a **recipe**: the exact runtime or visual step, and what to expect | UI, timing, anything only a running system shows |
| — | `[!]` | the gap, with `file:line` | missing, wrong, or the check is red |

An `[x]` without a citation is a `[?]`.

## The checklist file

Start from `${CLAUDE_SKILL_DIR}/../../templates/checklist.md`. Write outcomes, not steps: "an expired session lands on /login", not "edited the middleware".

## Moving the ticket and the handoff

**Any `[!]` outstanding** → the ticket stays where it is. Say why. Ready-for-review with a known gap is not ready.

**All green** (no `[!]`, and every `[?]` either run or accepted by the human as a post-merge check):

- **Solo or sous session** → move the ticket to `rfr` yourself through `/bk:rail` (on a markdown rail that's an edit to `status:` plus a `rail:` commit per `rail.commit`).
- **Line cook** → you never write the rail. Send the sous one message, then wait:

  ```
  [handoff] <ID> ready for the pass
  station: <station>   branch: <branch>
  files: <N changed>   check: <green | red>
  inspector: <no findings | N findings, fixed | N open — why>
  checklist: <absolute path>   [x] a · [?] b · [!] 0
  [rail] <ID> → rfr
  ```

  **Do not commit anything before the sous replies `[go]`.** A `[findings]` reply means fix, re-run this skill, and hand off again. The sous reads your diff and re-runs the check itself. That's the pass, and it's the sous's job, not a sign of distrust.

## Hard rules

- Route, don't certify. Runtime and visual items are `[?]` with a recipe, never a faked `[x]`.
- `[!]` means not done. Report it at the top; don't bury it.
- Every `file:line` and test name was read in this run. No invented references.
- This skill writes only the checklist, its INDEX row, and (solo/sous only) the rail. It never touches code, git history or another station.
- A cook never commits, pushes or edits a ticket file from this skill.
