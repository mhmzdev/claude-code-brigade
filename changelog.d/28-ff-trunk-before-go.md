level: patch

When trunk moves while a cook has nothing committed yet, the skills now say what to do: the sous
doesn't ask for a trunk merge before `[go]` (the pass reads the merge base and `/bk:open-pr` brings
trunk in), and if it does ask, the cook uses `git merge --ff-only`, with a stash recipe for files
that clash. A plain merge or pull before `[go]` is a commit by another route and needs the grant.
Nothing for you to do.
