---
# flat — read by kitchen.sh too
trunk: main
check: "scripts/check.sh"
install: ""
copy_into_stations: ""
kitchen_mode: worktree
permission_mode: auto
sous_model: opus
stations: 2
migrations: none
commis_model: opus

# nested — read by skills
rail:
  adapter: github
  commit: direct
  github: { owner: mhmzdev, project: 4, status_field: Status }
walk_in:
  - name: window-port-4747
    destructive: ["kitchen.sh live", "bk live"]
    safe: ["node plugins/bk/window/server/index.js --demo --port 4748"]
gates:
  assign: sous-chef
  plan_approval:
    feature: head-chef
    bug: sous-chef
    chore: sous-chef
    precedent: sous-chef
    hygiene: sous-chef
  pre_commit: sous-chef
  merge: head-chef
  deploy: head-chef
clean:
  counters:
    - name: shellcheck-info
      command: "shellcheck -S info -f gcc plugins/bk/skills/kitchen/kitchen.sh plugins/bk/hooks/guard.sh bin/bk"
    - name: todo-comments
      command: "git grep -n -E 'TODO|FIXME' -- ':!docs' ':!CHANGELOG.md'"
  umbrella: null
prices:
budget:
docs:
  specs: docs/specs
  backlog: none
  plans: docs/plans
  checklists: docs/checklists
  journal: docs/journal
  lessons: docs/lessons.md
  research: docs/research
  brainstorm: docs/brainstorm
  decisions: docs/decisions
  conventions: docs/conventions
  knowledge: docs/knowledge
  questions: docs/questions
---
This repo is the Brigade plugin itself, worked on by the Brigade (dogfooding). Read
`CLAUDE.md` first: the contract in `plugins/bk/skills/README.md` is the source of truth,
every PR bumps the version and adds a changelog entry, and `scripts/check.sh` is the gate.

The rail is the GitHub Project "Brigade: claude-code-brigade" (number 4) on the repo's
issues. Status mapping: backlog → Backlog, todo → Todo, in-progress → In Progress,
rfr → Ready for review, blocked → Blocked, done → Done. Lanes are labels (`lane:A`,
`lane:B`, `lane:C`); a backlog item's kind is a label (`bug`, `chore`, `precedent`; no
label means an item that needs a spec); `priority:high` is the head chef's word. Ticket
ids are issue numbers (`#28`); branches are `issue-28-<slug>`.

The sessions a cook or the sous runs are the plugin in **this checkout** (`./bin/bk open`
loads it with `--plugin-dir`), not the installed copy: editing a skill in a station changes
nothing for the sessions already running. The Window on port 4747 is the head chef's own;
anything that needs a Window runs the demo on 4748.

`docs/the-names.md` is a hand-written doc, not part of the kitchen's map; leave it be.
