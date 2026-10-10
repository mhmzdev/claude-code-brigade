# Brigade: machine-local notes

<!-- Gitignored. Never committed, never pasted into a message, journal, plan, checklist,
     ticket or PR: those refer to an account by its NAME only (Contract 2). -->

## Test accounts

<!-- One block per account, under its environment. The name is what sessions quote.

- **<name>** — <what it is for: role, tenant, what data it has>
  - url: <where to sign in>
  - login: <email, phone or username>
  - password: <the value alone on this line; same for code: token: secret:>
  - notes: <anything in words: how to get a one-time code, limits such as
    "shared with QA, don't change its profile">

Put each secret alone on a password: / code: / token: / secret: line. Those lines are what
`kitchen.sh leaks` searches for, so a secret written inside a sentence isn't protected.
A login the repo already commits (local seed users) needs no secret here: point at the doc.
-->

### local

### stage

### production

<!-- Test accounts only, never a real user's. Reading is fine; any action that writes needs
     the head chef's yes for that exact action. -->

## Other local notes

<!-- Ports, tracker CLI names, anything else that belongs to this machine. -->
