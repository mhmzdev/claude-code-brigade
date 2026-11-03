level: minor

**The record reaches a protected trunk, and a release is its own PR.** Two things stopped the
kitchen on a protected `main`. The sous's record (decisions, the lessons register, question
files) could not be pushed, so it sat on a local branch and `kitchen.sh lessons` and `debrief`
kept calling filed lessons due. And every PR had to carry a higher version than `main`, so each
time `main` moved a cook re-bumped, and a docs-only change needed a release. Now the sous's
handoff files the record with `kitchen.sh record-pr`: it goes to trunk when trunk takes it, else
into a `record/<date>` PR, and `lessons`, `decisions`, `questions`, `gaps` and `debrief` read an
open record branch like trunk. In this repo a PR that changes only `docs/` needs no release; any
other PR adds a `changelog.d/<id>-<slug>.md` fragment and leaves the version alone; and one
release PR, opened by `scripts/release.sh`, gives every waiting change its version. What you must
do: merge cook PRs as before, and when you want to ship, ask the sous to run
`scripts/release.sh`, then merge that PR (it is the release). A PR open when this lands drops its
version bump and adds a fragment once; the gate's message says how. Restart your sessions to load
the new skills.
