// The Ledger: the budget as a page. Reads the same event stream as the room, keeps the
// budget part of the snapshot, and draws it as dishes (tickets) or sessions over the shift,
// today or the week. Plain DOM, no dependencies, re-rendered on every snapshot.
const $ = (s) => document.querySelector(s);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmtTok = (n) => n >= 1e6 ? `${(n / 1e6).toFixed(n >= 1e7 ? 0 : 1)}M` : n >= 1e3 ? `${Math.round(n / 1e3)}k` : String(Math.round(n || 0));
const fmtUsd = (n) => n == null ? '–' : `$${n >= 100 ? n.toFixed(0) : n >= 10 ? n.toFixed(1) : n.toFixed(2)}`;
const fmtSecs = (x) => { if (x == null) return '–'; if (x < 60) return `${Math.round(x)}s`; const m = Math.round(x / 60); return m < 60 ? `${m}m` : `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, '0')}m`; };
const hhmm = (t) => t ? new Date(t).toTimeString().slice(0, 5) : '–';
const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
const STAGES = [['prep', 'Prep'], ['cook', 'Cook'], ['check', 'Check'], ['serve', 'Serve']];
const COLOR = { prep: 'var(--prep)', cook: 'var(--cook)', check: 'var(--check)', serve: 'var(--serve)', kitchen: 'var(--kitchen)' };
const MARKS = ['#d4654f', '#e9a93c', '#6f9bd6', '#4fa86f', '#8e6bd6', '#e0843c', '#3fb0b0', '#c75a9a', '#9aa84f', '#5a7fd6', '#d6a04f', '#7a6bd6'];
const markOf = (who) => who === 'sous' ? '#7d776c' : MARKS[(Number(String(who).replace(/\D+/g, '')) - 1 + 12) % 12] || '#7d776c';
const nameOf = (who) => who === 'sous' ? 'Sous Chef' : /^station-/.test(who) ? `Cook ${who.replace(/\D+/g, '')}` : who;

let state = null, ui = { view: 'dishes', range: 'shift', open: null, all: null, sess: null };

// ---------- the window: which sessions and tickets count ----------
function inWindow(b) {
  const since = b.windows?.[ui.range] ?? b.since ?? 0, now = b.computedAt || Date.now();
  const sessions = b.sessions.filter((s) => (s.lastAt || 0) >= since);
  const tickets = b.tickets.filter((t) => (t.servedAt || now) >= since);
  return { since, now, sessions, tickets };
}
// Spend by stage across the window's tickets, plus the kitchen's overhead: what the sessions spent that no ticket claims.
function split(sessions, tickets) {
  const seg = Object.fromEntries(STAGES.map(([k]) => [k, { cost: 0, secs: 0, steps: 0 }]));
  for (const t of tickets) for (const [k] of STAGES) { const g = t.stages?.[k]; if (!g) continue; seg[k].cost += g.cost; seg[k].secs += g.secs; seg[k].steps += g.steps; }
  const sessionsCost = sessions.reduce((a, s) => a + s.allCost, 0), ticketsCost = tickets.reduce((a, t) => a + t.allCost, 0);
  seg.kitchen = { cost: Math.max(0, sessionsCost - ticketsCost), secs: 0, steps: 0 };
  return seg;
}

// ---------- the top strip ----------
function renderSummary(b, w) {
  const seg = split(w.sessions, w.tickets);
  const spent = w.sessions.reduce((a, s) => a + s.allCost, 0);
  const ci = w.tickets.reduce((a, t) => a + (t.ci?.cost || 0), 0), ciMin = w.tickets.reduce((a, t) => a + (t.ci?.minutes || 0), 0);
  const total = spent + ci, cap = b.caps?.shift_usd;
  const hours = Math.max(0.25, (w.now - w.since) / 3600000), rate = total / hours;
  const bar = (scale) => ['prep', 'cook', 'check', 'serve', 'kitchen'].map((k) => `<span style="width:${scale ? Math.min(100, seg[k].cost / scale * 100) : 0}%;background:${COLOR[k]}" title="${k} ${fmtUsd(seg[k].cost)}"></span>`).join('');
  const unknown = b.unknownModels?.length ? `<span class="sub" style="color:var(--red)">no price for ${esc(b.unknownModels.join(', '))}</span>` : '';
  $('#summary').innerHTML = `<div>
      <span class="h">${ui.range === 'shift' ? 'SHIFT' : ui.range === 'today' ? 'TODAY' : 'THIS WEEK'} SPEND</span>
      <div class="big"><b>${fmtUsd(total)}</b>${cap ? `<span>of ${fmtUsd(cap)}</span>` : `<span>since ${hhmm(w.since)}${ui.range === 'week' ? ' a week ago' : ''}</span>`}</div>
      <span class="bar">${bar(cap || total)}</span>
      <span class="sub">${fmtUsd(rate)}/h${cap ? ` · ${cap > total ? `${((cap - total) / Math.max(rate, 0.01)).toFixed(1)}h left at this rate` : 'over the shift budget'}` : ''}</span>
      <span class="sub">Models <b style="color:var(--ink)">${fmtUsd(spent)}</b> · CI runners <b style="color:var(--ink)">${fmtUsd(ci)}</b> for ${Math.round(ciMin * 10) / 10} min</span>${unknown}
    </div>` + [...STAGES, ['kitchen', 'Kitchen']].map(([k, label]) => `<div><span class="h"><span class="sw" style="background:${COLOR[k]}"></span>${label.toUpperCase()}</span><b class="n">${fmtUsd(seg[k].cost)}</b><span class="sub">${total ? Math.round(seg[k].cost / total * 100) : 0}%${k === 'kitchen' ? ' · the sous, and work no ticket claims' : ` · ${plural(seg[k].steps, 'step')} · ${fmtSecs(seg[k].secs)}`}</span></div>`).join('');
}

// ---------- dishes ----------
const statusOf = (t) => { if (t.status === 'served') return ['served', 'SERVED']; const last = t.steps?.[t.steps.length - 1]?.stage; return last === 'serve' ? ['plating', 'PLATING'] : last === 'check' ? ['checking', 'CHECKING'] : last === 'cook' ? ['cooking', 'COOKING'] : ['prep', 'PREP']; };
function stageNote(k, t) {
  const g = t.stages?.[k], steps = (t.steps || []).filter((s) => s.stage === k);
  if (!g || !g.steps) return 'Not yet';
  if (k === 'prep') { const h = steps.filter((s) => s.kind !== 'own').map((s) => s.kind); return `plan${h.length ? ' + ' + h.join(' + ') : ''}${t.phases?.wait ? ` · waited ${fmtSecs(t.phases.wait)} for the sign-off` : ''}`; }
  if (k === 'cook') { const reds = steps.filter((s) => s.kind === 'runner' && s.ok === false).length, runs = steps.filter((s) => s.kind === 'runner').length; return runs ? `${plural(runs, 'check run')}${reds ? `, ${reds} red` : ', all green'}` : 'one pass, no check run yet'; }
  if (k === 'check') { const h = steps.filter((s) => s.kind !== 'own'); return h.length ? h.map((s) => s.kind + (s.ok === false ? ' (red)' : '')).join(', ') : 'the pass'; }
  return t.status === 'served' ? 'PR opened' : 'opening the PR';
}
function renderDishes(b, w) {
  const cap = b.caps?.ticket_usd;
  const rows = [...w.tickets].sort((a, x) => (x.startedAt || 0) - (a.startedAt || 0));
  if (!rows.length) { $('#body').innerHTML = '<p class="none">No ticket has been briefed in this window.</p>'; return; }
  $('#body').innerHTML = `<div class="table dishes"><div class="head"><span>DISH</span><span>STATION</span><span>STATUS</span><span>WHERE IT WENT</span><span class="r">TIME</span><span class="r">COST</span><span>${cap ? 'OF DISH CAP' : 'CI'}</span></div>` + rows.map((t) => {
    const [cls, label] = statusOf(t), open = ui.open === t.id, total = t.allCost || 0;
    const segs = STAGES.map(([k]) => `<span style="width:${total ? (t.stages?.[k]?.cost || 0) / total * 100 : 0}%;background:${COLOR[k]}"></span>`).join('');
    const p = cap ? total / cap : 0, capC = p > 1 ? 'var(--red)' : p > .75 ? 'var(--accent)' : 'var(--green)';
    const last = cap ? `<span class="cap"><span class="bar thin"><span style="width:${Math.min(100, p * 100)}%;background:${capC}"></span></span><span class="pct" style="color:${capC}">${Math.round(p * 100)}%</span></span>` : `<span class="t">${t.ci ? `${t.ci.minutes} min · ${t.ci.public ? 'free' : fmtUsd(t.ci.cost)}` : '–'}</span>`;
    return `<div class="item ${open ? 'open' : ''}" data-id="${esc(t.id)}">
      <button type="button" class="row" data-toggle="${esc(t.id)}"><span class="id"><span class="caret">${open ? '▼' : '▶'}</span>${esc(t.id)}</span><span class="who"><span class="mark" style="background:${markOf(t.cook)}"></span>${esc(nameOf(t.cook))}</span><span class="status ${cls}">${label}</span><span class="bar">${segs}</span><span class="t r">${fmtSecs(t.secs)}</span><b class="cost r">${fmtUsd(total)}</b>${last}</button>
      ${open ? renderDish(t) : ''}</div>`;
  }).join('') + '</div>';
}
function renderDish(t) {
  const u = t.tokens || {}, tokens = fmtTok(t.total + Object.values(t.helpers || {}).reduce((a, h) => a + h.total, 0));
  const cards = STAGES.map(([k, label]) => { const g = t.stages?.[k]; return `<div class="card ${g?.steps ? '' : 'empty'}" style="border-top-color:${COLOR[k]}"><span class="h">${label.toUpperCase()}</span><b class="n">${g?.steps ? fmtUsd(g.cost) : '—'}</b><span class="sub">${g?.steps ? `${fmtSecs(g.secs)} working · ${plural(g.steps, 'step')}` : ''}</span><span class="note">${esc(stageNote(k, t))}</span></div>`; }).join('');
  const redo = t.rework ? `<div class="redo">${t.rework.reds === 1 ? 'A red check' : `${t.rework.reds} red checks`} sent it back: the fix and the re-checks cost ${fmtUsd(t.rework.cost)} and ${fmtSecs(t.rework.secs)}${t.rework.settled ? '' : ', and it is not green yet'}.</div>` : '';
  const all = ui.all === t.id;
  const steps = all ? `<div class="steps"><div class="sh"><span>STAGE</span><span>WHO</span><span>WHAT</span><span>MODEL</span><span class="r">TIME</span><span class="r">COST</span></div>${(t.steps || []).map((s) => `<div class="sr"><span class="who"><span class="mark" style="background:${COLOR[s.stage]}"></span>${s.stage}</span><span class="muted">${esc(s.kind === 'own' ? nameOf(s.who) : s.who)}</span><span class="what"><span class="${s.ok === false ? 'bad' : ''}">${esc(s.note || '')}${s.ok === false ? ' · red' : s.ok === true ? ' · green' : ''}</span><span class="usage">${fmtTok(s.total)} tokens</span></span><span class="rate">${esc(String(s.model || '?').replace(/^claude-/, ''))}</span><span class="t r">${fmtSecs(s.secs)}</span><span class="r mono">${fmtUsd(s.cost)}</span></div>`).join('')}</div>` : '';
  return `<div class="detail"><div class="cards">${cards}</div>
    <div class="line"><span>Models <b>${fmtUsd(t.allCost)}</b> for ${tokens} tokens (in ${fmtTok(u.in || 0)} · out ${fmtTok(u.out || 0)} · cache read ${fmtTok(u.read || 0)} · cache write ${fmtTok((u.w5 || 0) + (u.w1 || 0))})</span><span>CI ${t.ci ? `<b>${t.ci.public ? 'free' : fmtUsd(t.ci.cost)}</b> for ${t.ci.minutes} min over ${plural(t.ci.runs, 'run')}` : 'not fetched yet'}</span><span>brief ${hhmm(t.startedAt)}${t.servedAt ? ` → served ${hhmm(t.servedAt)}` : ''}</span><span class="sp"></span><button type="button" data-all="${esc(t.id)}">${all ? 'Hide steps' : `Show all ${plural((t.steps || []).length, 'step')}`}</button></div>
    ${redo}${steps}</div>`;
}

// ---------- sessions ----------
function renderSessions(b, w) {
  const rows = [...w.sessions].sort((a, x) => (x.startedAt || 0) - (a.startedAt || 0));
  if (!rows.length) { $('#body').innerHTML = '<p class="none">No session has spoken in this window.</p>'; return; }
  $('#body').innerHTML = `<div class="table sessions"><div class="head"><span>SESSION</span><span>MODEL</span><span>START</span><span class="r">WORKING</span><span class="r">COST</span><span>HELPERS</span></div>` + rows.map((s) => {
    const open = ui.sess === s.id, helpers = Object.entries(s.helpers || {});
    const cards = open ? `<div class="detail"><div class="cards wrap"><div class="card" style="border-top-color:${markOf(s.role)}"><span class="h">${esc(nameOf(s.role).toUpperCase())}</span><b class="n">${fmtUsd(s.cost)}</b><span class="note">${plural(s.turns, 'turn')} · ${fmtTok(s.total)} tokens · ${fmtSecs(s.activeSecs)} working of ${fmtSecs(s.secs)}</span><span class="sub">in ${fmtTok(s.tokens.in)} · out ${fmtTok(s.tokens.out)} · cache read ${fmtTok(s.tokens.read)} · write ${fmtTok(s.tokens.w5 + s.tokens.w1)}</span></div>${helpers.map(([k, h]) => `<div class="card"><span class="h">${esc(k.toUpperCase())}</span><b class="n">${fmtUsd(h.cost)}</b><span class="note">${plural(h.runs, 'run')} · ${fmtTok(h.total)} tokens</span><span class="sub">${fmtSecs(h.secs)} in flight</span></div>`).join('')}</div></div>` : '';
    return `<div class="item ${open ? 'open' : ''}"><button type="button" class="row" data-sess="${esc(s.id)}"><span class="id"><span class="caret">${open ? '▼' : '▶'}</span><span class="mark" style="background:${markOf(s.role)}"></span>${esc(nameOf(s.role))}</span><span class="t">${esc(String(s.model || '?').replace(/^claude-/, ''))}</span><span class="t dim">${hhmm(s.startedAt)}</span><span class="t r">${fmtSecs(s.activeSecs)}</span><b class="cost r">${s.priced === false && !s.allCost ? 'no price' : fmtUsd(s.allCost)}</b><span class="helpers">${helpers.map(([k, h]) => `<span>${esc(k)} ×${h.runs} <b>${fmtUsd(h.cost)}</b></span>`).join('') || '<span class="dim">–</span>'}</span></button>${cards}</div>`;
  }).join('') + '</div>';
}

// ---------- render ----------
function render() {
  if (!state) return;
  const k = state.kitchen; $('#repo').textContent = k.repo; $('#mode').textContent = `${k.mode} · trunk ${k.trunk}`; $('#demo').hidden = !k.demo;
  for (const b of document.querySelectorAll('#views button')) b.classList.toggle('on', b.dataset.view === ui.view);
  for (const b of document.querySelectorAll('#ranges button')) b.classList.toggle('on', b.dataset.range === ui.range);
  const b = state.budget;
  if (!b) { $('#summary').innerHTML = ''; $('#body').innerHTML = '<p class="none">No budget yet: it is read from the session transcripts, so it appears once a session has spoken.</p>'; $('#foot').innerHTML = ''; return; }
  const w = inWindow(b);
  renderSummary(b, w);
  if (ui.view === 'dishes') renderDishes(b, w); else renderSessions(b, w);
  $('#foot').innerHTML = `<span>Prices: Anthropic list as of ${esc(b.asOf)}, per million tokens; cache writes at 1.25x input (2x for the 1-hour kind). CI at GitHub's list rates per runner minute, free on a public repo. A <code>prices:</code> or <code>budget:</code> block in .claude/brigade.md changes the table or the scale.</span><span class="sp"></span><span class="mono">kitchen.sh budget</span>`;
}

document.addEventListener('click', (e) => {
  const t = e.target.closest('[data-toggle],[data-all],[data-sess],[data-view],[data-range]'); if (!t) return;
  if (t.dataset.toggle) ui.open = ui.open === t.dataset.toggle ? null : t.dataset.toggle;
  if (t.dataset.all) ui.all = ui.all === t.dataset.all ? null : t.dataset.all;
  if (t.dataset.sess) ui.sess = ui.sess === t.dataset.sess ? null : t.dataset.sess;
  if (t.dataset.view) ui.view = t.dataset.view;
  if (t.dataset.range) ui.range = t.dataset.range;
  render();
});
document.addEventListener('keydown', (e) => {
  if (['input', 'textarea'].includes((e.target.tagName || '').toLowerCase()) || e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === 'Escape' || e.key === '$') { location.href = '/'; return; }
  const k = e.key.toLowerCase();
  if (k === 'd') { ui.view = 'dishes'; render(); }
  if (k === 's') { ui.view = 'sessions'; render(); }
});

const es = new EventSource('/events');
es.addEventListener('open', () => $('#conn').classList.remove('off'));
es.addEventListener('error', () => $('#conn').classList.add('off'));
es.addEventListener('snapshot', (e) => { state = JSON.parse(e.data); render(); });
