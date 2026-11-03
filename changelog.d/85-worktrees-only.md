level: minor

**Breaking for kitchens on `kitchen_mode: clone`: stations are git worktrees only.** The clone mode
is gone, so every path, test and contract rule exists once. A station is a worktree of the main
checkout at `../<repo>-stations/station-N`, next to the repo; its work is ephemeral. After the sous
merges a PR it runs the new `kitchen.sh done <station>`: it checks through the PR that the branch is
merged into trunk (and that the station holds nothing the PR doesn't), detaches the station at trunk,
and deletes the ticket branch locally and on origin, the origin one only while it is still at the PR's head; the folder and the cook's session stay. End of shift
is now `ship`, `done`, the reap, `clear`, and `done` says in one line what it did and did not delete.
What you must do: on a clone kitchen, `kitchen.sh` now stops with one line. Push or park any
unpushed work in `stations/`, run `kitchen.sh remove`, delete the `kitchen_mode` line from
`.claude/brigade.md`, then run `kitchen.sh setup`. A worktree kitchen needs nothing: a
`kitchen_mode: worktree` line is ignored, and you can delete it.
