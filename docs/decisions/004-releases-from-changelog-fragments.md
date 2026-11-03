---
type: adr
title: Cooks never bump the version; changelog fragments, and one release PR assigns it
status: accepted
date: 2026-11-03
source: ask A6 (#64)
supersedes: null
---

# 004 — Cooks never bump the version; changelog fragments, and one release PR assigns it

## Question

#64: every merge to main was a release, so every cook PR re-bumped its version each time main moved. `main` enforces admins with no push exceptions, so `release.yml` cannot stamp an `## [Unreleased]` section. How is the version assigned?

## Head chef said

> Approve (Recommended): Fragments + release.sh release PR; no more re-bump rounds.

## Decision

A cook PR that changes more than `docs/` adds `changelog.d/<id>-<slug>.md` (`level: minor|patch` plus the changelog paragraph) and never touches `plugin.json`, `CHANGELOG.md` or the Formula. `scripts/release.sh` builds one release PR from main's fragments, and that PR assigns the version. A docs-only PR needs nothing. "Every merge to main is a release" becomes "every merge of a release PR is".

## Why

It ends the re-bump rounds (#62, #63 and #19 each paid at least one). Batched releases are the price. The plugin cache is keyed on the version, so users get changes at release time.

## Applies to

This repo's release process (`AGENTS.md` Releasing, `scripts/`, `release.yml`), as built in #64. The plugin's record-PR behaviour is in Contract 12.
