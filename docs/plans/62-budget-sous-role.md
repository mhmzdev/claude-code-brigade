---
ticket: "#62"
title: The budget counts only the real sous as the sous; the head chef's sessions are their own rows
status: done
approved: 2026-11-03
lane: B
created: 2026-11-03
open_questions: none
migration: false
files:
  - plugins/bk/window/server/live/budget.js
  - plugins/bk/window/web/ledger.js
  - tests/budget.test.sh
  - plugins/bk/skills/README.md
  - plugins/bk/.claude-plugin/plugin.json
  - Formula/bk.rb
  - CHANGELOG.md
  - docs/plans/INDEX.md
  - docs/journal/62-budget-sous-role.md
---

# #62 — The budget counts only the real sous as the sous

## Why

On the 2026-10-25 shift the budget billed $106 of the head chef's own sessions in the main
checkout to the sous, and three of the five `context-bloat` hits in the debrief were those
sessions. `kitchenTranscripts` tags every main-checkout transcript `sous`, with no look at
`.claude/sous`. Everything else in EPIC #71 reads the budget, so this goes first.

## Current state

- `plugins/bk/window/server/live/budget.js:164-176` `kitchenTranscripts`: `places = [[root, 'sous'], …stations]`,
  so every transcript under the main checkout's project folder gets `role: 'sous'`.
- `budget.js:196` `session()` copies that role onto the session; `budget.js:319` is the only
  caller. Nothing reads `.claude/sous` or the live session registry.
- Consumers of the role, all in `budget.js`:
  - `:325` every non-`sous` session is a cook and gets ticket spans;
  - `:327` the sous's helpers that name a ticket (the taster) join that ticket;
  - `:332-333` the shift sums every session; `:337-338` per-actor totals are keyed by role;
  - `:339-340` `sousNow` (the newest `sous` session) starts the shift window;
  - `:399-400` the debrief's session rules, hit id `${role} ${hh:mm}`;
  - `:473` the CLI prints `role` in the Sessions table.
- The Window already does it right for live sessions: `live/index.js:26,37-41` reads `.claude/sous`
  (`cfg.sousNameFile`, `config.js:47`) and takes the live main-checkout session of that name, else the newest.
  That pick is not shared with the budget, and it only ever sees live sessions.
- A transcript carries no session name. Only the registry file `<config>/sessions/<pid>.json`
  (`name`, `sessionId`, `cwd`, `pid`) maps a name to a conversation, and only while the process lives.
- `plugins/bk/window/web/ledger.js:14-15` `markOf`/`nameOf` know `sous` and `station-N`;
  `:26-33` `split()` and `:36-37` the summary derive the Kitchen overhead as sessions' cost minus tickets' cost,
  so a head-chef session would land in "Kitchen: the sous, and work no ticket claims".
- `kitchen.sh budget` and `debrief` (`kitchen.sh:1456-1490`) only run `budget.js`; they need no change.

## Desired end state

- A main-checkout transcript is `sous` only if (head chef's decision, Decisions A1):
  1. it is the conversation of the live session named in `.claude/sous` (the registry maps name → sessionId);
  2. or no name is recorded and it is the newest live main-checkout session (the Window's own fallback);
  3. or it sent a message only a sous sends (`[brief]`, `[hello]`, `[go]`, `[approved]`, `[findings]`),
     which keeps a past shift's sous and a sous's earlier conversations before a `/clear` the sous's.
- Every other main-checkout transcript has role `head chef`.
- `kitchen.sh budget`, `--json` and the Ledger list `head chef` rows apart; the shift's spend and
  the Ledger's Kitchen overhead no longer include them; they get their own line.
- The debrief's `context-bloat` rule skips `head chef` sessions: its fix ("the sous or a cook hands off and clears sooner")
  is not the human's to apply.
- Verify: `tests/budget.test.sh` has a case with two main-checkout transcripts, one named in
  `.claude/sous`, that attributes only that one to the sous, and goes red against the old `kitchenTranscripts`.

## Not doing

- No change to `live/sessions.js` or `live/index.js`: the Window's own pick of the sous is right for live sessions.
  The budget gets its own small registry read in `budget.js` (the two files stay independent today, and `sessions.js` starts a watcher).
- No change to `kitchen.sh`: station-2 is editing it for #63; the budget and debrief commands only call `budget.js`.
- No change to Contract 12, the record-writing skills or anything of #63's.
- No new ledger fields in `.claude/budget.jsonl`: ticket lines are cook spans and never carried the sous's role.
- No price or phase changes.

## Approach

Classify at the one place that sees both the registry and the scanned transcript: `session()` in
`budget.js`. `kitchenTranscripts` returns `role: 'main'` for the main checkout's transcripts
(stations unchanged); `session()` resolves `'main'` to `'sous'` or `'head chef'` after scanning, because
rule 3 needs the transcript's own messages (`st.marks`, already collected for every session).
The recorded name and the live sessions are read once per `compute()`, not per transcript.
This mirrors the Window's rule (`live/index.js:37-41`) and adds only the behavioural test A1 asks for.

Interpretation to flag: a **recorded name that no live session carries** gets no "newest" fallback
(the ticket says the fallback is for "no name recorded"); dead sessions are then sous only by rule 3.
Otherwise a head-chef session open while the sous is down would be billed as the sous, which is this bug again.

## Phase 1: Classify main-checkout transcripts

**Status:** Done

### Changes

#### `plugins/bk/window/server/live/budget.js:164-176` (edit) — `kitchenTranscripts`

The main checkout's transcripts come out with a placeholder role the budget resolves later:

```js
const places = [[root, 'main'], ...stations.map((d) => [d, path.basename(d)])];
```

Update the doc comment above it: `role` is `main` for the main checkout until `session()` resolves it.

#### `plugins/bk/window/server/live/budget.js` after `kitchenTranscripts` (new code)

```js
// ---------- who in the main checkout is the sous ----------
// The main checkout holds the sous and, often, the head chef's own sessions. A transcript has no
// session name; the live registry (<config>/sessions/<pid>.json) maps name → sessionId while the
// process lives. The sous is: the live session named in .claude/sous, else (with no name recorded)
// the newest live one, as the Window picks (live/index.js); and any transcript that sent a message
// only a sous sends, which keeps a past shift's sous (and a sous before a /clear) the sous's.
// Every other main-checkout session is the head chef's.
export const HEAD_CHEF = 'head chef';
export const SOUS_ONLY = new Set(['brief', 'hello', 'go', 'approved', 'findings']);
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; } };
export function sousSessionId(root) {
  let recorded = ''; try { recorded = fs.readFileSync(path.join(root, '.claude', 'sous'), 'utf8').trim(); } catch { /* none recorded */ }
  const dir = path.join(configDir(), 'sessions'), rootReal = realpath(root), live = [];
  let files = []; try { files = fs.readdirSync(dir).filter((f) => f.endsWith('.json')); } catch { /* no sessions */ }
  for (const f of files) {
    let s; try { s = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')); } catch { continue; }
    if (s.cwd && s.sessionId && s.pid && alive(s.pid) && realpath(s.cwd) === rootReal) live.push(s);
  }
  if (recorded) return live.find((s) => s.name === recorded)?.sessionId || null;
  return live.sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))[0]?.sessionId || null;
}
```

#### `plugins/bk/window/server/live/budget.js:196` (edit) — `session()`

`session()` gains the resolved id from a closure variable set once per `compute()`:

```js
let sousId = null;   // the live sous's sessionId, read once per compute()
// …
function session({ file, dir, role, sessionId }) {
  const st = scanTranscript(file, states.get(file)); states.set(file, st);
  if (role === 'main') role = sessionId === sousId || st.marks.some((m) => m.dir === 'out' && SOUS_ONLY.has(m.kind)) ? 'sous' : HEAD_CHEF;
  …
```

#### `plugins/bk/window/server/live/budget.js:319` (edit) — `compute()`

```js
sousId = sousSessionId(root);
const all = kitchenTranscripts({ root, stations: stations() }).map(session);
```

#### `plugins/bk/window/server/live/budget.js:325` (edit) — cook spans skip the head chef

```js
for (const s of all) if (s.role !== 'sous' && s.role !== HEAD_CHEF) for (const sp of spans(s)) { … }
```

#### `plugins/bk/window/server/live/budget.js:332-333` (edit) — the shift is the kitchen's

`shift` sums `sessions` without the head chef's; a new `headChef` figure carries theirs:

```js
const kitchen = sessions.filter((s) => s.role !== HEAD_CHEF), chef = sessions.filter((s) => s.role === HEAD_CHEF);
for (const s of kitchen) { …same sums… }
…
return { …, shift, headChef: { sessions: chef.length, cost: round(chef.reduce((a, s) => a + s.allCost, 0)), total: chef.reduce((a, s) => a + s.allTotal, 0), activeSecs: chef.reduce((a, s) => a + s.activeSecs, 0) }, … };
```

(`actors` at `:337-338` stays keyed by role, so `actors['head chef']` appears by itself.)

### Success criteria

- [x] `node --check plugins/bk/window/server/live/budget.js` passes
- [x] `tests/budget.test.sh` passes after Phase 3 adds the cases (the existing cases don't change: the existing `sous1` fixture sends `[brief]`, so it stays the sous by rule 3)

## Phase 2: Show it, apart

**Status:** Done

### Changes

#### `plugins/bk/window/server/live/budget.js:399-400` (edit) — the debrief skips the head chef

```js
const subjects = r.unit === 'ticket' ? b.tickets : b.sessions.filter((s) => s.role !== HEAD_CHEF);
```

with a one-line comment: the rule's fix is for the sous and the cooks; the human's own sessions are theirs.

#### `plugins/bk/window/server/live/budget.js:466-473` (edit) — the terminal report

After the Shift line, when `b.headChef.sessions`, add
`Head chef (not in the shift): $X · N sessions · <tokens> tokens · <working> working`, and widen the
`WHO` column of the Sessions table so `head chef` fits (it is 9 characters; the table pads to 11, so no change needed — check the output by eye).

#### `plugins/bk/window/web/ledger.js:14-15` (edit) — name and colour

```js
const markOf = (who) => who === 'sous' ? '#7d776c' : who === 'head chef' ? '#b9b2a2' : MARKS[…];
const nameOf = (who) => who === 'sous' ? 'Sous Chef' : who === 'head chef' ? 'Head Chef' : /^station-/…;
```

#### `plugins/bk/window/web/ledger.js:27-33` (edit) — `split()`

```js
const sessionsCost = sessions.filter((s) => s.role !== 'head chef').reduce(…)
```

so the Kitchen overhead is the kitchen's.

#### `plugins/bk/window/web/ledger.js:37-38` and the summary line (edit) — `renderSummary`

`spent` sums the same filtered list; one more `<span class="sub">` under "Models … CI runners …":
`Head chef (your own sessions, not in this spend): $X`, shown only when they spent anything in the window.

### Success criteria

- [x] `node --check plugins/bk/window/web/ledger.js` passes (ES module syntax only; there is no browser test runner in this repo)
- [ ] Manual: `node plugins/bk/window/server/index.js --demo --port 4748`, open `http://localhost:4748/ledger.html`, Sessions view: a `Head Chef` row exists with its own colour, and the top strip's Kitchen figure is unchanged by it (the demo data has no head-chef session: `kitchen.sh budget` against the Phase 3 fixture is the real check). Port 4747 is the head chef's own Window and is not touched.

## Phase 3: Tests that can fail

**Status:** Done

### Changes

#### `tests/budget.test.sh` fixture, after the sous fixture (`:157-170`) (edit) — three main-checkout transcripts and a fake registry

Inside the node fixture, three more transcripts under `sousDir` (all with timestamps earlier than `sous1`'s last turn, so `sousNow` and the shift window stay on `sous1`):

- `sous2.jsonl`: the live sous by name. Quiet: sends only `[heard]` (not a sous-only kind), so only the registry makes it the sous. Opus 5.5 turns.
- `chef1.jsonl`: the head chef's own session. Sends a `[note]`-kind message, heavy turns (`read: 200000`) so an unfiltered debrief would trip `context-bloat`.
- `sous0.jsonl`: a past shift's sous, not in the registry, sends `[go]`.

In bash, before `cd "$APP"`: `printf 'app-sous' > "$APP/.claude/sous"`, and `$CLAUDE_CONFIG_DIR/sessions/{a,b}.json` for `sous2` (name `app-sous`, pid `$$`) and `chef1` (name `chef`, pid `$PPID`), `cwd` the `$APP` path (`pwd -P`), `updatedAt` set, so `process.kill(pid, 0)` succeeds in the reader.

#### `tests/budget.test.sh` new section `section "the head chef"` after "the shift" (new)

```bash
ok "the session named in .claude/sous is the sous" [ "$(field "$J" 'b.sessions.find(s=>s.id==="sous2").role')" = sous ]
ok "another main-checkout session is the head chef, not the sous" [ "$(field "$J" 'b.sessions.find(s=>s.id==="chef1").role')" = "head chef" ]
ok "a past sous that sent [go] stays the sous" [ "$(field "$J" 'b.sessions.find(s=>s.id==="sous0").role')" = sous ]
ok "the sous before the test still counts (it sends [brief])" [ "$(field "$J" 'b.sessions.find(s=>s.id==="sous1").role')" = sous ]
ok "per actor: the head chef is its own row, apart from the sous" [ "$(field "$J" 'b.actors["head chef"].sessions + "," + b.actors.sous.sessions')" = "1,3" ]
ok "the shift leaves the head chef's spend out and reports it apart" [ "$(field "$J" 'b.shift.cost + b.headChef.cost')" = "$(field "$J" 'Math.round(b.sessions.reduce((a,s)=>a+s.allCost,0)*10000)/10000')" ]
ok "kitchen.sh budget lists a head chef row and a line for them" has "$("$K" budget)" "^  head chef "  …and "^Head chef \(not in the shift\)"
ok "the debrief's context-bloat does not name the head chef" fails has "$("$K" debrief)" "head chef"
```

Variations (each rewrites `.claude/sous` or the registry, then restores them):

```bash
# no name recorded → the Window's pick: the newest live main-checkout session
rm "$APP/.claude/sous"; (set chef1's registry updatedAt to the newest) → chef1.role = sous, sous2.role = head chef
# a name recorded that no live session carries → no fallback
printf ghost > "$APP/.claude/sous" → chef1 = head chef, sous2 = head chef, sous0 (sent [go]) = sous
```

Edit the existing "the shift sums every session and helper" case (`:192`) to sum the sessions that are not the head chef's.

#### Prove the tests can fail (CLAUDE.md)

Before trusting the green run: revert `kitchenTranscripts` to `[root, 'sous']` and the `session()` resolution, run `tests/budget.test.sh`, and watch the new cases go red (at least: "another main-checkout session is the head chef", "per actor … apart", "debrief … does not name the head chef"). Record the failing case numbers in the checklist. Then restore.

### Success criteria

- [x] `tests/budget.test.sh` passes with the new cases
- [x] With the old classification put back, the new cases fail (shown, recorded, then undone)
- [x] `env -u BRIGADE_CLAUDE_ARGS -u BRIGADE_VIA_BK -u TMUX -u TMUX_PANE scripts/check.sh` passes (tell the sous before running: one station at a time)

## Phase 4: Docs and the release

**Status:** Done

### Changes

#### `plugins/bk/skills/README.md` Contract 2, "The budget" paragraph (edit)

One sentence: the sous is the session `.claude/sous` names, or one that sent a sous-only message; any other
session in the main checkout is the head chef's, listed apart and left out of the shift. Contract 11's debrief
list gets "(the head chef's own sessions are skipped)" on the `context-bloat` item. Nothing in Contract 12.

#### `plugins/bk/.claude-plugin/plugin.json` (edit) — `version`: `0.28.0` → `0.28.1`
#### `Formula/bk.rb:9` (edit) — the tarball url `v0.28.0` → `v0.28.1`
#### `CHANGELOG.md` (edit) — new top entry `## [0.28.1] - 2026-11-03`

For the busy human: the budget and the debrief no longer bill your own sessions in the main checkout to the sous;
they show as `head chef`, apart and out of the shift's spend. Nothing to do. (Patch: a fix.)

#### `docs/plans/INDEX.md` (edit) — a row for this plan

### Success criteria

- [x] `scripts/check.sh` release check passes (plugin.json is `0.28.1`, the top `CHANGELOG.md` entry, the formula url)
- [x] `git grep -n "every session.*sous\|sous.*every session" plugins docs README.md PLAYBOOK.md` finds no claim that contradicts the new rule

## Decisions

- **A1 (head chef, relayed by the sous):** B. The live session named in `.claude/sous` is the sous, else
  the newest, as in the Window. So is any main-checkout transcript that sent a sous-only message
  (`[brief]`, `[hello]`, `[go]`, `[approved]`, `[findings]`). Every other main-checkout transcript is
  `head chef`. Because under the literal Window rule a sous `/clear` or a past shift's sous would bill to
  the head chef, the bug in reverse. **This goes slightly past the ticket's literal text, by the head chef's call.**
- **Choices made inside A1 (the ticket's Done-when leaves them open; the sous can overrule in `[findings]`):**
  1. A recorded name that no live session carries gets no "newest" fallback (see Approach).
  2. The shift and the Ledger's spend leave the head chef's sessions out and report them on a line of their own; the ticket asks for "separately".
  3. The debrief skips `head chef` sessions (the ticket allows skipping or relabelling; the rule's fix is not theirs to apply).

## Testing

`tests/budget.test.sh` (handmade transcripts, a fake registry in `$CLAUDE_CONFIG_DIR/sessions`, `.claude/sous`) reaches
the classification through `kitchen.sh budget --json`, the printed report and `kitchen.sh debrief`. The Ledger page has no
test runner in this repo; it gets the syntax check and the manual run in Phase 2.

## References

- Ticket: GitHub issue #62; EPIC #71. Brief from the sous (journal).
- Window's pick: `plugins/bk/window/server/live/index.js:26,37-41`; registry shape: `live/sessions.js:11-33`.
- Commis result (journal, Q1): fact only; nothing recorded. Near miss: `.claude/sous-session` (`bin/bk:328`), kept only while the kitchen is paused.
