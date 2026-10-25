// The room, in 2.5D: a corner of a big kitchen floor seen from a fixed angle, two walls,
// boxes for the furniture (five faces each), the check as a working machine, and figures
// that always face the camera. Everything that moves is plain DOM: helpers walk by
// transitioning their floor position, bubbles and activity glyphs live inside each figure's
// billboard, and messages fly as small papers across the floor. Nothing is drawn to a
// canvas, so there is no dependency and no render loop beyond the papers in flight.

const T = 56;                                  // one floor unit, in px
const TILT = 60, ROT = 45;                     // the camera: fixed
const FLOOR = 2016;                            // the big floor, in px; the room is its top-left corner
const BB = `rotateZ(${-ROT}deg) rotateX(${-TILT}deg)`;   // the billboard transform, facing the camera
const PAL = ['#d4654f', '#e9a93c', '#6f9bd6', '#4fa86f', '#8e6bd6', '#e0843c', '#3fb0b0', '#c75a9a', '#9aa84f', '#5a7fd6', '#d6a04f', '#7a6bd6'];
const STEEL = { top: '#b7bfc6', south: '#8e979f', east: '#7b848c', side: '#6d757c' };
const BURNERS = 'radial-gradient(circle at 18% 50%, #2a2c30 0 11px, #4a4d52 12px 13px, transparent 14px), radial-gradient(circle at 40% 50%, #2a2c30 0 11px, #4a4d52 12px 13px, transparent 14px), linear-gradient(90deg, transparent 58%, #e8e0cf 58% 92%, transparent 92%) 0 50% / 100% 60% no-repeat, #b7bfc6';
const GLASS = { top: 'rgba(198,221,231,0.55)', south: 'rgba(198,221,231,0.38)', east: 'rgba(178,204,216,0.38)', side: 'rgba(178,204,216,0.3)' };
const BASE = { top: '#4a423b', south: '#6d625a', east: '#5e544c', side: '#544b44' };
const BOOK = { specs: '#4f86d9', backlog: '#b5533c', plans: '#56b27a', checklists: '#e8a33c', journal: '#9b6fd9', decisions: '#d8cfbf', questions: '#f0b84a', research: '#3fa9a3', brainstorm: '#e8873c', conventions: '#8a7f71', knowledge: '#6b8e9f', lessons: '#c9a227', claude: '#2a2520' };
const BOOK_NAME = { claude: 'CLAUDE.md', knowledge: 'domains' };
const PER_SHELF = 8, SHELVES = 3, PER_CUP = PER_SHELF * SHELVES;
const GREEN = '#6fcf7a', RED = '#e0533f', AMBER = '#e9a93c';

export const HELPER = {
  commis: { cap: '#4d7fd6', role: 'the record', about: 'The junior who fetches for the line. Before any question goes up, searches the record for a decision already made or a fact already written. Reads only; decides nothing.' },
  taster: { cap: '#8e6bd6', role: 'reviews', about: 'Tastes every plate before it leaves the pass. Reads a cook\'s diff, re-runs the check, walks the ticket\'s "Done when", and hands the sous a verdict with numbered findings.' },
  inspector: { cap: '#4fa86f', role: 'hygiene', about: 'The health inspector: looks, never cooks. Reads a branch diff and reports what should not be there, plus dead code the diff leaves behind.' },
  runner: { cap: '#e0843c', role: 'the check', about: 'Runs one noisy command (the check, a test suite, a scan) and brings back only pass or fail and the lines that matter, so nobody reads the whole output.' },
};
export const ABOUT = {
  sous: 'Runs the line from the pass. Assigns tickets, answers every gate the record settles, signs off bug, chore, precedent and hygiene plans, reviews every diff before it is committed, and is the only writer of the rail.',
  cook: 'Owns one station and one ticket per session: plan, implement, review, hand off for the pass, open the PR. Never asks the human; sends the commis first, then a [gate] to the sous.',
  head: 'You. Talk to the sous only. Decide what nobody has decided yet, sign off feature plans, merge, deploy.',
};
const GLYPH = { thinking: '…', editing: '✎', running: '↻', reading: '▤', waiting: '◔' };

const el = (cls, html = '') => { const d = document.createElement('div'); if (cls) d.className = cls; if (html) d.innerHTML = html; return d; };
const px = (v) => `${v * T}px`;
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const mmss = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
const num = (id) => (String(id || '').match(/\d+/) || [''])[0];

// Where everything stands, in floor units, for n stations: one row up to four cooks, then
// rows of three, each row stepped a little to the right; the floor grows with the rows.
export function layout(n) {
  n = Math.max(1, n);
  const rows = n <= 4 ? 1 : Math.ceil(n / 3), per = n <= 4 ? n : 3;
  const sp = rows === 1 ? 3.2 : 3.5, sw = 2.4;
  const y0 = rows === 1 ? 8.1 : 4.6, dy = 2.75, cx = rows === 1 ? 8 : 8.4;
  const stations = [];
  for (let i = 0; i < n; i++) {
    const r = Math.floor(i / per), c = i % per;
    stations.push({ x: cx + r * 0.5 + (c - (per - 1) / 2) * sp, y: y0 + r * dy, w: sw });
  }
  const D = Math.max(10.4, y0 + (rows - 1) * dy + 3.1);
  return { stations, D, homes: { commis: [2.1, 5], taster: [11.8, 3.1], inspector: [2.1, D + 0.2], runner: [20.6, 7.0] }, sous: [8, 2.9], chef: [14.2, 0.9], record: [1.5, 4.2], check: [14.9, 6.9] };
}

// A box: top, south, north, east, west faces around a floor rectangle. Labels sit on the
// south face (flipped back upright) or lie on the top.
function box(b) {
  const root = el('box');
  root.style.cssText = `left:${px(b.x)};top:${px(b.y)};width:${px(b.w)};height:${px(b.d)}`;
  const top = el('face top'); top.style.cssText = `transform:translateZ(${b.h}px);background:${b.top}`;
  if (b.topLabel) top.innerHTML = `<span class="toplabel" style="color:${b.ink || '#333'}">${b.topLabel}</span>`;
  const south = el('face south'); south.style.cssText = `height:${b.h}px;background:${b.south};border:${b.southBd || 'none'}`;
  if (b.label) south.innerHTML = `<div class="label ${b.lj || 'center'}${b.lv === 'top' ? ' high' : ''}" style="color:${b.ink || '#333'};font-size:${b.fs || '10px'}"><span class="name">${b.label}</span>${b.sub ? `<span class="sub" style="border-left-color:${b.mark || '#34312b'}">${b.sub}</span>` : ''}</div>`;
  const north = el('face north'); north.style.cssText = `height:${b.h}px;background:${b.side}`;
  const east = el('face east'); east.style.cssText = `width:${b.h}px;background:${b.east};border:${b.eastBd || 'none'}`;
  const west = el('face west'); west.style.cssText = `width:${b.h}px;background:${b.side}`;
  root.append(top, south, north, east, west);
  root.faces = { top, south, north, east, west };
  return root;
}

// The characters, as vector SVG: the same chefs and helpers the Window has always drawn
// (toque, double-breasted jacket, neckerchief, apron; the helpers' caps and tools), now
// standing in a billboard that always faces the camera. The face blinks and the right arm
// works by CSS animation, so nothing here runs a loop.
const OUT = 'stroke="#3b332c" stroke-width="1.2" stroke-opacity=".45"';
const SKIN = '#e7b58d', WHITE = '#f7f3ea';
const ROLE = { cook: { scarf: '#c7503f', apron: '#3d5a80', toque: 18 }, sous: { scarf: '#2a3a57', apron: '#2a3a57', toque: 28 }, head: { scarf: '#1f1f1f', apron: null, toque: 0 } };
const rr = (x, y, w, h, r, fill, extra = '') => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${fill}" ${extra}/>`;
const ci = (x, y, r, fill, extra = '') => `<circle cx="${x}" cy="${y}" r="${r}" fill="${fill}" ${extra}/>`;
const pg = (pts, fill) => `<polygon points="${pts}" fill="${fill}"/>`;
const face = (x, y, r) => `<g class="face" transform="translate(${x} ${y})"><g class="eyes">${ci(-r * .38, -r * .05, r * .14, '#2a2520')}${ci(r * .38, -r * .05, r * .14, '#2a2520')}</g><path d="M-2.5 ${r * .35} Q0 ${r * .5} 2.5 ${r * .35}" fill="none" stroke="#8a5a4a" stroke-width="1.2"/></g>`;
function chefSVG(role) {
  const R = ROLE[role], coat = role === 'head' ? '#2b2b2b' : WHITE;
  let s = `<svg class="chef" viewBox="-26 -118 52 136" width="52" height="136">`;
  s += rr(-10, -24, 8, 22, 3, '#2b2b2b') + rr(2, -24, 8, 22, 3, '#2b2b2b') + rr(-12, -5, 11, 6, 2, '#1a1a1a') + rr(1, -5, 11, 6, 2, '#1a1a1a');
  s += rr(-17, -64, 34, 44, 9, coat, OUT);
  if (role === 'head') {
    s += pg('-6,-64 0,-48 6,-64', '#f3eee2') + pg('-2,-60 2,-60 1,-44 -1,-44', '#8a2f2f') + pg('-10,-64 -6,-64 0,-50 -8,-52', '#1f1f1f') + pg('10,-64 6,-64 0,-50 8,-52', '#1f1f1f');
  } else {
    for (let i = 0; i < 3; i++) s += ci(-5, -56 + i * 9, 1.6, '#c9c2b2') + ci(5, -56 + i * 9, 1.6, '#c9c2b2');
    s += pg('-8,-64 0,-56 8,-64', '#e8e2d4') + pg('-7,-64 0,-57 7,-64 3,-66 0,-62 -3,-66', R.scarf) + pg('0,-57 -3,-50 3,-50', R.scarf);
    if (R.apron) s += rr(-13, -42, 26, 22, 4, R.apron, OUT);
  }
  s += rr(-21, -62, 9, 18, 4, coat, OUT) + rr(12, -62, 9, 18, 4, coat, OUT) + ci(-16, -43, 5, SKIN, OUT);
  s += `<g class="arm">${ci(16, -43, 5, SKIN, OUT)}<g class="tool">${rr(14, -67, 4, 26, 2, '#555')}${rr(13, -70, 6, 5, 0, '#ccc')}</g></g>`;
  s += ci(0, -74, 12, SKIN, OUT) + ci(-12, -74, 2.5, SKIN) + ci(12, -74, 2.5, SKIN) + ci(-5, -78, 1.6, '#e0856e', 'opacity=".35"') + ci(5, -78, 1.6, '#e0856e', 'opacity=".35"');
  if (role === 'head') s += rr(-13, -96, 26, 14, 4, '#1f1f1f', OUT) + rr(-17, -85, 34, 5, 2, '#1f1f1f', OUT) + rr(-13, -88, 26, 3, 0, '#8a2f2f');
  else {
    const h = R.toque;
    s += rr(-12, -84 - h + 8, 24, h + 2, 7, WHITE, OUT);
    for (const x of [-6, 0, 6]) s += `<line x1="${x}" y1="${-84 - h + 12}" x2="${x}" y2="-86" stroke="#d9d2c3" stroke-width="1"/>`;
    s += rr(-14, -86, 28, 7, 3, '#f3eee2', OUT);
  }
  s += face(0, -74, 12) + '</svg>';
  return s;
}
function helperSVG(kind) {
  const cap = HELPER[kind].cap;
  let s = `<svg class="helper" viewBox="-17 -56 34 74" width="34" height="74">`;
  s += `<g class="leg l" transform="translate(-3 -12)">${rr(-2, 0, 4, 12, 2, '#2b2b2b')}${rr(-3, 9, 6, 3.5, 1.5, '#1a1a1a')}</g><g class="leg r" transform="translate(3 -12)">${rr(-2, 0, 4, 12, 2, '#2b2b2b')}${rr(-3, 9, 6, 3.5, 1.5, '#1a1a1a')}</g>`;
  s += rr(-9, -34, 18, 24, 6, WHITE, OUT) + rr(-7, -22, 14, 11, 2, cap) + ci(-3, -29, 1.2, '#c9c2b2') + ci(3, -29, 1.2, '#c9c2b2');
  s += ci(0, -40, 7, SKIN, OUT) + rr(-8, -50, 16, 8, 3, cap, OUT) + rr(-9, -44, 18, 3, 1.5, cap);
  if (kind === 'inspector') s += rr(6, -34, 8, 11, 1, '#f3eee2', OUT) + rr(7, -31, 6, 1.5, 0, '#2a2520') + rr(7, -28, 6, 1.5, 0, '#2a2520');
  if (kind === 'taster') s += ci(9, -30, 3, '#ddd', OUT) + rr(8.5, -30, 1.5, 9, 0, '#ddd');
  if (kind === 'runner') s += rr(6, -36, 7, 9, 1, '#444', OUT);
  if (kind === 'commis') s += rr(-14, -32, 7, 9, 1, '#b5533c', OUT);
  s += face(0, -40, 7) + '</svg>';
  return s;
}
const BUBBLE_MAX = 110;
const shortOf = (text) => text.length > BUBBLE_MAX ? text.slice(0, BUBBLE_MAX).replace(/\s+\S*$/, '') + ' …' : text;
// A figure: a floor anchor that holds a billboard (the character, always facing the camera)
// and a ring on the floor. The billboard also carries the badge, the activity glyph, the
// bubble and, for everyone but the cooks (whose station says who they are), a name.
function figure({ id, name, role, label = true }) {
  const root = el('fig'); root.dataset.id = id;
  const ring = el('ring'); root.appendChild(ring);
  const bb = document.createElement('button'); bb.className = `bb ${ROLE[role] ? 'chef' : 'small'}`; bb.dataset.agent = id; bb.setAttribute('aria-label', name); bb.type = 'button';
  bb.innerHTML = `<div class="bubble" hidden></div><span class="badge" hidden></span><span class="glyph" hidden></span>${label ? `<span class="name">${name}</span>` : ''}${ROLE[role] ? chefSVG(role) : helperSVG(role)}`;
  bb.style.transform = BB;
  root.appendChild(bb);
  const f = { id, name, role, root, bb, ring, bubble: bb.querySelector('.bubble'), badge: bb.querySelector('.badge'), glyph: bb.querySelector('.glyph'), x: 0, y: 0, status: 'offline', activity: 'offline', said: '', model: null, pinned: false };
  f.place = (x, y) => { f.x = x; f.y = y; root.style.left = px(x); root.style.top = px(y); };
  // A bubble is cut at three lines; a click opens it whole and keeps it up, a second click lets it go.
  f.bubble.addEventListener('click', (e) => {
    e.stopPropagation();
    f.pinned = !f.pinned; f.bubble.classList.toggle('full', f.pinned);
    clearTimeout(f.bubbleT);
    if (f.pinned) f.bubble.textContent = f.said;
    else { f.bubble.textContent = shortOf(f.said); f.bubbleT = setTimeout(() => { f.bubble.hidden = true; }, 2500); }
  });
  return f;
}

// The check: a dish machine with an in-feed tray (what is queued), the machine itself (a
// door that spins while a run is in, a lamp, a readout, the last ten results on top), an
// out-feed with the last result, steam while it runs, and a beacon over it saying what is in.
function buildCheck() {
  const root = el('check');
  const mat = el('pad mat'); mat.style.cssText = 'left:756px;top:274px;width:246px;height:162px';
  const feed = el('cbox feed'); feed.style.cssText = 'left:767px;top:300px;width:67px;height:56px';
  feed.innerHTML = `<div class="face top" style="transform:translateZ(34px)"><div class="queue"></div></div><div class="face south" style="height:34px;background:#8e979f"><div class="label center" style="color:#2f3438;font-size:8px">NEXT</div></div><div class="face north" style="height:34px;background:#6d757c"></div><div class="face east" style="width:34px;background:#7b848c"></div><div class="face west" style="width:34px;background:#6d757c"></div>`;
  const machine = el('cbox machine'); machine.style.cssText = 'left:840px;top:291px;width:90px;height:73px';
  machine.innerHTML = `<div class="face top" style="transform:translateZ(70px)"><div class="hist"></div></div>
    <div class="face south" style="height:70px;background:#5b6067"><div class="front"><div class="door"><div class="spin"></div></div><div class="panel"><span class="lamp"></span><span class="lbl">CHECK</span><span class="readout"></span></div></div></div>
    <div class="face north" style="height:70px;background:#43484d"></div><div class="face east" style="width:70px;background:repeating-linear-gradient(0deg,#4b5056 0 6px,#42464c 6px 8px)"></div><div class="face west" style="width:70px;background:#43484d"></div>`;
  const out = el('cbox out'); out.style.cssText = 'left:935px;top:300px;width:56px;height:56px';
  out.innerHTML = `<div class="face top" style="transform:translateZ(34px)"><span class="plate"><span class="mark"></span></span></div><div class="face south" style="height:34px;background:#8e979f"></div><div class="face north" style="height:34px;background:#6d757c"></div><div class="face east" style="width:34px;background:#7b848c"></div><div class="face west" style="width:34px;background:#6d757c"></div>`;
  const fx = el('cfx'); fx.style.cssText = 'left:885px;top:328px';
  fx.innerHTML = `<div class="steam bb" style="transform:translateZ(72px) ${BB}"><i></i><i></i><i></i></div><div class="beacon bb" style="transform:translateZ(118px) ${BB}"><div class="card"><div class="row"><span class="lamp"></span><b>CHECK</b><span class="chip"></span><span class="time mono"></span></div><div class="row next mono"><span>next</span><span class="dots"></span><span class="stats"></span></div></div></div>`;
  root.append(mat, feed, machine, out, fx);
  return { root, parts: { feed, machine, out, fx, queue: feed.querySelector('.queue'), hist: machine.querySelector('.hist'), door: machine.querySelector('.door'), lamp: machine.querySelector('.lamp'), readout: machine.querySelector('.readout'), plate: out.querySelector('.plate'), mark: out.querySelector('.mark'), blamp: fx.querySelector('.beacon .lamp'), chip: fx.querySelector('.chip'), time: fx.querySelector('.time'), dots: fx.querySelector('.dots'), stats: fx.querySelector('.stats'), card: fx.querySelector('.card') } };
}

export function createScene(stage) {
  const scene = el('scene'); stage.appendChild(scene);
  const wallN = el('wall n', `<div class="paint"><div class="tiles"></div><div class="sign">MISE EN PLACE · THEN SHIP</div></div>`);
  const wallW = el('wall w', `<div class="tiles"></div>`);
  scene.append(wallN, wallW);
  const layers = { pads: el('layer'), boxes: el('layer'), figs: el('layer'), fx: el('layer') };
  Object.values(layers).forEach((l) => scene.appendChild(l));

  let L = layout(1), vw = innerWidth, vh = innerHeight;
  let hoverCb = null, selectCb = null, cameraCb = null, selected = null, hovered = null;
  function applyCamera() {
    const sc = Math.min(1.7, Math.max(0.75, Math.min(vw / 1290, vh / (650 + (L.D - 10.4) * 60))));
    const oy = L.D * T / 2;
    scene.style.transformOrigin = `448px ${oy}px`; scene.style.margin = `${-oy}px 0 0 -448px`;
    scene.style.transform = `scale(${sc}) rotateX(${TILT}deg) rotateZ(${ROT}deg)`;
    cameraCb?.({ scale: sc });
  }
  const bare = (t) => t === stage || t === scene || ['layer', 'face', 'wall', 'paint', 'tiles', 'pad'].some((c) => t.classList?.contains(c));
  stage.addEventListener('click', (e) => { if (bare(e.target)) selectCb?.(null); });
  window.addEventListener('resize', () => { vw = innerWidth; vh = innerHeight; applyCamera(); });

  // --- fixed furniture
  const fixed = [];
  const record = { boxes: [], about: '' };
  const check = buildCheck();
  let checkNote = 'Nothing has run yet.';
  function buildFixed() {
    for (const b of fixed) b.remove(); fixed.length = 0;
    const add = (b) => { const n = box(b); layers.boxes.appendChild(n); fixed.push(n); return n; };
    // the head chef's office: a glass corner top-right, with a striped floor and a desk
    const pad = el('pad'); pad.style.cssText = `left:${px(12.5)};top:0;width:${px(3.5)};height:${px(2.1)}`; layers.pads.appendChild(pad); fixed.push(pad);
    add({ x: 13.6, y: 0.25, w: 1.8, d: 0.55, h: 28, top: '#8a5a3c', south: '#6e4630', east: '#5e3b28', side: '#5a3826' });
    add({ x: 12.5, y: 2.0, w: 3.5, d: 0.12, h: 26, ...BASE, label: 'HEAD CHEF', ink: '#efe6d6', fs: '9px' });
    add({ x: 12.5, y: 2.0, w: 3.5, d: 0.12, h: 78, ...GLASS });
    add({ x: 12.5, y: 0, w: 0.12, d: 1.15, h: 26, ...BASE });
    add({ x: 12.5, y: 0, w: 0.12, d: 1.15, h: 78, ...GLASS });
    add({ x: 4, y: 1.4, w: 8, d: 0.7, h: 34, ...STEEL, label: 'THE PASS', ink: '#3a4046', fs: '11px' });
    add({ x: 1.4, y: 0, w: 1.3, d: 0.07, h: 86, top: '#9aa3aa', south: 'linear-gradient(90deg, transparent 82%, #6d757c 82% 86%, transparent 86%) 0 30% / 100% 30% no-repeat, #d5dbe0', southBd: '4px solid #9aa3aa', east: '#aab3ba', side: '#9aa3aa', label: 'WALK-IN', ink: '#5b6570', fs: '9px', lj: 'start', lv: 'top' });
    layers.boxes.appendChild(check.root); fixed.push(check.root);
    drawRecord(lastRecord, true);
  }
  for (const part of [check.parts.feed, check.parts.machine, check.parts.out]) {
    part.addEventListener('click', (e) => { e.stopPropagation(); selectCb?.('runner'); });
    part.addEventListener('mouseenter', () => hoverCb?.(`The check\n${checkNote}`, part)); part.addEventListener('mouseleave', () => hoverCb?.(null));
  }

  // --- the record: cupboards against the left wall that fill with one book per page written
  let lastRecord = { total: 0, kinds: {} }, recordKey = '';
  function drawRecord(rec, force = false) {
    const key = JSON.stringify(rec); if (!force && key === recordKey) return; recordKey = key; lastRecord = rec;
    for (const b of record.boxes) b.remove(); record.boxes = [];
    const total = rec?.total || 0, kinds = rec?.kinds || {};
    const cups = Math.min(2, Math.max(1, Math.ceil(total / PER_CUP)));
    const books = []; for (const [k, n] of Object.entries(kinds)) for (let i = 0; i < n; i++) books.push(BOOK[k] || '#8a7f71');
    const parts = Object.entries(kinds).sort((a, b) => b[1] - a[1]).map(([k, n]) => `${BOOK_NAME[k] || k} ${n}`).join(' · ');
    const about = `The record · ${total} page${total === 1 ? '' : 's'}\n${parts || 'Nothing written down yet.'} What the kitchen remembers: specs, tickets, plans, checklists, journals, decisions. The commis reads here before any question goes up.`;
    for (let c = 0; c < cups; c++) {
      const b = box({ x: 0.25, y: 2.8 + c * 2.05, w: 0.9, d: 1.9, h: 112, top: '#5a3826', south: '#7d5038', east: '#7d5038', side: '#5a3826', eastBd: '5px solid #7d5038', topLabel: c === 0 ? `THE RECORD${total ? ' · ' + total : ''}` : '', ink: '#f0dcc8' });
      const shelves = el('shelves');
      for (let s = 0; s < SHELVES; s++) {
        const sh = el('shelf');
        for (let i = 0; i < PER_SHELF; i++) { const col = books[c * PER_CUP + s * PER_SHELF + i]; if (!col) break; const bk = el('book'); bk.style.background = col; bk.style.height = `${70 + ((s * 7 + i * 3 + c) % 3) * 8}%`; sh.appendChild(bk); }
        shelves.appendChild(sh);
      }
      b.faces.east.appendChild(shelves);
      b.classList.add('pick'); b.addEventListener('click', (e) => { e.stopPropagation(); selectCb?.('commis'); });
      b.addEventListener('mouseenter', () => hoverCb?.(about, b)); b.addEventListener('mouseleave', () => hoverCb?.(null));
      layers.boxes.appendChild(b); record.boxes.push(b);
    }
    record.about = about;
  }

  // --- figures
  const figs = new Map();     // id → figure (sous, chef, station cooks, resident helpers)
  const stations = new Map(); // id → { box, cook, mark, pos, ticket }
  const extras = new Set();   // helpers that stepped in while the resident was out
  function addFig(f, x, y) {
    f.place(x, y); layers.figs.appendChild(f.root);
    f.bb.addEventListener('click', (e) => { e.stopPropagation(); selectCb?.(f.id); });
    f.bb.addEventListener('mouseenter', () => { hovered = f.id; hoverCb?.(hoverText(f), f.bb); });
    f.bb.addEventListener('mouseleave', () => { hovered = null; hoverCb?.(null); });
    return f;
  }
  const modelName = (m) => { const s = String(m || '').toLowerCase(); for (const n of ['fable', 'opus', 'sonnet', 'haiku']) if (s.includes(n)) return n[0].toUpperCase() + n.slice(1); return m || ''; };
  const hoverText = (f) => `${f.name}${f.model ? ': ' + modelName(f.model) : ''}\n${f.meta || ''}`;
  const sous = addFig(figure({ id: 'sous', name: 'Sous Chef', role: 'sous' }), ...layout(1).sous);
  const chef = addFig(figure({ id: 'headchef', name: 'Head Chef', role: 'head', label: false }), ...layout(1).chef);
  const residents = {};
  for (const [kind, h] of Object.entries(HELPER)) { const f = addFig(figure({ id: kind, name: kind, role: kind }), 0, 0); f.meta = h.role; f.busy = false; residents[kind] = f; }

  function setActor(f, a) {
    const status = a?.status || 'offline', act = a?.activity || 'offline';
    f.status = status; f.activity = act;
    f.ring.dataset.status = act === 'waiting' ? 'waiting' : status;
    f.root.classList.toggle('offline', act === 'offline');
    f.bb.dataset.activity = act;
    const g = GLYPH[act]; f.glyph.hidden = !g; if (g) f.glyph.textContent = g;
    if (a?.model) f.model = a.model;
  }

  function makeStation(id, i, name) {
    const st = { id, i, cook: addFig(figure({ id, name, role: 'cook', label: false }), 0, 0), mark: PAL[i % PAL.length], box: null, ticket: null };
    stations.set(id, st); return st;
  }
  function relayout(ids) {
    L = layout(ids.length); scene.style.width = `${FLOOR}px`; scene.style.height = `${FLOOR}px`; buildFixed();
    ids.forEach((id, i) => {
      const st = stations.get(id), p = L.stations[i]; st.pos = p;
      if (st.box) st.box.remove();
      st.box = box({ x: p.x - p.w / 2, y: p.y, w: p.w, d: 1.1, h: 38, ...STEEL, top: BURNERS, label: 'COOK ' + (i + 1), sub: st.ticket || '', mark: st.mark, ink: '#2f3438', fs: '10px', lj: 'center' });
      st.box.classList.add('pick', 'station'); st.box.addEventListener('click', (e) => { e.stopPropagation(); selectCb?.(id); });
      st.box.addEventListener('mouseenter', () => hoverCb?.(hoverText(st.cook), st.box)); st.box.addEventListener('mouseleave', () => hoverCb?.(null));
      st.box.faces.top.appendChild(el('flame')); st.box.faces.top.appendChild(el('steam', '<i></i><i></i><i></i>'));
      layers.boxes.appendChild(st.box);
      st.cook.place(p.x, p.y - 0.6);
    });
    sous.place(...L.sous); chef.place(...L.chef);
    for (const [kind, f] of Object.entries(residents)) if (!f.busy) f.place(...L.homes[kind]);
    applyCamera();
  }

  // --- the check, from the state: runners in flight are the machine and its queue, the
  // results the server kept are the history, the out-feed and the counters
  function drawCheck(s) {
    const p = check.parts, ck = s.check || { history: [], runs: 0, failed: 0, last: null };
    const running = [...s.helpers].filter((h) => h.kind === 'runner').sort((a, b) => a.since - b.since);
    const cur = running[0] || null, queue = running.slice(1);
    const markOf = (who) => stations.get(who)?.mark || '#8e979f';
    const nameOf = (who) => stations.get(who)?.cook.name || (who === 'sous' ? 'Sous Chef' : who);
    const mode = cur ? 'run' : !ck.last ? 'idle' : ck.last.ok === false ? 'fail' : ck.last.ok ? 'pass' : 'done';
    const lamp = { run: AMBER, pass: GREEN, fail: RED, idle: '#7d776c', done: '#9aa3aa' }[mode];
    const secs = cur ? (Date.now() - cur.since) / 1000 : (ck.last?.secs || 0);
    check.root.dataset.mode = mode;
    p.queue.innerHTML = queue.map((h) => `<span class="q" style="border-color:${markOf(h.from)}">${esc(num(h.from))}</span>`).join('');
    p.hist.innerHTML = (ck.history || []).slice(-10).map((r) => `<span style="background:${r.ok === false ? RED : r.ok ? GREEN : '#9aa3aa'}"></span>`).join('');
    for (const l of [p.lamp, p.blamp]) { l.style.background = lamp; l.style.boxShadow = `0 0 8px ${lamp}`; }
    p.readout.textContent = cur ? `C${num(cur.from) || '·'} ${mmss(secs)}` : ck.last ? `${mode.toUpperCase()} ${Math.round(secs)}s` : 'IDLE';
    p.readout.style.color = lamp;
    p.plate.hidden = !ck.last; if (ck.last) { p.plate.style.borderColor = markOf(ck.last.who); p.mark.style.background = ck.last.ok === false ? RED : ck.last.ok ? GREEN : '#9aa3aa'; p.mark.textContent = ck.last.ok === false ? '✕' : ck.last.ok ? '✓' : '·'; }
    p.card.style.borderColor = lamp;
    p.chip.textContent = cur ? `${nameOf(cur.from)} · ${cur.note || 'the check'}` : ck.last ? `${mode} · ${nameOf(ck.last.who)}` : 'idle';
    p.time.textContent = cur ? mmss(secs) : ck.last ? `${Math.round(secs)}s` : ''; p.time.style.color = lamp;
    p.dots.innerHTML = queue.length ? queue.map((h) => `<i style="background:${markOf(h.from)}"></i>`).join('') : '—';
    p.stats.textContent = `· ${ck.runs || 0} runs · ${ck.failed || 0} red`;
    checkNote = (cur ? `In the machine: ${nameOf(cur.from)}, ${cur.note || 'the check'}, ${mmss(secs)}. ` : 'Machine idle. ')
      + `Next: ${queue.length ? queue.map((h) => nameOf(h.from)).join(', ') : 'nobody'}. `
      + (ck.last ? `Last: ${ck.last.ok === false ? 'fail' : ck.last.ok ? 'pass' : 'done'} in ${Math.round(ck.last.secs)}s (${nameOf(ck.last.who)}). ` : '')
      + `${ck.runs || 0} runs this shift, ${ck.failed || 0} red.`;
    residents.runner.meta = checkNote;
    clearTimeout(check.timer); if (cur) check.timer = setTimeout(() => drawCheck(lastState), 1000);
  }

  let lastIds = '', lastState = null;
  function applySnapshot(s) {
    lastState = s;
    const ids = s.stations.map((x) => x.id);
    for (const id of [...stations.keys()]) if (!ids.includes(id)) { const st = stations.get(id); st.box?.remove(); st.cook.root.remove(); figs.delete(id); stations.delete(id); }
    s.stations.forEach((x, i) => { if (!stations.has(x.id)) { const st = makeStation(x.id, i, x.cook?.name || x.name || x.id); figs.set(x.id, st.cook); } });
    const key = ids.join(','); if (key !== lastIds) { lastIds = key; relayout(ids); }
    drawRecord(s.record);
    s.stations.forEach((x, i) => {
      const st = stations.get(x.id); st.i = i; st.mark = PAL[i % PAL.length];
      const name = x.cook?.name || x.name; if (st.cook.name !== name) { st.cook.name = name; st.cook.bb.setAttribute('aria-label', name); }
      setActor(st.cook, x.cook);
      st.cook.meta = [x.ticket, x.branch].filter(Boolean).join(' · ');
      if (st.ticket !== (x.ticket || null)) {
        st.ticket = x.ticket || null;
        let sub = st.box.querySelector('.label .sub');
        if (!sub) { sub = document.createElement('span'); sub.className = 'sub'; sub.style.borderLeftColor = st.mark; st.box.querySelector('.label').appendChild(sub); }
        sub.textContent = st.ticket || ''; sub.hidden = !st.ticket;
      }
      st.box.classList.toggle('cooking', ['editing', 'running'].includes(x.cook?.activity));
    });
    setActor(sous, s.sous); sous.meta = s.sous.session || '';
    const n = s.headChef.pending.length;
    chef.badge.hidden = !n; chef.badge.textContent = String(n);
    sous.badge.hidden = !n; sous.badge.textContent = '!';
    chef.status = 'idle'; chef.activity = n ? 'thinking' : 'idle'; chef.ring.dataset.status = 'idle'; chef.meta = n ? `${n} question${n === 1 ? '' : 's'} waiting` : 'nothing waiting on you';
    for (const id of [...helpers.keys()]) if (!s.helpers.find((h) => h.id === id)) endHelper(id);
    for (const h of s.helpers) if (!helpers.has(h.id)) startHelper(h);
    figs.set('sous', sous); figs.set('headchef', chef); for (const [k, f] of Object.entries(residents)) figs.set(k, f);
    drawCheck(s);
    if (hovered) { const f = figs.get(hovered); if (f) hoverCb?.(hoverText(f), f.bb); }
  }

  // --- helpers walk to their jobs: the commis to the record, the runner to the check, the
  // taster and the inspector to the station that called; an extra hand steps in if the
  // resident is already out.
  const helpers = new Map();
  const posOf = (who) => who === 'sous' ? L.sous : (who === 'headchef' || who === 'head-chef') ? L.chef : stations.get(who)?.pos ? [stations.get(who).pos.x, stations.get(who).pos.y - 0.6] : L.sous;
  function walk(f, [x, y], then) {
    const d = Math.hypot(x - f.x, y - f.y), secs = Math.max(.4, d / 4);
    f.root.style.transition = `left ${secs}s linear, top ${secs}s linear`;
    f.root.classList.add('walking'); f.place(x, y);
    clearTimeout(f.walkT); f.walkT = setTimeout(() => { f.root.classList.remove('walking'); then?.(); }, secs * 1000);
  }
  function startHelper(h) {
    if (!HELPER[h.kind]) return;
    let f = residents[h.kind];
    if (f.busy) { f = figure({ id: h.kind, name: h.kind, role: h.kind }); f.meta = HELPER[h.kind].role; f.extra = true; addFig(f, ...L.homes[h.kind]); extras.add(f); }
    f.busy = true; f.note = h.note || ''; if (h.kind !== 'runner') f.meta = `${HELPER[h.kind].role} · ${f.note || 'working'}`;
    const from = posOf(h.from), at = [from[0] + 0.8, from[1] + 0.2];
    const target = h.kind === 'commis' ? [L.record[0] + 0.3, L.record[1] + 0.8]
      : h.kind === 'runner' ? L.check
      : h.kind === 'taster' ? (() => { const p = posOf(h.note?.match(/station-\d+/)?.[0] || h.from); return [p[0] + 0.8, p[1] + 0.2]; })()
      : at;
    f.glyph.hidden = false; f.glyph.textContent = GLYPH.running;
    f.bb.classList.toggle('atwork', h.kind === 'runner');   // the beacon over the machine names it; a label there would sit on the machine
    walk(f, target, () => { f.bb.dataset.activity = 'running'; });
    helpers.set(h.id, f);
  }
  function endHelper(id) {
    const f = helpers.get(id); if (!f) return; helpers.delete(id);
    f.busy = false; f.note = ''; if (f.role !== 'runner') f.meta = HELPER[f.role].role; f.glyph.hidden = true; f.bb.dataset.activity = ''; f.bb.classList.remove('atwork');
    walk(f, L.homes[f.role], () => { if (f.extra) { f.root.remove(); extras.delete(f); } });
  }

  // --- what is said: a bubble over the speaker, cut at three lines (the whole text is in
  // the popover and the console); a paper flies from sender to receiver for every message
  function say(who, text, ttl) {
    const f = figs.get(who === 'head-chef' ? 'headchef' : who); if (!f) return;
    f.said = text;
    f.bubble.textContent = f.pinned ? text : shortOf(text); f.bubble.hidden = false;
    clearTimeout(f.bubbleT); if (!f.pinned) f.bubbleT = setTimeout(() => { f.bubble.hidden = true; }, (ttl ?? Math.min(9, 3 + text.length / 25)) * 1000);
  }
  const papers = [];
  function flyMessage({ from, to, kind, text }) {
    const a = posOf(from), b = posOf(to);
    const p = { el: el('paper', kind.replace(/[[\]]/g, '')), t: 0, a, b, dur: Math.max(.9, Math.hypot(b[0] - a[0], b[1] - a[1]) / 9) };
    p.el.style.transform = `translateZ(var(--z,60px)) ${BB}`; p.el.style.left = px(a[0]); p.el.style.top = px(a[1]);
    layers.fx.appendChild(p.el); papers.push(p); tick();
    if (text) say(from, `${kind} ${text}`);
  }
  // The only render loop: papers in flight (and the frame counter), at most 30 a second.
  let raf = 0, last = 0, frames = 0, frameAt = performance.now();
  function tick() { if (!raf) { last = performance.now(); raf = requestAnimationFrame(step); } }
  function step(now) {
    raf = 0; const dt = Math.min(.1, (now - last) / 1000); last = now; frames++;
    for (let i = papers.length - 1; i >= 0; i--) {
      const p = papers[i]; p.t += dt; const u = Math.min(1, p.t / p.dur), e = u < .5 ? 2 * u * u : -1 + (4 - 2 * u) * u;
      const x = p.a[0] + (p.b[0] - p.a[0]) * e, y = p.a[1] + (p.b[1] - p.a[1]) * e, z = 60 + Math.sin(e * Math.PI) * 90;
      p.el.style.left = px(x); p.el.style.top = px(y); p.el.style.setProperty('--z', `${z}px`);
      if (u >= 1) { p.el.style.opacity = String(Math.max(0, 1 - (p.t - p.dur) * 4)); if (p.t > p.dur + .3) { p.el.remove(); papers.splice(i, 1); } }
    }
    if (papers.length) setTimeout(() => { raf = requestAnimationFrame(step); }, 33);
  }
  function fps() { const now = performance.now(), s = (now - frameAt) / 1000, f = s > 0 ? frames / s : 0; frames = 0; frameAt = now; return Math.round(f); }

  relayout([]);
  return {
    applySnapshot, say, fps, layout: () => L,
    figure: (id) => figs.get(id) || null,
    recordAbout: () => record.about, checkNote: () => checkNote,
    onHover(fn) { hoverCb = fn; }, onSelect(fn) { selectCb = fn; }, onCamera(fn) { cameraCb = fn; },
    setSelected(who) {
      selected = who && figs.has(who) ? who : null;
      for (const f of [...figs.values(), ...extras]) f.root.classList.toggle('selected', f.id === selected);
      check.root.classList.toggle('selected', selected === 'runner');
    },
    onEvent(ev) {
      switch (ev.type) {
        case 'message': flyMessage(ev); break;
        case 'bubble': say(ev.who, ev.text); break;
        case 'helper:start': startHelper(ev); break;
        case 'helper:end': endHelper(ev.id); break;
        case 'ask': say('headchef', `Question from ${ev.from}: ${ev.text}`, 8); break;
      }
    },
  };
}
