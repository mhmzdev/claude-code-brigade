#!/usr/bin/env node
// session-state.js — what one session's transcript says about clearing it (Contract 5, the
// sous clears sessions). `kitchen.sh clear` and `kitchen.sh board` call it:
//
//   node session-state.js <transcript.jsonl>
//
// prints one key=value per line, for a shell to read:
//   lastTurnStart=<ms>   when the session's last turn began (the last message typed or sent to
//                        it), 0 if none: a handoff written after this is a fresh one
//   open=<kind|none>     the last message the session sent that still waits for an answer
//                        ([gate], [plan], [handoff], [walk-in] with nothing received since)
//   lastRead=<tokens>    cache-read tokens per turn over the last ten turns
//   over=<n>             how many turns were over the context line
//   line=<tokens>        the context line itself (budget.js CONTEXT_LINE)
//
// Nothing here decides anything: kitchen.sh does, from these numbers.
import fs from 'node:fs';
import { scanTranscript, CONTEXT_LINE } from './budget.js';

const WAITS = new Set(['gate', 'plan', 'handoff', 'walk-in']);

export function sessionState(file) {
  const st = scanTranscript(file);
  // The last turn's start: the last user line that is text, not a tool result.
  let lastTurnStart = 0;
  let text = ''; try { text = fs.readFileSync(file, 'utf8'); } catch { /* unreadable: no turns */ }
  for (const line of text.split('\n')) {
    if (!line) continue;
    let o; try { o = JSON.parse(line); } catch { continue; }
    if (o?.type !== 'user') continue;
    const content = o.message?.content;
    const isResult = Array.isArray(content) && content.some((b) => b.type === 'tool_result');
    if (isResult) continue;
    const t = Date.parse(o.timestamp) || 0;
    if (t > lastTurnStart) lastTurnStart = t;
  }
  // The last thing it sent that waits: an out mark of a waiting kind with no in mark after it.
  const marks = [...st.marks].sort((a, b) => (a.t || 0) - (b.t || 0));
  let open = 'none';
  for (const m of marks) {
    if (m.dir === 'out' && WAITS.has(m.kind)) open = m.kind;
    else if (m.dir === 'in') open = 'none';
  }
  const last = st.turns.slice(-10);
  const lastRead = last.length ? Math.round(last.reduce((a, t) => a + (t.u?.read || 0), 0) / last.length) : 0;
  const over = st.turns.filter((t) => (t.u?.read || 0) > CONTEXT_LINE).length;
  return { lastTurnStart, open, lastRead, over, line: CONTEXT_LINE };
}

const isMain = process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(new URL(import.meta.url).pathname);
if (isMain) {
  const file = process.argv[2];
  if (!file) { console.error('usage: session-state.js <transcript.jsonl>'); process.exit(2); }
  const s = sessionState(file);
  for (const [k, v] of Object.entries(s)) console.log(`${k}=${v}`);
}
