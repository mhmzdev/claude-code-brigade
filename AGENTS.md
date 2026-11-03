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
                                    status, live, run SKILL (a session here already running the
                                    skill; setup and feedback are shortcuts), stations, profiles;
                                    everything else goes to kitchen.sh.
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
│                                   lessons, decisions, inbox, doctor, sessions, live, budget
├── window/                         the Window (/bk:live): a Node server with no dependencies
│                                   (server/, live/ readers of the registry, transcripts, git,
│                                   rail, record; live/budget.js the budget reader, which
│                                   kitchen.sh budget runs too) and a 2.5D room in plain DOM
│                                   and CSS 3D (web/: scene.js the room and its characters,
│                                   main.js the HUD; ledger.html/js/css the Ledger page)
├── hooks/hooks.json, hooks/guard.sh  PreToolUse guard: no human dialog in a station outside a
│                                   grilling; no [gate] question without the commis's result
├── agents/                         commis (searches the record), inspector (report-only),
│                                   taster (the pass), runner (noisy commands)
└── templates/                      spec, ticket, plan, checklist, journal, decision, question,
                                    SCHEMA, brigade.local
scripts/check.sh                    THE gate: manifests, shellcheck, frontmatter, hooks json, tests, release check
scripts/release-check.sh            step 5 of the gate: version, CHANGELOG, formula, and the rule for
                                    what a PR may change (docs only / fragment / release)
scripts/release.sh                  opens the release PR: collects changelog.d/, bumps the version
changelog.d/                        one fragment per change waiting for a release (a PR adds its own)
.github/workflows/check.yml         runs the gate in CI on Linux and macOS
.github/workflows/release.yml       tags each green merge to main that moved the version v<version>,
                                    with a GitHub release, then pushes the rendered formula to the
                                    tap (needs TAP_TOKEN)
CHANGELOG.md                        one entry per version, newest first
tests/kitchen.test.sh               behaviour tests for kitchen.sh, both kitchen modes
tests/guard.test.sh                 behaviour tests for hooks/guard.sh: clone and worktree stations
tests/bk.test.sh                    behaviour tests for bin/bk: stub tmux and claude, a fake registry
tests/budget.test.sh                behaviour tests for the budget: handmade transcripts, a stub gh
tests/window.test.sh                behaviour tests for the Window's live reader (tests/window-live.mjs):
                                    how a helper in flight is seen, from the sub-agent's meta file
tests/release.test.sh               behaviour tests for scripts/release-check.sh and release.sh:
                                    throwaway repos with a bare origin and a stub gh
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
   registry, covering profiles, attach and peek, the pause and the resume; and
   `tests/budget.test.sh`: `kitchen.sh budget` over handmade transcripts (a sous, two cook
   conversations on one ticket, their sub-agents) and a stub `gh`, covering dedupe, prices,
   ticket spans and phases, the ledger, CI minutes and the journal line; and
   `tests/window.test.sh`: the Window's live reader against handmade transcripts and
   sub-agent meta files, covering a helper seen in flight, ended by its result or by
   `finished`, and one already out when the Window attaches; and
   `tests/release.test.sh`: the release check and `scripts/release.sh` in throwaway repos
   (a bare origin, a stub `gh`), covering a docs-only branch, a fragment, a cook that bumps,
   a release PR and the PR `release.sh` builds;
5. a release check (`scripts/release-check.sh`, tested by `tests/release.test.sh`): `version`
   in `plugin.json` is `X.Y.Z`, it's the top entry of `CHANGELOG.md` (`## [X.Y.Z] -
   YYYY-MM-DD`) and `Formula/bk.rb` downloads that tag; and on a branch, by what it changes
   against its merge base with `origin/main`: only `docs/` needs nothing, a release PR (only
   those three files and the fragments it deletes) must raise the version and leave no
   fragment, any other PR must add a `changelog.d/` fragment and leave the version alone
   (see Releasing).

The tests are sealed off from the machine: git runs with `GIT_CONFIG_GLOBAL=/dev/null`, `HOME`
points into the temp dir, and `open` only runs with `--terminal print` or `--no-launch`, so
nothing opens on your screen or writes to your real config. `KEEP=1 tests/kitchen.test.sh`
keeps the temp dir for poking at.

**CI runs the same gate** (`.github/workflows/check.yml`) on every pull request and on
`main` after each merge, on Linux (bash 5) and macOS (pinned to the system bash 3.2 that most users
have). The `claude` CLI isn't installed there, so step 1 is skipped in CI: run the gate locally
too. A red check means don't merge.

**When you add behaviour to `kitchen.sh`, `guard.sh`, `bin/bk` or `budget.js`, add a test for it, and make sure it can fail:**
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
  In the dogfood kitchen the sous merges a cook's PR itself once it passed the pass and CI is
  green (`kitchen.sh ship`, `gates.merge: sous-chef` in `.claude/brigade.md`); every such merge is
  a release too, so a red `main` is the next ticket.
  Run `scripts/check.sh` locally before opening the PR; CI skips manifest validation.
- **A cook never bumps the version.** `main` is protected, so a version can only arrive in a
  PR, and a bump in every PR meant each one re-bumped whenever `main` moved. Instead:
  - a PR that changes **only `docs/`** is not a release and carries nothing;
  - any other PR adds one file, `changelog.d/<id>-<slug>.md`: a first line `level: minor`
    (a change in how a kitchen runs) or `level: patch` (a fix, or a change that doesn't
    touch the plugin's behaviour), a blank line, then a short paragraph for the busy human
    (what changed for them, and what they must do). It leaves `version`, the formula's `url`
    and every `## [X.Y.Z]` heading alone. `scripts/check.sh` (`scripts/release-check.sh`)
    fails the PR otherwise, and says what to do;
  - the **release is its own PR**. When the head chef says ship, the sous runs
    `scripts/release.sh` (`--dry-run` to look first): it takes every fragment on
    `origin/main`, writes one `## [X.Y.Z] - YYYY-MM-DD` entry, bumps `plugin.json` and the
    formula's `url` (a minor if any fragment says minor, else a patch), deletes the fragments
    and opens the PR from `release/vX.Y.Z`. The head chef merges it; that merge is the
    release. Changes merged since the last release wait for the next one (the marketplace
    cache is keyed on the version, so users get them at the release, not before).
  - A PR open when this rule landed carries an old bump: drop the bump in `plugin.json`,
    `CHANGELOG.md` and `Formula/bk.rb` once and add a fragment instead.
- **The tag and the GitHub release are automatic.** When `check` goes green on `main`,
  `.github/workflows/release.yml` tags the merge `v<version>` and publishes a release whose
  notes are its `CHANGELOG.md` entry, if the merge moved the version; any other merge finds
  the tag already there and leaves it. Never tag by hand. The README doesn't carry a version.
- **So is the Homebrew tap.** The same workflow downloads the tag's tarball, writes its
  sha256 into `Formula/bk.rb` and pushes the result to `mhmzdev/homebrew-brigade`, which is
  what `brew install mhmzdev/brigade/bk` reads (always the full name: homebrew-core has an unrelated `bk`). The formula in this repo is the template:
  `scripts/release.sh` bumps its `url` with the version (the gate checks it); never edit the tap's copy by hand.
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
