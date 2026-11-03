---
ticket: "#89"
title: kitchen.sh clear passes a served cook on trunk, and no longer trusts a journal's mtime alone
plan: docs/plans/89-clear-served-cook.md
last_verified: 2026-11-03
---

# Acceptance — #89 kitchen.sh clear passes a served cook on trunk

## Contents

- [Flows](#flows)
- [Edge cases](#edge-cases)
- [Acceptance criteria](#acceptance-criteria)
- [Known limitations](#known-limitations)

## Flows

### Served cook, answers the sous's ack, is cleared

1. `kitchen.sh done station-N` after the merge → the station is detached at trunk and `.claude/served` names the ticket and PR.
2. The cook answers the sous's ack (a new turn after its handoff), then `kitchen.sh clear station-N` → `Cleared station-N`: `/clear` then `/bk:line-cook` typed into its pane.

### Mid-ticket cook with a stale handoff

1. A cook on its ticket branch, whose journal's last `## Handoff` is stamped before its last turn, has the journal refreshed by a `git checkout` → `clear` still refuses ("stamped before its last turn").

## Edge cases

- Served but the station has an untracked file → refused.
- Marker names a ticket with no journal (or no `## Handoff`) on trunk → refused.
- No marker (the cook never went through `done`) → the stamp check decides.
- Marker present but the cook is on a new ticket branch → refused.
- A served cook with an unanswered `[gate]` → refused.
- A handoff heading with no stamp (older journal) → judged by its mtime.

## Acceptance criteria

- [x] `clear` passes a cook whose station is clean and detached at trunk, whose ticket's PR `done` recorded, and whose journal on trunk carries a `## Handoff`, whatever its last turn — `tests/kitchen.test.sh` "clear clears a served cook on trunk, whatever its last turn" passes (red against origin/main's kitchen.sh)
- [x] the mtime is not the only proof — `kitchen.sh:2522-2528` (the handoff's own stamp decides; the mtime is the fallback for an unstamped heading); tests "clear refuses an old handoff whose journal was touched after the last turn (a checkout), by its own stamp" and "clear refuses an unstamped handoff whose mtime is older…" / "…and clears one whose mtime is newer" pass
- [x] a mid-ticket cook with an old handoff is still refused — "clear refuses a handoff stamped before the cook's last turn" and "clear refuses a cook on a new ticket branch even with the marker still there" pass
- [x] a served cook waiting on an answer is still refused — "…but not one still waiting on an answer" passes
- [x] `done` leaves the marker, kept out of git — "done leaves a marker of what it served" and "…kept out of git" pass
- [x] each new case can fail — 11 tests red with origin/main's kitchen.sh in place; the dirty and new-branch cases red when `served_handoff`'s status / branch check is removed
- [x] a trunk journal with only the template's commented `## Handoff` is no handoff — `has_handoff` (kitchen.sh), test "clear refuses a served cook whose journal on trunk only holds the template's commented handoff" passes (red on the code before the fix)
- [x] a changelog.d fragment, `level: patch` — `changelog.d/89-clear-served-cook.md:1`
- [x] the contract and skills agree — `plugins/bk/skills/README.md:802` (Contract 5) and the kitchen, sous-chef, line-cook skills and PLAYBOOK carry the same served-cook rule; `git grep "newer than its last turn"` lists no place without it
- [x] the plan's files are all it touched — `kitchen.sh scope`: outside (0)
- [x] `kitchen.sh check` is green for this tree — "check: green"
- [?] a real kitchen: after the next `ship` → `done` → ack, `kitchen.sh clear station-N` clears the cook — run it on the next served ticket after release (the sous's installed plugin is the released copy, not this one)

## Known limitations

- The marker is only written by `done`: a cook cleared before `done` runs takes the stamp path (handoff newer than its last turn), as before.
- An abandoned ticket leaves its marker; `clear` trusts it only while the station is clean and detached at trunk and that ticket's handoff is on trunk, and the next `done` overwrites it.
- A handoff's stamp is minute-precision: a 59 s slack applies.
