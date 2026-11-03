---
type: adr
title: After a ticket ships the sous runs ship → done → reap → clear; stations are worktrees only
status: accepted
date: 2026-11-03
source: head chef 2026-11-03 (inbox; #85, #86 as filed)
supersedes: null
---

# 006 — After a ticket ships the sous runs ship → done → reap → clear; stations are worktrees only

## Question

What does the sous do when a cook's PR is served, and what happens to the station and the processes it started?

## Head chef said

> after a cook's [served] and the sous's LGTM, wait for CI (gh pr checks N --watch via the runner), run kitchen.sh ship N, then kitchen.sh clear <station> (gates.merge: sous-chef).

> #86 kitchen.sh procs: cooks register every background process they start; the sous reaps registered ones after ship and before clear; scan is report-only; never kill a system or unknown process; handoffs carry the list.

> #85 worktrees only: drop clone mode; when a ticket is done delete its branch and reset the station; the worktree folder stays (the cook lives in it); breaking for clone kitchens, say so in the fragment.

## Decision

After `[served]` and the LGTM, the sous waits for CI, then runs `kitchen.sh ship <PR>`, `kitchen.sh done <station>` (branch deleted locally and on origin only at the merged PR's head; the station detached at trunk), `kitchen.sh procs --reap <station>` (only registered processes whose identity still matches), and `kitchen.sh clear <station>`. Stations are git worktrees only. The kitchen kills only processes it registered, never a system or unknown one; the scan reports.

## Why

The machine stays healthy, the next cook starts on a clean station, and nothing the kitchen didn't start is ever touched.

## Applies to

Contract 5 (End of shift), Contract 7 (processes), Contract 8 (one station mode); built in #85, #86, #89.
