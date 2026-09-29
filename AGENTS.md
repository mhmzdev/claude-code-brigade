# AGENTS.md — working on The Brigade

This repo **is** a Claude Code plugin: the Brigade, a way to run several Claude Code
sessions like a professional kitchen (a sous chef leads, line cooks work one ticket each in
their own station, the human is head chef). You're here to change the plugin itself, not to
use it on a product. `CLAUDE.md` is a symlink to this file, so every coding agent reads the
same instructions.

User-facing overview: [`README.md`](README.md). Every name the plugin uses:
[`docs/the-names.md`](docs/the-names.md).

## Contents

- [Layout](#layout)
- [The contract is the source of truth](#the-contract-is-the-source-of-truth)
- [Rules for changing skills](#rules-for-changing-skills)
- [Checking a change](#checking-a-change)
- [Releasing](#releasing)
- [Dogfooding](#dogfooding)

## Layout

```
.claude-plugin/marketplace.json     the marketplace: name claude-code-brigade, one plugin
plugins/bk/                         the plugin (skills are invoked /bk:<skill>)
├── .claude-plugin/plugin.json      name "bk", version, agents list
├── skills/README.md                THE CONTRACT: rules every skill follows (Contracts 1–11)
├── skills/<name>/SKILL.md          one skill each: setup, kitchen, sous-chef, line-cook, rail,
│                                   brainstorm, grill-me, spec, file-tickets, pick-ticket,
│                                   create-plan, implement, review-task, open-pr, clean, handoff
├── skills/kitchen/kitchen.sh       the only script: stations, boards, role, questions, lessons
├── agents/                         inspector (report-only), taster (the pass), runner (noisy commands)
└── templates/                      spec, ticket, plan, checklist, journal
docs/the-names.md                   the Brigade names, plus Qafila as an alternate
assets/hero.jpeg                    README banner
```

## The contract is the source of truth

`plugins/bk/skills/README.md` defines the cast, the config (`.claude/brigade.md` in a
consuming repo), the rail and its six operations, ids and paths, who answers each gate, the
message kinds, the walk-in, stations, lanes, and journals/handoffs/lessons. A skill says *how*
to do its step; the contract says what every step shares.

**When a skill and the contract disagree, the skill has a bug.** When you change a shared
rule, change the contract first, then grep every skill for the old wording and update it in
the same change. A contradiction between two skills makes a live session do two different
things, and it only shows up mid-service.

## Rules for changing skills

- **Nothing repo-specific in the plugin.** No product names, board ids, ticket numbers,
  incident dates or paths from a consuming repo. Anything repo-specific belongs in that
  repo's `.claude/brigade.md`, which skills read at run time.
- **Names live in one place.** Skills describe roles; the names come from the contract and
  `docs/the-names.md`, so a rename stays small.
- **Invoking a skill is its approval** (Contract 5). No "does this look right?", no "continue
  to phase 2?". A skill stops only for a real decision.
- **`disable-model-invocation: true` only on `implement` and `setup`.** `implement` is the one
  gate a human must type (typing it is the plan sign-off); `setup` changes a repo's layout.
  Every other skill must stay model-invocable, or cooks stall waiting for a human to type it.
- **Every lifecycle skill starts with the station check** (`kitchen.sh role`): a session inside
  a station is a line cook, even after `/clear`.
- **Message kinds** used in any skill must exist in Contract 6's table.
- **Frontmatter:** `name`, a `description` with trigger phrases, `argument-hint`,
  `allowed-tools`. Every skill file has a `## Contents` list; keep it in sync with its headings.
- **Write for one busy human** (Contract 10): the point first, one idea per sentence, jargon
  glossed on first use.

## Checking a change

There's no test suite yet; run these by hand before committing.

1. **Manifests:**
   ```bash
   claude plugin validate .
   claude plugin validate plugins/bk
   ```
2. **The script:**
   ```bash
   bash -n plugins/bk/skills/kitchen/kitchen.sh
   shellcheck -S warning plugins/bk/skills/kitchen/kitchen.sh
   ```
3. **`kitchen.sh` behaviour:** exercise it in a throwaway repo under a scratch directory (a
   bare `origin`, a clone with `.claude/brigade.md`), in **both** `kitchen_mode: clone` and
   `worktree`: `setup` refusing an unpushed config, `setup`, `role` from a station,
   `open --terminal print`, `files`, `rail`, `questions`, `lessons`, `sync` skipping a dirty
   station, `remove`. Run git with `GIT_CONFIG_GLOBAL=/dev/null` so your own git config can't
   hide a bug. **Never** run `open` with a real terminal while testing: use
   `--terminal print` or `--terminal warp --no-launch`, or you'll open windows on the
   human's screen.
4. **Prose changes across several skills:** do a consistency read against the contract (a
   fresh read-only sub-agent is good at this), listing every file that now disagrees.

## Releasing

- **`main` is the release.** The marketplace installs from `main`, so every push reaches
  anyone who runs `/plugin marketplace update`. Don't push half-finished skill changes.
- **Bump `version` in `plugins/bk/.claude-plugin/plugin.json`** for every release, and add a
  line to the Status section of `README.md`.
- **A renamed skill or plugin is breaking.** Say so in the commit and README: installs are
  tied to the plugin name (`bk@claude-code-brigade`), and people type skill names.
- Commit subjects: `feat: …`, `fix(kitchen): …`, `docs(readme): …`.

## Dogfooding

You can install the Brigade in this repo and use it to work on itself. Remember that
**the plugin you run is not the plugin you edit**: sessions run the installed copy cached
from `main`, never the files in this checkout or a station. To try an edit before
releasing, start a separate session with the local copy (`claude --plugin-dir ./plugins/bk`)
against a throwaway repo, not in the kitchen you're working in.
