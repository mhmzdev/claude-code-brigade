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
mkdir -p "$APP/.claude" "$APP/stations/station-1/.git" "$APP/docs/journal"
printf -- '---\ntrunk: main\nkitchen_mode: clone\n---\n' > "$APP/.claude/brigade.md"
git -C "$APP" add -A; git -C "$APP" commit -qm init
slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
SOUS_DIR="$CLAUDE_CONFIG_DIR/projects/$(slug "$(cd "$APP" && pwd -P)")"
COOK_DIR="$CLAUDE_CONFIG_DIR/projects/$(slug "$(cd "$APP/stations/station-1" && pwd -P)")"
mkdir -p "$SOUS_DIR/sous1/subagents" "$COOK_DIR/cook1/subagents" "$COOK_DIR/cook2" "$COOK_DIR/cook3/subagents"

# ---------- the transcripts ----------
# Written by node so the timestamps are today's. T0 = 09:00 local today; everything is
# minutes after it. One API turn is written as two lines sharing a message id, as Claude Code does.
node - "$SOUS_DIR" "$COOK_DIR" <<'EOF'
const fs = require('fs'), path = require('path');
const [sousDir, cookDir] = process.argv.slice(2);
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
  asst(5, 'claude-opus-5-5', { in: 100, out: 1000, read: 100000 }, [runnerCall]),
  result(6, runnerCall.id, { toolUseResult: { agentId: 'r1', status: 'done' } }),
  asst(10, 'claude-opus-5-5', { in: 0, out: 2000, read: 200000 }, [send('sous', '[handoff] BKLG-001 ready for the pass')]),
  peer(11, 'app-sous', '[go] commit and open the PR'),
  asst(12, 'claude-opus-5-5', { in: 0, out: 500, read: 50000 }, [goodbye]),
  asst(13, 'claude-opus-5-5', { in: 0, out: 100, read: 1000 }, [{ type: 'text', text: 'after the ticket' }]),   // after [served]: the session's, not the ticket's
]);
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
  peer(22, 'app-sous', '[approved] BKLG-002: /x/docs/plans/BKLG-002.md · sous'),
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
EOF

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
ok "an unpriced model counts its tokens and costs nothing" [ "$(field "$J" 'b.sessions.find(s=>s.id==="sous1").priced')" = false ]
ok "the sous conversation's priced turns still add up" [ "$(field "$J" 'b.sessions.find(s=>s.id==="sous1").cost')" = 0.04 ]
ok "the shift sums every session and helper" [ "$(field "$J" 'b.shift.cost')" = "$(field "$J" 'Math.round(b.sessions.reduce((a,s)=>a+s.allCost,0)*10000)/10000')" ]
ok "per actor: station-1 today spans three conversations" [ "$(field "$J" 'b.actors["station-1"].sessions')" = 3 ]
ok "the unknown model is reported" [ "$(field "$J" 'b.unknownModels.join()')" = claude-mystery-9 ]

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
ok "it is written once, not on every run" [ "$(grep -c '"kind":"ticket"' "$APP/.claude/budget.jsonl")" = 1 ]
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
ok "the ticket row carries its CI minutes" has "$OUT" "BKLG-001 .*\\\$4.63 +3m"

section "the journal line"
OUT="$("$K" budget --ticket BKLG-001 --journal-line --session app-cook-1)"
ok "one journal line, dated, for the cook to append" has "$OUT" "^- [0-9]{4}-[0-9]{2}-[0-9]{2} 09:12 · app-cook-1 · cost: \\\$4\.63 · "
ok "it carries the tokens, the phases, the helpers and CI" has "$OUT" "tokens \(in 1\.0M, out 5k, cache read 450k, cache write 50k\) · brief→served 42m \(plan 31m, wait 2m, build 8m, pass 1m, ship 1m\) · helpers: runner 1 \(\\\$0\.05\), taster 1 \(\\\$2\.00\) · CI 3 min \(\\\$0\.10\)"
OUT="$("$K" budget --ticket BKLG-002 --journal-line)"
ok "a ticket not served yet reads brief→PR, with the phases known so far and no CI" has "$OUT" "^- .* · cook3 · cost: \\\$0\.87 · 1\.7M tokens .* · brief→PR [0-9]+[smh].*\(plan 1m, wait 1m\) · helpers: runner 2 \(\\\$0\.02\)$"
ok "an unknown ticket is an error" fails "$K" budget --ticket BKLG-999 --journal-line

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
J="$("$K" budget --json)"
ok "the shift window starts at the sous's current conversation, today at 08:58" [ "$(field "$J" 'b.windows.shift > b.windows.today && b.windows.week < b.windows.today && new Date(b.windows.shift).getMinutes()')" = 58 ]
ok "no budget: block means no caps" [ "$(field "$J" 'Object.keys(b.caps).length')" = 0 ]
printf -- '---\ntrunk: main\nkitchen_mode: clone\nbudget:\n  shift_usd: 60\n  ticket_usd: 12\n---\n' > "$APP/.claude/brigade.md"
J="$("$K" budget --json)"
ok "a budget: block gives the Ledger its scale" [ "$(field "$J" 'b.caps.shift_usd + "/" + b.caps.ticket_usd')" = 60/12 ]
printf -- '---\ntrunk: main\nkitchen_mode: clone\n---\n' > "$APP/.claude/brigade.md"

section "prices from the config"
printf -- '---\ntrunk: main\nkitchen_mode: clone\nprices:\n  opus: { in: 8, out: 40, read: 0.4 }\n---\n' > "$APP/.claude/brigade.md"
J="$("$K" budget --json)"
ok "a prices: block in brigade.md overrides the built-in table" [ "$(field "$J" 'b.sessions.find(s=>s.id==="cook1").cost')" = 1.218 ]
printf -- '---\ntrunk: main\nkitchen_mode: clone\n---\n' > "$APP/.claude/brigade.md"

section "windows and roles"
OUT="$("$K" budget --since 7d)"
ok "--since 7d says since when" has "$OUT" "^Shift \(since 20[0-9][0-9]-"
ok "a week is as far back as it looks" has "$("$K" budget --since 30d)" "^Shift \(since .*today\)"
ok "budget from a station reports the whole kitchen" has "$(cd "$APP/stations/station-1" && "$K" budget --since 7d)" "BKLG-001 +station-1"
ok "without node it says what to install" has "$(PATH="$TMP/nonode" "$K" budget 2>&1)" "needs node 20"

# =============================================================================
echo "# passed $PASS · failed $FAIL · total $N"
[[ $FAIL -eq 0 ]]
