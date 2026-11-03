level: minor

**A cook's uncommitted work now has a copy that is not a commit.** Nothing is committed before the
sous's `[go]`, so a ticket's whole tree used to live in one folder for hours: remove or reset the
station and it was gone. `kitchen.sh checkpoint` now saves it to `refs/brigade/<station>/<ticket>`
(the branch, the index and the files are not touched), `implement` does it after each phase,
`review-task` and the handoff at their end, and `kitchen.sh restore` puts it back on a clean
station. The taster reads the diff from that copy and refuses a station that has changed since it.
`sync` says which clean stations still hold one, and `done` drops it once the PR is merged. It
lives in the repo, so it survives a removed station, not a lost disk. What you must do: nothing; the
skills call it.
