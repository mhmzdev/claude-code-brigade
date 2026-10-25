---
id: BKLG-NNN           # SNNN-NN (lane A) | BKLG-NNN (lane B) | HYG-NNN (lane C)
title: <one line>
lane: B                # A | B | C
status: backlog        # backlog | todo | in-progress | rfr | done | blocked
cook: null             # station name once claimed
kind: item             # BKLG only: item (becomes a spec and tickets) | bug | chore | precedent (all three planned and built directly)
precedent: []          # kind: precedent only: the instances in the code it follows (paths), two at least
precedent_why: null    # kind: precedent only: where the record says why the pattern exists
spec: null             # lane A: the parent spec. BKLG: the spec it became
priority: normal       # high | normal | low
blocked_by: []         # ticket ids
files: []              # paths it will likely touch
created: YYYY-MM-DD
---

# <ID> — <title>

## Why

<The problem, in plain words. Who notices, and what changes once it's done.>

## Done when

<!-- A backlog item of kind: item leaves this section out: the spec's tickets carry it. A bug, a chore and a precedent keep it. -->

- [ ] <observable outcome>
- [ ] `<check>` passes

## Notes

<Prior art, links, constraints. For HYG tickets: the exact findings list, file:line each. For a precedent: how the instances agree, and what this one adds.>
