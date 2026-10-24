// Boot: connect to the server's event stream, feed the scene, render the panel.
// Layout: top bar (identity, the line), rail left, the room centre with questions as a banner,
// inspector right while a figure is selected, console bottom with the prompt at its foot.
import { createKitchen } from './kitchen.js';

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const linkify = (s) => esc(s).replace(/https?:\/\/[^\s<)]+/g, (u) => `<a href="${u}" target="_blank" rel="noopener">${u.replace(/^https?:\/\/(www\.)?/, '')}</a>`);
const kindClass = (k) => esc(k.replace(/[[\]]/g, ''));
const logItem = (m) => `<li><span class="k ${kindClass(m.kind)}">${esc(m.kind)}</span><span class="who">${esc(m.from)} → ${esc(m.to)}</span><span class="txt">${linkify(m.text)}</span></li>`;

const scene = await createKitchen($('#kitchen'), $('#stage'));
window.__window = scene;

$('#rail-toggle').addEventListener('click', () => document.body.classList.toggle('norail'));
$('#console-toggle').addEventListener('click', () => document.body.classList.toggle('noconsole'));
// Drag the console's top edge to resize it; the room takes the rest.
$('#console-bar .grip').addEventListener('pointerdown', (e) => {
  e.preventDefault(); document.body.classList.remove('noconsole');
  const move = (ev) => { const h = Math.min(window.innerHeight * .7, Math.max(90, window.innerHeight - ev.clientY)); document.documentElement.style.setProperty('--console', `${h}px`); };
  const up = () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); };
  window.addEventListener('pointermove', move); window.addEventListener('pointerup', up);
});

// Hover descriptions come from the scene; the tooltip is plain HTML so it costs nothing to draw.
const tip = document.createElement('div'); tip.id = 'tip'; tip.hidden = true; document.body.appendChild(tip);
scene.onHover((text, at) => {
  if (!text) { tip.hidden = true; return; }
  const [head, ...rest] = text.split('\n');
  tip.innerHTML = `<b>${esc(head)}</b>${esc(rest.join(' '))}`; tip.hidden = false;
  const r = $('#kitchen').getBoundingClientRect(); const x = r.left + at.x, y = r.top + at.y;
  tip.style.left = `${Math.min(x + 14, window.innerWidth - tip.offsetWidth - 8)}px`; tip.style.top = `${Math.max(8, y - tip.offsetHeight - 10)}px`;
});

// ---------- control calls ----------
async function control(body) {
  const r = await fetch('/api/control', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  return r.json();
}
function showResult(el, out) {
  el.hidden = false; el.className = `note ${out.ok ? 'ok' : 'bad'}`;
  if (out.ok) el.textContent = out.via === 'demo' ? `Done (demo).` : `Typed into the session's tmux pane.`;
  else el.innerHTML = `${esc(out.reason || 'Could not reach the session.')}${out.command ? `<code>${esc(out.command)}</code>` : ''}`;
  if (out.ok) setTimeout(() => { el.hidden = true; }, 2500);
}

// ---------- state → panel ----------
let state = null, focus = null, controlsFor = null;
const actorOf = (s, who) => who === 'sous' ? s.sous : s.stations.find((x) => x.id === who)?.cook;
const stationOf = (s, who) => s.stations.find((x) => x.id === who);
const involves = (m, who) => m.from === who || m.to === who || (who === 'headchef' && (m.from === 'head-chef' || m.to === 'head-chef'));

function renderOverview(s) {
  const qs = s.headChef.pending;
  $('#attention').hidden = qs.length === 0;
  $('#questions').innerHTML = qs.map((q) => `<li data-q="${esc(q.id)}"><div class="from">${esc(q.from)} · via the sous</div>${esc(q.text)}<div class="opts">${(q.options || []).map((o) => `<button data-opt="${esc(o)}">${esc(o)}</button>`).join('')}</div><div class="note" hidden></div></li>`).join('');
  // The line as chips in the top bar: status dot, name, activity. The selected one is ringed.
  const actor = (a, sub, who) => `<li class="actor ${a.activity === 'waiting' ? 'waiting' : ''} ${focus === who ? 'selected' : ''}" data-who="${esc(who)}" title="${esc(sub)}"><span class="st ${esc(a.status)}"></span><span class="name">${esc(a.name)}</span><span class="act">${esc(a.activity)}</span><span class="sub">${esc(sub)}</span></li>`;
  const sousSub = s.sous.session ? `${s.sous.session}${s.sous.model ? ' · ' + s.sous.model : ''}` : 'no sous session';
  $('#line').classList.toggle('many', s.stations.length > 4);
  $('#line').innerHTML = actor(s.sous, sousSub, 'sous') + s.stations.map((st) => actor(st.cook, [st.id, st.ticket, st.branch, st.dirty ? 'dirty' : null, st.ahead ? `+${st.ahead}` : null, st.cook.model].filter(Boolean).join(' · '), st.id)).join('');
  const cols = ['backlog', 'todo', 'in-progress', 'rfr', 'done'];
  // The rail as a board down the left: one section per status, id and title per ticket.
  $('#rail').innerHTML = cols.map((c) => { const ts = s.rail[c] || []; return `<div class="col ${ts.length ? '' : 'empty'}"><h3>${c === 'in-progress' ? 'doing' : c}<span>${ts.length}</span></h3><div class="chips">${ts.slice(0, 12).map((t) => `<div class="t ${esc(t.kind || '')}" title="${esc(t.title)}">${esc(t.id)}<span class="title">${esc(t.title || '')}</span></div>`).join('')}${ts.length > 12 ? `<div class="t more">+${ts.length - 12} more</div>` : ''}</div></div>`; }).join('');
  // The console: everything heard, or only what involves the selected figure.
  const lines = focus ? s.log.filter((m) => involves(m, focus)) : s.log;
  $('#log').innerHTML = lines.slice(-80).reverse().map(logItem).join('');
  $('#count').textContent = `${lines.length} line${lines.length === 1 ? '' : 's'}`;
  const f = $('#filter'); f.hidden = !focus;
  if (focus) f.textContent = focus === 'headchef' ? 'Head chef' : (actorOf(s, focus)?.name || focus);
}

function renderDetail(s) {
  const who = focus;
  if (who === 'headchef') {
    const qs = s.headChef.pending;
    $('#d-head').innerHTML = `<div class="top"><span class="st dot"></span><h1>Head Chef</h1><span class="act">you</span></div><dl><dt>talks to</dt><dd>the sous only</dd><dt>waiting on you</dt><dd>${qs.length ? qs.length + ' question(s)' : 'nothing'}</dd></dl>`;
    if (controlsFor !== who) { controlsFor = who; $('#d-controls').innerHTML = `<h2>Needs you</h2><ul id="d-questions"></ul>`; }
    $('#d-questions').innerHTML = qs.length ? qs.map((q) => `<li data-q="${esc(q.id)}"><div class="from">${esc(q.from)} · via the sous</div>${esc(q.text)}<div class="opts">${(q.options || []).map((o) => `<button data-opt="${esc(o)}">${esc(o)}</button>`).join('')}</div><div class="note" hidden></div></li>`).join('') : '<li class="note">No open questions.</li>';
    return;
  }
  const a = actorOf(s, who), st = stationOf(s, who);
  if (!a) { setFocus(null); return; }
  const facts = who === 'sous'
    ? [['session', a.session || 'not running'], ['model', a.model], ['where', 'the main checkout'], ['pid', a.pid], ['attach', a.tmux ? `tmux attach -t ${a.tmux}` : null]]
    : [['session', a.session || 'not running'], ['model', a.model], ['station', st.path || st.id], ['ticket', st.ticket], ['branch', st.branch || 'detached at trunk'], ['tree', st.dirty ? 'dirty' : 'clean'], ['ahead', st.ahead ? `+${st.ahead} commits` : null], ['pid', a.pid], ['peek', a.tmux ? `tmux attach -t ${a.tmux}` : null]];
  $('#d-head').innerHTML = `<div class="top"><span class="st ${esc(a.activity === 'waiting' ? 'waiting' : a.status)}"></span><h1>${esc(a.name)}</h1><span class="act">${esc(a.activity)}</span></div><dl>${facts.filter(([, v]) => v).map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`).join('')}</dl>${a.bubble?.text ? `<div class="note">“${esc(a.bubble.text)}”</div>` : ''}`;
  if (controlsFor !== who) {
    controlsFor = who;
    const models = s.kitchen.models || ['fable', 'opus', 'sonnet', 'haiku'];
    const how = s.kitchen.control === 'tmux' ? 'Typed into the session\'s tmux pane.' : s.kitchen.control === 'demo' ? 'Demo: applied directly.' : 'No tmux on this machine: the Window shows you the command to paste.';
    $('#d-controls').innerHTML = `<h2>Controls <span class="pill">${esc(s.kitchen.control || 'none')}</span></h2>
      <div class="row"><div class="menu" id="c-model"><button type="button" aria-haspopup="listbox"><span class="val">${esc(a.model || models[0])}</span></button><ul role="listbox" hidden>${models.map((m) => `<li role="option" data-v="${esc(m)}" aria-selected="${m === a.model}">${esc(m)}</li>`).join('')}<li role="option" class="other" data-v="__other">other…</li></ul></div><button id="c-model-go" class="quiet">Change model</button></div>
      <div class="row"><input id="c-send" placeholder="Type a line to ${esc(a.name)}…" /><button id="c-send-go">Send</button></div>
      <div class="row shift"><button id="c-handoff" class="quiet">${who === 'sous' ? 'Handoff' : 'Handoff'} <small>/bk:handoff</small></button><button id="c-clear" class="danger">/clear · end of shift</button></div>
      <div id="c-shift" class="note"></div>
      <div class="note">${how}</div><div id="c-note" class="note" hidden></div>`;
    const menu = makeMenu($('#c-model'), a.model || models[0]);
    $('#c-model-go').onclick = async () => {
      let v = menu.value();
      if (v === '__other') v = await dialog({ title: 'Another model', text: 'The name as /model accepts it, for example claude-sonnet-5-5.', input: 'model name', ok: 'Change' });
      if (!v) return;
      showResult($('#c-note'), await control({ who, action: 'model', value: v }));
    };
    $('#c-send-go').onclick = async () => { const v = $('#c-send').value; if (!v.trim()) return; showResult($('#c-note'), await control({ who, action: 'send', value: v })); $('#c-send').value = ''; };
    $('#c-send').onkeydown = (e) => { if (e.key === 'Enter') { e.preventDefault(); $('#c-send-go').click(); } };
    $('#c-handoff').onclick = async () => { showResult($('#c-note'), await control({ who, action: 'handoff' })); };
    $('#c-clear').onclick = async () => {
      const sh = shiftOf(state, who);
      const yes = await dialog({ title: `Send /clear to ${a.name}?`, text: sh.ok ? 'Its conversation ends and a fresh one carries on from the handoff.' : `${sh.why} Clear anyway?`, ok: '/clear', danger: true });
      if (!yes) return;
      showResult($('#c-note'), await control({ who, action: 'clear' }));
    };
  }
  // End of shift: the clear button opens only once the handoff is written (the sous) or the
  // ticket is served (a cook). Until then it stays dim and the note says why.
  const sh = shiftOf(s, who);
  $('#c-clear').classList.toggle('dim', !sh.ok); $('#c-handoff').classList.toggle('due', !sh.ok && sh.needsHandoff);
  $('#c-shift').textContent = sh.why;
}

// A styled stand-in for <select>: one button, a list that opens under it, closes on click-away or Esc.
function makeMenu(root, initial) {
  const btn = root.querySelector('button'), list = root.querySelector('ul'), val = root.querySelector('.val');
  let value = initial;
  const close = () => { list.hidden = true; root.classList.remove('open'); document.removeEventListener('pointerdown', away, true); document.removeEventListener('keydown', key, true); };
  const away = (e) => { if (!root.contains(e.target)) close(); };
  const key = (e) => { if (e.key === 'Escape') { e.stopPropagation(); close(); } };
  btn.onclick = () => {
    if (!list.hidden) return close();
    list.hidden = false; root.classList.add('open');
    document.addEventListener('pointerdown', away, true); document.addEventListener('keydown', key, true);
  };
  list.onclick = (e) => {
    const li = e.target.closest('li'); if (!li) return;
    value = li.dataset.v;
    for (const o of list.children) o.setAttribute('aria-selected', String(o === li));
    val.textContent = value === '__other' ? 'other…' : value;
    close();
  };
  return { value: () => value };
}

// In-panel dialog in the Window's own style. Resolves true/false, or the typed string when `input` is set.
function dialog({ title, text, input, ok = 'OK', cancel = 'Cancel', danger = false }) {
  return new Promise((resolve) => {
    const el = document.createElement('div'); el.id = 'dialog';
    el.innerHTML = `<div class="box" role="dialog" aria-modal="true"><h3>${esc(title)}</h3>${text ? `<p>${esc(text)}</p>` : ''}${input !== undefined ? `<input placeholder="${esc(input)}" />` : ''}<div class="acts"><button class="no">${esc(cancel)}</button><button class="go ${danger ? 'danger' : ''}">${esc(ok)}</button></div></div>`;
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
function shiftOf(s, who) {
  if (who === 'sous') {
    const a = s.sous, fresh = a.handoffAt && (!a.startedAt || a.handoffAt > a.startedAt);
    if (fresh) return { ok: true, why: `Handoff written ${ago(a.handoffAt)}. A fresh sous reads it first.`, needsHandoff: false };
    return { ok: false, why: a.handoffAt ? `Its handoff is from before this conversation. Run the handoff first, then clear.` : 'No handoff written yet. Run the handoff first, then clear.', needsHandoff: true };
  }
  const st = s.stations.find((x) => x.id === who); if (!st) return { ok: false, why: '', needsHandoff: false };
  if (st.ticket) return { ok: false, why: `Holds ${st.ticket}: a clear now loses its context. Cooks hand off on their own at the PR; mid-ticket, run the handoff first.`, needsHandoff: true };
  if (st.dirty) return { ok: false, why: 'Its tree is dirty: something is not committed.', needsHandoff: false };
  return { ok: true, why: 'Between tickets: clear it and it checks in fresh.', needsHandoff: false };
}
function ago(t) { const m = Math.round((Date.now() - t) / 60000); return m < 1 ? 'just now' : m < 60 ? `${m} min ago` : `${Math.round(m / 60)} h ago`; }

function render(s) {
  $('#repo').textContent = s.kitchen.repo; $('#mode').textContent = `${s.kitchen.mode} · trunk ${s.kitchen.trunk}`;
  $('#demo').hidden = !s.kitchen.demo;
  renderOverview(s);
  $('#inspector').hidden = !focus;
  if (focus) renderDetail(s);
  $('#chat').placeholder = focus && focus !== 'headchef' ? `Say something to ${actorOf(s, focus)?.name || focus}…` : 'Say something to the sous…';
}
function setFocus(who) {
  focus = who; controlsFor = null; scene.setSelected(who);
  if (state) render(state);
}
scene.onSelect(setFocus);
$('#back').addEventListener('click', () => setFocus(null));
$('#filter').addEventListener('click', () => setFocus(null));
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && focus) setFocus(null); });
$('#line').addEventListener('click', (e) => { const li = e.target.closest('[data-who]'); if (li) setFocus(li.dataset.who); });
// Question options: the overview card and the head-chef detail share one handler.
document.addEventListener('click', async (e) => {
  const b = e.target.closest('button[data-opt]'); if (!b) return;
  const li = b.closest('[data-q]'); const note = li.querySelector('.note');
  for (const x of li.querySelectorAll('button')) x.disabled = true;
  const out = await control({ who: 'sous', action: 'answer', value: { id: li.dataset.q, option: b.dataset.opt } });
  showResult(note, out); if (!out.ok) for (const x of li.querySelectorAll('button')) x.disabled = false;
});
$('#chatform').addEventListener('submit', async (e) => {
  e.preventDefault(); const v = $('#chat').value; if (!v.trim()) return;
  const who = focus && focus !== 'headchef' ? focus : 'sous';
  const out = await control({ who, action: 'send', value: v }); showResult($('#chatnote'), out); if (out.ok) $('#chat').value = '';
});

const es = new EventSource('/events');
es.addEventListener('open', () => $('#conn').classList.remove('off'));
es.addEventListener('error', () => $('#conn').classList.add('off'));
es.addEventListener('snapshot', (e) => { state = JSON.parse(e.data); scene.applySnapshot(state); render(state); });
for (const t of ['message', 'bubble', 'helper:start', 'helper:end', 'ask', 'answered', 'ticket']) {
  es.addEventListener(t, (e) => scene.onEvent({ type: t, ...JSON.parse(e.data) }));
}
const fpsSamples = [];
setInterval(() => { fpsSamples.push(scene.fps()); if (fpsSamples.length > 8) fpsSamples.shift(); $('#fps').textContent = `${Math.round(fpsSamples.reduce((a, b) => a + b, 0) / fpsSamples.length)} fps`; }, 250);
