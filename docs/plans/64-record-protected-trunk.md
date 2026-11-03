---
ticket: "#64"
title: The record reaches a protected trunk, and a docs-only change needs no release
status: done
approved: 2026-11-03
lane: B
created: 2026-11-03
open_questions: none
migration: false
files:
  - scripts/release-check.sh
  - scripts/release.sh
  - scripts/check.sh
  - tests/release.test.sh
  - changelog.d/64-record-protected-trunk.md
  - plugins/bk/skills/kitchen/kitchen.sh
  - tests/kitchen.test.sh
  - plugins/bk/skills/handoff/SKILL.md
  - plugins/bk/skills/README.md
  - .github/workflows/release.yml
  - CHANGELOG.md
  - AGENTS.md
---

# #64 — The record reaches a protected trunk, and a docs-only change needs no release

## Why

Two rules collide on this repo's protected `main`. The record (Contract 12) is meant to reach
trunk straight away (`rail.commit: direct`), but a push to `main` is refused, so the sous's
decision 001 and the lessons register sit on `docs/sous-record-2026-10-25`, and
`kitchen.sh lessons` and `debrief` keep calling both lessons due. And `scripts/check.sh` step 5
refuses any PR without a higher version, so a docs-only PR needs a release and every cook PR
re-bumps each time `main` moves (#62, #63 and #19 each lost a round or more to it).

## Current state

- `scripts/check.sh:79-109`: step 5 demands `plugin.json`'s version be the top `CHANGELOG.md`
  entry and the one `Formula/bk.rb` downloads, and (lines 99-105) on any branch that isn't
  `origin/main` itself, higher than `origin/main`'s. No path is exempt.
- `.github/workflows/release.yml:38-46`: tags `v<version>` and publishes the release from the
  CHANGELOG entry; if the tag already exists it exits 0 ("nothing to release"). The tap step
  (line 48 on) then runs every time and is idempotent.
- `AGENTS.md:166-195` (`CLAUDE.md` is a symlink to it): "Every merge to `main` is a release.
  In every PR, bump `version` … If another PR lands first, bring `main` in and bump again."
- `main` is protected: `enforce_admins: true`, no push allowances, no rulesets
  (`gh api repos/mhmzdev/claude-code-brigade/branches/main/protection`, read this run). Nothing,
  a workflow included, can push a commit to `main`; every change arrives in a PR.
- `kitchen.sh` reads the record from this checkout's working tree only: `cmd_lessons`
  (`kitchen.sh:1047`, register at `:1049`), `cmd_questions` (`:1089`, `$ROOT/$qdir` at `:1094`),
  `cmd_decisions` (`:1169`, register at `:1171`, `record_dirs` at `:1156`), `cmd_gaps` (`:1315`,
  `$ROOT/$qdir` at `:1326`) and `cmd_debrief` (`:1472`, `--register "$ROOT/…"` at `:1478`).
- `plugins/bk/skills/handoff/SKILL.md:66-102`: steps 1, 3 and 4 file the record and say "commit
  per `rail.commit`"; nothing handles a refused push.
- The commis found none of this decided in the record (journal, 2026-11-03).

## Desired end state

1. After a sous handoff on a protected trunk, the record is in an open PR on a `record/<date>`
   branch, the main checkout is back on a clean trunk, and the sous handoff's Notes say which
   PR. On an unprotected trunk with `rail.commit: direct` it still lands on trunk directly.
   Verify: `tests/kitchen.test.sh` "record-pr" cases.
2. `kitchen.sh lessons`, `decisions`, `questions`, `gaps` and `debrief` read the record from this
   checkout **and** from every `record/*` branch not yet on `origin/<trunk>`, so a filed item
   stops showing as due once its branch is pushed. Verify: the same cases, each red against the
   old readers.
3. In this repo: a PR that touches only `docs/**` merges with no version change and no entry;
   any other PR carries a changelog fragment and **no** version bump; the version is assigned in
   one release PR that `scripts/release.sh` opens; `release.yml` tags only when the version
   moved. Verify: `tests/release.test.sh`, and `scripts/check.sh` on this very branch.
4. `AGENTS.md`'s Releasing section says so, so a cook never bumps again.

## Not doing

- Stamping `## [Unreleased]` from `release.yml`: it would have to push to `main` (see
  Decisions, How 1).
- Moving the rail's files (specs, backlog tickets) off `rail.commit`: this ticket is the
  *record*. A markdown rail on a protected trunk is the same problem and is left to a ticket
  of its own.
- Changing the config schema (`.claude/brigade.md` is a protected path and no key is needed).
- #58's lines: `kitchen.sh clear`, `board`'s context warning, the "who clears sessions" lines in
  Contract 5, the sous-chef and line-cook skills, PLAYBOOK, README. Whichever of #58 and this PR
  merges second brings `main` in.
- A bump or entry for this PR in `plugin.json`/`CHANGELOG.md`: see Decisions, How 6.

## Approach

Two independent halves, one PR.

**This repo's release rule (phases 1 and 4).** Move step 5 into `scripts/release-check.sh` so it
can be tested in a throwaway repo. It sorts a branch by what it changes against its merge base
with `origin/main`: docs-only (every path under `docs/`) needs nothing; a *release* PR (only
`plugin.json`, `CHANGELOG.md`, `Formula/bk.rb` and deleted fragments) must raise the version and
consume every fragment; any other PR must add a fragment `changelog.d/<id>-<slug>.md` and leave
the version, the formula URL and every `## [x.y.z]` heading alone. `scripts/release.sh` builds the
release PR from the fragments on `origin/main`, so cooks never touch the files two PRs always
fight over (the top of `CHANGELOG.md`, `plugin.json`). `release.yml` is unchanged in behaviour (the
tag already exists after a docs-only or fragment-only merge, so it exits 0); its comments and
log line say so.

**The plugin (phases 2 and 3).** `kitchen.sh record-pr` is the existing `rail.commit: daily-pr`
idea (`README.md:254-257`) applied to the record: commit the dirty record paths on a branch, try
trunk when `rail.commit` is `direct`, else push the branch and open the PR, and leave the main
checkout on trunk. The readers get one helper, `record_view`, that builds a temp copy of the
record paths with unmerged `record/*` branches laid over it, so the five commands change a
variable, not their logic. Pattern followed: `cmd_budget`/`cmd_debrief` shelling out to
`budget.js` with a path (`:1472-1481`) for the register, and `record_dirs` (`:1156`) for the
paths.

## Decisions

### Changes the ticket

None. The ticket names both ways of assigning the version ("a `## [Unreleased]` section that
`release.yml` stamps, or a bump the merger makes") and leaves the rest to the plan. How 1 takes
the second, as a release PR; it is flagged there because it turns "every merge to `main` is a
release" into "every merge of a release PR is", and the head chef may read it as a change to the
ticket.

### How

1. **A release PR, not a stamp.** `release.yml` stamping `## [Unreleased]` needs a push to
   `main`, which protection forbids even for admins (evidence above), so it cannot work without
   loosening the repo's settings. A bump the merger makes on each PR's branch just before merging
   re-opens the very race the ticket removes (a second PR merging in between needs the bump
   redone, with a conflict). `scripts/release.sh` builds the bump from `origin/main` every time,
   so it is re-runnable and conflict-free. Cost: a release is one extra small PR, opened by the
   sous on the head chef's word and merged by them, and a batch of merges can ride one release.
   Because only a changed version reaches users (the plugin cache is keyed on it), unreleased
   changes sit on `main` until then; that is the point of choosing when.
2. **Changelog fragments, `changelog.d/<id>-<slug>.md`.** First line `level: minor` or
   `level: patch` (CLAUDE.md's rule: minor for a change in how a kitchen runs), a blank line, then
   the paragraph for the busy human that would have been the CHANGELOG entry. Two PRs inserting
   under one `## [Unreleased]` heading would conflict on the same line; separate files do not.
   `release.sh` joins them in file-name order, takes the highest level, and deletes them.
   `changelog.d/README.md` is not a fragment.
3. **Docs-only means every changed path is under `docs/`**, the ticket's own list. `README.md`,
   `PLAYBOOK.md`, `AGENTS.md` and `assets/` are not exempt (they take a fragment, a `patch`).
   Changed paths are `git diff --name-only <merge-base>` (the working tree too, so the gate works
   before the commit) plus untracked files, so a PR is judged by what it changes (#13), not by
   where trunk has moved.
4. **The command is `kitchen.sh record-pr`**, from the main checkout only (like `asks --add`, it
   refuses a station). It files the record paths: every `docs:` key except journal, plans,
   checklists, backlog, research, brainstorm and specs, plus the lessons register (the same list
   `record_dirs` uses at `:1156-1167`, with the register added, as relative paths). Nothing to file
   → "Nothing to file", exit 0. The branch is `record/<YYYY-MM-DD>`, then `-2`, `-3`.
5. **`rail.commit: direct` tries trunk first** (push `HEAD:<trunk>`); a refused push (protected
   trunk, or any other reason) falls back to the branch and PR, so the plugin needs no "is it
   protected" probe. `daily-pr` goes straight to the PR. `gh` missing or `pr create` failing
   leaves the branch pushed, prints the exact `gh pr create` line, and exits 1.
6. **This PR carries a fragment (`level: minor`) and no version bump.** `release.sh` assigns the
   version after it merges (the next minor above whatever `main` is then). The PRs open when it
   merges convert once: drop the bump, add a fragment; the gate's message says exactly that.
7. **The readers look at `record/*` branches, not at open PRs.** A ref test
   (`for-each-ref refs/heads/record refs/remotes/origin/record`, minus any ref already an ancestor
   of `origin/<trunk>`) needs no network and no `gh`, so it works in the tests and offline; it is
   "as of the last fetch". A record PR closed unmerged leaves its branch counting until the
   branch is deleted; the handoff note says to delete it.
8. **Scope of the readers: `lessons`, `decisions`, `questions`, `gaps`, `debrief`.** The ticket
   names three; `decisions` and `questions` have the identical flaw (a decision filed on a record
   branch is listed due again, an open question file parked there is parked a second time), and
   share the helper, so all five change.
9. **The lessons register is a union, question and decision files are overlays.** The register is
   only ever read as "which keys are listed" (`:1055-1058`), so working copy plus every branch's
   copy is concatenated; any other file takes the newest branch's version.
10. **`record_view` is a temp dir** (`mktemp -d`, removed by the command that made it). Journals,
    `.claude/` and the stations are read as before.
11. **Tests:** a new `tests/release.test.sh` (the gate and `release.sh`, in throwaway repos with a
    bare origin) added to `check.sh` step 4; `record-pr` and the readers in `tests/kitchen.test.sh`
    with a pre-receive hook on the bare origin that refuses pushes to `main`, and a stub `gh`.

## Protected paths

- `AGENTS.md` (the real file behind the root `CLAUDE.md` symlink): edited in phase 4, the last
  phase. Contract 5 lists the root `CLAUDE.md` as refused in auto mode once; the Releasing
  section is a Done-when box, so this edit is required. If it is refused the cook sends
  `[gate] #64 edit denied: AGENTS.md, …` and the head chef lifts it at the station.

## Phase 1: the release gate and the release PR

**Status:** Done (scripts/release-check.sh, scripts/release.sh, check.sh step 4+5 wiring, changelog.d/{README,64-…}.md, tests/release.test.sh 42/42; each case seen red against a broken script; full gate to run with the sous's OK)

Starts only after the sous says #76 has merged; then `git merge origin/main`.

### Changes

#### `scripts/release-check.sh` (new)

Step 5 as its own script (so a test can run it in a throwaway repo). The consistency checks move
here unchanged from `check.sh:81-98`; the branch rule is new.

```bash
#!/usr/bin/env bash
# scripts/release-check.sh — step 5 of scripts/check.sh: is this tree releasable?
#  1. plugin.json's version is the top CHANGELOG.md entry and the one Formula/bk.rb downloads.
#  2. On a branch, by what it changes against its merge base with origin/main:
#       only docs/**                      no release: nothing to carry
#       a release (only plugin.json, CHANGELOG.md, Formula/bk.rb, changelog.d/ deletions)
#                                         must raise the version and consume every fragment
#       anything else                     adds changelog.d/<id>-<slug>.md and leaves the
#                                         version, the formula url and the `## [x.y.z]` headings alone
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
MANIFEST=plugins/bk/.claude-plugin/plugin.json
FRAGDIR=changelog.d
FAILED=0
fail() { echo "   ✗ $1"; FAILED=1; }
version_of() { sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' | head -1; }
newer() { …as check.sh:84-88… }
fragments_at() {  # fragments_at <ref> → the fragment files at a ref (README.md is not one)
  git ls-tree -r --name-only "$1" -- "$FRAGDIR" 2>/dev/null | grep -v "^$FRAGDIR/README.md$" || true
}
version=$(version_of <"$MANIFEST")
# … the three consistency checks of check.sh:92-98, then:
if ! git rev-parse -q --verify origin/main >/dev/null; then
  echo "   ! no origin/main: the branch rule is not checked"
else
  base=$(git merge-base HEAD origin/main)
  changed=$( { git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u )
  main_version=$(git show "origin/main:$MANIFEST" | version_of)
  if [[ -z "$changed" ]]; then :                                   # main itself, or behind it
  else
    docs_only=true; release_files=true
    while IFS= read -r p; do
      case "$p" in docs/*) ;; *) docs_only=false ;; esac
      case "$p" in "$MANIFEST"|CHANGELOG.md|Formula/bk.rb|"$FRAGDIR"/*) ;; *) release_files=false ;; esac
    done <<<"$changed"
    left=$(ls "$FRAGDIR"/*.md 2>/dev/null | grep -v "/README.md$" || true)
    if $docs_only; then echo "   ✓ docs only: no release"
    elif [[ "$version" != "$main_version" ]]; then
      if ! $release_files; then
        fail "this PR bumps the version ($main_version → $version) and changes more than the release files: drop the bump in plugin.json, CHANGELOG.md and Formula/bk.rb and add changelog.d/<id>-<slug>.md; the release PR (scripts/release.sh) assigns the version"
      else
        newer "$version" "$main_version" || fail "release: $version must be higher than origin/main's $main_version"
        [[ -z "$left" ]] || fail "release: fragments left in $FRAGDIR/ (the release consumes them): $left"
      fi
    else
      new=$( { git diff --name-only --diff-filter=A "$base" -- "$FRAGDIR"; git ls-files --others --exclude-standard -- "$FRAGDIR"; } | sort -u | grep -v "^$FRAGDIR/README.md$" || true)
      [[ -n "$new" ]] || fail "this PR changes more than docs/ and has no fragment: add $FRAGDIR/<id>-<slug>.md (first line 'level: minor' or 'level: patch', then the paragraph for the head chef)"
      for f in $new; do
        head -1 "$f" | grep -qE '^level: (minor|patch)$' || fail "$f: first line must be 'level: minor' or 'level: patch'"
        [[ -n "$(sed '1,/^$/d' "$f")" ]] || fail "$f: no paragraph after the level line"
      done
      git diff "$base" -- CHANGELOG.md | grep -qE '^\+## \[' && fail "CHANGELOG.md: this PR adds a '## [x.y.z]' entry; entries are written by the release PR from the fragments"
    fi
  fi
  pending=$(fragments_at origin/main | wc -l | tr -d ' ')
  (( pending == 0 )) || echo "   · $pending change(s) on main wait for a release: scripts/release.sh"
fi
(( FAILED == 0 )) && echo "   ✓ v$version"
exit "$FAILED"
```

#### `scripts/check.sh:79-109` (edit)

Replace the body of step 5 with a call. Keep the `step` line and the `before` pattern:

```bash
step "5. release (version, CHANGELOG.md, Formula/bk.rb, changelog.d/)"
if out=$(bash scripts/release-check.sh 2>&1); then printf '%s\n' "$out"
else printf '%s\n' "$out"; fail "release check"; fi
```

Also: header comment lines 10-12 describe the new rule; the shellcheck list at `:36` gains
`scripts/release-check.sh scripts/release.sh tests/release.test.sh`; step 4 (`:61` on) runs
`tests/release.test.sh` the way it runs `tests/window.test.sh`, and its title line names it.

#### `scripts/release.sh` (new)

Opens the release PR from `origin/main`'s fragments. `--dry-run` stops before the push.

```bash
#!/usr/bin/env bash
# scripts/release.sh [--dry-run] — open the release PR: one version for every change waiting in
# changelog.d/ on origin/main. Run from any checkout of this repo; touches none of its files.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
MANIFEST=plugins/bk/.claude-plugin/plugin.json
git fetch origin main --quiet
frags=$(git ls-tree -r --name-only origin/main -- changelog.d | grep -v '^changelog.d/README.md$' | sort || true)
[[ -n "$frags" ]] || { echo "Nothing to release: no fragments in changelog.d/ on origin/main."; exit 0; }
cur=$(git show "origin/main:$MANIFEST" | sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' | head -1)
level=patch
for f in $frags; do [[ "$(git show "origin/main:$f" | head -1)" == "level: minor" ]] && level=minor; done
IFS=. read -r a b c <<<"$cur"
if [[ $level == minor ]]; then new="$a.$((b+1)).0"; else new="$a.$b.$((c+1))"; fi
branch="release/v$new"
[[ -z "$(git ls-remote --heads origin "$branch")" ]] || { echo "$branch already exists on origin: merge or close that release PR first." >&2; exit 1; }
wt=$(mktemp -d); trap 'git worktree remove --force "$wt" 2>/dev/null || true' EXIT
git worktree add -q -b "$branch" "$wt" origin/main
(
  cd "$wt"
  entry=$(mktemp)
  { printf '## [%s] - %s\n' "$new" "$(date +%F)"
    for f in $frags; do printf '\n'; sed '1,/^$/d' "$f"; done; } >"$entry"
  awk -v ef="$entry" '/^## \[/ && !d { while ((getline l < ef) > 0) print l; print ""; d=1 } { print }' CHANGELOG.md >CHANGELOG.md.new && mv CHANGELOG.md.new CHANGELOG.md
  sed "s/\"version\": *\"$cur\"/\"version\": \"$new\"/" "$MANIFEST" >m.new && mv m.new "$MANIFEST"
  sed "s#/archive/refs/tags/v$cur\.tar\.gz#/archive/refs/tags/v$new.tar.gz#" Formula/bk.rb >f.new && mv f.new Formula/bk.rb
  # shellcheck disable=SC2086
  git rm -q $frags
  git add "$MANIFEST" CHANGELOG.md Formula/bk.rb
  git commit -qm "release: v$new"
)
echo "release: v$new ($level) from: $(echo $frags | tr '\n' ' ')"
$DRY && { echo "dry run: branch $branch is local only"; exit 0; }
git push -q -u origin "$branch"
gh pr create --base main --head "$branch" --title "release: v$new" --body "Releases the changes waiting in changelog.d/: $(echo $frags). Merging this tags v$new."
```

(`DRY` is parsed from `$1` at the top; the sketch above shows the shape, the real file has it.)

#### `changelog.d/README.md` (new)

Five lines: what a fragment is, the `level:` line, "the release PR collects these".

#### `changelog.d/64-record-protected-trunk.md` (new)

`level: minor`, then the paragraph for the head chef: the record reaches a protected trunk in a
PR, docs-only changes need no release, cooks stop bumping, and what they must do (ask the sous
to run `scripts/release.sh` when they want to ship; restart sessions for the new skills).

#### `tests/release.test.sh` (new)

Throwaway repos (the `new_repo` pattern of `tests/kitchen.test.sh:48-57`): a bare origin, a clone
with the real `scripts/release-check.sh` and `release.sh` copied in, a minimal `plugin.json`,
`CHANGELOG.md`, `Formula/bk.rb`. Cases, each worded as the sentence it proves:

1. main itself, consistent: passes
2. a docs-only branch: passes with no fragment and the same version
3. a docs-only branch with the working tree dirty (uncommitted): still passes
4. a code change with no fragment: fails, naming `changelog.d/`
5. a code change with a valid fragment: passes
6. a fragment whose first line is not `level: minor|patch`: fails
7. a fragment with no paragraph: fails
8. `changelog.d/README.md` alone is not a fragment: fails
9. docs plus one code file: needs the fragment
10. a code change that also bumps the version: fails with "drop the bump"
11. a code change that adds a `## [x.y.z]` heading: fails
12. a release shape (only the three files, version higher, no fragments left): passes
13. a release whose version is not higher: fails
14. a release that leaves a fragment: fails
15. `release.sh --dry-run`: version is a minor when any fragment says minor, a patch otherwise;
    the CHANGELOG entry sits above the previous top entry and holds each fragment's paragraph;
    plugin.json and Formula url moved; fragments gone; branch `release/v…` exists locally only
16. the branch `release.sh` builds passes `release-check.sh` (case 12 by construction)
17. `release.sh` with no fragments: "Nothing to release", exit 0
18. `release.sh` when `release/v…` is already on origin: refuses

### Success criteria

- [x] `bash tests/release.test.sh` passes
- [x] **Each case goes red when it should.** Break on purpose and watch: drop the docs-only
      branch (2, 3), drop the `level:` check (6), drop the "left fragments" check (14), make
      `release.sh` always `patch` (15), drop the `-z "$changed"` guard (1)
- [ ] `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh` passes on
      this very branch (it carries the fragment and no bump): the rule applied to its own PR
- [ ] Manual: on a scratch clone with a fragment on `origin/main`, `scripts/release.sh --dry-run`
      prints the version and leaves the clone's own files untouched (`git status` clean)

## Phase 2: `kitchen.sh record-pr`

**Status:** Done (kitchen.sh record-pr + rail_commit/record_paths; tests/kitchen.test.sh "record-pr" section)

### Changes

#### `plugins/bk/skills/kitchen/kitchen.sh` — usage header (edit, near `:67`)

One entry under `gaps`/`doctor`:

```
#   kitchen.sh record-pr                  file the record (the dirty paths under the docs map's
#                                         decisions, conventions, knowledge, questions and the
#                                         lessons register): with rail.commit direct, push it to
#                                         trunk; if that is refused, or with daily-pr, push a
#                                         record/<date> branch and open a PR. Back on trunk,
#                                         clean, either way. Main checkout only
```

#### `plugins/bk/skills/kitchen/kitchen.sh:1156` (new functions after `record_dirs`)

```bash
# rail_commit → rail.commit from the config (direct | daily-pr), else direct.
rail_commit() {
  local v=""
  [[ -f "$CONFIG" ]] && v=$(awk '
    NR==1 && $0=="---" { inside=1; next }
    inside && $0=="---" { exit }
    inside && /^rail:/ { inrail=1; next }
    inrail && /^[^ ]/ { inrail=0 }
    inrail && /^  commit:/ { sub(/^  commit:[ ]*/, ""); sub(/[ ]+#.*$/, ""); print; exit }' "$CONFIG")
  printf '%s' "${v:-direct}"
}
# record_paths → the record's own paths, relative to the repo: every docs key but journal, plans,
# checklists, backlog, research, brainstorm and specs (those are the rail's or a cook's), plus
# the lessons register. Only the ones that exist.
record_paths() {
  local key path seen=" "
  while IFS= read -r key; do
    case "$key" in journal|plans|checklists|backlog|research|brainstorm|specs) continue ;; esac
    path="$(docs_path "$key")"; path="${path%/}"
    [[ "$path" == none || -z "$path" || "$seen" == *" $path "* ]] && continue
    seen="$seen$path "
    echo "$path"
  done < <(docs_keys)
}
```

#### `plugins/bk/skills/kitchen/kitchen.sh` (new `cmd_record_pr`, before `cmd_doctor` near `:1359`)

```bash
cmd_record_pr() {
  local paths=() p dirty branch n=1 day msg mode url remote_ok=false
  [[ "$(cd "$HERE" && pwd -P)" == "$ROOT_REAL" ]] || { echo "Only the sous files the record, from the main checkout ($ROOT_REAL)." >&2; return 1; }
  while IFS= read -r p; do paths+=("$p"); done < <(record_paths)
  dirty="$(git -C "$ROOT" status --porcelain -- "${paths[@]}" | sed 's/^...//')"
  [[ -n "$dirty" ]] || { echo "Nothing to file: the record paths are clean."; return 0; }
  [[ "$(git -C "$ROOT" branch --show-current)" == "$TRUNK" ]] || { echo "The main checkout is not on $TRUNK; switch to it first." >&2; return 1; }
  git -C "$ROOT" fetch origin "$TRUNK" --quiet 2>/dev/null || true
  # bring trunk up to date without touching the dirty record files; if origin changed one of them, stop
  git -C "$ROOT" merge --ff-only "origin/$TRUNK" >/dev/null 2>&1 || { echo "Could not fast-forward $TRUNK to origin/$TRUNK with the record files dirty; commit or stash by hand." >&2; return 1; }
  day="$(date +%Y-%m-%d)"; branch="record/$day"
  while git -C "$ROOT" show-ref -q --verify "refs/heads/$branch" || git -C "$ROOT" show-ref -q --verify "refs/remotes/origin/$branch"; do n=$((n+1)); branch="record/$day-$n"; done
  msg="docs(record): the sous's record, $day ($(printf '%s\n' "$dirty" | wc -l | tr -d ' ') file(s))"
  git -C "$ROOT" switch -q -c "$branch"
  git -C "$ROOT" add -- "${paths[@]}"
  git -C "$ROOT" commit -q -m "$msg"
  mode="$(rail_commit)"
  if [[ "$mode" == direct ]] && git -C "$ROOT" push -q origin "HEAD:refs/heads/$TRUNK" 2>/dev/null; then
    git -C "$ROOT" switch -q "$TRUNK" && git -C "$ROOT" merge -q --ff-only "$branch" && git -C "$ROOT" branch -q -d "$branch"
    echo "Filed on $TRUNK: $msg"; return 0
  fi
  git -C "$ROOT" push -q -u origin "$branch" || { git -C "$ROOT" switch -q "$TRUNK"; echo "Could not push $branch; the commit is on it locally." >&2; return 1; }
  git -C "$ROOT" switch -q "$TRUNK"
  if url="$(cd "$ROOT" && gh pr create --base "$TRUNK" --head "$branch" --title "$msg" --body "The sous's record (Contract 12), filed on a branch because $TRUNK takes no direct push. Files: $(printf '%s ' $dirty)" 2>/dev/null)"; then
    echo "Record PR: $url"; return 0
  fi
  echo "Pushed $branch; open the PR by hand: gh pr create --base $TRUNK --head $branch" >&2; return 1
}
```

`git add -- "${paths[@]}"` stages only the record paths, so a dirty `.claude/` or a rail file
stays out. The test fixture is the proof (below).

Wire it: dispatch (`:1570`) gains `record-pr) cmd_record_pr ;;`. No new flags, so the argument
loop (`:237-267`) is untouched.

#### `tests/kitchen.test.sh` (new section "record-pr", after the lessons section near `:436`)

A repo `R` from `new_repo`, journals with a `lesson(plugin)` line, `rail: commit: direct`, a
decision file and a register row written but uncommitted. The bare origin gets
`hooks/pre-receive` that exits 1 for `refs/heads/main` (the protected trunk); a `gh` stub earlier
on `PATH` prints a PR URL and logs its arguments.

1. a protected trunk: `record-pr` prints `Record PR: <url>`; the main checkout is on `main`,
   clean (`git status --porcelain` empty); `origin` has `record/<today>`; `gh` was called with
   `--head record/<today>`
2. the record commit holds the decision and the register, not an unrelated dirty rail file
3. an unprotected trunk (no hook): `Filed on main`, `origin/main` has the commit, no `record/`
   branch left, `gh` not called
4. `rail.commit: daily-pr` on an unprotected trunk: goes to a PR, not to `main`
5. nothing dirty: "Nothing to file", exit 0
6. run from a station: refused
7. a second run the same day: the branch is `record/<today>-2`
8. `gh` failing: the branch is pushed, the exit is 1, the message carries the `gh pr create` line

### Success criteria

- [ ] `bash tests/kitchen.test.sh` passes (the new section included)
- [ ] Break it, watch it go red: `git add -A` instead of the record paths (2); skip the
      `switch "$TRUNK"` after the push (1, 5); drop the fallback when the push is refused (1);
      always push to trunk (4)
- [ ] `shellcheck -S warning plugins/bk/skills/kitchen/kitchen.sh` clean
- [ ] Gate: `env -u … scripts/check.sh` passes (ask the sous first)

## Phase 3: the readers see unmerged record branches

**Status:** Done (record_branches, record_view, REC in the five readers; "the record on a branch" section)

### Changes

#### `plugins/bk/skills/kitchen/kitchen.sh` (new, after `record_paths`)

```bash
# record_branches → the record branches not yet on trunk, oldest first: local and remote-tracking
# refs under record/, minus any already an ancestor of origin/<trunk>. As of the last fetch.
record_branches() {
  local ref
  git -C "$ROOT" rev-parse -q --verify "origin/$TRUNK" >/dev/null || return 0
  git -C "$ROOT" for-each-ref --sort=committerdate --format='%(refname)' refs/heads/record refs/remotes/origin/record |
    while IFS= read -r ref; do
      git -C "$ROOT" merge-base --is-ancestor "$ref" "origin/$TRUNK" 2>/dev/null || echo "$ref"
    done
}
# record_view → a temp dir holding the record as the kitchen should read it: this checkout's own
# record paths, then every unmerged record branch laid over them (the register is the union).
# Prints the dir, or "$ROOT" itself when no record branch is open. The caller removes a temp one.
record_view() {
  local view ref p reg files=() branches=()
  while IFS= read -r ref; do branches+=("$ref"); done < <(record_branches)
  (( ${#branches[@]} )) || { printf '%s' "$ROOT"; return 0; }
  view="$(mktemp -d "${TMPDIR:-/tmp}/brigade-record.XXXXXX")"
  reg="$(cfg_docs lessons docs/lessons.md)"
  while IFS= read -r p; do
    [[ -e "$ROOT/$p" ]] && { mkdir -p "$view/$(dirname "$p")"; cp -R "$ROOT/$p" "$view/$p"; }
  done < <(record_paths; echo "$reg")
  [[ -f "$ROOT/$reg" ]] && cp "$ROOT/$reg" "$view/.register" || : >"$view/.register"
  for ref in "${branches[@]}"; do
    while IFS= read -r p; do files+=("$p"); done < <(git -C "$ROOT" ls-tree -r --name-only "$ref" -- $(record_paths) "$reg")
    (( ${#files[@]} )) && git -C "$ROOT" archive "$ref" -- "${files[@]}" | tar -x -C "$view"
    git -C "$ROOT" show "$ref:$reg" >>"$view/.register" 2>/dev/null || true
    files=()
  done
  mkdir -p "$view/$(dirname "$reg")"; mv "$view/.register" "$view/$reg"
  printf '%s' "$view"
}
```

Readers (each: `REC="$(record_view)"` at the top, `[[ "$REC" == "$ROOT" ]] || trap … ; rm -rf "$REC"` at the end;
the code reads the record through `$REC` and everything else through `$ROOT` as before):

- `cmd_lessons` `:1049` `lessons_file="$REC/$(cfg_docs lessons docs/lessons.md)"`
- `cmd_questions` `:1090-1094` `$ROOT/$qdir` → `$REC/$qdir`
- `cmd_decisions` `:1171` register → `$REC/…`; `record_dirs` (`:1156-1167`) takes the root as an
  optional argument (`record_dirs "$REC"`, default `$ROOT`) and `where="${hits#"$REC"/}"`
- `cmd_gaps` `:1326` `$ROOT/$qdir` → `$REC/$qdir` (the asks log `.claude/asks.md` stays `$ROOT`'s)
- `cmd_debrief` `:1478` `--register "$REC/$(cfg_docs lessons docs/lessons.md)"`

The sous's `.claude/asks.md` and the journals are not part of the view.

#### `tests/kitchen.test.sh` (new section "the record on a branch")

On the phase 2 repo, after a protected-trunk `record-pr`:

1. `lessons`: a key the register on the record branch lists shows `promoted`, not `DUE`
2. …and it shows `DUE` again once the branch is deleted (proves the branch is the only source)
3. a record branch already merged into `origin/main` is not read twice (no duplicates, still
   `promoted` from trunk)
4. two record branches each add a register row: both keys `promoted` (the union)
5. `decisions`: a head-chef answer cited by a decision file on the record branch is `filed`, not `DUE`
6. `gaps`: an answered question file with `fix:` on the record branch is not listed; without
   the branch it is
7. `questions`: an open question file only on the record branch is listed as `(record)`
8. `debrief`: a stub `node` on `PATH` prints the `--register` file it was given; it holds the
   branch's row
9. the temp view is gone afterwards (`ls "$TMPDIR"/brigade-record.*` empty)
10. no record branch open: `record_view` is `$ROOT` (nothing is copied; `TMPDIR` stays empty)

### Success criteria

- [ ] `bash tests/kitchen.test.sh` passes
- [ ] Red on purpose: make `record_branches` print nothing (1, 4, 5, 6, 7, 8 fail); use the
      newest branch's register only (4 fails); drop the ancestor filter (3 fails); skip `rm -rf` (9)
- [ ] `shellcheck -S warning` clean; `shellcheck -S info` count does not rise (the config's counter)
- [ ] Gate passes

## Phase 4: skills, contract, workflow and this repo's rules

**Status:** Done (handoff step 7 + note line, Contract 12 sentence, release.yml comments, CHANGELOG header, AGENTS.md Releasing/Checking/Layout, README closing line)

### Changes

#### `plugins/bk/skills/handoff/SKILL.md:66-102` (edit) and the sous note (`:148` on)

- Steps 1, 3 and 4: replace "commit per `rail.commit`" for the record files with "leave it in the
  working tree; step 7 files it". (Tickets fired through `/bk:rail` still commit per
  `rail.commit`.)
- New step 7, **Land the record**, before CI minutes (which become step 8, the note step 9):

  ```markdown
  7. **Land the record**:
     ```bash
     "${CLAUDE_SKILL_DIR}/../kitchen/kitchen.sh" record-pr
     ```
     It commits the record files this handoff wrote, pushes them to trunk if `rail.commit` is
     `direct` and trunk takes it, else opens a `record/<date>` PR, and leaves this checkout on
     a clean trunk. `lessons`, `decisions`, `questions`, `gaps` and `debrief` read an open
     record branch like trunk, so what you just filed stops showing as due at once. Say the PR
     in one line to the head chef (it is theirs to merge, like any PR) and put it in the note's
     Notes. When a record PR is merged or closed, delete its branch (a closed PR's branch counts
     until it is gone).
  ```
- The note template's `## Notes` gains `- record PR: <url or "none">`. The skill's `## Contents`
  list is unchanged (step numbers are not headings).

#### `plugins/bk/skills/README.md:912-916` (Contract 12, "Who writes what", edit)

One sentence added: the sous files the record with `kitchen.sh record-pr`, which goes to trunk when
`rail.commit` allows it and to a `record/<date>` PR when trunk is protected, and the commands that
list what is due read those branches too. No change to the four rules, to Contract 5 or to the
"who clears sessions" lines (#58's).

#### `.github/workflows/release.yml:1-9, 38-46` (edit)

Comments: "Every merge to main is a release" → a merge that moves the version (the release PR) is;
check.sh refuses a version change anywhere else. The tag step's `already exists` message becomes
`v$version is already released: this merge did not move the version`, so a docs or fragment merge
is read as intended. No change in logic: the tap step stays (idempotent, it retries a push that
failed). Verified by reading, plus the same logic exercised by `release.sh`'s tests.

#### `CHANGELOG.md:1-12` (edit)

The header paragraph's "Every merge to `main` is a release. It bumps `version` … adds an entry here"
→ a release PR (`scripts/release.sh`) collects the fragments waiting in `changelog.d/` into one entry
and bumps the version; a docs-only merge is not a release. No `## [x.y.z]` entry is added (How 6).

#### `AGENTS.md:166-195` (edit; the Releasing section) and Layout (`:20-69`)

- Releasing: rewrite the "Every merge to `main` is a release" bullet to the new rule: a cook never
  bumps `version` or writes a CHANGELOG entry; a PR that changes more than `docs/` carries
  `changelog.d/<id>-<slug>.md` (format, `level:`); a docs-only PR carries nothing; the sous opens the
  release with `scripts/release.sh` when the head chef says ship, and the head chef merges it
  (`check` skips docs-only, validates a release shape); "If another PR lands first, bring `main`
  in and bump again" goes. Keep the tag, tap and rename bullets; the tag bullet says "when a merge
  moves the version".
- "Checking a change", step 5: the release check is `scripts/release-check.sh`; step 4 lists
  `tests/release.test.sh`.
- Layout: `scripts/release-check.sh`, `scripts/release.sh`, `changelog.d/`, `tests/release.test.sh`.
- Releasing gains the one-time note for PRs open when this merges: drop the bump, add a fragment.

(`AGENTS.md` is the protected path: last edit of the last phase.)

### Success criteria

- [ ] Consistency read: a fresh read-only sub-agent lists every file that still says "every merge is
      a release" or "bump again" (`git grep -n -i -E 'every merge|bump again|bump \`version\`'`
      returns only deliberate uses)
- [ ] `grep -n '^## Contents' -A12 plugins/bk/skills/handoff/SKILL.md` still matches its headings
- [ ] Gate passes on the whole branch: `env -u … scripts/check.sh`
- [ ] Manual: on a scratch clone of the repo with this branch merged, add `docs/x.md` alone on a
      branch and run `bash scripts/release-check.sh`: "docs only: no release"; add a code file:
      the failure names `changelog.d/`

## Testing

`tests/release.test.sh` reaches the gate and `release.sh` (phase 1); `tests/kitchen.test.sh`
reaches `record-pr` and all five readers (phases 2 and 3). `release.yml` has no runner here: its
change is comments and a log line, read in the diff. Every new case is broken on purpose once and
seen red (the criteria above) before the suite is trusted green.

## References

- Ticket: #64 (`gh issue view 64`); EPIC #71; journal `docs/journal/64-record-protected-trunk.md`
- `scripts/check.sh:79-109`, `.github/workflows/release.yml:38-48`, `AGENTS.md:166-195`
- `kitchen.sh:1047,1089,1156,1169,1315,1472` (the readers), `:1570` (dispatch), `:173` (`cfg_docs`)
- Contract 12 (`README.md:826`), `README.md:254-257` (`daily-pr`), handoff skill steps 1-8
- #13 (merge-base diff), #62/#63/#19 (the rounds the re-bump cost), PR #76 (to merge first)
