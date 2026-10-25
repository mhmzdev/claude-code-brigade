---
ticket: "#19"
plan: docs/plans/gh-19-claude-dir-edits.md
last_verified: 2026-10-25
---

# Acceptance — #19 A plan that edits .claude/ is seen coming, and a denied edit is a gate, never a workaround

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

### A plan edits `.claude/`

1. The cook writes `files:` with a path under `.claude/` → `create-plan` has it check every path against Contract 5, add a "Protected paths" section and list the paths in `[plan]`.
2. The sous reads the plan → it goes to the head chef whatever the kind, with the station, the phase and what they will do there.
3. The cook reaches the edit and is refused → it sends `[gate] <ID> edit denied: <path>, …` and waits.
4. The head chef edits in that cook's terminal, or moves that session to a mode that prompts → the sous sends `[heard]`, the cook checks the edit is in and goes on.

## Edge cases

- The sous is asked to make the refused edit, or to relay "yes" in its place → Contract 5 and the sous skill say it never does either.
- The cook thinks of `sed -i`, a redirect, `cp`, `git apply` or a sub-agent → refused by name in Contract 5; line-cook "Things you never do" repeats it.
- A plan edits `.claude/worktrees/` only → not protected (Contract 5 excepts it).
- A solo session is refused → `implement` says so and stops.

## Acceptance criteria

- [x] The contract defines protected paths once and lists them — `plugins/bk/skills/README.md:494-499`
- [x] A protected-path plan is the head chef's for every kind — `plugins/bk/skills/README.md:470`, `:520` (sign-off cell), `plugins/bk/skills/sous-chef/SKILL.md:290`, `plugins/bk/skills/line-cook/SKILL.md:120`, `plugins/bk/skills/create-plan/SKILL.md:151`, `PLAYBOOK.md:219`, `:242`
- [x] The denied-edit gate is defined: form, no commis, no `Qn`, never worked around, head chef lifts it, sous sends `[heard]` — `plugins/bk/skills/README.md:504-512`, table row `:531`, Contract 6 `:559`
- [x] `create-plan` makes the cook check, write the section and say so in `[plan]` — `plugins/bk/skills/create-plan/SKILL.md:114`, `:133`, `:142`, `:147`; template `plugins/bk/templates/plan.md:20`, `:37`
- [x] The cook's skills carry the rule — `plugins/bk/skills/line-cook/SKILL.md:110`, `:126`, never-do bullet; `plugins/bk/skills/implement/SKILL.md:103`
- [x] The sous skill says how to show the head chef the plan, and how to answer the gate — `plugins/bk/skills/sous-chef/SKILL.md:307`, `:328`, pointer `:242`
- [x] Wording that said "only a grilling" is brought into line (cleared by the sous) — `plugins/bk/skills/sous-chef/SKILL.md:46`, brief `:184-187`, `plugins/bk/skills/setup/SKILL.md:208-216`, `plugins/bk/skills/line-cook/SKILL.md:15-18`, `PLAYBOOK.md`, `README.md`
- [x] The head chef reads the same thing — `README.md:266`, `PLAYBOOK.md:224`, `:483`, `:489`
- [x] No code changed — `git diff origin/main --stat -- plugins/bk/hooks plugins/bk/skills/kitchen/kitchen.sh bin` prints nothing
- [x] The gate is green — `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh`: kitchen 270/270, guard 27/27, bk 82/82, budget 70/70, manifests, shellcheck, version 0.28.0 above origin/main's 0.27.4. Without the unsets, 7 kitchen tests fail on this machine, and the same 7 fail on a clean `origin/main` (#50)
- [x] The consistency sweep (fresh read-only agent) found nothing left that disagrees, apart from the Window panel text and two edge cases listed below — journal
- [?] A live sous shows a protected-path plan to the head chef with station and phase — run: in a throwaway repo, `./bin/bk open` from this checkout, give a cook a bug ticket whose plan edits `.claude/skills/x/SKILL.md`; expect the sous to ask the head chef, not sign itself
- [?] Auto mode refuses the edit and the cook sends `edit denied` and waits — same session: expect `[gate] <ID> edit denied: <path>, …` and no `sed -i` or redirect attempt
- [?] The root `CLAUDE.md` is refused in auto mode — assumed from the ticket, not on Claude Code's protected list (plan Decision 3); if it never is, the flag costs one head-chef line and is one line to drop

## Known limitations

- The Window's Head Chef panel still says "Talk to the sous only" (`plugins/bk/window/web/scene.js:31`). The sous is filing a follow-up.
- `guard.sh` would refuse an `edit denied` gate whose path contains a `Q1`-style token, for lacking `commis:` (`plugins/bk/hooks/guard.sh:78`). Rare; a follow-up.
- The `[heard]` that follows a lift carries no `(head chef)` tag, so the budget counts that ask as the sous's (`plugins/bk/window/server/live/budget.js:140`, `:237`). A follow-up.
- Nothing is added mechanically (no seeded permission, no `kitchen.sh` marker): an allow rule can't lift protected paths (plan Decision 1).
