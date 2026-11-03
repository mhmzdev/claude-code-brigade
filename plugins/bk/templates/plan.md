---
ticket: <ID>
title: <one line>
lane: B                # A | B (lane C tickets have no plan)
status: draft          # draft | approved | active | done — /bk:implement sets approved on the chef's sign-off
approved: null         # YYYY-MM-DD, set by /bk:implement once the chef's sign-off is there
open_questions: none   # must be "none" before implement will start
migration: false       # true if any phase adds one
files: []              # every path the plan touches: the ticket's write scope, which the pass enforces (kitchen.sh scope). Exact paths, globs, or a folder/
created: YYYY-MM-DD
---

# Plan — <ID> <title>

## Contents

- [Goal](#goal)
- [Current state](#current-state)
- [Approach](#approach)
- [Decisions](#decisions)
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

## Decisions

### Changes the ticket

<!-- A choice that alters what the ticket delivers (scope against its Done when, user-visible behaviour, a contract rule, a schema, a name people already type, a cost) or contradicts the record. The head chef's, whatever the kind (Contract 5). "None" is the usual answer. One line each: the ticket says … · the plan does … · because …. -->

None.

### How

<!-- Every other choice: what a new thing is called, columns, order, which function, which file. The sous's to sign for a bug, chore or precedent plan; written here, it becomes the record. A decision the commis found settled cites its source. -->

- <choice> — <why>, or `settled in <path>`

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
