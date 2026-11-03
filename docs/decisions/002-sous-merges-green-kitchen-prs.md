---
type: adr
title: The sous merges a kitchen PR that passed its pass, is green, mergeable and up to date
status: accepted
date: 2026-11-03
source: head chef, sous session 2026-11-03 (inbox 13:30; also 12:34 and 12:46)
supersedes: docs/decisions/001-kitchen-prs-merge-first.md
---

# 002 — The sous merges a kitchen PR that passed its pass, is green, mergeable and up to date

## Question

Under decision 001, LGTM'd kitchen PRs waited for the head chef to merge them. On 2026-11-03 the head chef merged their own #74 ahead of #73 and #63, and each wait cost the cooks another bring-main-in and re-bump round. Who merges a kitchen PR, and when?

## Head chef said

> new standing rule, record it as a decision. A kitchen PR that has passed your pass, is green on CI, mergeable and up to date with main is yours to merge (gh pr merge <N> --merge), right after the [served]; don't wait for me. If something breaks on main, that's the next ticket: brief a cook at once. I'm filing it and building kitchen.sh ship <PR> so the checks are mechanical; until it lands, do it by hand with gh. If the merge asks for a permission in your pane, tell me.

## Decision

Right after a cook's `[served]`, the sous merges the PR with `gh pr merge <N> --merge` if all four hold: it passed the sous's pass, both CI jobs are green, GitHub calls it mergeable, and it contains every `origin/main` commit. A break on main becomes the next ticket, and a cook is briefed at once. The head chef merges their own PRs.

## Why

Waiting for a human merge was the main cause of re-bump rounds. The four checks are mechanical, so they need no human judgement.

## Applies to

Kitchen PRs in this repo. It supersedes 001 (merge order) and the head chef's 2026-11-03 12:46 instruction ("tell me and I merge"). `kitchen.sh ship <PR>`, when it lands, does the same checks.
