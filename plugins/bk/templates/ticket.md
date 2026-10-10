---
id: BKLG-NNN           # SNNN-NN (lane A) | BKLG-NNN (lane B) | HYG-NNN (lane C)
title: <one line>
lane: B                # A | B | C
status: backlog        # backlog | todo | in-progress | rfr | done | blocked
cook: null             # station name once claimed
spec: null             # lane A: the parent spec. BKLG: the spec it became
blocked_by: []         # ticket ids
files: []              # paths it will likely touch
created: YYYY-MM-DD
---

# <ID> — <title>

## Why

<The problem, in plain words. Who notices, and what changes once it's done.>

## Done when

<!-- A backlog item that needs a spec leaves this section out: the spec's tickets carry it. -->

- [ ] <observable outcome>
- [ ] `<check>` passes

## Notes

<Prior art, links, constraints. For HYG tickets: the exact findings list, file:line each.>
