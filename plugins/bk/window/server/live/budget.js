// The kitchen's budget: what each session and each ticket spends, in tokens, money, time
// and CI minutes. Nothing here is recorded by the kitchen itself: Claude Code already
// writes every API turn's usage and model into the session transcript
// (<config>/projects/<cwd slug>/<sessionId>.jsonl) and every sub-agent's into
// <sessionId>/subagents/agent-<id>.jsonl, so the budget is read, not kept. Two things are
// kept, in .claude/budget.jsonl (out of git): a line per served ticket, because Claude Code
// deletes transcripts after its cleanup period, and the CI minutes `gh` reports per branch.
//
// Shared by kitchen.sh budget (the CLI at the bottom of this file) and the Window's server.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// ---------- prices ----------
// USD per million tokens, Anthropic list prices as of PRICES_AS_OF. `read` is a cache read;
// a cache write costs 1.25x input for the 5-minute kind and 2x for the 1-hour kind. The first
// pattern that matches the model id wins; a `prices:` block in .claude/brigade.md is tried
// first (Contract 2). An unknown model still has its tokens counted, with no price.
export const PRICES_AS_OF = '2026-10-24';
export const PRICES = [
  [/fable|mythos/, { in: 10, out: 50, read: 0.25 }],
  [/opus-5-5/, { in: 4, out: 20, read: 0.20 }],
  [/opus/, { in: 5, out: 25, read: 0.50 }],
  [/sonnet-5/, { in: 2, out: 10, read: 0.20 }],
  [/sonnet/, { in: 3, out: 15, read: 0.30 }],
  [/haiku-5/, { in: 0.10, out: 0.50, read: 0.01 }],
  [/haiku-4-5/, { in: 1, out: 5, read: 0.10 }],
  [/haiku/, { in: 0.80, out: 4, read: 0.08 }],
];
// GitHub-hosted runners, USD per minute, list rates as of PRICES_AS_OF; a public repo pays nothing.
export const CI_RATES = { UBUNTU: 0.008, MACOS: 0.08, WINDOWS: 0.016 };

export function priceFor(model, overrides = []) {
  const m = String(model || '').toLowerCase();
  for (const [key, p] of overrides) if (m.includes(String(key).toLowerCase())) return p;
  for (const [re, p] of PRICES) if (re.test(m)) return p;
  return null;
}
// Cost of one usage record, or null when the model has no price.
export function costOf(u, model, overrides) {
  const p = priceFor(model, overrides); if (!p) return null;
  return (u.in * p.in + u.out * p.out + u.read * p.read + u.w5 * p.in * 1.25 + u.w1 * p.in * 2) / 1e6;
}
// The `prices:` block of .claude/brigade.md: `  <substring of a model id>: { in: 4, out: 20, read: 0.2 }`.
export function readPriceOverrides(root) {
  const file = path.join(root, '.claude', 'brigade.md');
  let text; try { text = fs.readFileSync(file, 'utf8'); } catch { return []; }
  const block = text.match(/^prices:\n((?:[ \t]+.*\n?)*)/m); if (!block) return [];
  const out = [];
  for (const line of block[1].split('\n')) {
    const m = line.match(/^[ \t]+([\w.\-[\]]+):\s*\{([^}]*)\}/); if (!m) continue;
    const p = { in: 0, out: 0, read: 0 };
    for (const kv of m[2].split(',')) { const [k, v] = kv.split(':').map((s) => s.trim()); if (k in p) p[k] = Number(v) || 0; }
    out.push([m[1], p]);
  }
  return out;
}

// The `budget:` block of .claude/brigade.md: `  shift_usd: 60` and `  ticket_usd: 12`, the scale the Ledger
// draws spend against. A meter, not a limit (Contract 2).
export function readCaps(root) {
  const file = path.join(root, '.claude', 'brigade.md');
  let text; try { text = fs.readFileSync(file, 'utf8'); } catch { return {}; }
  const block = text.match(/^budget:\n((?:[ \t]+.*\n?)*)/m); if (!block) return {};
  const out = {};
  for (const line of block[1].split('\n')) { const m = line.match(/^[ \t]+(shift_usd|ticket_usd):\s*([\d.]+)/); if (m) out[m[1]] = Number(m[2]); }
  return out;
}

// ---------- reading one transcript ----------
const TICKET = /\b(S\d{3}-\d{2}|BKLG-\d{3}|HYG-\d{3})\b/i;
const KIND = /^\s*\[([a-z-]+)\]/i;
const zero = () => ({ in: 0, out: 0, read: 0, w5: 0, w1: 0 });
const add = (a, b) => { a.in += b.in; a.out += b.out; a.read += b.read; a.w5 += b.w5; a.w1 += b.w1; return a; };
const total = (u) => u.in + u.out + u.read + u.w5 + u.w1;

function usageOf(msg) {
  const u = msg.usage || {};
  const cc = u.cache_creation || {};
  const w = u.cache_creation_input_tokens || 0;
  const w1 = cc.ephemeral_1h_input_tokens || 0;
  return { in: u.input_tokens || 0, out: u.output_tokens || 0, read: u.cache_read_input_tokens || 0, w5: Math.max(0, w - w1), w1 };
}

// Reads a transcript incrementally. `st` is the per-file state kept between calls (offset,
// the partial last line, the turns seen so far). One API turn is written as several lines
// that share message.id, each carrying the whole turn's usage, so it is counted once.
export function scanTranscript(file, st = null) {
  st ||= { offset: 0, rest: '', byId: new Map(), turns: [], marks: [], agents: new Map(), pendingAgents: new Map(), first: null, last: null, size: 0, lastText: '' };
  let size; try { size = fs.statSync(file).size; } catch { return st; }
  if (size < st.offset) Object.assign(st, { offset: 0, rest: '', byId: new Map(), turns: [], marks: [], first: null, last: null });
  if (size === st.offset) return st;
  const fd = fs.openSync(file, 'r');
  let text;
  try { const buf = Buffer.alloc(size - st.offset); fs.readSync(fd, buf, 0, buf.length, st.offset); text = st.rest + buf.toString('utf8'); } finally { fs.closeSync(fd); }
  st.offset = size; st.size = size;
  const lines = text.split('\n'); st.rest = lines.pop();
  for (const line of lines) {
    if (!line) continue;
    let o; try { o = JSON.parse(line); } catch { continue; }
    if (!o || typeof o !== 'object' || (o.type !== 'assistant' && o.type !== 'user')) continue;
    const t = Date.parse(o.timestamp) || null;
    if (t) { st.first ||= t; st.last = t; }
    const msg = o.message || {}; const content = Array.isArray(msg.content) ? msg.content : [];
    if (o.type === 'assistant') {
      const id = msg.id || o.uuid;
      const u = usageOf(msg);
      if (st.byId.has(id)) { const turn = st.byId.get(id); turn.u.out = Math.max(turn.u.out, u.out); }
      else { const turn = { t, model: msg.model || null, u }; st.byId.set(id, turn); st.turns.push(turn); }
      for (const b of content) {
        if (b.type === 'text' && b.text && b.text.trim()) st.lastText = b.text.trim().slice(0, 400);
        if (b.type !== 'tool_use') continue;
        const inp = b.input || {};
        if (b.name === 'Agent') st.pendingAgents.set(b.id, { kind: String(inp.subagent_type || 'agent').replace(/^bk:/, ''), note: `${inp.description || ''} ${inp.prompt || ''}` });
        else if (b.name === 'SendMessage') { const text = String(inp.message || inp.content || inp.summary || ''); st.marks.push({ t, dir: 'out', kind: (text.match(KIND) || [])[1] || 'note', ticket: (text.match(TICKET) || [])[1]?.toUpperCase() || null, text: text.slice(0, 200) }); }
      }
    } else {
      for (const b of content) {
        if (b.type !== 'tool_result') continue;
        const a = st.pendingAgents.get(b.tool_use_id);
        if (a) { st.pendingAgents.delete(b.tool_use_id); const agentId = o.toolUseResult?.agentId; if (agentId) st.agents.set(agentId, { ...a, ticket: (a.note.match(TICKET) || [])[1]?.toUpperCase() || null }); }
      }
      // Text the session was sent: the head chef's prompt, or a message from another session.
      // A message from another session arrives wrapped: "Another Claude session sent a message:\n<cross-session-message …>\n[kind] …".
      const raw = typeof msg.content === 'string' ? msg.content : content.filter((b) => b.type === 'text').map((b) => b.text).join(' ');
      const typed = raw.replace(/^[^<]*<cross-session-message[^>]*>\s*/, '');
      if (typed && !content.some((b) => b.type === 'tool_result')) { const k = (typed.match(KIND) || [])[1]; if (k) st.marks.push({ t, dir: 'in', kind: k, ticket: (typed.match(TICKET) || [])[1]?.toUpperCase() || null, text: typed.slice(0, 200) }); }
    }
  }
  return st;
}

// ---------- the kitchen's sessions ----------
const slug = (p) => p.replace(/[^A-Za-z0-9]/g, '-');
const realpath = (p) => { try { return fs.realpathSync(p); } catch { return p; } };
export const configDir = () => process.env.CLAUDE_CONFIG_DIR || path.join(process.env.HOME || '', '.claude');

// Every transcript of the main checkout and the stations: [{ file, dir, role, sessionId }].
export function kitchenTranscripts({ root, stations }) {
  const base = path.join(configDir(), 'projects');
  const places = [[root, 'sous'], ...stations.map((d) => [d, path.basename(d)])];
  const out = [], seen = new Set();
  for (const [dir, role] of places) {
    for (const d of new Set([dir, realpath(dir)])) {
      const pdir = path.join(base, slug(d));
      let files = []; try { files = fs.readdirSync(pdir).filter((f) => f.endsWith('.jsonl')); } catch { continue; }
      for (const f of files) { const file = path.join(pdir, f); if (seen.has(file)) continue; seen.add(file); out.push({ file, dir: pdir, role, sessionId: f.replace(/\.jsonl$/, '') }); }
    }
  }
  return out;
}

// ---------- the budget itself ----------
const IDLE_GAP = 5 * 60 * 1000; // a gap longer than this is the session waiting, not working
const PHASES = [['plan', 'brief', 'plan'], ['wait', 'plan', 'approved'], ['build', 'approved', 'handoff'], ['pass', 'handoff', 'go'], ['ship', 'go', 'served']];

export function createBudget({ root, stations = () => [], ledgerFile = path.join(root, '.claude', 'budget.jsonl'), now = Date.now } = {}) {
  const states = new Map();   // file → scan state
  const overrides = readPriceOverrides(root);
  const unknown = new Set();

  const sum = (turns) => {
    const u = zero(); let cost = 0, priced = true, model = null;
    for (const x of turns) { add(u, x.u); if (!x.model || x.model.startsWith('<')) continue; model = x.model; const c = costOf(x.u, x.model, overrides); if (c === null) { priced = false; unknown.add(x.model); } else cost += c; }
    return { tokens: u, total: total(u), cost: priced || cost ? round(cost) : 0, priced, model };
  };
  const activeSecs = (turns) => { let s = 0; for (let i = 1; i < turns.length; i++) { const g = turns[i].t - turns[i - 1].t; if (g > 0 && g <= IDLE_GAP) s += g; } return Math.round(s / 1000); };

  // One session: its own turns, its sub-agents (each priced on its own model), its ticket spans.
  function session({ file, dir, role, sessionId }) {
    const st = scanTranscript(file, states.get(file)); states.set(file, st);
    const own = sum(st.turns);
    const helpers = {};
    let agentFiles = []; try { agentFiles = fs.readdirSync(path.join(dir, sessionId, 'subagents')).filter((f) => /^agent-.*\.jsonl$/.test(f)); } catch { /* none */ }
    const agentRuns = [];
    for (const f of agentFiles) {
      const af = path.join(dir, sessionId, 'subagents', f);
      const as = scanTranscript(af, states.get(af)); states.set(af, as);
      const meta = st.agents.get(f.replace(/^agent-|\.jsonl$/g, '')) || { kind: 'agent', ticket: null };
      const s = sum(as.turns);
      const run = { kind: meta.kind, ticket: meta.ticket, t: as.first, secs: as.first && as.last ? Math.round((as.last - as.first) / 1000) : 0, note: String(meta.note || '').trim().split(/\s+do\s+/)[0].slice(0, 80), ok: meta.kind === 'runner' ? verdict(as.lastText) : null, ...s };
      agentRuns.push(run);
      const h = (helpers[meta.kind] ||= { runs: 0, cost: 0, total: 0, secs: 0 });
      h.runs++; h.cost = round(h.cost + s.cost); h.total += s.total; h.secs += run.secs;
    }
    const helperCost = agentRuns.reduce((a, r) => a + r.cost, 0), helperTotal = agentRuns.reduce((a, r) => a + r.total, 0);
    return {
      id: sessionId, role, file, model: own.model, startedAt: st.first, lastAt: st.last, turns: st.turns.length,
      tokens: own.tokens, total: own.total, cost: own.cost, priced: own.priced,
      helpers, helperCost: round(helperCost), helperTotal, allCost: round(own.cost + helperCost), allTotal: own.total + helperTotal,
      secs: st.first && st.last ? Math.round((st.last - st.first) / 1000) : 0, activeSecs: activeSecs(st.turns),
      _turns: st.turns, _marks: st.marks, _agents: agentRuns,
    };
  }

  // A cook's ticket spans: from the brief (or the first message naming the ticket) to [served].
  function spans(s) {
    const out = []; let cur = null;
    const marks = [...s._marks].sort((a, b) => (a.t || 0) - (b.t || 0));
    for (const m of marks) {
      if (m.ticket && (!cur || (cur.id !== m.ticket && cur.servedAt))) { cur = { id: m.ticket, cook: s.role, session: s.id, from: m.t, servedAt: null, marks: {} }; out.push(cur); }
      if (!cur) continue;
      if (m.kind === 'brief' && m.dir === 'in' && (!m.ticket || m.ticket === cur.id)) cur.marks.brief ||= m.t;
      if (['plan', 'handoff', 'served'].includes(m.kind) && m.dir === 'out') cur.marks[m.kind] ||= m.t;
      if (['approved', 'go'].includes(m.kind) && m.dir === 'in') cur.marks[m.kind] ||= m.t;
      if (m.kind === 'served' && m.dir === 'out') cur.servedAt = m.t;
    }
    for (const sp of out) {
      const start = sp.marks.brief || sp.from, end = sp.servedAt || null;
      const turns = s._turns.filter((t) => t.t >= start && (!end || t.t <= end));
      const own = sum(turns);
      const agents = s._agents.filter((a) => a.t >= start && (!end || a.t <= end));
      Object.assign(sp, { startedAt: start, status: end ? 'served' : 'open', secs: Math.round(((end || now()) - start) / 1000),
        tokens: own.tokens, total: own.total, cost: own.cost, _runs: agents, _turns: turns, model: own.model,
        phases: Object.fromEntries(PHASES.map(([name, a, b]) => [name, sp.marks[a] && sp.marks[b] ? Math.max(0, Math.round((sp.marks[b] - sp.marks[a]) / 1000)) : null])) });
      delete sp.from;
      finish(sp);
    }
    return out;
  }
  const fold = (runs) => { const h = {}; for (const r of runs) { const x = (h[r.kind] ||= { runs: 0, cost: 0, total: 0, secs: 0 }); x.runs++; x.cost = round(x.cost + r.cost); x.total += r.total; x.secs += r.secs; } return h; };
  const merge = (a, b) => {
    const [x, y] = (a.startedAt || 0) <= (b.startedAt || 0) ? [a, b] : [b, a];
    const marks = { ...y.marks, ...x.marks }; if (y.marks.served) marks.served = y.marks.served;
    const m = { ...x, marks, session: y.session, servedAt: y.servedAt || x.servedAt, status: y.servedAt || x.servedAt ? 'served' : 'open', tokens: add(zero(), x.tokens), total: x.total + y.total, cost: round(x.cost + y.cost), _runs: [...x._runs, ...y._runs], _turns: [...x._turns, ...y._turns], model: y.model || x.model };
    add(m.tokens, y.tokens);
    m.secs = Math.round(((m.servedAt || now()) - m.startedAt) / 1000);
    m.phases = Object.fromEntries(PHASES.map(([name, p, q]) => [name, marks[p] && marks[q] ? Math.max(0, Math.round((marks[q] - marks[p]) / 1000)) : null]));
    finish(m); return m;
  };
  // Stages: prep (brief → the sign-off), cook (→ handoff), check (→ go), serve (→ served). A ticket
  // without a plan (hygiene) cooks from the brief. Steps: the cook's own turns per stage, and every
  // sub-agent run. Rework: everything after the first red runner until the next green one.
  const STAGES = ['prep', 'cook', 'check', 'serve'];
  const finish = (sp) => {
    sp.helpers = fold(sp._runs); sp.helperCost = round(sp._runs.reduce((a, r) => a + r.cost, 0)); sp.allCost = round(sp.cost + sp.helperCost);
    const mk = sp.marks || {}, prepEnd = mk.approved || mk.plan || null;
    const bounds = [prepEnd, mk.handoff || null, mk.go || null];
    const stageAt = (t) => { for (let i = 0; i < 3; i++) if (bounds[i] && t < bounds[i]) return STAGES[i]; return bounds[2] ? 'serve' : bounds[1] ? 'check' : (prepEnd || /^HYG-/.test(sp.id)) ? 'cook' : 'prep'; };
    const stages = Object.fromEntries(STAGES.map((k) => [k, { cost: 0, total: 0, secs: 0, steps: 0 }]));
    const steps = [];
    for (const k of STAGES) {
      const turns = sp._turns.filter((t) => stageAt(t.t) === k); if (!turns.length) continue;
      const s = sum(turns), secs = activeSecs(turns);
      steps.push({ t: turns[0].t, stage: k, who: sp.cook, model: s.model, kind: 'own', note: `${turns.length} turns`, cost: s.cost, total: s.total, secs, ok: null });
    }
    for (const r of sp._runs) steps.push({ t: r.t, stage: stageAt(r.t), who: r.kind, model: r.model, kind: r.kind, note: r.note || '', cost: r.cost, total: r.total, secs: r.secs, ok: r.ok });
    steps.sort((a, b) => (a.t || 0) - (b.t || 0));
    for (const st of steps) { const g = stages[st.stage]; g.cost = round(g.cost + st.cost); g.total += st.total; g.secs += st.secs; g.steps++; }
    sp.stages = stages; sp.steps = steps;
    const red = steps.find((s) => s.kind === 'runner' && s.ok === false);
    if (red) {
      const green = steps.find((s) => s.kind === 'runner' && s.ok === true && s.t > red.t);
      const after = (t) => t > red.t && (!green || t <= green.t);
      const turns = sp._turns.filter((t) => after(t.t)), runs = sp._runs.filter((r) => after(r.t));
      const s = sum(turns);
      sp.rework = { reds: steps.filter((s) => s.kind === 'runner' && s.ok === false).length, cost: round(s.cost + runs.reduce((a, r) => a + r.cost, 0)), secs: activeSecs(turns) + runs.reduce((a, r) => a + r.secs, 0), settled: !!green };
    } else sp.rework = null;
  };

  // The ledger: served tickets and CI results, one JSON line each, latest wins.
  function readLedger() {
    const tickets = new Map(), ci = new Map();
    let text = ''; try { text = fs.readFileSync(ledgerFile, 'utf8'); } catch { return { tickets, ci }; }
    for (const line of text.split('\n')) { if (!line.trim()) continue; try { const o = JSON.parse(line); if (o.kind === 'ci') ci.set(o.ticket, o); else if (o.kind === 'ticket') tickets.set(o.id, o); } catch { /* a foreign line */ } }
    return { tickets, ci };
  }
  function append(o) { fs.mkdirSync(path.dirname(ledgerFile), { recursive: true }); fs.appendFileSync(ledgerFile, JSON.stringify(o) + '\n'); }

  // The whole picture since `since` (ms epoch; 0 for everything). `write` appends newly served
  // tickets to the ledger.
  function compute({ since = startOfToday(), write = false } = {}) {
    unknown.clear();
    const all = kitchenTranscripts({ root, stations: stations() }).map(session);
    const ledger = readLedger();
    const sessions = all.filter((s) => s.lastAt && s.lastAt >= since).sort((a, b) => (a.startedAt || 0) - (b.startedAt || 0));
    // Tickets: every span from every cook session (not just today's: a ticket may straddle days).
    // A ticket worked across two conversations (a /clear in between) is one ticket: its spans merge.
    const byId = new Map();
    for (const s of all) if (s.role !== 'sous') for (const sp of spans(s)) { const prev = byId.get(sp.id); byId.set(sp.id, prev ? merge(prev, sp) : sp); }
    // The sous's helpers that name a ticket (the taster at the pass) are that ticket's.
    for (const s of all) if (s.role === 'sous') for (const a of s._agents) { const sp = a.ticket && byId.get(a.ticket); if (sp && a.t >= sp.startedAt && (!sp.servedAt || a.t <= sp.servedAt + 60000)) { sp._runs.push(a); finish(sp); } }
    for (const [id, o] of ledger.tickets) if (!byId.has(id)) byId.set(id, { ...o, fromLedger: true });
    for (const [id, c] of ledger.ci) { const sp = byId.get(id); if (sp) sp.ci = { minutes: c.minutes, cost: c.cost, runs: c.runs, branch: c.branch, at: c.t, public: c.public }; }
    if (write) for (const sp of byId.values()) if (sp.status === 'served' && !sp.fromLedger && !ledger.tickets.has(sp.id)) append({ kind: 'ticket', t: sp.servedAt, ...strip(sp) });
    const tickets = [...byId.values()].filter((t) => (t.servedAt || now()) >= since).sort((a, b) => (a.startedAt || 0) - (b.startedAt || 0)).map(strip);
    const shift = { tokens: zero(), total: 0, cost: 0, secs: 0, activeSecs: 0, helperCost: 0, ci: { minutes: 0, cost: 0 } };
    for (const s of sessions) { add(shift.tokens, s.tokens); shift.total += s.allTotal; shift.cost += s.allCost; shift.secs += s.secs; shift.activeSecs += s.activeSecs; shift.helperCost += s.helperCost; }
    for (const t of tickets) if (t.ci) { shift.ci.minutes += t.ci.minutes; shift.ci.cost += t.ci.cost; }
    shift.cost = round(shift.cost); shift.helperCost = round(shift.helperCost); shift.ci.cost = round(shift.ci.cost); shift.ci.minutes = Math.round(shift.ci.minutes * 10) / 10;
    // Per actor: the role's sessions today, and its current (latest) one.
    const actors = {}, today = startOfToday();
    for (const s of sessions.filter((x) => (x.lastAt || 0) >= today)) { const a = (actors[s.role] ||= { sessions: 0, cost: 0, total: 0, secs: 0, activeSecs: 0, helpers: {}, current: null }); a.sessions++; a.cost = round(a.cost + s.allCost); a.total += s.allTotal; a.secs += s.secs; a.activeSecs += s.activeSecs; for (const [k, h] of Object.entries(s.helpers)) { const x = (a.helpers[k] ||= { runs: 0, cost: 0, total: 0, secs: 0 }); x.runs += h.runs; x.cost = round(x.cost + h.cost); x.total += h.total; x.secs += h.secs; } a.current = pub(s); }
    const sousNow = all.filter((s) => s.role === 'sous').sort((a, b) => (b.lastAt || 0) - (a.lastAt || 0))[0];
    const windows = { shift: sousNow?.startedAt || startOfToday(), today: startOfToday(), week: now() - 7 * 86400000 };
    return { asOf: PRICES_AS_OF, since, computedAt: now(), shift, sessions: sessions.map(pub), tickets, actors, unknownModels: [...unknown], windows, caps: readCaps(root) };
  }
  const pub = (s) => { const { _turns, _marks, _agents, file, ...rest } = s; return rest; };
  const strip = (sp) => { const { marks, fromLedger, _runs, _turns, ...rest } = sp; return rest; };

  // CI minutes for one ticket's branch, through gh; written to the ledger. Returns the record or null.
  function ci(ticket, { branch = null, gh = runGh } = {}) {
    const q = gh(['pr', 'list', '--state', 'all', '--search', `${ticket} in:title`, '--json', 'number,headRefName,url', '--limit', '3']);
    const prs = parse(q) || [];
    branch ||= prs[0]?.headRefName || null;
    if (!branch) return null;
    const runs = parse(gh(['run', 'list', '--branch', branch, '--json', 'databaseId,conclusion,createdAt', '--limit', '100'])) || [];
    const repo = parse(gh(['repo', 'view', '--json', 'isPrivate,nameWithOwner'])) || {};
    const minutes = { UBUNTU: 0, MACOS: 0, WINDOWS: 0 }; let unbilled = 0;
    for (const r of runs) {
      const t = parse(gh(['api', `repos/${repo.nameWithOwner || '{owner}/{repo}'}/actions/runs/${r.databaseId}/timing`])) || {};
      let any = false;
      for (const os of Object.keys(minutes)) { const ms = t.billable?.[os]?.total_ms || 0; if (ms) { any = true; minutes[os] += ms / 60000; } }
      if (!any && t.run_duration_ms) unbilled += t.run_duration_ms / 60000;
    }
    const billed = Object.values(minutes).reduce((a, b) => a + b, 0);
    const cost = repo.isPrivate === false ? 0 : Object.entries(minutes).reduce((a, [os, m]) => a + m * CI_RATES[os], 0);
    const rec = { kind: 'ci', t: now(), ticket, branch, pr: prs[0]?.number || null, runs: runs.length, minutes: Math.round((billed || unbilled) * 10) / 10, byOs: minutes, unbilled: !billed, public: repo.isPrivate === false, cost: round(cost) };
    append(rec);
    return rec;
  }
  return { compute, ci, spans, session, overrides };
}

const round = (n) => Math.round(n * 10000) / 10000;
// A runner's reply says pass or fail; the same reading as the Window's check machine.
export const verdict = (v) => { v = String(v || ''); return /\b(fail|failed|failing|error|errors|red|not ok|✕|✗)\b/i.test(v) ? false : /\b(pass|passed|passing|ok|green|clean|✓|success)\b/i.test(v) ? true : null; };
const parse = (s) => { try { return JSON.parse(s); } catch { return null; } };
function runGh(args) { try { return execFileSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }); } catch { return ''; } }
export function startOfToday(d = new Date()) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime(); }

// ---------- formatting, shared by the CLI and the Window ----------
export const fmtTokens = (n) => n >= 1e6 ? `${(n / 1e6).toFixed(n >= 1e7 ? 0 : 1)}M` : n >= 1e3 ? `${Math.round(n / 1e3)}k` : String(n);
export const fmtUsd = (n, priced = true) => (priced || n ? `$${n >= 100 ? n.toFixed(0) : n >= 10 ? n.toFixed(1) : n.toFixed(2)}` : 'no price');
export const fmtSecs = (s) => { if (s == null) return '–'; if (s < 60) return `${s}s`; const m = Math.round(s / 60); return m < 60 ? `${m}m` : `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, '0')}m`; };
const hhmm = (t) => t ? new Date(t).toTimeString().slice(0, 5) : '–';
const helpersLine = (h) => Object.entries(h || {}).map(([k, x]) => `${k} ${x.runs} (${fmtUsd(x.cost)})`).join(', ') || '–';

// One line for a ticket's journal (Contract 11), written by open-pr at the PR: the ticket is
// still open then (no [served] yet), so the span runs brief→PR and has no ship phase or CI.
export function journalLine(t, session = '') {
  const d = new Date(t.servedAt || Date.now());
  const when = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')} ${hhmm(d)}`;
  const u = t.tokens || zero();
  const ph = Object.entries(t.phases || {}).filter(([, v]) => v != null).map(([k, v]) => `${k} ${fmtSecs(v)}`).join(', ');
  return `- ${when} · ${session || t.session || t.cook} · cost: ${fmtUsd(t.allCost ?? t.cost)} · ${fmtTokens(t.total)} tokens (in ${fmtTokens(u.in)}, out ${fmtTokens(u.out)}, cache read ${fmtTokens(u.read)}, cache write ${fmtTokens(u.w5 + u.w1)}) · ${t.status === 'served' ? 'brief→served' : 'brief→PR'} ${fmtSecs(t.secs)}${ph ? ` (${ph})` : ''} · helpers: ${helpersLine(t.helpers)}${t.ci ? ` · CI ${t.ci.minutes} min (${fmtUsd(t.ci.cost)})` : ''}`;
}

export function report(b, { ticket = null } = {}) {
  const lines = [];
  const u = b.shift.tokens;
  if (ticket) {
    const t = b.tickets.find((x) => x.id === ticket.toUpperCase());
    if (!t) return `No spend recorded for ${ticket}: no cook session names it, and the ledger has no line for it.`;
    lines.push(`${t.id}  ${t.status} · ${t.cook} · brief ${hhmm(t.startedAt)}${t.servedAt ? ` → served ${hhmm(t.servedAt)}` : ''} · ${fmtSecs(t.secs)}`);
    lines.push(`  cost      ${fmtUsd(t.allCost)}  (own ${fmtUsd(t.cost)}, helpers ${fmtUsd(t.helperCost)})`);
    lines.push(`  tokens    ${fmtTokens(t.total)}  in ${fmtTokens(t.tokens.in)} · out ${fmtTokens(t.tokens.out)} · cache read ${fmtTokens(t.tokens.read)} · cache write ${fmtTokens(t.tokens.w5 + t.tokens.w1)}`);
    lines.push(`  phases    ${Object.entries(t.phases).map(([k, v]) => `${k} ${fmtSecs(v)}`).join(' · ')}`);
    lines.push(`  helpers   ${helpersLine(t.helpers)}`);
    lines.push(`  CI        ${t.ci ? `${t.ci.minutes} min over ${t.ci.runs} runs on ${t.ci.branch} (${t.ci.public ? 'public repo, free' : fmtUsd(t.ci.cost)})` : 'not fetched (kitchen.sh budget --ci)'}`);
    return lines.join('\n');
  }
  const sinceLabel = `since ${new Date(b.since).toDateString() === new Date().toDateString() ? hhmm(b.since) + ' today' : new Date(b.since).toISOString().slice(0, 10)}`;
  lines.push(`Shift (${sinceLabel}): ${fmtUsd(b.shift.cost)} · ${fmtTokens(b.shift.total)} tokens (in ${fmtTokens(u.in)} · out ${fmtTokens(u.out)} · cache read ${fmtTokens(u.read)} · cache write ${fmtTokens(u.w5 + u.w1)}) · ${fmtSecs(b.shift.activeSecs)} working · CI ${b.shift.ci.minutes} min (${fmtUsd(b.shift.ci.cost)})`);
  lines.push(`Prices: Anthropic list as of ${b.asOf}${b.unknownModels.length ? `; no price for ${b.unknownModels.join(', ')} (add a prices: block to .claude/brigade.md)` : ''}.`);
  lines.push('');
  lines.push('Sessions');
  lines.push(`  ${'WHO'.padEnd(11)} ${'MODEL'.padEnd(8)} ${'START'.padEnd(6)} ${'WORKING'.padEnd(8)} ${'TOKENS'.padEnd(7)} ${'COST'.padEnd(7)} HELPERS`);
  for (const s of b.sessions) lines.push(`  ${s.role.padEnd(11)} ${String(shortModel(s.model) || '?').padEnd(8)} ${hhmm(s.startedAt).padEnd(6)} ${fmtSecs(s.activeSecs).padEnd(8)} ${fmtTokens(s.allTotal).padEnd(7)} ${fmtUsd(s.allCost, s.priced).padEnd(7)} ${helpersLine(s.helpers)}`);
  if (!b.sessions.length) lines.push('  (no sessions in this window)');
  lines.push('');
  lines.push('Tickets');
  lines.push(`  ${'ID'.padEnd(9)} ${'COOK'.padEnd(10)} ${'STATUS'.padEnd(7)} ${'B→S'.padEnd(7)} ${'PLAN'.padEnd(6)} ${'WAIT'.padEnd(6)} ${'BUILD'.padEnd(6)} ${'PASS'.padEnd(6)} ${'SHIP'.padEnd(6)} ${'TOKENS'.padEnd(7)} ${'COST'.padEnd(7)} CI`);
  for (const t of b.tickets) lines.push(`  ${t.id.padEnd(9)} ${String(t.cook).padEnd(10)} ${t.status.padEnd(7)} ${fmtSecs(t.secs).padEnd(7)} ${['plan', 'wait', 'build', 'pass', 'ship'].map((k) => fmtSecs(t.phases?.[k]).padEnd(6)).join(' ')} ${fmtTokens(t.total).padEnd(7)} ${fmtUsd(t.allCost).padEnd(7)} ${t.ci ? `${t.ci.minutes}m` : '–'}`);
  if (!b.tickets.length) lines.push('  (none)');
  return lines.join('\n');
}
export function shortModel(m) { const s = String(m || '').toLowerCase(); for (const n of ['fable', 'opus', 'sonnet', 'haiku']) if (s.includes(n)) return n; return m || null; }

// ---------- the CLI: node budget.js --root <repo> [--since today|7d] [--ticket ID] [--ci] [--json] [--journal-line] ----------
// A week is as far back as the budget looks: the numbers live on this machine and the
// transcripts are pruned anyway.
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const flag = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
  const { readConfig } = await import('./config.js');
  const cfg = readConfig(path.resolve(flag('--root', process.cwd())));
  const sinceArg = flag('--since', 'today');
  const since = sinceArg === '7d' || sinceArg === 'week' ? Date.now() - 7 * 86400000 : startOfToday();
  const budget = createBudget({ root: cfg.root, stations: cfg.stations });
  const ticket = flag('--ticket', null);
  if (args.includes('--ci')) {
    const b0 = budget.compute({ since: ticket ? 0 : since, write: true });
    const ids = ticket ? [ticket.toUpperCase()] : b0.tickets.map((t) => t.id);
    for (const id of ids) { const r = budget.ci(id); if (!r) console.error(`${id}: no PR found, so no CI runs to count.`); }
  }
  const b = budget.compute({ since: ticket ? 0 : since, write: true });
  if (args.includes('--json')) console.log(JSON.stringify(ticket ? b.tickets.find((t) => t.id === ticket.toUpperCase()) || null : b, null, 2));
  else if (args.includes('--journal-line')) { const t = b.tickets.find((x) => x.id === String(ticket).toUpperCase()); if (!t) { console.error(`No spend recorded for ${ticket}.`); process.exit(1); } console.log(journalLine(t, flag('--session', ''))); }
  else console.log(report(b, { ticket }));
}
