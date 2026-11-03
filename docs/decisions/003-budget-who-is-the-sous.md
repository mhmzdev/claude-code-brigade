---
type: adr
title: In the budget, the sous is the named live session plus any transcript that sent a sous-only message
status: accepted
date: 2026-11-03
source: ask A3, ask A5 (#62)
supersedes: null
---

# 003 — In the budget, the sous is the named live session plus any transcript that sent a sous-only message

## Question

#62: transcripts carry no session name, and `.claude/sous` holds only the current name. How does the budget tell a past sous conversation from the head chef's own sessions in the main checkout?

## Head chef said

> B: name + sous messages (Recommended)

Then, on the plan: "Approve", covering its three choices.

## Decision

A main-checkout session is the sous if it is the live session named in `.claude/sous` (or, when no name is recorded, the newest live one, as the Window picks), or if it sent a sous-only message (`[brief]`, `[hello]`, `[go]`, `[approved]`, `[findings]`). Every other main-checkout session is `head chef`. A recorded name that no live session carries gets no fallback. The head chef's sessions sit outside the kitchen's spend, on their own line, and the debrief's `context-bloat` rule skips them.

## Why

The name alone would bill a sous's past conversations, before a `/clear` or on an earlier shift, to the head chef: the bug in reverse. A fallback for a dead name would bill a head chef session open while the sous is down as the sous.

## Applies to

`window/server/live/budget.js`, the Ledger, the debrief (shipped in 0.29.1, PR #73).
