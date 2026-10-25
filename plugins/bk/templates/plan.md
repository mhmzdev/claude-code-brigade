---
ticket: <ID>
title: <one line>
lane: B                # A | B (lane C tickets have no plan)
status: draft          # draft | approved | active | done — /bk:implement sets approved on the chef's sign-off
approved: null         # YYYY-MM-DD, set by /bk:implement once the chef's sign-off is there
open_questions: none   # must be "none" before implement will start
migration: false       # true if any phase adds one
files: []              # every path the plan touches
created: YYYY-MM-DD
---

# Plan — <ID> <title>

## Contents

- [Goal](#goal)
- [Current state](#current-state)
- [Approach](#approach)
- [Protected paths](#protected-paths)
- [Phases](#phases)
- [Success criteria](#success-criteria)
- [Risks](#risks)

## Goal

<One paragraph: what's true when this ships.>

## Current state

<How the code works today, with file:line references.>

## Approach

<The chosen design, and the alternative it beat.>

## Protected paths

<!-- Delete this section (and its Contents line) when `files:` lists no protected path (Contract 5). -->

<Each protected path (Contract 5) this plan edits, and the phase that edits it, last when the order allows. Auto mode will refuse the edit; the head chef lifts it at the station.>

## Phases

### Phase 1 — <name>

- <change> — `path/to/file`
- Check: `<check>` passes

## Success criteria

- [ ] <outcome, checkable>

## Risks

- <risk> → <mitigation>
