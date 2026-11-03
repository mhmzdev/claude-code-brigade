# changelog.d

One file per change that is waiting for a release, written by the PR that makes it:
`<id>-<slug>.md`. The first line is `level: minor` (a change in how a kitchen runs) or
`level: patch` (a fix, or a change that doesn't touch the plugin's behaviour); then a blank
line; then the paragraph for the busy human (what changed for them, and what they must do).

A PR never bumps the version and never writes a `## [x.y.z]` entry: `scripts/release.sh` opens
the release PR that collects every fragment into one entry, bumps the version and deletes them.
A PR that changes only `docs/` carries no fragment. See `AGENTS.md`, "Releasing".
