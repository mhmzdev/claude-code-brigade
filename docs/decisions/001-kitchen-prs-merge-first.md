---
type: adr
title: A served kitchen PR merges before the head chef's own next PR
status: accepted
date: 2026-10-25
source: ask A2 (sous, 2026-10-25)
supersedes: null
---

# 001 — A served kitchen PR merges before the head chef's own next PR

## Question

The head chef's own PRs (#49, #54, #55, #56) merged while the kitchen's LGTM'd PRs (#52, #53)
waited, and each took the next patch version. Every time, the cooks had to bring main in
again and bump the version again (#52 went from 0.27.4 to 0.27.9). Asked by the sous: hold
your own merges while a kitchen PR is ready, have cooks leave version headroom, or warn
before yours?

## Head chef said

> Kitchen PRs merge first (the option the sous recommended, chosen 2026-10-25)

## Decision

When the sous says a kitchen PR has its LGTM and green CI, the head chef merges it before
merging their own next PR. The sous says so the moment one is ready, and names the merge
order when several are.

## Why

Every PR bumps the version (AGENTS.md, "Releasing"), so any merge invalidates the version of
every open PR. A cook's re-merge and re-bump costs a round of the cook, the sous and CI, and
the cook can't be cleared meanwhile. The head chef's own PRs are the ones they can hold.

## Applies to

This repo, wherever the head chef merges their own PRs alongside the kitchen's. It doesn't
stop the head chef merging an urgent fix of their own; it means telling the sous, so the
cooks re-merge straight after.
