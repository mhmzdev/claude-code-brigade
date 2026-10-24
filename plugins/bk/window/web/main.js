// Boot: connect to the server's event stream, feed the room, draw the HUD around it.
// The HUD floats over the 2.5D room: identity and what needs you at the top, the line down
// the left, a sheet at the bottom for the rail or everything heard, the composer at the
// foot, an inspector on the right while a figure is selected, and a popover on the figure.
import { createScene, HELPER, ABOUT } from './scene.js';

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const linkify = (s) => esc(s).replace(/https?:\/\/[^\s<)]+/g, (u) => `<a href="${u}" target="_blank" rel="noopener">${u.replace(/^https?:\/\/(www\.)?/, '')}</a>`);
const kindClass = (k) => esc(k.replace(/[[\]]/g, ''));
const hhmm = (t) => new Date(t).toTimeString().slice(0, 5);
const NAME = { 'head-chef': 'head chef', headchef: 'head chef' };
const who = (id) => NAME[id] || id;
const LINE_KEYS = '123456789';

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
let state = null, focus = null, controlsFor = null;
let ui = { line: true, sheet: null, insp: false, gateX: false, answered: {} };
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
    const tk = st ? (st.ticket || a?.model || '') : (a?.model || '');
    return `<li><button type="button" data-who="${esc(id)}" class="${focus === id ? 'sel' : ''}"><span class="st ${esc(statusOf(a))}"></span><span class="nm">${esc(a?.name || id)}</span>${a?.activity === 'waiting' ? '<span class="gate" title="waiting"></span>' : ''}<span class="sp"></span><span class="tk">${esc(tk)}</span>${i < 9 ? `<kbd>${i + 1}</kbd>` : ''}</button></li>`;
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
    $('#rail').innerHTML = COLS.map(([k, n]) => { const ts = s.rail[k] || []; return `<div class="col ${ts.length ? '' : 'empty'}"><h3><span>${n}</span><span>${ts.length}</span></h3><div class="items">${ts.slice(0, 14).map((t) => `<span class="t ${esc(t.kind || '')} ${holder[t.id] ? 'held' : ''}" data-cook="${esc(holder[t.id] || '')}" title="${esc(t.title || '')}">${esc(t.id)}</span>`).join('')}${ts.length > 14 ? `<span class="more">+${ts.length - 14}</span>` : ''}${ts.length ? '' : '<span class="none">empty</span>'}</div></div>`; }).join('');
    $('#count').textContent = '';
  } else {
    const lines = focus ? s.log.filter((m) => involves(m, focus)) : s.log;
    $('#log').innerHTML = lines.slice(-120).reverse().map((m) => `<li><span class="t">${hhmm(m.t)}</span><span class="k ${kindClass(m.kind)}">${esc(m.kind)}</span><span class="who">${esc(who(m.from))} → ${esc(who(m.to))}</span><span class="txt">${linkify(m.text)}</span></li>`).join('');
    $('#count').textContent = `${lines.length} line${lines.length === 1 ? '' : 's'}`;
  }
}

// ---------- the popover on the selected figure, and the hover tip ----------
function place(el, anchor, below) {
  const r = anchor.getBoundingClientRect(), x = Math.min(Math.max(r.left + r.width / 2, 160), innerWidth - 160);
  const under = below ?? r.top < 300;
  el.style.left = `${x}px`; el.style.top = `${under ? r.bottom + 10 : r.top - 10}px`; el.style.transform = under ? 'translate(-50%,0)' : 'translate(-50%,-100%)';
}
function renderPop(s) {
  const p = $('#pop'), f = focus && scene.figure(focus);
  const hidden = !f || ui.insp || ui.sheet || ui.gateX;
  p.hidden = hidden; if (hidden) return;
  const a = actorOf(s, focus), st = stationOf(s, focus), line = isLine(focus);
  const meta = line ? [st?.ticket, a?.model, st?.branch, st ? null : a?.session].filter(Boolean).join(' · ') : isHelper(focus) ? `${HELPER[focus].role} · reports to the sous` : (s.headChef.pending.length ? `${s.headChef.pending.length} waiting on you` : 'nothing waiting on you');
  const note = f.said || (focus === 'headchef' ? ABOUT.head : isHelper(focus) ? HELPER[focus].about : '');
  p.innerHTML = `<div class="top"><span class="dot" style="background:var(--${statusOf(a) === 'busy' ? 'busy' : statusOf(a) === 'waiting' ? 'wait' : a ? 'idle' : 'muted'})"></span><b>${esc(nameOf(focus))}</b>${a ? `<span class="pill" data-s="${esc(statusOf(a))}">${esc(a.activity)}</span>` : ''}<span class="sp"></span><button type="button" class="link" data-act="close">Esc</button></div>
    <div class="meta">${esc(meta)}</div>${note ? `<p>${esc(note)}</p>` : ''}
    <div class="acts">${line ? `<button type="button" class="go" data-act="message">Message<kbd>/</kbd></button><button type="button" class="gold" data-act="handoff">Handoff</button>` : ''}${focus === 'headchef' && s.headChef.pending.length ? `<button type="button" class="go" data-act="gate">Answer<kbd>G</kbd></button>` : ''}<button type="button" data-act="details">Details<kbd>i</kbd></button></div><div class="note" hidden></div>`;
  place(p, f.bb);
}
$('#pop').addEventListener('click', async (e) => {
  const b = e.target.closest('[data-act]'); if (!b) return;
  if (b.dataset.act === 'close') setFocus(null);
  if (b.dataset.act === 'message') $('#chat').focus();
  if (b.dataset.act === 'details') { ui.insp = true; render(state); }
  if (b.dataset.act === 'gate') { ui.gateX = true; render(state); }
  if (b.dataset.act === 'handoff') showResult($('#pop .note'), await control({ who: focus, action: 'handoff' }), 4000);
});
const tip = $('#tip');
scene.onHover((text, anchor) => {
  if (!text) { tip.hidden = true; return; }
  const [head, ...rest] = text.split('\n');
  tip.innerHTML = `<b>${esc(head)}</b>${rest.join(' ').trim() ? `<span class="meta">${esc(rest.join(' '))}</span>` : ''}`; tip.hidden = false; place(tip, anchor, false);
});
// The figures move with the camera; the popover follows after the camera settles.
let camT = 0;
scene.onCamera(() => { if (!$('#pop').hidden) { requestAnimationFrame(() => renderPop(state)); clearTimeout(camT); camT = setTimeout(() => renderPop(state), 480); } });

// ---------- the inspector ----------
function renderInspector(s) {
  const open = ui.insp && focus; $('#inspector').hidden = !open; if (!open) return;
  const id = focus, a = actorOf(s, id), st = stationOf(s, id), f = scene.figure(id);
  let facts;
  if (id === 'headchef') facts = [['talks to', 'the sous only'], ['waiting', s.headChef.pending.length ? `${s.headChef.pending.length} question(s)` : 'nothing']];
  else if (isHelper(id)) facts = [['role', HELPER[id].role], ['reports', 'the sous']];
  else if (id === 'sous') facts = [['session', a.session || 'not running'], ['model', a.model], ['where', 'the main checkout'], ['pid', a.pid], ['attach', a.tmux ? `tmux attach -t ${a.tmux}` : null]];
  else facts = [['session', a.session || 'not running'], ['model', a.model], ['ticket', st.ticket], ['station', st.path || st.id], ['branch', st.branch || 'detached at trunk'], ['tree', st.dirty ? 'dirty' : 'clean'], ['ahead', st.ahead ? `+${st.ahead} commits` : null], ['pid', a.pid], ['peek', a.tmux ? `tmux attach -t ${a.tmux}` : null]];
  const about = id === 'headchef' ? ABOUT.head : isHelper(id) ? HELPER[id].about : id === 'sous' ? ABOUT.sous : ABOUT.cook;
  $('#d-head').innerHTML = `<div class="top"><span class="dot" style="background:var(--${statusOf(a) === 'busy' ? 'busy' : statusOf(a) === 'waiting' ? 'wait' : a ? 'idle' : 'muted'})"></span><strong>${esc(nameOf(id))}</strong>${a ? `<span class="pill" data-s="${esc(statusOf(a))}">${esc(a.activity)}</span>` : ''}<span class="sp"></span><button type="button" class="link" id="insp-close">Close</button></div>
    <dl>${facts.filter(([, v]) => v).map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`).join('')}</dl>${f?.said ? `<p class="say">“${esc(f.said)}”</p>` : ''}<p class="about">${esc(about)}</p>`;
  $('#insp-close').onclick = () => { ui.insp = false; render(state); };
  if (id === 'headchef') {
    const qs = s.headChef.pending;
    if (controlsFor !== id) { controlsFor = id; $('#d-controls').innerHTML = `<div class="h">Needs you</div><ul id="d-questions"></ul>`; }
    $('#d-questions').innerHTML = qs.length ? qs.map((q) => `<li data-q="${esc(q.id)}"><div class="from">${esc(q.from)} · via the sous</div>${esc(q.text)}<div class="opts">${(q.options || []).map((o) => `<button type="button" data-opt="${esc(o)}">${esc(o)}</button>`).join('')}</div><div class="note" hidden></div></li>`).join('') : '<li class="note">No open questions.</li>';
  } else if (isHelper(id)) {
    controlsFor = id; $('#d-controls').innerHTML = `<p class="hint">A sub-agent: it is spawned for one job and reports back. Nothing to control.</p>`;
  } else {
    if (controlsFor !== id) {
      controlsFor = id;
      const models = s.kitchen.models || ['fable', 'opus', 'sonnet', 'haiku'];
      const how = s.kitchen.control === 'tmux' ? 'Controls type into the session\'s tmux pane.' : s.kitchen.control === 'demo' ? 'Demo: applied directly.' : 'No tmux on this machine: the Window shows you the command to paste.';
      $('#d-controls').innerHTML = `<div class="row"><div class="menu" id="c-model"><button type="button" aria-haspopup="listbox"><span class="val">${esc(a.model || models[0])}</span></button><ul role="listbox" hidden>${models.map((m) => `<li role="option" data-v="${esc(m)}" aria-selected="${m === a.model}">${esc(m)}</li>`).join('')}<li role="option" class="other" data-v="__other">other…</li></ul></div><button type="button" id="c-model-go">Change model</button></div>
        <div class="row"><button type="button" id="c-handoff" class="gold">Handoff <small>/bk:handoff</small></button><button type="button" id="c-clear" class="danger">/clear <small>end of shift</small></button><span class="pill">${esc(s.kitchen.control || 'none')}</span></div>
        <p class="hint" id="c-shift"></p><p class="hint">${how}</p><div id="c-note" class="note" hidden></div>`;
      const menu = makeMenu($('#c-model'), a.model || models[0]);
      $('#c-model-go').onclick = async () => {
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
    // End of shift: /clear opens only once the handoff is written (the sous) or the ticket is served (a cook).
    const sh = shiftOf(s, id);
    $('#c-clear').classList.toggle('dim', !sh.ok); $('#c-handoff').classList.toggle('due', !sh.ok && sh.needsHandoff);
    $('#c-shift').textContent = sh.why;
  }
  const heard = s.log.filter((m) => involves(m, id)).slice(-60).reverse();
  $('#d-heard').innerHTML = heard.length ? heard.map((m) => `<li><div class="row"><span class="k">${esc(m.kind)}</span><span class="who">${esc(who(m.from))} → ${esc(who(m.to))}</span><span class="sp"></span><span class="t">${hhmm(m.t)}</span></div><p>${linkify(m.text)}</p></li>`).join('') : '<li class="none">Nothing heard yet.</li>';
}

// A styled stand-in for <select>: one button, a list that opens under it, closes on click-away or Esc.
function makeMenu(root, initial) {
  const btn = root.querySelector('button'), list = root.querySelector('ul'), val = root.querySelector('.val');
  let value = initial;
  const close = () => { list.hidden = true; root.classList.remove('open'); document.removeEventListener('pointerdown', away, true); document.removeEventListener('keydown', key, true); };
  const away = (e) => { if (!root.contains(e.target)) close(); };
  const key = (e) => { if (e.key === 'Escape') { e.stopPropagation(); close(); } };
  btn.onclick = () => { if (!list.hidden) return close(); list.hidden = false; root.classList.add('open'); document.addEventListener('pointerdown', away, true); document.addEventListener('keydown', key, true); };
  list.onclick = (e) => { const li = e.target.closest('li'); if (!li) return; value = li.dataset.v; for (const o of list.children) o.setAttribute('aria-selected', String(o === li)); val.textContent = value === '__other' ? 'other…' : value; close(); };
  return { value: () => value };
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
  renderTop(s); renderLine(s); renderSheet(s); renderInspector(s); renderPop(s);
  $('#target').textContent = nameOf(target()); $('#chat').placeholder = `Say something to ${nameOf(target())}…   ( / )`;
}
function setFocus(id) {
  focus = id; controlsFor = null; if (!id) ui.insp = false; scene.setSelected(id);
  render(state);
}
scene.onSelect(setFocus);
$('#line').addEventListener('click', (e) => { const b = e.target.closest('[data-who]'); if (b) setFocus(b.dataset.who === focus ? null : b.dataset.who); });
$('#hud-top .toggles').addEventListener('click', (e) => { const b = e.target.closest('[data-t]'); if (!b) return; if (b.dataset.t === 'line') ui.line = !ui.line; else ui.sheet = ui.sheet === b.dataset.t ? null : b.dataset.t; render(state); });
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
  if (e.key === 'Escape') { if (tag === 'input') e.target.blur(); else if (ui.insp || ui.sheet || ui.gateX) { ui.insp = false; ui.sheet = null; ui.gateX = false; render(state); } else setFocus(null); return; }
  if (tag === 'input' || tag === 'select' || tag === 'textarea' || e.metaKey || e.ctrlKey || e.altKey || !state) return;
  const k = e.key.toLowerCase(), i = LINE_KEYS.indexOf(e.key);
  if (i >= 0) { const id = lineIds(state)[i]; if (id) setFocus(id === focus ? null : id); return; }
  if (k === '/') { e.preventDefault(); $('#chat').focus(); }
  if (k === 'i') { if (!focus) focus = 'sous'; ui.insp = !ui.insp; scene.setSelected(focus); render(state); }
  if (k === 'r') { ui.sheet = ui.sheet === 'rail' ? null : 'rail'; render(state); }
  if (k === 'h') { ui.sheet = ui.sheet === 'heard' ? null : 'heard'; render(state); }
  if (k === 'l') { ui.line = !ui.line; render(state); }
  if (k === 'g' && state.headChef.pending.length) { ui.gateX = !ui.gateX; render(state); }
  const oi = 'abcdefghi'.indexOf(k);
  if (ui.gateX && oi >= 0) { const b = document.querySelectorAll('#gate button[data-opt]')[oi]; if (b && !b.disabled) b.click(); }
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
for (const t of ['message', 'bubble', 'helper:start', 'helper:end', 'ask', 'answered', 'ticket']) {
  es.addEventListener(t, (e) => { scene.onEvent({ type: t, ...JSON.parse(e.data) }); if (t === 'bubble' || t === 'message') renderPop(state); });
}
const fpsSamples = [];
setInterval(() => { fpsSamples.push(scene.fps()); if (fpsSamples.length > 8) fpsSamples.shift(); const f = Math.round(fpsSamples.reduce((a, b) => a + b, 0) / fpsSamples.length); $('#fps').textContent = f ? `${f} fps` : 'still'; }, 250);
