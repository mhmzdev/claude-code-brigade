---
ticket: "#91"
title: "Positive authorization: a cook may commit, push or open a PR only on a grant the sous writes (kitchen.sh grant); merge never"
plan: docs/plans/91-positive-authorization.md
last_verified: 2026-11-03
---

# Acceptance — #91 Positive authorization

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

### The sous grants, the cook ships

1. The sous runs `kitchen.sh grant station-1 commit push open-pr` from the main checkout → `station-1: commit push open-pr`, and `.claude/grants/station-1` holds the three words, out of git.
2. The cook's `git commit`, `git push origin <branch>` and `gh pr create` now pass the hook; before the grant each was refused naming the missing action, the sous and `kitchen.sh grant`.
3. At `[served]` the sous runs `grant station-1 --none` → `station-1: none`; the cook's next `git commit` is refused. `done` and `clear` remove it too.

### What is never granted

1. `git push origin main`, `HEAD:main`, `--force`, `-f`, `--force-with-lease`, `+ref`, `--all`, `--mirror`, `--delete`, `gh pr merge`, `git reset --hard`, `git clean -fdx` → refused with every grant.
2. `kitchen.sh grant station-1 merge` → refused: the sous merges.

## Edge cases

- A cook runs `kitchen.sh grant …` → refused ("Only the sous grants"), nothing written; `--show` of its own station works, another's is refused.
- The main checkout, a repo without the Brigade, a nested repo, a `claude --worktree` folder, a non-`station-*` worktree and a `station-9` outside the kitchen → every refusable command passes.
- `git log --grep 'x; git push'`, `grep -rn 'git commit\|git push' plugins`, `kitchen.sh here --note 'done; git push next'`, a heredoc commit message or PR body that names `git push`, `gh pr merge` or `git reset --hard` → pass (quoted text and heredoc bodies are not commands); `sh -c 'git push'`, `bash -c "…; git commit"`, `echo "$(git push origin main)"`, `\git push`, `eval git push`, `sudo -u x git push`, `env -u X git commit`, `timeout 5 git push`, `git push \⏎ origin main` (continuation), `git -C d commit` → found.
- `git merge origin/main`, `pull`, `rebase`, `cherry-pick`, `revert`, `am` → need `commit`; `--ff-only` (merge, pull) and `--abort`/`--quit` pass.
- A Write/Edit/MultiEdit/NotebookEdit to `<station>/.claude/check.log`, `procs`, `served` or under `<main>/.claude/grants/` → refused, also through `..` and a relative path; a Bash command naming the grants folder → refused.
- Unreadable hook input (cut-off JSON, no command, no path) → passes, never crashes.

## Acceptance criteria

- [x] `kitchen.sh grant` writes, replaces, clears and shows; refuses a station, `merge`, an unknown action or station — `tests/kitchen.test.sh` section "grant" (23 tests), `kitchen.sh:2417` (`cmd_grant`)
- [x] `clear` and `done` remove a station's grant, a refused one keeps it — `kitchen.sh:2496`, `:2618`; tests "clear takes the cleared cook's grant away", "…a refused clear leaves the cook's grant", "done takes the ticket's grant away…", "…a refused done leaves…"
- [x] The guard refuses `git commit`, `git push`, `gh pr create` with no grant and passes each with its grant — `tests/guard.test.sh` (419 tests) "no grant" and "with a grant" sections, for a station and a legacy-config station; `guard.sh:84` (`need`), `:119` (`guard_git`)
- [x] Trunk push, force/delete/--all/--mirror/`+` pushes, `gh pr merge`, `reset --hard`, `clean -x/-X` are refused whatever is granted — "refused whatever is granted" section (24 commands per station); `guard.sh:97` (`guard_push`)
- [x] Commits by another route need `commit`; `--ff-only` and `--abort` pass — "commits by another route" and "what passes" sections (the sous's amendment)
- [x] The file tools and Bash cannot write the grants or the receipts — "the grants folder and the receipts" section; `guard.sh:195-215`
- [x] Solo checkout, non-Brigade repo and non-stations are left alone — "left alone outside a station" section (42 tests)
- [x] Every rule goes red without its code — 34 mutations on copies of `guard.sh` and `kitchen.sh`, all red, controls green (journal, "mutations"); two survivors (bare push from trunk; a backslash before a wrapper name) found, their tests fixed, red. The pass's three findings (quotes, continuations, `\git`/`eval`/`sudo -u`) each have tests that fail on the previous guard.sh
- [x] Contract 5 states the grant rule; Contracts 3, 6, 7, 8 and "Hooks that back this up" follow; the skills that said "commit before `[go]`" name the grant — `README.md:595`; a read-only consistency sub-agent's list was fixed (journal, plan Phase 3)
- [x] Works under macOS's bash 3.2 — `tests/guard.test.sh` 347/347 and the grant section 23/23 run with `/bin/bash` 3.2.57
- [x] `kitchen.sh scope` has nothing outside the plan's `files:`; the changelog fragment (`level: minor`) passes `scripts/release-check.sh`
- [x] `scripts/check.sh` green on the final tree — the receipt `kitchen.sh check --receipt` prints (the last act before `[handoff]`; the earlier run was red on one shellcheck warning, fixed)
- [?] The real Claude Code sends the JSON these tests feed (a `Bash` call with `tool_input.command`, an `Edit`/`Write` with `file_path`) — in a throwaway Brigade, start a station session with `claude --plugin-dir ./plugins/bk`, run `git commit -m x` (expect the refusal text), then `kitchen.sh grant station-1 commit` from the main checkout and run it again (expect it to pass). Post-merge, in the real kitchen: the next cook's `[go]` is the live proof
- [?] The Linux (bash 5) and macOS (bash 3.2) CI jobs on the new tests — CI after the PR opens

## Known limitations

- The Bash rules are patterns: `gh api`, a script file that pushes, `ssh host "git push"` and a quoted command not after `sh -c` pass. The header and Contract 5 say guardrail, not wall; the boundary is branch protection and the sous merging.
- `git push` when the station's branch tracks trunk but has another name passes the trunk rule (the target is not named); `push.default` decides what git does.
- A grant is not tied to a ticket id: its life is the ticket's (`[go]` to `[served]`, `done`, `clear`).
- Bash writes to `check.log` / `procs` (a redirect, `sed -i`) are not refused: Edit/Write only, as the sous asked.
- The scanner is not a shell: a heredoc whose delimiter is built by expansion, `$(…)` nested deeper than the quotes it opens in, `source`d scripts and `alias`es are not followed.
- Deviation from the sous's signed call 2 (quotes), settled at the pass: quoted text and heredoc bodies are not commands; `sh -c`/`eval` scripts, `$( )` and backticks in double quotes are read.
