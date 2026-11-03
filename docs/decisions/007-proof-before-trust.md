---
type: adr
title: The pass trusts artefacts, not words: gate receipts, grants for outward actions, the plan's files as write scope, file-backed approvals
status: accepted
date: 2026-11-03
source: head chef 2026-11-03 (inbox; #90, #91, #92 as filed); asks A10, A11, A12
supersedes: null
---

# 007 — The pass trusts artefacts, not words

## Question

After comparing the Brigade with the PROOF pack, which of its guarantees does the kitchen adopt, and how far do head-chef approvals go?

## Head chef said

> #90 gate receipts: kitchen.sh check writes a receipt per run; the taster and open-pr trust the receipt.

> #91 positive authorization: kitchen.sh grant: commit/push/open-pr granted with the sous's [go], enforced by the guard; replaces the Bash blocklist part of #69.

> #92 write scope: plan files enforced at the pass, kitchen.sh scope, overlap report.

> (A10) Cook-proof now (file the UserPromptSubmit hook as its own ticket). (A11) Allow setup + approve. (A12) Accept.

## Decision

- A check's proof is its receipt (tree, command, exit, output digest, config line); nobody's word stands in for it.
- A cook's commit, push and PR need a grant the sous writes with `[go]`; merge is never granted.
- A plan's `files:` is the ticket's write scope; a path outside it is a finding, and overlapping scopes don't build at once.
- Feature approvals (#70) are written by the human-only `/bk:approve` into a file cooks can't write; `approve` is the second skill allowed `disable-model-invocation` beside `setup`. Approvals are cook-proof, not yet sous-proof (#103). Walk-in and production-write plans are caught through `signer: head-chef` or the sous's `[approved]`.

## Why

PROOF's rule: "this step is not done when you say so". Each artefact is something a model can't produce by asserting it.

## Applies to

Contracts 4, 5, 8; built in #90, #91, #92; #70 and #103 to come.
