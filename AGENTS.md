# AGENTS.md — working on The Brigade

This repo **is** a Claude Code plugin: the Brigade, a way to run several Claude Code
sessions like a professional kitchen (a sous chef leads, line cooks work one ticket each in
their own station, the human is head chef). You're here to change the plugin itself, not to
use it on a product. `CLAUDE.md` is a symlink to this file, so every coding agent reads the
same instructions.

User-facing overview: [`README.md`](README.md). How each flow runs: [`PLAYBOOK.md`](PLAYBOOK.md). Every name the plugin uses:
[`docs/the-names.md`](docs/the-names.md). What changed in each version: [`CHANGELOG.md`](CHANGELOG.md).

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
bin/bk                              the bk command: open (start + attach), attach, peek, stop (a
                                    pause: handoff, save ids, exit) with resume on the next open,
                                    status, live, profiles; everything else goes to kitchen.sh.
                                    Finds the plugin as ../plugins/bk from its own real path, so
                                    it runs from a checkout and from Homebrew's libexec alike
Formula/bk.rb                       the Homebrew formula template (tap mhmzdev/homebrew-brigade);
                                    release.yml fills in the sha256 and pushes it to the tap
plugins/bk/                         the plugin (skills are invoked /bk:<skill>)
├── .claude-plugin/plugin.json      name "bk", version, agents list
├── skills/README.md                THE CONTRACT: rules every skill follows (Contracts 1–12)
├── skills/<name>/SKILL.md          one skill each: setup, kitchen, sous-chef, line-cook, rail,
│                                   brainstorm, grill-me, spec, file-tickets, pick-ticket,
│                                   create-plan, implement, review-task, open-pr, clean, handoff,
│                                   feedback, live
├── skills/kitchen/kitchen.sh       the runtime script: stations, boards, role, sous, questions,
│                                   lessons, decisions, inbox, doctor, sessions, live
├── window/                         the Window (/bk:live): a Node server with no dependencies
│                                   (server/, live/ readers of the registry, transcripts, git,
│                                   rail, record) and a PixiJS room (web/, PixiJS vendored)
├── hooks/hooks.json, hooks/guard.sh  PreToolUse guard: no human dialog in a station outside a
│                                   grilling; no [gate] question without the commis's result
├── agents/                         commis (searches the record), inspector (report-only),
│                                   taster (the pass), runner (noisy commands)
└── templates/                      spec, ticket, plan, checklist, journal, decision, question,
                                    SCHEMA, brigade.local
scripts/check.sh                    THE gate: manifests, shellcheck, frontmatter, hooks json, tests, version
.github/workflows/check.yml         runs the gate in CI on Linux and macOS
.github/workflows/release.yml       tags each green merge to main v<version>, with a GitHub release,
                                    then pushes the rendered formula to the tap (needs TAP_TOKEN)
CHANGELOG.md                        one entry per version, newest first
tests/kitchen.test.sh               behaviour tests for kitchen.sh, both kitchen modes
tests/guard.test.sh                 behaviour tests for hooks/guard.sh: clone and worktree stations
tests/bk.test.sh                    behaviour tests for bin/bk: stub tmux and claude, a fake registry
docs/the-names.md                   the Brigade names, plus Qafila as an alternate
PLAYBOOK.md                         how each flow runs, as questions and answers; the contract wins over it
assets/hero.jpeg                    README banner
.github/ISSUE_TEMPLATE/feedback.yml the issue form /bk:feedback mirrors
```

## The contract is the source of truth

`plugins/bk/skills/README.md` defines the cast, the config (`.claude/brigade.md` in a
consuming repo), the rail and its six operations, ids and paths, who answers each gate (and
the three kinds of unknown), the message kinds, the walk-in, stations, lanes,
journals/handoffs/lessons, and the record (what the kitchen remembers and how it's filed). A
skill says *how* to do its step; the contract says what every step shares.

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
- **`disable-model-invocation: true` only on `setup`**, which changes a repo's layout.
  Every other skill must stay model-invocable, or cooks stall waiting for a human to type it.
  That includes `implement`: a cook starts it on the sous's `[approved]` (the sous's own for
  a bug, chore or hygiene ticket; the head chef's, relayed, for a feature), and the skill
  itself checks the sign-off is there.
- **The head chef talks to the sous only** (Contract 5). No skill may tell a cook to ask
  the human or open an `AskUserQuestion` dialog; a cook's question is a `[gate]` to the sous,
  and it goes to the `commis` first. The hook in `hooks/guard.sh` enforces both in a
  station; a skill that needs a dialog there during a grilling writes `.claude/grilling`
  first and removes it after.
- **Only the head chef decides what nobody has decided** (Contract 5). A skill may let the
  sous answer from the record or sign off a bug, chore or hygiene plan; it may never let the
  sous decide a fork the record doesn't settle or approve a feature plan.
- **Every lifecycle skill starts with the station check** (`kitchen.sh role`): a session inside
  a station is a line cook, even after `/clear`.
- **Message kinds** used in any skill must exist in Contract 6's table.
- **Frontmatter:** `name`, a `description` with trigger phrases, `argument-hint`,
  `allowed-tools`. Every skill file has a `## Contents` list; keep it in sync with its headings.
- **Write for one busy human** (Contract 10): the point first, one idea per sentence, jargon
  glossed on first use.

## Checking a change

**One command is the gate:**

```bash
scripts/check.sh
```

It runs, in order:

1. `claude plugin validate` on the marketplace and the plugin (skipped, with a warning, if the
   `claude` CLI isn't installed);
2. `bash -n` and `shellcheck` on `kitchen.sh`, `hooks/guard.sh`, `bin/bk` and the test
   scripts (`shellcheck` is required);
3. a frontmatter check on every skill: `name` matches its folder, a real `description`, and
   `disable-model-invocation: true` only on `setup`; every agent is listed in
   `plugin.json`; `hooks/hooks.json` is valid JSON with a top-level `hooks` key;
4. `tests/kitchen.test.sh`: about 180 behaviour tests of `kitchen.sh` in throwaway repos, in
   both `clone` and `worktree` mode, including a workspace repo that holds the app repo; and
   `tests/guard.test.sh`: the hook guard fed the JSON Claude Code sends, in a clone station,
   a worktree station, the main checkout and a repo without the Brigade; and
   `tests/bk.test.sh`: `bin/bk` against a stub `tmux` that logs its calls and a fake session
   registry, covering profiles, attach and peek, the pause and the resume;
5. a release check: `version` in `plugin.json` is `X.Y.Z`, it's the top entry of
   `CHANGELOG.md` (`## [X.Y.Z] - YYYY-MM-DD`), `Formula/bk.rb` downloads that tag, and on a
   branch it's higher than `origin/main`'s.

The tests are sealed off from the machine: git runs with `GIT_CONFIG_GLOBAL=/dev/null`, `HOME`
points into the temp dir, and `open` only runs with `--terminal print` or `--no-launch`, so
nothing opens on your screen or writes to your real config. `KEEP=1 tests/kitchen.test.sh`
keeps the temp dir for poking at.

**CI runs the same gate** (`.github/workflows/check.yml`) on every pull request and on
`main` after each merge, on Linux (bash 5) and macOS (pinned to the system bash 3.2 that most users
have). The `claude` CLI isn't installed there, so step 1 is skipped in CI: run the gate locally
too. A red check means don't merge.

**When you add behaviour to `kitchen.sh`, `guard.sh` or `bin/bk`, add a test for it, and make sure it can fail:**
break the code on purpose and watch the test go red before you trust it green. Every test in
the suite was checked that way when it was written.

**Prose changes across several skills** have no automated check. Do a consistency read
against the contract (a fresh read-only sub-agent is good at this), listing every file that
now disagrees.

## Releasing

- **`main` is the release, and it's protected.** The marketplace installs from `main`, so
  whatever lands there reaches anyone who runs `/plugin marketplace update`. Nobody pushes to
  `main` directly, admins included: work on a branch, open a PR, and merge once **both** CI
  jobs are green and the branch is up to date with `main`. No approving review is required
  (a solo maintainer can't approve their own PR), so reading the diff before merging is on you.
  Run `scripts/check.sh` locally before opening the PR; CI skips manifest validation.
- **Every merge to `main` is a release.** In every PR, bump `version` in
  `plugins/bk/.claude-plugin/plugin.json` and add its entry at the top of `CHANGELOG.md`:
  `## [X.Y.Z] - YYYY-MM-DD`, then a short paragraph for the busy human (what changed for
  them, and what they must do). Minor for a change in how a kitchen runs, patch for fixes
  and changes that don't touch the plugin's behaviour. `scripts/check.sh` fails the PR
  without both. If another PR lands first, bring `main` in and bump again.
- **The tag and the GitHub release are automatic.** When `check` goes green on `main`,
  `.github/workflows/release.yml` tags the merge `v<version>` and publishes a release whose
  notes are its `CHANGELOG.md` entry. Never tag by hand. The README doesn't carry a version.
- **So is the Homebrew tap.** The same workflow downloads the tag's tarball, writes its
  sha256 into `Formula/bk.rb` and pushes the result to `mhmzdev/homebrew-brigade`, which is
  what `brew install mhmzdev/brigade/bk` reads. The formula in this repo is the template:
  bump its `url` with the version (the gate checks it) and never edit the tap's copy by hand.
  The push needs the `TAP_TOKEN` secret (a fine-grained token with contents: write on the tap).
- **A renamed skill or plugin is breaking.** Say so in bold in its `CHANGELOG.md` entry and
  in the commit: installs are tied to the plugin name (`bk@claude-code-brigade`), and people
  type skill names.
- Commit subjects: `feat: …`, `fix(kitchen): …`, `docs(readme): …`.

## Dogfooding

You can install the Brigade in this repo and use it to work on itself. Remember that
**the plugin you run is not the plugin you edit**: sessions run the installed copy cached
from `main`, never the files in this checkout or a station. To try an edit before
releasing, start a separate session with the local copy (`claude --plugin-dir ./plugins/bk`)
against a throwaway repo, not in the kitchen you're working in. `bin/bk` run from this
checkout is the exception: every session it starts loads *this checkout's* `plugins/bk`
(that is what `--plugin-dir` is for), so `./bin/bk open` in a throwaway repo tries your edit
as a whole kitchen. The Homebrew `bk` loads the plugin installed next to it, never this one.
