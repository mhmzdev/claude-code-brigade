level: patch

`kitchen.sh clear` now clears a cook that has been served and merged, however many acks it
answered after its handoff: `kitchen.sh done` records what it served, and a clean station
detached at trunk whose ticket's journal on trunk carries a `## Handoff` is cleared without a
newer one. A cook mid-ticket is judged by the handoff's own `## Handoff — YYYY-MM-DD HH:MM`
stamp (a `git checkout` of the journal no longer passes a stale handoff), and `clear` looks at
the branch ticket's own journal first. You don't need to do anything.
