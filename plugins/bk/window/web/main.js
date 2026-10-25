// Boot: connect to the server's event stream, feed the room, draw the HUD around it.
// The HUD floats over the 2.5D room: identity and what needs you at the top, the line down
// the left, a sheet at the bottom for the rail or everything heard, the composer at the
// foot, and the details of the selected figure on the right.
import { createScene, HELPER, ABOUT } from './scene.js';

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const linkify = (s) => esc(s).replace(/https?:\/\/[^\s<)]+/g, (u) => `<a href="${u}" target="_blank" rel="noopener">${u.replace(/^https?:\/\/(www\.)?/, '')}</a>`);
const kindClass = (k) => esc(k.replace(/[[\]]/g, ''));
const hhmm = (t) => new Date(t).toTimeString().slice(0, 5);
const NAME = { 'head-chef': 'head chef', headchef: 'head chef' };
const who = (id) => NAME[id] || id;
const LINE_KEYS = '123456789';
// Numbers, formatted the way the budget prints them in the terminal.
const fmtTok = (n) => n >= 1e6 ? `${(n / 1e6).toFixed(n >= 1e7 ? 0 : 1)}M` : n >= 1e3 ? `${Math.round(n / 1e3)}k` : String(Math.round(n || 0));
const fmtUsd = (n) => n == null ? '–' : `$${n >= 100 ? n.toFixed(0) : n >= 10 ? n.toFixed(1) : n.toFixed(2)}`;
const fmtSecs = (x) => { if (x == null) return '–'; if (x < 60) return `${Math.round(x)}s`; const m = Math.round(x / 60); return m < 60 ? `${m}m` : `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, '0')}m`; };
const spent = (s, id) => s.budget?.actors?.[id] || null;
const ticketSpend = (s, id) => (s.budget?.tickets || []).find((t) => t.id === id) || null;

const scene = createScene($('#stage'));
window.__window = scene;

// ---------- control calls ----------
async function control(body) {
  const r = await fetch('/api/control', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  return r.json();
}
function showResult(el, out, ttl = 2500) {
  el.hidden = false; el.className = `${el.className.replace(/\b(ok|bad)\b/g, '').trim()} ${out.ok ? 'ok' : 'bad'}`;
  if (out.ok) el.textContent = out.via === 'demo' ? 'Done (demo).' : 'Typed into the session\'s tmux pane.';
  else el.innerHTML = `${esc(out.reason || 'Could not reach the session.')}${out.command ? `<code>${esc(out.command)}</code>` : ''}`;
  clearTimeout(el._t); if (out.ok) el._t = setTimeout(() => { el.hidden = true; }, ttl);
}

// ---------- state ----------
let state = null, focus = null, controlsFor = null, modelMenu = null, modelShown = null;
let ui = { line: true, sheet: null, insp: false, dtab: null, noteOpen: false, gateX: false, answered: {} };
const actorOf = (s, id) => id === 'sous' ? s.sous : s.stations.find((x) => x.id === id)?.cook;
const stationOf = (s, id) => s.stations.find((x) => x.id === id);
const isLine = (id) => id === 'sous' || !!stationOf(state, id);
const isHelper = (id) => !!HELPER[id];
const involves = (m, id) => m.from === id || m.to === id || (id === 'headchef' && (m.from === 'head-chef' || m.to === 'head-chef'));
const lineIds = (s) => ['sous', ...s.stations.map((x) => x.id)];
const target = () => (focus && isLine(focus)) ? focus : 'sous';
const nameOf = (id) => id === 'headchef' ? 'Head Chef' : isHelper(id) ? id : (actorOf(state, id)?.name || id);
const statusOf = (a) => !a ? 'offline' : a.activity === 'waiting' ? 'waiting' : a.status;

// ---------- the top: identity, the gate, the toggles ----------
function renderTop(s) {
  $('#repo').textContent = s.kitchen.repo; $('#mode').textContent = `${s.kitchen.mode} · trunk ${s.kitchen.trunk}`; $('#demo').hidden = !s.kitchen.demo;
  for (const b of document.querySelectorAll('#hud-top .toggles button')) b.classList.toggle('on', b.dataset.t === 'line' ? ui.line : ui.sheet === b.dataset.t);
  const qs = s.headChef.pending, q = qs[0], g = $('#gate');
  if (!q) { g.innerHTML = ''; return; }
  const done = ui.answered[q.id];
  if (done) { g.innerHTML = `<div class="done"><span class="dot"></span><span>${esc(q.from)} → <b>${esc(done)}</b></span><span class="note">typed into the sous</span></div>`; return; }
  const n = qs.length;
  g.innerHTML = `<div class="card" data-q="${esc(q.id)}">
    <button type="button" class="head"><span class="n">${n}</span><span class="lbl">NEEDS YOU</span><span class="txt">${esc(q.text)}</span><span class="tog">${ui.gateX ? 'Hide' : 'Answer · G'}</span></button>
    ${ui.gateX ? `<div class="more"><div class="from">${esc(q.from)} · via the sous${n > 1 ? ` · ${n - 1} more waiting` : ''}</div><p>${esc(q.text)}</p><div class="opts">${(q.options || []).map((o, i) => `<button type="button" data-opt="${esc(o)}">${esc(o)}<kbd>${'ABCDEFGHI'[i] || ''}</kbd></button>`).join('')}</div><div class="note" hidden></div></div>` : ''}
  </div>`;
  g.querySelector('.head').onclick = () => { ui.gateX = !ui.gateX; render(state); };
}
async function answer(li, b) {
  const note = li.querySelector('.note');
  for (const x of li.querySelectorAll('button[data-opt]')) x.disabled = true;
  const out = await control({ who: 'sous', action: 'answer', value: { id: li.dataset.q, option: b.dataset.opt } });
  if (out.ok) { ui.answered[li.dataset.q] = b.dataset.opt; ui.gateX = false; render(state); }
  else { showResult(note, out); for (const x of li.querySelectorAll('button[data-opt]')) x.disabled = false; }
}

// ---------- the line ----------
function renderLine(s) {
  $('#linepane').hidden = !ui.line;
  $('#line').innerHTML = lineIds(s).map((id, i) => {
    const a = actorOf(s, id), st = stationOf(s, id);
    const tk = st ? (st.ticket || a?.model || '') : (a?.model || ''), sp = spent(s, id);
    return `<li><button type="button" data-who="${esc(id)}" class="${focus === id ? 'sel' : ''}"><span class="st ${esc(statusOf(a))}"></span><span class="nm">${esc(a?.name || id)}</span>${a?.activity === 'waiting' ? '<span class="gate" title="waiting"></span>' : ''}<span class="sp"></span><span class="tk">${esc(tk)}</span>${sp ? `<span class="cost" title="spent today, sub-agents included">${esc(fmtUsd(sp.cost))}</span>` : ''}${i < 9 ? `<kbd>${i + 1}</kbd>` : ''}</button></li>`;
  }).join('');
}

// ---------- the sheet: the rail, or everything heard ----------
const COLS = [['backlog', 'Backlog'], ['todo', 'TODO'], ['in-progress', 'Doing'], ['rfr', 'RFR'], ['done', 'Done']];
function renderSheet(s) {
  const open = !!ui.sheet; $('#sheet').hidden = !open;
  $('#railsum').innerHTML = COLS.map(([k, n]) => `<span>${n} <b class="${k === 'in-progress' ? 'doing' : ''}">${(s.rail[k] || []).length}</b></span>`).join('');
  if (!open) return;
  for (const b of document.querySelectorAll('#sheet [data-tab]')) b.classList.toggle('on', b.dataset.tab === ui.sheet);
  $('#rail').hidden = ui.sheet !== 'rail'; $('#log').hidden = ui.sheet !== 'heard';
  const f = $('#filter'); f.hidden = !(ui.sheet === 'heard' && focus); if (focus) f.textContent = nameOf(focus);
  if (ui.sheet === 'rail') {
    const holder = {}; for (const st of s.stations) if (st.ticket) holder[st.ticket] = st.id;
    const tip = (t) => { const b = ticketSpend(s, t.id); return [t.title, b ? `${fmtUsd(b.allCost)} · ${fmtTok(b.total)} tokens · ${fmtSecs(b.secs)}` : null].filter(Boolean).join('\n'); };
    $('#rail').innerHTML = COLS.map(([k, n]) => { const ts = s.rail[k] || []; return `<div class="col ${ts.length ? '' : 'empty'}"><h3><span>${n}</span><span>${ts.length}</span></h3><div class="items">${ts.slice(0, 14).map((t) => `<span class="t ${esc(t.kind || '')} ${holder[t.id] ? 'held' : ''}" data-cook="${esc(holder[t.id] || '')}" title="${esc(tip(t))}">${esc(t.id)}</span>`).join('')}${ts.length > 14 ? `<span class="more">+${ts.length - 14}</span>` : ''}${ts.length ? '' : '<span class="none">empty</span>'}</div></div>`; }).join('');
    $('#count').textContent = '';
  } else {
    const lines = focus ? s.log.filter((m) => involves(m, focus)) : s.log;
    $('#log').innerHTML = lines.slice(-120).reverse().map((m) => `<li><span class="t">${hhmm(m.t)}</span><span class="k ${kindClass(m.kind)}">${esc(m.kind)}</span><span class="who">${esc(who(m.from))} → ${esc(who(m.to))}</span><span class="txt">${linkify(m.text)}</span></li>`).join('');
    $('#count').textContent = `${lines.length} line${lines.length === 1 ? '' : 's'}`;
  }
}

// ---------- the budget: the chip at the foot, which opens the Ledger ----------
function renderBudgetSum(s) {
  const b = s.budget, el = $('#budgetsum');
  el.hidden = !b; if (!b) return;
  // The shift: since the sous's current conversation began (the snapshot holds a week).
  const since = b.windows?.shift || b.since || 0, now = b.computedAt || Date.now();
  const sessions = b.sessions.filter((x) => (x.lastAt || 0) >= since), tickets = b.tickets.filter((t) => (t.servedAt || now) >= since);
  const models = sessions.reduce((a, x) => a + x.allCost, 0), ci = tickets.reduce((a, t) => a + (t.ci?.cost || 0), 0), ciMin = tickets.reduce((a, t) => a + (t.ci?.minutes || 0), 0);
  const total = sessions.reduce((a, x) => a + x.allTotal, 0), working = sessions.reduce((a, x) => a + x.activeSecs, 0);
  const cap = b.caps?.shift_usd, spent = models + ci;
  el.innerHTML = `<span class="spent"><b>${esc(fmtUsd(spent))}</b>${cap ? `<span class="bar"><span style="width:${Math.min(100, spent / cap * 100)}%"></span></span>` : ''}</span><span>${esc(fmtTok(total))} tok</span><span>${esc(fmtSecs(working))} working</span><span>CI ${esc(String(Math.round(ciMin * 10) / 10))} min</span><kbd>$</kbd>`;
}
// ---------- the hover tip ----------
// anchor: an element, or a rect ({ left, width, top, bottom }) such as a figure's head
function place(el, anchor, below) {
  const r = typeof anchor.getBoundingClientRect === 'function' ? anchor.getBoundingClientRect() : anchor, x = Math.min(Math.max(r.left + r.width / 2, 160), innerWidth - 160);
  const under = below ?? r.top < 300;
  el.style.left = `${x}px`; el.style.top = `${under ? r.bottom + 10 : r.top - 10}px`; el.style.transform = under ? 'translate(-50%,0)' : 'translate(-50%,-100%)';
}
const tip = $('#tip');
scene.onHover((text, anchor) => {
  if (!text) { tip.hidden = true; return; }
  const [head, ...rest] = text.split('\n');
  tip.innerHTML = `<b>${esc(head)}</b>${rest.join(' ').trim() ? `<span class="meta">${esc(rest.join(' '))}</span>` : ''}`; tip.hidden = false; place(tip, anchor, false);
});

// ---------- the inspector ----------
// The head says who, with chips for the ticket, model and tree and a strip of what it has
// spent; the tabs hold the rest. Activity (the latest words, then what was heard) comes first
// because it is what a busy head chef reads; Cost and Session sit behind their tabs. The
// controls (the model, Handoff, /clear) are pinned at the foot for a line actor.
const TABS = { line: [['now', 'Activity'], ['cost', 'Cost'], ['session', 'Session']], headchef: [['needs', 'Needs you'], ['now', 'Activity']], helper: [['now', 'Activity'], ['about', 'About']] };
const shortPath = (v) => /\//.test(v) && v.length > 30 ? '…/' + v.split('/').filter(Boolean).slice(-2).join('/') : v;
const heardList = (heard) => heard.length ? `<ol class="heard">${heard.map((m) => `<li><div class="row"><span class="k">${esc(m.kind)}</span><span class="who">${esc(who(m.from))} → ${esc(who(m.to))}</span><span class="sp"></span><span class="t">${hhmm(m.t)}</span></div><p>${linkify(m.text)}</p></li>`).join('')}</ol>` : '<p class="none">Nothing heard yet.</p>';
function renderInspector(s) {
  const open = ui.insp && focus; $('#inspector').hidden = !open; if (!open) return;
  const id = focus, a = actorOf(s, id), st = stationOf(s, id), f = scene.figure(id);
  const kind = id === 'headchef' ? 'headchef' : isHelper(id) ? 'helper' : 'line';
  const tabs = TABS[kind]; if (!tabs.some(([k]) => k === ui.dtab)) ui.dtab = tabs[0][0];
  const heard = s.log.filter((m) => involves(m, id)).slice(-60).reverse();
  const sp = kind === 'line' ? spent(s, id) : null, cur = sp?.current;
  const chips = kind === 'line'
    ? [st?.ticket && [st.ticket, 'var(--accent)'], a?.model && [a.model, 'var(--muted)'], st && [st.dirty ? 'dirty' : 'clean', st.dirty ? 'var(--wait)' : 'var(--busy)'], st?.ahead && [`+${st.ahead}`, '#6f9bd6']]
    : kind === 'helper' ? [[HELPER[id].role, 'var(--muted)']] : [[s.headChef.pending.length ? `${s.headChef.pending.length} waiting on you` : 'nothing waiting on you', 'var(--accent)']];
  const counts = { now: heard.length || '', needs: s.headChef.pending.length || '' };
  $('#d-head').innerHTML = `<div class="top"><span class="dot" style="background:var(--${statusOf(a) === 'busy' ? 'busy' : statusOf(a) === 'waiting' ? 'wait' : a ? 'idle' : 'muted'})"></span><strong>${esc(nameOf(id))}</strong>${a ? `<span class="pill" data-s="${esc(statusOf(a))}">${esc(a.activity)}</span>` : ''}<span class="sp"></span><button type="button" class="link" id="insp-close">Close</button></div>
    <div class="chips">${chips.filter(Boolean).map(([t, c]) => `<span><i style="background:${c}"></i>${esc(t)}</span>`).join('')}</div>
    ${sp ? `<div class="stats"><div><span>Today</span><b class="gold">${esc(fmtUsd(sp.cost))}</b><small>${sp.sessions} conversation${sp.sessions === 1 ? '' : 's'}</small></div><div><span>This conversation</span><b>${esc(fmtUsd(cur?.allCost ?? 0))}</b><small>${esc(fmtTok(cur?.allTotal || 0))} tok</small></div><div><span>Working</span><b>${esc(fmtSecs(sp.activeSecs))}</b><small>today</small></div></div>` : ''}
    <div class="tabs">${tabs.map(([k, n]) => `<button type="button" data-dtab="${k}" class="${ui.dtab === k ? 'on' : ''}">${n}${counts[k] ? `<span>${counts[k]}</span>` : ''}</button>`).join('')}</div>`;
  $('#insp-close').onclick = () => setFocus(null);
  const body = $('#d-body');
  if (ui.dtab === 'now') {
    const note = f?.said || '', long = note.length > 180;
    body.innerHTML = `${note ? `<div class="sec"><div class="h">Latest</div><p class="say ${long && !ui.noteOpen ? 'clamp' : ''}">${esc(note)}</p>${long ? `<button type="button" class="link gold" id="d-note">${ui.noteOpen ? 'Show less' : 'Show all'}</button>` : ''}</div>` : ''}
      <div class="sec"><div class="h">Heard</div>${heardList(heard)}</div>`;
    const nb = $('#d-note'); if (nb) nb.onclick = () => { ui.noteOpen = !ui.noteOpen; render(state); };
  } else if (ui.dtab === 'cost') {
    // Each token kind at the model's list price (the budget sends the table it priced the conversation on); the helpers at what they cost.
    const u = cur?.tokens, p = cur?.price, t = st?.ticket && ticketSpend(s, st.ticket);
    const rows = u ? [['Input', '#e9a93c', u.in, p && u.in * p.in / 1e6], ['Cache read', '#a88a52', u.read, p && u.read * p.read / 1e6], ['Cache write', '#c9a25e', u.w5 + u.w1, p && (u.w5 * 1.25 + u.w1 * 2) * p.in / 1e6], ['Output', '#d4654f', u.out, p && u.out * p.out / 1e6]].filter((r) => r[2]) : [];
    const hs = Object.entries(sp?.helpers || {});
    body.innerHTML = `<div class="sec"><div class="h">This conversation</div>${rows.length ? `<div class="grid">${rows.map(([k, c, n, usd]) => `<span class="k"><i style="background:${c}"></i>${k}</span><span class="n">${esc(fmtTok(n))}</span><span class="usd">${usd == null ? '–' : esc(fmtUsd(usd))}</span>`).join('')}</div>${p ? '' : '<p class="none">No price for this model: add a prices: block to .claude/brigade.md.</p>'}` : '<p class="none">Nothing spent yet.</p>'}</div>
      ${t ? `<div class="sec"><div class="h">On ${esc(t.id)}</div><div class="grid"><span class="k">since the brief · ${esc(fmtSecs(t.secs))}</span><span class="n">${esc(fmtTok(t.total))}</span><span class="usd">${esc(fmtUsd(t.allCost))}</span>${t.ci ? `<span class="k"><i style="background:#6f9bd6"></i>CI</span><span class="n">${esc(String(t.ci.minutes))} min</span><span class="usd">${esc(fmtUsd(t.ci.cost))}</span>` : ''}</div></div>` : ''}
      <div class="sec"><div class="h">Helpers today</div>${hs.length ? `<div class="grid">${hs.map(([k, h]) => `<span class="k">${esc(k)}</span><span class="n">${h.runs} run${h.runs === 1 ? '' : 's'}</span><span class="usd">${esc(fmtUsd(h.cost))}</span>`).join('')}</div>` : '<p class="none">No helper calls today.</p>'}</div>
      <a class="more" href="/ledger">Open in Ledger →</a>`;
  } else if (ui.dtab === 'session') {
    const kv = id === 'sous'
      ? [['session', a.session || 'not running'], ['where', 'the main checkout'], ['pid', a.pid]]
      : [['session', a.session || 'not running'], ['station', st.path || st.id], ['branch', st.branch || 'detached at trunk'], ['tree', st.dirty ? 'dirty' : 'clean'], ['ahead', st.ahead ? `+${st.ahead} commits` : null], ['pid', a.pid]];
    const peek = a.tmux ? `tmux attach -t ${a.tmux}` : '';
    body.innerHTML = `<div class="kv">${kv.filter(([, v]) => v).map(([k, v]) => `<div><span class="k">${esc(k)}</span><span class="v" title="${esc(v)}">${esc(shortPath(String(v)))}</span><button type="button" class="copy" data-copy="${esc(v)}">Copy</button></div>`).join('')}</div>
      ${peek ? `<div class="sec"><div class="h">Peek at the pane</div><div class="code"><code>${esc(peek)}</code><button type="button" class="copy" data-copy="${esc(peek)}">Copy</button></div></div>` : ''}
      <p class="about">${esc(id === 'sous' ? ABOUT.sous : ABOUT.cook)}</p>`;
  } else if (ui.dtab === 'needs') {
    const qs = s.headChef.pending;
    body.innerHTML = `<ul id="d-questions">${qs.length ? qs.map((q) => `<li data-q="${esc(q.id)}"><div class="from">${esc(q.from)} · via the sous</div>${esc(q.text)}<div class="opts">${(q.options || []).map((o) => `<button type="button" data-opt="${esc(o)}">${esc(o)}</button>`).join('')}</div><div class="note" hidden></div></li>`).join('') : '<li class="none">No open questions.</li>'}</ul>`;
  } else if (ui.dtab === 'about') {
    body.innerHTML = `<p class="about">${esc(HELPER[id].about)}</p><p class="about">A sub-agent: it is spawned for one job and reports back. Nothing to control.</p>`;
  }
  // The foot: the controls, for a line actor. Built once per actor; the state keeps it current.
  const foot = $('#d-foot'); foot.hidden = kind !== 'line';
  if (kind !== 'line') return;
  if (controlsFor !== id) {
    controlsFor = id;
    const models = s.kitchen.models || ['fable', 'opus', 'sonnet', 'haiku'];
    const how = s.kitchen.control === 'tmux' ? 'Controls type into the session\'s tmux pane.' : s.kitchen.control === 'demo' ? 'Demo: applied directly.' : 'No tmux on this machine: the Window shows you the command to paste.';
    foot.innerHTML = `<div class="row"><div class="menu" id="c-model"><button type="button" aria-haspopup="listbox"><span class="val">${esc(a.model || models[0])}</span></button><ul role="listbox" hidden>${models.map((m) => `<li role="option" data-v="${esc(m)}" aria-selected="${m === a.model}">${esc(m)}</li>`).join('')}<li role="option" class="other" data-v="__other">other…</li></ul></div><button type="button" id="c-model-go" disabled>Change model</button></div>
      <div class="row"><button type="button" id="c-handoff">Handoff</button><button type="button" id="c-clear">/clear</button></div>
      <p class="hint" id="c-shift"></p><p class="hint">${how}</p><div id="c-note" class="note" hidden></div>`;
    const go = $('#c-model-go');
    const menu = makeMenu($('#c-model'), a.model || models[0], () => { go.disabled = menu.value() === modelShown; });
    modelMenu = menu; modelShown = a.model;
    go.onclick = async () => {
      let v = menu.value();
      if (v === '__other') v = await dialog({ title: 'Another model', text: 'The name as /model accepts it, for example claude-sonnet-5-5.', input: 'model name', ok: 'Change' });
      if (!v) return;
      showResult($('#c-note'), await control({ who: id, action: 'model', value: v }));
    };
    $('#c-handoff').onclick = async () => { showResult($('#c-note'), await control({ who: id, action: 'handoff' })); };
    $('#c-clear').onclick = async () => {
      const sh = shiftOf(state, id);
      const yes = await dialog({ title: `Send /clear to ${nameOf(id)}?`, text: sh.ok ? 'Its conversation ends and a fresh one carries on from the handoff.' : `${sh.why} Clear anyway?`, ok: '/clear', danger: true });
      if (!yes) return;
      showResult($('#c-note'), await control({ who: id, action: 'clear' }));
    };
  }
  // The model follows the session: a /model typed in the pane (or sent from here) shows as soon as the reader sees it.
  if (a.model !== modelShown) { modelShown = a.model; if (a.model) modelMenu.set(a.model); }
  // End of shift: /clear opens only once the handoff is written (the sous) or the ticket is served (a cook).
  const sh = shiftOf(s, id);
  $('#c-clear').classList.toggle('dim', !sh.ok); $('#c-handoff').classList.toggle('due', !sh.ok && sh.needsHandoff);
  $('#c-shift').textContent = sh.why;
}
// The tabs and the Copy buttons are rebuilt on every render, so the panel listens for them once.
$('#inspector').addEventListener('click', (e) => {
  const t = e.target.closest('[data-dtab]'); if (t) { ui.dtab = t.dataset.dtab; ui.noteOpen = false; render(state); return; }
  const c = e.target.closest('[data-copy]'); if (!c) return;
  navigator.clipboard?.writeText(c.dataset.copy).catch(() => {});
  c.textContent = 'Copied'; c.classList.add('ok'); setTimeout(() => { c.textContent = 'Copy'; c.classList.remove('ok'); }, 1200);
});

// A styled stand-in for <select>: one button, a list that opens under it, closes on click-away or Esc.
function makeMenu(root, initial, onChange) {
  const btn = root.querySelector('button'), list = root.querySelector('ul'), val = root.querySelector('.val');
  let value = initial;
  const close = () => { list.hidden = true; root.classList.remove('open'); document.removeEventListener('pointerdown', away, true); document.removeEventListener('keydown', key, true); };
  const away = (e) => { if (!root.contains(e.target)) close(); };
  const key = (e) => { if (e.key === 'Escape') { e.stopPropagation(); close(); } };
  btn.onclick = () => { if (!list.hidden) return close(); list.hidden = false; root.classList.add('open'); document.addEventListener('pointerdown', away, true); document.addEventListener('keydown', key, true); };
  const set = (v) => { value = v; for (const o of list.children) o.setAttribute('aria-selected', String(o.dataset.v === v)); val.textContent = v === '__other' ? 'other…' : v; onChange?.(v); };
  list.onclick = (e) => { const li = e.target.closest('li'); if (!li) return; set(li.dataset.v); close(); };
  return { value: () => value, set };
}
// In-page dialog in the Window's own style. Resolves true/false, or the typed string when `input` is set.
function dialog({ title, text, input, ok = 'OK', cancel = 'Cancel', danger = false }) {
  return new Promise((resolve) => {
    const el = document.createElement('div'); el.id = 'dialog';
    el.innerHTML = `<div class="box" role="dialog" aria-modal="true"><h3>${esc(title)}</h3>${text ? `<p>${esc(text)}</p>` : ''}${input !== undefined ? `<input placeholder="${esc(input)}" />` : ''}<div class="acts"><button type="button" class="no">${esc(cancel)}</button><button type="button" class="go ${danger ? 'danger' : ''}">${esc(ok)}</button></div></div>`;
    const field = el.querySelector('input');
    const done = (v) => { el.remove(); document.removeEventListener('keydown', key, true); resolve(v); };
    const key = (e) => { e.stopPropagation(); if (e.key === 'Escape') done(input !== undefined ? '' : false); if (e.key === 'Enter') el.querySelector('.go').click(); };
    el.querySelector('.no').onclick = () => done(input !== undefined ? '' : false);
    el.querySelector('.go').onclick = () => done(input !== undefined ? field.value.trim() : true);
    el.onclick = (e) => { if (e.target === el) el.querySelector('.no').click(); };
    document.addEventListener('keydown', key, true);
    document.body.appendChild(el);
    (field || el.querySelector('.go')).focus();
  });
}
// Is this actor at a quiet point for a /clear? Returns { ok, why, needsHandoff }.
function shiftOf(s, id) {
  if (id === 'sous') {
    const a = s.sous, fresh = a.handoffAt && (!a.startedAt || a.handoffAt > a.startedAt);
    if (fresh) return { ok: true, why: `Handoff written ${ago(a.handoffAt)}. A fresh sous reads it first.`, needsHandoff: false };
    return { ok: false, why: a.handoffAt ? 'Its handoff is from before this conversation. Run the handoff first, then clear.' : 'No handoff written yet. Run the handoff first, then clear.', needsHandoff: true };
  }
  const st = stationOf(s, id); if (!st) return { ok: false, why: '', needsHandoff: false };
  if (st.ticket) return { ok: false, why: `Holds ${st.ticket}: a clear now loses its context. Cooks hand off on their own at the PR; mid-ticket, run the handoff first.`, needsHandoff: true };
  if (st.dirty) return { ok: false, why: 'Its tree is dirty: something is not committed.', needsHandoff: false };
  return { ok: true, why: 'Between tickets: clear it and it checks in fresh.', needsHandoff: false };
}
function ago(t) { const m = Math.round((Date.now() - t) / 60000); return m < 1 ? 'just now' : m < 60 ? `${m} min ago` : `${Math.round(m / 60)} h ago`; }

// ---------- render everything ----------
function render(s) {
  if (!s) return;
  renderTop(s); renderLine(s); renderSheet(s); renderBudgetSum(s); renderInspector(s);
  $('#target').textContent = nameOf(target()); $('#chat').placeholder = `Say something to ${nameOf(target())}…   ( / )`;
}
// Selecting a character (a click in the room or on the line, a number key) opens its details; the composer is addressed to it.
function setFocus(id) {
  focus = id; controlsFor = null; ui.dtab = null; ui.noteOpen = false; ui.insp = !!id; scene.setSelected(id);
  render(state);
}
scene.onSelect(setFocus);
$('#line').addEventListener('click', (e) => { const b = e.target.closest('[data-who]'); if (b) setFocus(b.dataset.who === focus ? null : b.dataset.who); });
$('#hud-top .toggles').addEventListener('click', (e) => { const b = e.target.closest('[data-t]'); if (!b || b.dataset.t === 'ledger') return; if (b.dataset.t === 'line') ui.line = !ui.line; else ui.sheet = ui.sheet === b.dataset.t ? null : b.dataset.t; render(state); });
$('#sheet .tabs').addEventListener('click', (e) => { const b = e.target.closest('[data-tab]'); if (b) { ui.sheet = b.dataset.tab; render(state); } });
$('#sheet-close').addEventListener('click', () => { ui.sheet = null; render(state); });
$('#railsum').addEventListener('click', () => { ui.sheet = ui.sheet === 'rail' ? null : 'rail'; render(state); });
$('#filter').addEventListener('click', () => setFocus(null));
$('#rail').addEventListener('click', (e) => { const t = e.target.closest('.t.held'); if (t?.dataset.cook) { ui.sheet = null; setFocus(t.dataset.cook); } });
// Question options: the gate, the head chef's inspector page, and the popover share one handler.
document.addEventListener('click', (e) => { const b = e.target.closest('button[data-opt]'); if (!b) return; const li = b.closest('[data-q]'); if (li) answer(li, b); });
$('#chatform').addEventListener('submit', async (e) => {
  e.preventDefault(); const v = $('#chat').value; if (!v.trim()) return;
  const out = await control({ who: target(), action: 'send', value: v }); showResult($('#chatnote'), out); if (out.ok) $('#chat').value = '';
});
document.addEventListener('keydown', (e) => {
  const tag = (e.target.tagName || '').toLowerCase();
  if (e.key === 'Escape') { if (tag === 'input') e.target.blur(); else if (ui.sheet || ui.gateX) { ui.sheet = null; ui.gateX = false; render(state); } else setFocus(null); return; }
  if (tag === 'input' || tag === 'select' || tag === 'textarea' || e.metaKey || e.ctrlKey || e.altKey || !state) return;
  const k = e.key.toLowerCase(), i = LINE_KEYS.indexOf(e.key);
  if (i >= 0) { const id = lineIds(state)[i]; if (id) setFocus(id === focus ? null : id); return; }
  // While a question is open, a–i answer it and nothing else.
  const oi = 'abcdefghi'.indexOf(k);
  if (ui.gateX && oi >= 0) { const b = document.querySelectorAll('#gate button[data-opt]')[oi]; if (b && !b.disabled) b.click(); return; }
  if (k === '/') { e.preventDefault(); $('#chat').focus(); }
  if (k === 'i') { if (focus) setFocus(null); else setFocus('sous'); }
  if (k === 'r') { ui.sheet = ui.sheet === 'rail' ? null : 'rail'; render(state); }
  if (k === 'h') { ui.sheet = ui.sheet === 'heard' ? null : 'heard'; render(state); }
  if (e.key === '$') { location.href = '/ledger'; return; }
  if (k === 'l') { ui.line = !ui.line; render(state); }
  if (k === 'g' && state.headChef.pending.length) { ui.gateX = !ui.gateX; render(state); }
});

// ---------- the stream ----------
const es = new EventSource('/events');
es.addEventListener('open', () => $('#conn').classList.remove('off'));
es.addEventListener('error', () => $('#conn').classList.add('off'));
es.addEventListener('snapshot', (e) => {
  state = JSON.parse(e.data);
  for (const id of Object.keys(ui.answered)) if (!state.headChef.pending.find((q) => q.id === id)) delete ui.answered[id];
  scene.applySnapshot(state); render(state);
});
for (const t of ['message', 'bubble', 'helper:start', 'helper:end', 'ask', 'answered', 'ticket', 'check']) {
  es.addEventListener(t, (e) => { scene.onEvent({ type: t, ...JSON.parse(e.data) }); if ((t === 'bubble' || t === 'message') && ui.insp) renderInspector(state); });
}
const fpsSamples = [];
setInterval(() => { fpsSamples.push(scene.fps()); if (fpsSamples.length > 8) fpsSamples.shift(); const f = Math.round(fpsSamples.reduce((a, b) => a + b, 0) / fpsSamples.length); $('#fps').textContent = f ? `${f} fps` : 'still'; }, 250);
