#!/usr/bin/env bash
# =============================================================================
# tests/budget.test.sh — behaviour tests for the kitchen's budget:
# plugins/bk/window/server/live/budget.js through `kitchen.sh budget`.
#
# Builds a throwaway kitchen (a repo with .claude/brigade.md and one station) and a fake
# Claude Code config dir holding handmade transcripts: a sous conversation that spawns a
# taster, a cook conversation that is briefed, plans, builds with a runner, hands off and
# serves BKLG-001, plus a second cook conversation on the same ticket. gh is a stub that
# answers with fixed runs and timings. Nothing touches the real machine: HOME and
# CLAUDE_CONFIG_DIR point into the temp dir.
#
# Usage:   tests/budget.test.sh            (exit 0 = all passed)
#          KEEP=1 tests/budget.test.sh     (keep the temp dir for poking at)
# =============================================================================

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K="$REPO/plugins/bk/skills/kitchen/kitchen.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/brigade-budget.XXXXXX")"
export HOME="$TMP/home" CLAUDE_CONFIG_DIR="$TMP/cfg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
  GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset BRIGADE_TRUNK BRIGADE_KITCHEN BRIGADE_KITCHEN_MODE
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
cleanup() { [[ -n "${KEEP:-}" ]] && echo "kept: $TMP" || rm -rf "$TMP"; }
trap cleanup EXIT

# A sealed PATH with node (the reader needs it) and a stub gh; a second one without node.
NB="$TMP/bin"; mkdir -p "$NB" "$TMP/nonode"
for t in git bash sh awk sed grep head tail cat mkdir rm cp mv ls readlink chmod printf uname dirname basename sort uniq wc tr find date mktemp cut env touch node; do
  p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$NB/$t"
  [[ "$t" != node ]] && [[ -n "${p:-}" ]] && ln -sf "$p" "$TMP/nonode/$t"
done
command -v node >/dev/null || { echo "Bail out! node is required for the budget tests"; exit 1; }
cat > "$NB/gh" <<'EOF'
#!/usr/bin/env bash
# gh stub: one PR for BKLG-001 on branch bklg-001-fix, two runs, 2 Linux minutes and 1 macOS minute each run split.
case "$1 $2" in
  "pr list") echo '[{"number":7,"headRefName":"bklg-001-fix","url":"https://example.test/pr/7"}]' ;;
  "run list") echo '[{"databaseId":101,"conclusion":"success","createdAt":"2026-10-24T10:00:00Z"},{"databaseId":102,"conclusion":"failure","createdAt":"2026-10-24T10:20:00Z"}]' ;;
  "repo view") echo '{"isPrivate":true,"nameWithOwner":"acme/app"}' ;;
  "api repos/acme/app/actions/runs/101/timing") echo '{"billable":{"UBUNTU":{"total_ms":60000},"MACOS":{"total_ms":30000}},"run_duration_ms":80000}' ;;
  "api repos/acme/app/actions/runs/102/timing") echo '{"billable":{"UBUNTU":{"total_ms":60000},"MACOS":{"total_ms":30000}},"run_duration_ms":80000}' ;;
  *) echo "gh stub: unexpected: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$NB/gh"
export PATH="$NB"

PASS=0; FAIL=0; N=0
ok() { local desc="$1"; shift; N=$((N+1)); if ( "$@" ) >/dev/null 2>&1; then PASS=$((PASS+1)); echo "ok $N - $desc"; else FAIL=$((FAIL+1)); echo "not ok $N - $desc"; fi; }
has() { printf '%s' "$1" | grep -qE -- "$2"; }
fails() { ! "$@"; }
section() { echo "# $1"; }
# field <json> <js expression over `b`> → prints the value
field() { node -e 'const b=JSON.parse(require("fs").readFileSync(0,"utf8")); const v=(()=>{return eval(process.argv[1])})(); console.log(typeof v==="object"?JSON.stringify(v):String(v))' "$2" <<<"$1"; }

# ---------- the kitchen ----------
APP="$TMP/app"
git init -q "$APP"; git -C "$APP" checkout -q -b main
mkdir -p "$APP/.claude" "$APP/docs/journal"
printf -- '---\ntrunk: main\n---\n' > "$APP/.claude/brigade.md"
git -C "$APP" add -A; git -C "$APP" commit -qm init
git -C "$APP" worktree add -q --detach "$APP-stations/station-1" HEAD   # a station is a worktree
slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
SOUS_DIR="$CLAUDE_CONFIG_DIR/projects/$(slug "$(cd "$APP" && pwd -P)")"
COOK_DIR="$CLAUDE_CONFIG_DIR/projects/$(slug "$(cd "$APP-stations/station-1" && pwd -P)")"
mkdir -p "$SOUS_DIR/sous1/subagents" "$COOK_DIR/cook1/subagents" "$COOK_DIR/cook2" "$COOK_DIR/cook3/subagents" "$COOK_DIR/cook4/subagents" "$COOK_DIR/cook6/subagents"

# ---------- the transcripts ----------
# Written by node so the timestamps are today's. T0 = 09:00 local today; everything is
# minutes after it. One API turn is written as two lines sharing a message id, as Claude Code does.
node - "$SOUS_DIR" "$COOK_DIR" "$APP-stations/station-1" <<'EOF'
const fs = require('fs'), path = require('path');
const [sousDir, cookDir, stationDir] = process.argv.slice(2);
const d = new Date(); d.setHours(9, 0, 0, 0); const T0 = d.getTime();
const at = (min) => new Date(T0 + min * 60000).toISOString();
let n = 0;
const usage = (u) => ({ input_tokens: u.in || 0, output_tokens: u.out || 0, cache_read_input_tokens: u.read || 0, cache_creation_input_tokens: (u.w5 || 0) + (u.w1 || 0), cache_creation: { ephemeral_5m_input_tokens: u.w5 || 0, ephemeral_1h_input_tokens: u.w1 || 0 } });
const asst = (min, model, u, content, id = `msg_${++n}`) => ({ type: 'assistant', timestamp: at(min), message: { id, model, usage: usage(u), content } });
const user = (min, text) => ({ type: 'user', timestamp: at(min), isMeta: true, message: { role: 'user', content: [{ type: 'text', text }] } });
const peer = (min, from, text) => user(min, `Another Claude session sent a message:\n<cross-session-message from="uds:/tmp/x.sock" from-name="${from}" from-mode="prompting">\n${text}`);
const result = (min, toolId, extra = {}) => ({ type: 'user', timestamp: at(min), message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: toolId, content: 'done' }] }, ...extra });
const send = (to, message) => ({ type: 'tool_use', id: `tu_${++n}`, name: 'SendMessage', input: { to, message } });
const agent = (kind, description) => ({ type: 'tool_use', id: `tu_${++n}`, name: 'Agent', input: { subagent_type: `bk:${kind}`, description, prompt: `do ${description}` } });
const write = (file, lines) => fs.writeFileSync(file, lines.map((l) => JSON.stringify(l)).join('\n') + '\n');

// The first cook conversation: briefed at 0, plans at 1, approved at 2, runner at 5, handoff at 10, go at 11, served at 12.
const runnerCall = agent('runner', 'the check'), goodbye = send('sous', '[served] https://example.test/pr/7');
write(path.join(cookDir, 'cook1.jsonl'), [
  user(-1, 'start'),
  asst(-0.5, 'claude-opus-5-5', { in: 1000, out: 500, read: 10000, w5: 2000 }, [{ type: 'text', text: 'hello' }], 'msg_dup'),   // before the brief: the session's, not the ticket's
  asst(-0.5, 'claude-opus-5-5', { in: 1000, out: 500, read: 10000, w5: 2000 }, [send('sous', '[check-in] station-1, fresh')], 'msg_dup'),   // the same turn, second line
  peer(0, 'app-sous', '[brief] BKLG-001 Fix the thing. Bug: I sign the plan.'),
  asst(0.5, 'claude-opus-5-5', { in: 100, out: 1000, read: 100000, w1: 50000 }, [send('sous', '[plan] BKLG-001 ready: /x/docs/plans/BKLG-001-fix.md')]),
  peer(2, 'app-sous', '[approved] BKLG-001: /x/docs/plans/BKLG-001-fix.md · sous, per gates.plan_approval.bug'),
  asst(3, 'claude-opus-5-5', { in: 0, out: 0, read: 0 }, [send('sous', '[gate] BKLG-001 Q1, see journal: retry 3 or 5 times? recommend 3. commis: nothing recorded in decisions, specs, journals')]),
  peer(4, 'app-sous', '[heard] Q1: 3 times (head chef), because the upstream throttles at 5'),
  asst(5, 'claude-opus-5-5', { in: 100, out: 1000, read: 100000 }, [runnerCall]),
  result(6, runnerCall.id, { toolUseResult: { agentId: 'r1', status: 'done' } }),
  asst(10, 'claude-opus-5-5', { in: 0, out: 2000, read: 200000 }, [send('sous', '[handoff] BKLG-001 ready for the pass')]),
  peer(11, 'app-sous', '[go] commit and open the PR'),
  asst(12, 'claude-opus-5-5', { in: 0, out: 500, read: 50000 }, [goodbye]),
  asst(13, 'claude-opus-5-5', { in: 0, out: 100, read: 1000 }, [{ type: 'text', text: 'after the ticket' }]),   // after [served]: the session's, not the ticket's
]);
// A fourth cook conversation on BKLG-003: three red checks, heavy turns (the context line), the record
// answering a gate the commis called nothing. The debrief's fixture.
const r4 = agent('runner', 'check 1'), r5 = agent('runner', 'check 2'), r6 = agent('runner', 'check 3');
write(path.join(cookDir, 'cook4.jsonl'), [
  peer(40, 'app-sous', '[brief] BKLG-003 A third thing.'),
  asst(41, 'claude-sonnet-5-5', { in: 0, out: 1000, read: 200000 }, [send('sous', '[gate] BKLG-003 Q1: which queue? commis: nothing recorded in decisions')]),
  peer(42, 'app-sous', '[heard] Q1: the fare queue, settled in docs/knowledge/queues.md'),
  peer(43, 'app-sous', '[approved] BKLG-003: /x/docs/plans/BKLG-003.md · sous'),
  asst(44, 'claude-sonnet-5-5', { in: 0, out: 1000, read: 200000 }, [r4]), result(45, r4.id, { toolUseResult: { agentId: 'r4', status: 'done' } }),
  asst(46, 'claude-sonnet-5-5', { in: 0, out: 1000, read: 210000 }, [r5]), result(47, r5.id, { toolUseResult: { agentId: 'r5', status: 'done' } }),
  asst(48, 'claude-sonnet-5-5', { in: 0, out: 1000, read: 220000 }, [r6]), result(49, r6.id, { toolUseResult: { agentId: 'r6', status: 'done' } }),
]);
for (const [id, min, text] of [['r4', 44.5, 'FAIL'], ['r5', 46.5, 'fail'], ['r6', 48.5, 'failed again']]) write(path.join(cookDir, 'cook4', 'subagents', `agent-${id}.jsonl`), [
  { type: 'user', isSidechain: true, agentId: id, timestamp: at(min), message: { role: 'user', content: 'run the check' } },
  asst(min + 0.2, 'claude-haiku-5-5', { in: 0, out: 1000, read: 0 }, [{ type: 'text', text }]),
]);
// A fifth cook conversation on BKLG-004: the head chef signed its plan with no why (the over-ask rule).
write(path.join(cookDir, 'cook5.jsonl'), [
  peer(60, 'app-sous', '[brief] BKLG-004 A fourth thing, a chore.'),
  asst(61, 'claude-sonnet-5-5', { in: 0, out: 1000, read: 1000 }, [send('sous', '[plan] BKLG-004 ready: /x/docs/plans/BKLG-004.md')]),
  peer(62, 'app-sous', '[approved] BKLG-004: /x/docs/plans/BKLG-004.md · head chef: "Approve"'),
]);
// A sixth cook conversation on BKLG-005, served before the others begin: three runners that read as red
// (the old reading would count three reds), but the station's check.log holds the real runs inside its span:
// two red, one green that moved the tree. The log wins where it has lines, so two reds and no finding.
const c1 = agent('runner', 'check 1'), c2 = agent('runner', 'check 2'), c3 = agent('runner', 'check 3');
const c6 = [c1, c2, c3];
write(path.join(cookDir, 'cook6.jsonl'), [
  peer(-60, 'app-sous', '[brief] BKLG-005 A log thing.'),
  peer(-59, 'app-sous', '[approved] BKLG-005: /x/docs/plans/BKLG-005.md · sous'),
  ...c6.flatMap((c, i) => [asst(-58 + i, 'claude-sonnet-5-5', { in: 0, out: 10, read: 0 }, [c]), result(-57.5 + i, c.id, { toolUseResult: { agentId: `c${i + 1}`, status: 'done' } })]),
  asst(-48, 'claude-sonnet-5-5', { in: 0, out: 10, read: 0 }, [send('sous', '[served] https://example.test/pr/9')]),
]);
c6.forEach((c, i) => write(path.join(cookDir, 'cook6', 'subagents', `agent-c${i + 1}.jsonl`), [
  { type: 'user', isSidechain: true, agentId: `c${i + 1}`, timestamp: at(-57.9 + i), message: { role: 'user', content: 'run the check' } },
  asst(-57.6 + i, 'claude-haiku-5-5', { in: 0, out: 10, read: 0 }, [{ type: 'text', text: 'FAIL' }]),
]));
const iso = (min) => new Date(T0 + min * 60000).toISOString().replace(/\.\d+Z$/, 'Z');
fs.mkdirSync(path.join(stationDir, '.claude'), { recursive: true });
fs.writeFileSync(path.join(stationDir, '.claude', 'check.log'), [
  `${iso(-55)} tree=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa rc=1 secs=40 cmd=0123456789ab`,
  `${iso(-53)} tree=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb rc=1 secs=41 cmd=0123456789ab`,
  `${iso(-51)} tree=cccccccccccccccccccccccccccccccccccccccc rc=0 secs=42 cmd=0123456789ab moved`,
  'a line that is not a run',
].join('\n') + '\n');
// The runner, a Haiku sub-agent of the first cook conversation.
write(path.join(cookDir, 'cook1', 'subagents', 'agent-r1.jsonl'), [
  { type: 'user', isSidechain: true, agentId: 'r1', timestamp: at(5.1), message: { role: 'user', content: 'run the check' } },
  asst(5.9, 'claude-haiku-5-5', { in: 0, out: 100000, read: 0 }, [{ type: 'text', text: 'pass' }]),
]);
// A second cook conversation (after a /clear) that named the same ticket earlier: the spans merge, so the ticket starts here.
write(path.join(cookDir, 'cook2.jsonl'), [
  peer(-30, 'app-sous', '[brief] BKLG-001 Fix the thing. Bug: I sign the plan.'),
  asst(-29, 'claude-sonnet-5-5', { in: 1000000, out: 0, read: 0 }, [send('sous', '[check-in] station-1 on BKLG-001, handing off before a clear')]),
]);
// A third cook conversation on a ticket that is not served yet: its journal line reads brief→PR.
// It is approved, runs the check red, fixes, runs it green: the rework is the fix and the re-run.
const red = agent('runner', 'the check'), green = agent('runner', 'the check again');
write(path.join(cookDir, 'cook3.jsonl'), [
  peer(20, 'app-sous', '[brief] BKLG-002 Another thing.'),
  asst(21, 'claude-haiku-5-5', { in: 0, out: 1000000, read: 0 }, [send('sous', '[plan] BKLG-002 ready: /x/docs/plans/BKLG-002.md')]),
  peer(22, 'app-sous', '[approved] BKLG-002: /x/docs/plans/BKLG-002.md · head chef: "yes" · why: migration'),
  asst(22.2, 'claude-haiku-5-5', { in: 0, out: 0, read: 0 }, [send('sous', '[gate] BKLG-002 Q1: which helper? commis: fact only')]),
  asst(22.4, 'claude-haiku-5-5', { in: 0, out: 0, read: 0 }, [send('sous', '[gate] BKLG-002 Q2: rounding? commis: nothing recorded in decisions')]),
  peer(22.6, 'app-sous', '[heard] Q2: round half up, settled in docs/decisions/003-rounding.md (2026-09-01)'),
  asst(23, 'claude-haiku-5-5', { in: 0, out: 200000, read: 0 }, [red]),
  result(24, red.id, { toolUseResult: { agentId: 'r2', status: 'done' } }),
  asst(25, 'claude-haiku-5-5', { in: 0, out: 400000, read: 0 }, [{ type: 'text', text: 'fixing' }]),
  asst(26, 'claude-haiku-5-5', { in: 0, out: 0, read: 0 }, [green]),
  result(27, green.id, { toolUseResult: { agentId: 'r3', status: 'done' } }),
  asst(28, 'claude-haiku-5-5', { in: 0, out: 100000, read: 0 }, [{ type: 'text', text: 'after green' }]),
]);
write(path.join(cookDir, 'cook3', 'subagents', 'agent-r2.jsonl'), [
  { type: 'user', isSidechain: true, agentId: 'r2', timestamp: at(23.1), message: { role: 'user', content: 'run' } },
  asst(23.9, 'claude-haiku-5-5', { in: 0, out: 20000, read: 0 }, [{ type: 'text', text: 'FAIL: 2 of 48 tests failed' }]),
]);
write(path.join(cookDir, 'cook3', 'subagents', 'agent-r3.jsonl'), [
  { type: 'user', isSidechain: true, agentId: 'r3', timestamp: at(26.1), message: { role: 'user', content: 'run' } },
  asst(26.9, 'claude-haiku-5-5', { in: 0, out: 20000, read: 0 }, [{ type: 'text', text: 'pass: 48 tests' }]),
]);
// The sous: one conversation, a taster for BKLG-001 at the pass.
const taste = agent('taster', 'taste BKLG-001 in station-1');
write(path.join(sousDir, 'sous1.jsonl'), [
  user(-2, 'run the kitchen'),
  asst(-1, 'claude-opus-5-5', { in: 0, out: 1000, read: 0 }, [send('app-cook-1', '[brief] BKLG-001 Fix the thing. Bug: I sign the plan.')]),
  asst(10.5, 'claude-opus-5-5', { in: 0, out: 1000, read: 0 }, [taste]),
  result(10.9, taste.id, { toolUseResult: { agentId: 't1', status: 'done' } }),
  asst(14, 'claude-mystery-9', { in: 1000, out: 1000, read: 0 }, [{ type: 'text', text: 'an unpriced model' }]),
]);
write(path.join(sousDir, 'sous1', 'subagents', 'agent-t1.jsonl'), [
  { type: 'user', isSidechain: true, agentId: 't1', timestamp: at(10.6), message: { role: 'user', content: 'taste' } },
  asst(10.8, 'claude-sonnet-5-5', { in: 1000000, out: 0, read: 0 }, [{ type: 'text', text: 'ship' }]),
]);
// Three more conversations in the main checkout, none of them sous1 (#62). sous2 is the sous that is
// running, named in .claude/sous and the registry, and says nothing only a sous says. chef1 is the head
// chef's own session, heavy enough to trip the debrief's context rule if it were counted. sous0 is a past
// shift's sous: gone from the registry, but it sent a [go]. All end before sous1's last turn (14), so the
// shift window stays on sous1.
write(path.join(sousDir, 'sous2.jsonl'), [
  user(3, 'run the kitchen again'),
  asst(4, 'claude-opus-5-5', { in: 0, out: 1000, read: 0 }, [send('app-cook-1', '[heard] Q1: yes')]),
]);
write(path.join(sousDir, 'chef1.jsonl'), [
  user(5, 'triage the PRs'),
  asst(6, 'claude-opus-5-5', { in: 0, out: 1000, read: 200000 }, [send('app-sous', '[plan] BKLG-009 ready: /x/docs/plans/BKLG-009.md')]),
]);
write(path.join(sousDir, 'sous0.jsonl'), [
  user(-30, 'run the kitchen, yesterday'),
  asst(-29, 'claude-opus-5-5', { in: 0, out: 1000, read: 0 }, [send('app-cook-1', '[go] commit and open the PR')]),
]);
EOF

# The live registry Claude Code keeps (<config>/sessions/<pid>.json): who is running now, by name.
# Both pids are alive (this script and its parent); sous2 is the sous by name, chef1 the newer session.
mkdir -p "$CLAUDE_CONFIG_DIR/sessions" "$APP/.claude"
APP_REAL="$(cd "$APP" && pwd -P)"
registry() { # <sous2 updatedAt> <chef1 updatedAt>
  printf '{"pid":%s,"sessionId":"sous2","name":"app-sous","cwd":"%s","updatedAt":%s}\n' "$$" "$APP_REAL" "$1" > "$CLAUDE_CONFIG_DIR/sessions/$$.json"
  printf '{"pid":%s,"sessionId":"chef1","name":"chef","cwd":"%s","updatedAt":%s}\n' "$PPID" "$APP_REAL" "$2" > "$CLAUDE_CONFIG_DIR/sessions/$PPID.json"
}
registry 1000 2000
printf 'app-sous\n' > "$APP/.claude/sous"

cd "$APP" || exit 1
# =============================================================================
section "the shift"
OUT="$("$K" budget 2>&1)"
ok "budget prints the shift, sessions and tickets" has "$OUT" "^Shift \(since .*today\)"
ok "the ticket is listed, served, by station-1" has "$OUT" "BKLG-001 +station-1 +served"
ok "an unpriced model is named, with where to put its price" has "$OUT" "no price for claude-mystery-9 .*prices: block"
J="$("$K" budget --json)"
# cook1 own turns: dup once (1000/500/10000/2000w5) + 100/1000/100000/50000w1 + 100/1000/100000 + 0/2000/200000 + 0/500/50000 + 0/100/1000
#   in 1200 · out 5100 · read 461000 · w5 2000 · w1 50000 → total 519300
ok "one API turn written as two lines is counted once" [ "$(field "$J" 'b.sessions.find(s=>s.id==="cook1").total')" = 519300 ]
# opus 5.5: in 4, out 20, read 0.2, w5 5, w1 8 per MTok → (4800 + 102000 + 92200 + 10000 + 400000)/1e6 = 0.609
ok "a cook conversation is priced on its model" [ "$(field "$J" 'b.sessions.find(s=>s.id==="cook1").cost')" = 0.609 ]
ok "the 1-hour cache write is priced at 2x, the 5-minute at 1.25x" [ "$(field "$J" 'b.sessions.find(s=>s.id==="cook1").tokens.w1')" = 50000 ]
# the runner: 100k output on haiku 5.5 at $0.50 → $0.05, on the cook's session as a helper
ok "a sub-agent is priced on its own model and charged to its session" [ "$(field "$J" 'b.sessions.find(s=>s.id==="cook1").helpers.runner.cost')" = 0.05 ]
ok "a session's all-in cost adds its helpers" [ "$(field "$J" 'b.sessions.find(s=>s.id==="cook1").allCost')" = 0.659 ]
ok "a session carries its model's price table, for the Window's cost rows" [ "$(field "$J" 'b.sessions.find(s=>s.id==="cook1").price.out')" = 20 ]
ok "an unpriced model counts its tokens and costs nothing" [ "$(field "$J" 'b.sessions.find(s=>s.id==="sous1").priced')" = false ]
ok "the sous conversation's priced turns still add up" [ "$(field "$J" 'b.sessions.find(s=>s.id==="sous1").cost')" = 0.04 ]
ok "the shift sums every session and helper of the kitchen" [ "$(field "$J" 'b.shift.cost')" = "$(field "$J" 'Math.round(b.sessions.filter(s=>s.role!=="head chef").reduce((a,s)=>a+s.allCost,0)*10000)/10000')" ]
ok "per actor: station-1 today spans six conversations" [ "$(field "$J" 'b.actors["station-1"].sessions')" = 6 ]
ok "the unknown model is reported" [ "$(field "$J" 'b.unknownModels.join()')" = claude-mystery-9 ]

section "the head chef"
# Two main-checkout transcripts, one named in .claude/sous: only that one is the sous (and sous1, which sent a [brief],
# and sous0, which sent a [go], are the sous by what they said).
role() { field "$1" "b.sessions.find(s=>s.id===\"$2\").role"; }
ok "the live session named in .claude/sous is the sous" [ "$(role "$J" sous2)" = sous ]
ok "another main-checkout session is the head chef, not the sous" [ "$(role "$J" chef1)" = "head chef" ]
ok "a past sous that sent [go] stays the sous, though no registry lists it" [ "$(role "$J" sous0)" = sous ]
ok "a sous that sent [brief] stays the sous" [ "$(role "$J" sous1)" = sous ]
ok "per actor: the head chef is a row of its own, apart from the sous" [ "$(field "$J" 'b.actors["head chef"].sessions + "," + b.actors.sous.sessions')" = "1,3" ]
ok "the head chef's spend is reported apart and is not in the shift" [ "$(field "$J" 'b.headChef.sessions + "," + Math.round((b.shift.cost + b.headChef.cost)*10000)/10000')" = "1,$(field "$J" 'Math.round(b.sessions.reduce((a,s)=>a+s.allCost,0)*10000)/10000')" ]
ok "the head chef's session makes no ticket, though it sent a [plan] naming one" [ "$(field "$J" 'b.tickets.some(t=>t.id==="BKLG-009")')" = false ]
OUT="$("$K" budget)"
ok "kitchen.sh budget lists the head chef as its own row" has "$OUT" "^  head chef +opus"
ok "kitchen.sh budget gives the head chef a line outside the shift" has "$OUT" "^Head chef \(not in the shift\): .*1 session"
ok "the debrief's context rule skips the head chef's heavy session (only cook4 trips it)" [ "$(field "$("$K" debrief --json)" 'b.find(f=>f.key==="context-bloat").count')" = 1 ]
# No name recorded: the Window's pick, the newest live main-checkout session.
rm -f "$APP/.claude/sous"
J2="$("$K" budget --json)"
ok "with no name recorded, the newest live session is the sous" [ "$(role "$J2" chef1)" = sous ]
ok "with no name recorded, the older live session is not, unless it spoke as the sous" [ "$(role "$J2" sous2)" = "head chef" ]
# A name recorded for a session that is not running: no fallback.
printf 'ghost\n' > "$APP/.claude/sous"
J3="$("$K" budget --json)"
ok "a recorded name nobody carries gets no fallback: the live sessions are the head chef's" [ "$(role "$J3" chef1)/$(role "$J3" sous2)" = "head chef/head chef" ]
ok "a recorded name nobody carries still leaves a past sous who sent [go] the sous" [ "$(role "$J3" sous0)" = sous ]
printf 'app-sous\n' > "$APP/.claude/sous"

section "the ticket"
T="$("$K" budget --ticket BKLG-001 --json)"
ok "the ticket's spend starts at the brief, not the conversation" [ "$(field "$T" 'b.tokens.in')" = 1000200 ]   # 1000000 from cook2, 200 from cook1 after the brief; the 1000 before it is not the ticket's
ok "the ticket's spend ends at [served]" [ "$(field "$T" 'b.tokens.out')" = 4500 ]   # 1000+1000+2000+500: not the 500 before the brief nor the 100 after
ok "two conversations on one ticket merge into one span" [ "$(field "$T" 'b.startedAt < b.servedAt && b.status')" = served ]
ok "brief→served is wall-clock from the first brief" [ "$(field "$T" 'Math.round(b.secs/60)')" = 42 ]
ok "phases: plan runs from the first brief (the earlier conversation) to the plan" [ "$(field "$T" 'b.phases.plan')" = 1830 ]
ok "phases: wait 90s" [ "$(field "$T" 'b.phases.wait')" = 90 ]
ok "phases: build 8m" [ "$(field "$T" 'b.phases.build')" = 480 ]
ok "phases: pass 60s, ship 60s" [ "$(field "$T" 'b.phases.pass + b.phases.ship')" = 120 ]
ok "the cook's runner is the ticket's helper" [ "$(field "$T" 'b.helpers.runner.runs')" = 1 ]
ok "the sous's taster that names the ticket is the ticket's helper too" [ "$(field "$T" 'b.helpers.taster.cost')" = 2 ]
OUT="$("$K" budget --ticket BKLG-001)"
ok "the ticket report says CI is not fetched yet" has "$OUT" "CI +not fetched"
ok "the ticket report reads top-down" has "$OUT" "^BKLG-001  served · station-1 · brief 08:30 → served 09:12 · 42m"

section "the ledger"
ok "a served ticket is written to .claude/budget.jsonl" grep -q '"kind":"ticket","t":.*"id":"BKLG-001"' "$APP/.claude/budget.jsonl"
ok "the ledger is kept out of git" git -C "$APP" check-ignore -q .claude/budget.jsonl
ok "each served ticket is written once, not on every run (BKLG-001 and the check-log ticket BKLG-005)" [ "$(grep -c '"kind":"ticket"' "$APP/.claude/budget.jsonl")" = 2 ]
mv "$COOK_DIR" "$COOK_DIR.gone"
OUT="$("$K" budget --ticket BKLG-001)"
ok "a ticket whose transcripts are gone is still reported from the ledger" has "$OUT" "^BKLG-001  served · station-1"
mv "$COOK_DIR.gone" "$COOK_DIR"

section "CI"
OUT="$("$K" budget --ci --ticket BKLG-001)"
# two runs × (1 Linux min + 0.5 macOS min) = 3 min; private repo → 2×0.008 + 1×0.08 = $0.096
ok "--ci counts the PR branch's billable minutes" has "$OUT" "CI +3 min over 2 runs on bklg-001-fix"
ok "and prices them at the runners' list rates" has "$OUT" "\(\\\$0.10\)"
ok "the CI result reaches the ledger" grep -q '"kind":"ci","t":.*"ticket":"BKLG-001","branch":"bklg-001-fix"' "$APP/.claude/budget.jsonl"
OUT="$("$K" budget)"
ok "the shift's CI line sums the tickets" has "$OUT" "CI 3 min \(\\\$0.10\)"
ok "the ticket row carries its asks (asked/to the head chef) and its CI minutes" has "$OUT" "BKLG-001 .*\\\$4.63 +1/1 +3m"

section "the journal line"
OUT="$("$K" budget --ticket BKLG-001 --journal-line --session app-cook-1)"
ok "one journal line, dated, for the cook to append" has "$OUT" "^- [0-9]{4}-[0-9]{2}-[0-9]{2} 09:12 · app-cook-1 · cost: \\\$4\.63 · "
ok "…and the asks: one went to the head chef and waited a minute" has "$OUT" " · asks: 1 \\(1 to the head chef, waited 1m\\)$"
ok "it carries the tokens, the phases, the helpers and CI" has "$OUT" "tokens \(in 1\.0M, out 5k, cache read 450k, cache write 50k\) · brief→served 42m \(plan 31m, wait 2m, build 8m, pass 1m, ship 1m\) · helpers: runner 1 \(\\\$0\.05\), taster 1 \(\\\$2\.00\) · CI 3 min \(\\\$0\.10\)"
OUT="$("$K" budget --ticket BKLG-002 --journal-line)"
ok "a ticket not served yet reads brief→PR, with the phases known so far and no CI" has "$OUT" "^- .* · cook3 · cost: \\\$0\.87 · 1\.7M tokens .* · brief→PR [0-9]+[smh].*\(plan 1m, wait 1m\) · helpers: runner 2 \(\\\$0\.02\) · asks: 2 \\(1 from the record, 1 unanswered, waited 12s\\)$"
ok "an unknown ticket is an error" fails "$K" budget --ticket BKLG-999 --journal-line

section "the check log"
BJ="$("$K" budget --json)"
ok "a ticket with check.log lines in its span counts the log's runs, not the runners' replies" [ "$(field "$BJ" 'JSON.stringify(b.tickets.find(t=>t.id==="BKLG-005").checks)')" = '{"source":"log","runs":3,"reds":2}' ]
ok "…and the log's runs are its check steps" [ "$(field "$BJ" 'b.tickets.find(t=>t.id==="BKLG-005").steps.filter(s=>s.kind==="check").map(s=>s.ok+(s.note?":"+s.note:"")).join()')" = "false,false,true:moved" ]
ok "a ticket with no log lines still reads its runners" [ "$(field "$BJ" 'JSON.stringify(b.tickets.find(t=>t.id==="BKLG-003").checks)')" = '{"source":"runner","runs":3,"reds":3}' ]
ok "a junk line in the log is ignored" [ "$(field "$BJ" 'b.tickets.find(t=>t.id==="BKLG-005").checks.runs')" = 3 ]
ok "two red log runs are not a check-red-repeat finding even with three red-reading runners" bash -c '! "$1" debrief | grep -q "BKLG-005: .*red runs"' _ "$K"

section "the debrief"
OUT="$("$K" debrief)"
ok "the check red three times on one ticket is a finding, with its fix" has "$OUT" "^repo +check-red-repeat +1 +watch +the check went red three times.*
 +BKLG-003: 3 red runs
 +fix: a faster or narrower local check"
ok "a gate the record had after the commis said nothing is a finding" has "$OUT" "^repo +record-missed +2 +DUE .*
 +BKLG-002: 1 gate the record had after all
 +BKLG-003: 1 gate the record had after all"
ok "a session carrying heavy turns is a plugin finding, per session" has "$OUT" "^plugin +context-bloat +1 +watch +a session's last turns averaged more than 150k.*
 +station-1 09:40: 2[0-9][0-9]k per turn over the last 4, 4 turns over the line"
ok "a ticket still red after three checks is rework-heavy too" has "$OUT" "^repo +rework-heavy +1 +watch .*
 +BKLG-003: rework \\\$[0-9.]+ of \\\$[0-9.]+"
ok "a ticket with one red and light rework trips nothing" bash -c '! printf "%s" "$1" | grep -q "BKLG-002: .*red"' _ "$OUT"
ok "nothing tripped on a quiet ticket" bash -c '! printf "%s" "$1" | grep -q "BKLG-001"' _ "$OUT"
J="$("$K" debrief --json)"
ok "a head chef [approved] with no why is an over-ask, per ticket" has "$OUT" "^plugin +over-ask +1 +watch +the head chef signed a plan with no reason.*
 +BKLG-004: a head chef \[approved\] with no why:"
ok "a head chef [approved] that names its why is not" fails has "$OUT" "BKLG-002: a head chef"
ok "--json carries the same findings" [ "$(field "$J" 'b.map(f=>f.key+":"+f.status).join()')" = "check-red-repeat:watch,rework-heavy:watch,record-missed:DUE,over-ask:watch,context-bloat:watch" ]
mkdir -p "$APP/docs"; printf '| key | scope | ticket |\n|---|---|---|\n| `record-missed` | repo | BKLG-010 |\n' > "$APP/docs/lessons.md"
ok "a key the register lists is promoted, not due" has "$("$K" debrief)" "^repo +record-missed +2 +promoted"
rm "$APP/docs/lessons.md"

section "stages, steps and rework"
T="$("$K" budget --ticket BKLG-001 --json)"
ok "prep is brief to the sign-off: the cook's turns before [approved]" [ "$(field "$T" 'b.stages.prep.cost')" = 2.4404 ]
ok "check holds the handoff turn and the sous's taster" [ "$(field "$T" 'b.stages.check.cost')" = 2.08 ]
ok "the runner is a step in the stage it ran in, with its verdict" [ "$(field "$T" 'b.steps.find(s=>s.kind==="runner").stage + b.steps.find(s=>s.kind==="runner").ok')" = cooktrue ]
ok "the cook's own turns are one step per stage" [ "$(field "$T" 'b.steps.filter(s=>s.kind==="own").map(s=>s.stage).join()')" = prep,cook,check,serve ]
ok "a ticket with no red run has no rework" [ "$(field "$T" 'b.rework')" = null ]
T="$("$K" budget --ticket BKLG-002 --json)"
# after the red runner at 24: the fix turn (400k out on haiku = $0.20), the green runner (20k out = $0.01); not the 100k after green
ok "rework is what came after the first red runner, up to the green one" [ "$(field "$T" 'b.rework.cost')" = 0.21 ]
ok "rework counts the reds and says whether it settled" [ "$(field "$T" 'b.rework.reds + "," + b.rework.settled')" = "1,true" ]
ok "the stage split sums to the ticket" [ "$(field "$T" 'Math.round(Object.values(b.stages).reduce((a,g)=>a+g.cost,0)*10000)/10000 === b.allCost')" = true ]

section "asks"
ok "two gates on BKLG-002: one answered from the record, one still open" [ "$(field "$T" 'b.asks.gates + "," + b.asks.record + "," + b.asks.open + "," + b.asks.sous')" = "2,1,1,0" ]
ok "the answer is matched to its question by number, not by order" [ "$(field "$T" 'b.asks.items.map(a=>a.q+":"+(a.by||"-")).join()')" = "Q1:-,Q2:record" ]
ok "the commis verdict rides in from the gate" [ "$(field "$T" 'b.asks.items.map(a=>a.commis).join()')" = "fact,nothing" ]
T="$("$K" budget --ticket BKLG-001 --json)"
ok "a relayed answer counts as the head chef's, with the wait" [ "$(field "$T" 'b.asks.headChef + "," + b.asks.waitedSecs')" = "1,60" ]
printf -- '# Asks\n\n- A1 · 2026-10-24 09:05 · BKLG-001 · ruling · Q: Which currency?\n- A1 answered · 2026-10-24 09:30 · PKR\n- A2 · 2026-10-24 09:06 · BKLG-001 · access · Q: Staging login?\n' > "$APP/.claude/asks.md"
T="$("$K" budget --ticket BKLG-001 --json)"
ok "the ask log adds the sous's own asks about the ticket, with their gaps" [ "$(field "$T" 'b.asks.logged + "," + b.asks.unanswered + "," + b.asks.headChef + "," + JSON.stringify(b.asks.gaps)')" = '2,1,2,{"ruling":1,"access":1}' ]
OUT="$("$K" budget --ticket BKLG-001)"
ok "…and the ticket report prints them" has "$OUT" "asks      2 \\(2 to the head chef, waited 1m, gaps: ruling 1, access 1\\)"
ok "…with each gate, who answered, the wait and the commis verdict" has "$OUT" "09:03 Q1 → head chef, 1m · commis: nothing · BKLG-001 Q1, see journal"
rm "$APP/.claude/asks.md"
J="$("$K" budget --json)"
ok "the shift window starts at the sous's current conversation, today at 08:58" [ "$(field "$J" 'b.windows.shift > b.windows.today && b.windows.week < b.windows.today && new Date(b.windows.shift).getMinutes()')" = 58 ]
ok "no budget: block means no caps" [ "$(field "$J" 'Object.keys(b.caps).length')" = 0 ]
printf -- '---\ntrunk: main\nbudget:\n  shift_usd: 60\n  ticket_usd: 12\n---\n' > "$APP/.claude/brigade.md"
J="$("$K" budget --json)"
ok "a budget: block gives the Ledger its scale" [ "$(field "$J" 'b.caps.shift_usd + "/" + b.caps.ticket_usd')" = 60/12 ]
printf -- '---\ntrunk: main\n---\n' > "$APP/.claude/brigade.md"

section "prices from the config"
printf -- '---\ntrunk: main\nprices:\n  opus: { in: 8, out: 40, read: 0.4 }\n---\n' > "$APP/.claude/brigade.md"
J="$("$K" budget --json)"
ok "a prices: block in brigade.md overrides the built-in table" [ "$(field "$J" 'b.sessions.find(s=>s.id==="cook1").cost')" = 1.218 ]
printf -- '---\ntrunk: main\n---\n' > "$APP/.claude/brigade.md"

section "windows and roles"
OUT="$("$K" budget --since 7d)"
ok "--since 7d says since when" has "$OUT" "^Shift \(since 20[0-9][0-9]-"
ok "a week is as far back as it looks" has "$("$K" budget --since 30d)" "^Shift \(since .*today\)"
ok "budget from a station reports the whole kitchen" has "$(cd "$APP-stations/station-1" && "$K" budget --since 7d)" "BKLG-001 +station-1"
ok "without node it says what to install" has "$(PATH="$TMP/nonode" "$K" budget 2>&1)" "needs node 20"

# =============================================================================
section "ticket ids from the rail's own form (#59)"
# A github rail: #13, branch issue-13-…; a jira rail: PROJ-7; the markdown ids still work on both.
mkrail() { # <dir> <config body> → a kitchen with one station and its Claude project dir
  git init -q "$1"; git -C "$1" checkout -q -b main
  mkdir -p "$1/.claude"
  printf -- '---\ntrunk: main\n%s\n---\n' "$2" > "$1/.claude/brigade.md"
  git -C "$1" add -A; git -C "$1" commit -qm init
  git -C "$1" worktree add -q --detach "$1-stations/station-1" HEAD
  mkdir -p "$CLAUDE_CONFIG_DIR/projects/$(slug "$(cd "$1-stations/station-1" && pwd -P)")"
}
APPG="$TMP/appg"; APPJ="$TMP/appj"
mkrail "$APPG" 'rail:
  adapter: github'
mkrail "$APPJ" 'rail:
  adapter: jira'
mkdir -p "$CLAUDE_CONFIG_DIR/projects/$(slug "$(cd "$APPG" && pwd -P)")"
node - "$CLAUDE_CONFIG_DIR/projects/$(slug "$(cd "$APPG-stations/station-1" && pwd -P)")" "$CLAUDE_CONFIG_DIR/projects/$(slug "$(cd "$APPJ-stations/station-1" && pwd -P)")" "$CLAUDE_CONFIG_DIR/projects/$(slug "$(cd "$APPG" && pwd -P)")" <<'EOF'
const fs = require('fs'), path = require('path');
const [gdir, jdir, sdir] = process.argv.slice(2);
const d = new Date(); d.setHours(9, 0, 0, 0); const T0 = d.getTime();
const at = (min) => new Date(T0 + min * 60000).toISOString();
let n = 0;
const usage = (u) => ({ input_tokens: u.in || 0, output_tokens: u.out || 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 });
const asst = (min, u, content) => ({ type: 'assistant', timestamp: at(min), message: { id: `g_${++n}`, model: 'claude-opus-5-5', usage: usage(u), content } });
const peer = (min, text, from = 'app-sous') => ({ type: 'user', timestamp: at(min), isMeta: true, message: { role: 'user', content: [{ type: 'text', text: `Another Claude session sent a message:\n<cross-session-message from="uds:/tmp/x.sock" from-name="${from}" from-mode="prompting">\n${text}` }] } });
const typed = (min, text) => ({ type: 'user', timestamp: at(min), message: { role: 'user', content: text } });
const send = (message) => ({ type: 'tool_use', id: `tu_${++n}`, name: 'SendMessage', input: { to: 'sous', message } });
const write = (file, lines) => fs.writeFileSync(file, lines.map((l) => JSON.stringify(l)).join('\n') + '\n');
// #13 is briefed, planned, served; #14 is named only inside a URL and a word (no ticket); BKLG-005 is a markdown id on a github rail.
write(path.join(gdir, 'g1.jsonl'), [
  peer(0, '[brief] #13 Fix the thing. Bug: I sign the plan. See https://example.test/issues/14 and utf-8.'),
  asst(1, { out: 1000 }, [send('[plan] #13 ready: /x/docs/plans/gh-13-fix.md')]),
  peer(2, '[approved] #13: /x/docs/plans/gh-13-fix.md · sous, per gates.plan_approval.bug'),
  asst(3, { out: 1000 }, [send('[handoff] #13 ready for the pass')]),
  peer(4, '[go] commit and open the PR'),
  asst(5, { out: 1000 }, [send('[served] #13 https://example.test/pull/9')]),
  peer(6, '[findings] #13 main moved: bring it in'),
  asst(7, { out: 100 }, [send('[served] #13 https://example.test/pull/9')]),
]);
// A cook that opens with a stray mention of an earlier ticket and a PR number, then is briefed on #15.
write(path.join(gdir, 'g3.jsonl'), [
  asst(19, { out: 100 }, [send('[check-in] station-2, fresh; the last PR #76 was merged')]),
  peer(20, '[brief] #15 A new thing.'),
  asst(21, { out: 2000 }, [send('[plan] #15 ready: /x/docs/plans/gh-15.md')]),
]);
// A stray mention of another ticket before the brief: the brief still starts its own ticket.
write(path.join(gdir, 'g4.jsonl'), [
  asst(29, { out: 100 }, [send('[check-in] station-2, fresh; my last ticket was #12')]),
  peer(30, '[brief] #16 Another new thing.'),
  asst(31, { out: 2000 }, [send('[plan] #16 ready: /x/docs/plans/gh-16.md')]),
]);
// Served once, then the pass comes back (findings) with no second [served] yet: still a round.
write(path.join(gdir, 'g5.jsonl'), [
  peer(40, '[brief] #17 A last thing.'),
  asst(41, { out: 100 }, [send('[served] #17 https://example.test/pull/11')]),
  peer(42, '[findings] #17 main moved: bring it in'),
]);
write(path.join(gdir, 'g2.jsonl'), [
  peer(10, '[brief] BKLG-005 A markdown id on a github rail.'),
  asst(11, { out: 500 }, [send('[served] BKLG-005 https://example.test/pull/10')]),
  asst(12, { out: 100 }, [send('[served] BKLG-005 https://example.test/pull/10')]),
  asst(13, { out: 100 }, [send('[served] BKLG-005 https://example.test/pull/10')]),
]);
// The sous: every turn is woken by something. #13 gets a mix of kinds (5 of 11 turns are relays); #15 only relays
// (8 of 9); #16 seven relays (below the floor of eight turns). A turn nobody named a ticket for is not counted.
const cook1 = 'app-cook-1', cook2 = 'app-cook-2';
const sturns = (start, n, text = 'ok') => Array.from({ length: n }, (_, i) => asst(start + i * 0.01, { out: 10 }, [{ type: 'text', text }]));
write(path.join(sdir, 'sous.jsonl'), [
  asst(-1, { out: 10 }, [send('[brief] #13 Fix the thing.')]),
  typed(0, 'run the kitchen'), ...sturns(0.1, 1),
  peer(1, '[check-in] station-1 mid-ticket on #13', cook1), ...sturns(1.1, 1),
  peer(2, '[rail] claim #13 todo cook=station-1', cook1), ...sturns(2.1, 2),
  peer(3, '[status] implement started', cook1), ...sturns(3.1, 1),
  peer(4, '[heard] ok', cook1), ...sturns(4.1, 1),
  peer(5, '[gate] #13 Q1, see journal. commis: nothing', cook1), ...sturns(5.1, 2),
  peer(6.5, '[plan] #13 ready: /x', cook1), ...sturns(6.6, 1),
  peer(7.5, '[handoff] #13 ready for the pass', cook1), ...sturns(7.6, 2),
  peer(8.5, '[served] #13 https://example.test/pull/9', cook1), ...sturns(8.6, 1),
  peer(20, '[rail] claim #15 todo cook=station-2', cook2), ...sturns(20.1, 4),
  peer(21, '[check-in] station-2 on #15', cook2), ...sturns(21.1, 4),
  peer(22, '[gate] #15 Q1, see journal. commis: nothing', cook2), ...sturns(22.1, 1),
  peer(30, '[rail] claim #16 todo cook=station-1', cook1), ...sturns(30.1, 4),
  peer(31, '[status] plan written', cook1), ...sturns(31.1, 3),
]);
write(path.join(jdir, 'j1.jsonl'), [
  peer(0, '[brief] PROJ-7 Fix the thing.'),
  asst(1, { out: 1000 }, [send('[plan] PROJ-7 ready: /x/docs/plans/proj-7-fix.md')]),
  asst(2, { out: 1000 }, [send('[served] PROJ-7 https://example.test/pull/3')]),
]);
EOF
GJ="$(cd "$APPG" && "$K" budget --json)"
ok "a github rail attributes spend to #13, and a PR number in a check-in is not a ticket" [ "$(field "$GJ" 'b.tickets.map(t=>t.id).sort().join(",")')" = "#12,#13,#15,#16,#17,BKLG-005" ]
ok "a brief starts its own ticket even after a stray mention of another" [ "$(field "$GJ" 'b.tickets.find(t=>t.id==="#16").tokens.out')" = 2000 ]
ok "…as a served ticket with its phases" [ "$(field "$GJ" 'b.tickets.find(t=>t.id==="#13").status + "," + (b.tickets.find(t=>t.id==="#13").phases.plan != null)')" = "served,true" ]
ok "a number inside a URL, and a word like utf-8, name no ticket" [ "$(field "$GJ" 'b.tickets.length')" = 6 ]
ok "--ticket 13 shows that ticket's spend" has "$(cd "$APPG" && "$K" budget --ticket 13)" "^#13 +served"
ok "--ticket '#13' shows the same" has "$(cd "$APPG" && "$K" budget --ticket '#13')" "^#13 +served"
ok "the ticket list names it" has "$(cd "$APPG" && "$K" budget)" "#13 +station-1 +served"
ok "a jira rail reads PROJ-7" [ "$(field "$(cd "$APPJ" && "$K" budget --json)" 'b.tickets.map(t=>t.id).join(",")')" = "PROJ-7" ]
ok "…and --ticket proj-7 finds it" has "$(cd "$APPJ" && "$K" budget --ticket proj-7)" "^PROJ-7 +served"
ok "a markdown rail still ignores #13 and PROJ-7" [ "$(field "$(cd "$APP" && "$K" budget --json)" 'b.tickets.filter(t=>t.id==="#13"||t.id==="PROJ-7").length')" = 0 ]
ok "the journal line works for a github ticket" has "$(cd "$APPG" && "$K" budget --ticket 13 --journal-line --session app-cook-1)" "app-cook-1 · cost:"
# the sous's turns by the kind of message that woke them
S13="$(cd "$APPG" && "$K" budget --ticket 13 --json)"
ok "the sous's turns on #13, by kind" [ "$(field "$S13" 'JSON.stringify(b.sousTurns)')" = '{"total":11,"byKind":{"check-in":1,"rail":2,"status":1,"heard":1,"gate":2,"plan":1,"handoff":2,"served":1},"routine":5}' ]
ok "a status with no id belongs to the ticket its sender named last" [ "$(field "$(cd "$APPG" && "$K" budget --ticket 16 --json)" 'b.sousTurns.byKind.status')" = 3 ]
ok "a turn woken by the head chef typing counts for no ticket" [ "$(field "$GJ" 'b.tickets.reduce((a,t)=>a+(t.sousTurns?t.sousTurns.total:0),0)')" = "$((11 + 9 + 7))" ]
OUT="$(cd "$APPG" && "$K" budget --ticket 13)"
ok "the ticket report prints them" has "$OUT" "sous turns  11 \\(.*rail 2.*\\) · 5 relays"
ok "…and the rounds after the first [served]" has "$OUT" "1 round after the first \\[served\\]"
ok "the ledger row carries them" has "$(cat "$APPG/.claude/budget.jsonl")" '"sousTurns":\{"total":11'
DB="$(cd "$APPG" && "$K" debrief --json)"
ok "relay-heavy trips on the ticket whose sous turns were mostly relays" [ "$(field "$DB" 'b.find(r=>r.key==="relay-heavy").hits.map(h=>h.id).join(",")')" = "#15" ]
ok "…not on seven relays (under the floor), nor on a mixed ticket" [ "$(field "$DB" 'b.find(r=>r.key==="relay-heavy").count')" = 1 ]
ok "ship-rounds is DUE on two tickets pushed again after the first [served]" [ "$(field "$DB" 'b.find(r=>r.key==="ship-rounds").hits.map(h=>h.id).sort().join(",") + "," + b.find(r=>r.key==="ship-rounds").status')" = "#13,#17,BKLG-005,DUE" ]
ok "…and says what the fix is" has "$(cd "$APPG" && "$K" debrief)" "assign the version at merge"
ok "the existing markdown fixtures trip neither rule" [ "$(field "$("$K" debrief --json)" 'b.filter(r=>r.key==="relay-heavy"||r.key==="ship-rounds").length')" = 0 ]
# the Window's branch reader
ok "issue-13-fix reads as #13 on github" [ "$(node --input-type=module -e "import { idOfBranch } from '$REPO/plugins/bk/window/server/live/ticket-id.js'; console.log([idOfBranch('issue-13-fix','github'), idOfBranch('issue-13-fix','markdown'), idOfBranch('bklg-004-x','github'), idOfBranch('proj-7-x','jira'), idOfBranch(null,'github')].join('|'))")" = "#13||BKLG-004|PROJ-7|" ]

# =============================================================================
echo "# passed $PASS · failed $FAIL · total $N"
[[ $FAIL -eq 0 ]]
