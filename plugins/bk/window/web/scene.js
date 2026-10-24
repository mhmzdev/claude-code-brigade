// The room, in 2.5D: a floor plane tilted and turned with CSS 3D, boxes for the furniture
// (five faces each), and figures that always face the camera. Everything that moves is
// plain DOM: helpers walk by transitioning their floor position, bubbles and activity
// glyphs live inside each figure's billboard, and messages fly as small papers across the
// floor. Nothing is drawn to a canvas, so there is no dependency and no render loop
// beyond the few animations in flight.

const T = 56;                                  // one floor unit, in px
const TILT = 58, ROT0 = 45;                    // the camera: fixed tilt, rotation kept within ±90°
const PAL = ['#d4654f', '#e9a93c', '#6f9bd6', '#4fa86f', '#8e6bd6', '#e0843c', '#3fb0b0', '#c75a9a', '#9aa84f', '#5a7fd6', '#d6a04f', '#7a6bd6'];
const STEEL = { top: '#b7bfc6', south: '#8e979f', east: '#7b848c', side: '#6d757c' };
const BURNERS = 'radial-gradient(circle at 18% 50%, #2a2c30 0 11px, #4a4d52 12px 13px, transparent 14px), radial-gradient(circle at 40% 50%, #2a2c30 0 11px, #4a4d52 12px 13px, transparent 14px), linear-gradient(90deg, transparent 58%, #e8e0cf 58% 92%, transparent 92%) 0 50% / 100% 60% no-repeat, #b7bfc6';
const GLASS = { top: 'rgba(198,221,231,0.55)', south: 'rgba(198,221,231,0.38)', east: 'rgba(178,204,216,0.38)', side: 'rgba(178,204,216,0.3)' };
const BASE = { top: '#4a423b', south: '#6d625a', east: '#5e544c', side: '#544b44' };
const BOOK = { specs: '#4f86d9', backlog: '#b5533c', plans: '#56b27a', checklists: '#e8a33c', journal: '#9b6fd9', decisions: '#d8cfbf', questions: '#f0b84a', research: '#3fa9a3', brainstorm: '#e8873c', conventions: '#8a7f71', knowledge: '#6b8e9f', lessons: '#c9a227', claude: '#2a2520' };
const BOOK_NAME = { claude: 'CLAUDE.md', knowledge: 'domains' };
const PER_SHELF = 8, SHELVES = 3, PER_CUP = PER_SHELF * SHELVES;

export const HELPER = {
  commis: { cap: '#4d7fd6', role: 'the record', about: 'The junior who fetches for the line. Before any question goes up, searches the record for a decision already made or a fact already written. Reads only; decides nothing.' },
  taster: { cap: '#8e6bd6', role: 'reviews', about: 'Tastes every plate before it leaves the pass. Reads a cook\'s diff, re-runs the check, walks the ticket\'s "Done when", and hands the sous a verdict with numbered findings.' },
  inspector: { cap: '#4fa86f', role: 'hygiene', about: 'The health inspector: looks, never cooks. Reads a branch diff and reports what should not be there, plus dead code the diff leaves behind.' },
  runner: { cap: '#e0843c', role: 'the check', about: 'Runs one noisy command (the check, a test suite, a scan) and brings back only pass or fail and the lines that matter, so nobody reads the whole output.' },
};
export const ABOUT = {
  sous: 'Runs the line from the pass. Assigns tickets, answers every gate the record settles, signs off bug, chore and hygiene plans, reviews every diff before it is committed, and is the only writer of the rail.',
  cook: 'Owns one station and one ticket per session: plan, implement, review, hand off for the pass, open the PR. Never asks the human; sends the commis first, then a [gate] to the sous.',
  head: 'You. Talk to the sous only. Decide what nobody has decided yet, sign off feature plans, merge, deploy.',
};
const GLYPH = { thinking: '…', editing: '✎', running: '↻', reading: '▤', waiting: '◔' };

const el = (cls, html = '') => { const d = document.createElement('div'); if (cls) d.className = cls; if (html) d.innerHTML = html; return d; };
const px = (v) => `${v * T}px`;

// Where everything stands, in floor units, for n stations: the line in one or two rows
// between the record (left) and the walk-in; the check moves down with the floor.
export function layout(n) {
  n = Math.max(1, n);
  const rows = n <= 4 ? 1 : Math.ceil(n / 4), per = Math.ceil(n / rows);
  const sp = Math.min(3.5, 10.4 / per), sw = Math.min(2.4, sp - 0.35);
  const y0 = rows === 1 ? 7 : 4.7, dy = 2.5;
  const stations = [];
  for (let i = 0; i < n; i++) {
    const r = Math.floor(i / per), c = i % per, k = Math.min(per, n - r * per);
    stations.push({ x: 8 + (c - (k - 1) / 2) * sp, y: y0 + r * dy, w: sw });
  }
  const D = Math.max(10, y0 + (rows - 1) * dy + 3.1);
  return { stations, D, homes: { commis: [2.1, 5], taster: [11.8, 3.1], inspector: [2.1, D - 1.4], runner: [13.3, D - 1.5] }, sous: [8, 2.9], chef: [14.5, 1.15], record: [1.5, 4.2], check: [14.6, D - 2.5] };
}

// A box: top, south, north, east, west faces around a floor rectangle. Labels sit on the
// south face (flipped back upright) or lie on the top.
function box(b) {
  const root = el('box');
  root.style.cssText = `left:${px(b.x)};top:${px(b.y)};width:${px(b.w)};height:${px(b.d)}`;
  const top = el('face top'); top.style.cssText = `transform:translateZ(${b.h}px);background:${b.top}`;
  if (b.topLabel) top.innerHTML = `<span class="toplabel" style="color:${b.ink || '#333'}">${b.topLabel}</span>`;
  const south = el('face south'); south.style.cssText = `height:${b.h}px;background:${b.south};border:${b.southBd || 'none'}`;
  if (b.label) south.innerHTML = `<div class="label ${b.lj || 'center'}" style="color:${b.ink || '#333'};font-size:${b.fs || '10px'}"><span class="name">${b.label}</span>${b.sub ? `<span class="sub" style="border-left-color:${b.mark || '#34312b'}">${b.sub}</span>` : ''}</div>`;
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
  s += `<ellipse cx="0" cy="2" rx="22" ry="8" fill="#000" opacity=".18"/>`;
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
  s += `<ellipse cx="0" cy="1" rx="11" ry="4" fill="#000" opacity=".18"/>`;
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
// A figure: a floor anchor that holds a billboard (the character, always facing the camera)
// and a ring on the floor. The billboard also carries the badge, the activity glyph, the
// bubble and, for everyone but the cooks (whose station says who they are), a name.
function figure({ id, name, role, label = true }) {
  const root = el('fig'); root.dataset.id = id;
  const ring = el('ring'); root.appendChild(ring);
  const bb = document.createElement('button'); bb.className = `bb ${ROLE[role] ? 'chef' : 'small'}`; bb.dataset.agent = id; bb.setAttribute('aria-label', name); bb.type = 'button';
  bb.innerHTML = `<div class="bubble" hidden></div><span class="badge" hidden></span><span class="glyph" hidden></span>${label ? `<span class="name">${name}</span>` : ''}${ROLE[role] ? chefSVG(role) : helperSVG(role)}`;
  root.appendChild(bb);
  const f = { id, name, role, root, bb, ring, bubble: bb.querySelector('.bubble'), badge: bb.querySelector('.badge'), glyph: bb.querySelector('.glyph'), x: 0, y: 0, status: 'offline', activity: 'offline', said: '' };
  f.place = (x, y) => { f.x = x; f.y = y; root.style.left = px(x); root.style.top = px(y); };
  return f;
}

export function createScene(stage) {
  const scene = el('scene'); stage.appendChild(scene);
  const edges = ['n', 'e', 's', 'w'].map((s) => { const d = el(`edge ${s}`); scene.appendChild(d); return d; });
  const layers = { pads: el('layer'), boxes: el('layer'), figs: el('layer'), fx: el('layer') };
  Object.values(layers).forEach((l) => scene.appendChild(l));

  let rot = ROT0, zoom = 1, drag = null, dragged = false, L = layout(1), vw = innerWidth, vh = innerHeight;
  let hoverCb = null, selectCb = null, cameraCb = null, selected = null, hovered = null;
  const camera = () => ({ rot, tilt: TILT, zoom });
  const baseScale = () => Math.min((vw - 40) / (1120 + (L.D - 10) * 40), (vh - 150) / (640 + (L.D - 10) * 40));
  function applyCamera(instant = false) {
    const sc = baseScale() * zoom;
    scene.style.transition = instant || drag ? 'none' : '';
    scene.style.transform = `scale(${sc}) rotateX(${TILT}deg) rotateZ(${rot}deg)`;
    const bb = `rotateZ(${-rot}deg) rotateX(${-TILT}deg)`;
    for (const f of allFigs()) { f.bb.style.transition = instant || drag ? 'none' : ''; f.bb.style.transform = bb; }
    for (const p of papers) p.el.style.transform = `translateZ(var(--z,60px)) ${bb}`;
    const wallNear = Math.cos(rot * Math.PI / 180) < -0.15;
    if (wall) wall.classList.toggle('faded', wallNear);
    cameraCb?.(camera());
  }
  function resizeFloor() {
    scene.style.width = `${16 * T}px`; scene.style.height = px(L.D); scene.style.margin = `${-L.D * T / 2}px 0 0 ${-8 * T}px`;
  }

  // --- the camera: drag to turn (within ±90°), wheel to zoom
  stage.addEventListener('pointerdown', (e) => { if (e.button !== 0) return; drag = { x: e.clientX, r: rot }; dragged = false; stage.classList.add('dragging'); });
  const endDrag = () => { if (!drag) return; drag = null; stage.classList.remove('dragging'); applyCamera(true); setTimeout(() => { dragged = false; }, 0); };
  window.addEventListener('pointermove', (e) => { if (!drag) return; if (!(e.buttons & 1)) return endDrag(); const dx = e.clientX - drag.x; if (Math.abs(dx) > 4) dragged = true; rot = Math.min(90, Math.max(-90, drag.r - dx * 0.35)); applyCamera(true); });
  window.addEventListener('pointerup', endDrag); window.addEventListener('pointercancel', endDrag); window.addEventListener('blur', endDrag);
  stage.addEventListener('wheel', (e) => { e.preventDefault(); zoom = Math.min(2.6, Math.max(0.55, zoom * (e.deltaY < 0 ? 1.08 : 1 / 1.08))); applyCamera(); }, { passive: false });
  stage.addEventListener('click', (e) => { if (dragged) return; if (e.target === stage || e.target === scene || e.target.classList.contains('layer') || e.target.classList.contains('face')) selectCb?.(null); });
  window.addEventListener('resize', () => { vw = innerWidth; vh = innerHeight; applyCamera(true); });

  // --- fixed furniture
  let wall = null, office = null, record = { boxes: [], label: null, about: '' };
  const fixed = [];
  function buildFixed() {
    for (const b of fixed) b.remove(); fixed.length = 0;
    const D = L.D;
    const add = (b) => { const n = box(b); if (b.pick) { n.classList.add('pick'); n.addEventListener('click', (e) => { e.stopPropagation(); if (!dragged) selectCb?.(b.pick); }); n.addEventListener('mouseenter', () => hoverCb?.(b.about || null, n)); n.addEventListener('mouseleave', () => hoverCb?.(null)); } layers.boxes.appendChild(n); fixed.push(n); return n; };
    wall = add({ x: 0, y: -0.45, w: 16, d: 0.45, h: 100, top: '#5e544c', south: '#7d7168', east: '#6a5f57', side: '#5e544c', label: 'MISE EN PLACE · THEN SHIP', ink: '#efe2c8', fs: '16px' });
    // the head chef's office: a glass corner top-right, with a striped floor and a desk
    const pad = el('pad'); pad.style.cssText = `left:${px(12.5)};top:0;width:${px(3.5)};height:${px(2.1)}`; layers.pads.appendChild(pad); fixed.push(pad);
    add({ x: 13.6, y: 0.25, w: 1.8, d: 0.55, h: 28, top: '#8a5a3c', south: '#6e4630', east: '#5e3b28', side: '#5a3826' });
    add({ x: 12.5, y: 2.0, w: 3.5, d: 0.12, h: 26, ...BASE, label: 'HEAD CHEF', ink: '#efe6d6', fs: '9px' });
    office = add({ x: 12.5, y: 2.0, w: 3.5, d: 0.12, h: 78, ...GLASS });
    add({ x: 12.5, y: 0, w: 0.12, d: 1.15, h: 26, ...BASE });
    add({ x: 12.5, y: 0, w: 0.12, d: 1.15, h: 78, ...GLASS });
    add({ x: 4, y: 1.4, w: 8, d: 0.7, h: 34, ...STEEL, label: 'THE PASS', ink: '#3a4046', fs: '11px' });
    add({ x: 1.4, y: -0.06, w: 1.3, d: 0.06, h: 86, top: '#9aa3aa', south: 'linear-gradient(90deg, transparent 82%, #6d757c 82% 86%, transparent 86%) 0 30% / 100% 30% no-repeat, #d5dbe0', southBd: '4px solid #9aa3aa', east: '#aab3ba', side: '#9aa3aa', label: 'WALK-IN', ink: '#5b6570', fs: '9px', lj: 'start' });
    add({ x: 14.4, y: D - 3.2, w: 1.3, d: 1.4, h: 58, top: 'radial-gradient(circle, transparent 0 22px, #d7dde1 23px 27px, transparent 28px), #3b3e43', south: '#5b6067', east: '#4b5056', side: '#43484d', pick: 'runner', about: 'The check\nWhere the runner takes a noisy command and brings back pass or fail.', label: 'CHECK', ink: '#d7dde1', fs: '9px' });
    drawRecord(lastRecord, true);
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
      // the east face is the open side: shelves of books, in the colour of each page's kind
      const shelves = el('shelves');
      for (let s = 0; s < SHELVES; s++) {
        const sh = el('shelf');
        for (let i = 0; i < PER_SHELF; i++) { const col = books[c * PER_CUP + s * PER_SHELF + i]; if (!col) break; const bk = el('book'); bk.style.background = col; bk.style.height = `${70 + ((s * 7 + i * 3 + c) % 3) * 8}%`; sh.appendChild(bk); }
        shelves.appendChild(sh);
      }
      b.faces.east.appendChild(shelves);
      b.classList.add('pick'); b.addEventListener('click', (e) => { e.stopPropagation(); if (!dragged) selectCb?.('commis'); });
      b.addEventListener('mouseenter', () => hoverCb?.(about, b)); b.addEventListener('mouseleave', () => hoverCb?.(null));
      layers.boxes.appendChild(b); record.boxes.push(b);
    }
    record.about = about;
  }

  // --- figures
  const figs = new Map();     // id → figure (sous, chef, station cooks, resident helpers)
  const stations = new Map(); // id → { box, cook, mark, pos, steam }
  const extras = new Set();   // helpers that stepped in while the resident was out
  const allFigs = () => [...figs.values(), ...extras];
  function addFig(f, x, y) {
    f.place(x, y); layers.figs.appendChild(f.root);
    f.bb.addEventListener('click', (e) => { e.stopPropagation(); if (!dragged) selectCb?.(f.id); });
    f.bb.addEventListener('mouseenter', () => { hovered = f.id; hoverCb?.(hoverText(f), f.bb); });
    f.bb.addEventListener('mouseleave', () => { hovered = null; hoverCb?.(null); });
    f.bb.style.transform = `rotateZ(${-rot}deg) rotateX(${-TILT}deg)`;
    return f;
  }
  const hoverText = (f) => `${f.name}\n${f.meta || ''}`;
  const sous = addFig(figure({ id: 'sous', name: 'Sous Chef', role: 'sous' }), ...layout(1).sous);
  const chef = addFig(figure({ id: 'headchef', name: 'Head Chef (you)', role: 'head' }), ...layout(1).chef);
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
    L = layout(ids.length); resizeFloor(); buildFixed();
    ids.forEach((id, i) => {
      const st = stations.get(id), p = L.stations[i]; st.pos = p;
      if (st.box) st.box.remove();
      st.box = box({ x: p.x - p.w / 2, y: p.y, w: p.w, d: 1.1, h: 38, ...STEEL, top: BURNERS, label: (p.w < 2.1 ? '' : 'COOK ') + (i + 1), sub: st.ticket || '', mark: st.mark, ink: '#2f3438', fs: '10px', lj: 'center' });
      st.box.classList.add('pick', 'station'); st.box.addEventListener('click', (e) => { e.stopPropagation(); if (!dragged) selectCb?.(id); });
      st.box.addEventListener('mouseenter', () => hoverCb?.(hoverText(st.cook), st.box)); st.box.addEventListener('mouseleave', () => hoverCb?.(null));
      st.box.faces.top.appendChild(el('flame')); st.box.faces.top.appendChild(el('steam', '<i></i><i></i><i></i>'));
      layers.boxes.appendChild(st.box);
      st.cook.place(p.x, p.y - 0.6);
    });
    sous.place(...L.sous); chef.place(...L.chef);
    for (const [kind, f] of Object.entries(residents)) if (!f.busy) f.place(...L.homes[kind]);
    applyCamera(true);
  }

  let lastIds = '';
  function applySnapshot(s) {
    const ids = s.stations.map((x) => x.id);
    for (const id of [...stations.keys()]) if (!ids.includes(id)) { const st = stations.get(id); st.box?.remove(); st.cook.root.remove(); figs.delete(id); stations.delete(id); }
    s.stations.forEach((x, i) => { if (!stations.has(x.id)) { const st = makeStation(x.id, i, x.cook?.name || x.name || x.id); figs.set(x.id, st.cook); } });
    const key = ids.join(','); if (key !== lastIds) { lastIds = key; relayout(ids); }
    drawRecord(s.record);
    s.stations.forEach((x, i) => {
      const st = stations.get(x.id); st.i = i; st.mark = PAL[i % PAL.length];
      const name = x.cook?.name || x.name; if (st.cook.name !== name) { st.cook.name = name; st.cook.bb.setAttribute('aria-label', name); }
      setActor(st.cook, x.cook);
      st.cook.meta = [x.ticket, x.cook?.model, x.branch].filter(Boolean).join(' · ');
      if (st.ticket !== (x.ticket || null)) { st.ticket = x.ticket || null; const sub = st.box.querySelector('.label .sub'); if (sub) { sub.textContent = st.ticket || ''; sub.hidden = !st.ticket; } else if (st.ticket) { const lb = st.box.querySelector('.label'); const span = document.createElement('span'); span.className = 'sub'; span.style.borderLeftColor = st.mark; span.textContent = st.ticket; lb.appendChild(span); } }
      st.box.classList.toggle('cooking', ['editing', 'running'].includes(x.cook?.activity));
    });
    setActor(sous, s.sous); sous.meta = [s.sous.session, s.sous.model].filter(Boolean).join(' · ');
    const n = s.headChef.pending.length;
    chef.badge.hidden = !n; chef.badge.textContent = String(n);
    sous.badge.hidden = !n; sous.badge.textContent = '!';
    chef.status = 'idle'; chef.activity = n ? 'thinking' : 'idle'; chef.ring.dataset.status = 'idle'; chef.meta = n ? `${n} question${n === 1 ? '' : 's'} waiting` : 'nothing waiting on you';
    for (const id of [...helpers.keys()]) if (!s.helpers.find((h) => h.id === id)) endHelper(id);
    for (const h of s.helpers) if (!helpers.has(h.id)) startHelper(h);
    figs.set('sous', sous); figs.set('headchef', chef); for (const [k, f] of Object.entries(residents)) figs.set(k, f);
    if (hovered) { const f = figs.get(hovered); if (f) hoverCb?.(hoverText(f), f.bb); }
  }

  // --- helpers walk to their jobs: the commis to the record, the runner to the check, the
  // taster and the inspector to the station that called; an extra hand steps in if the
  // resident is already out.
  const helpers = new Map();
  const posOf = (who) => who === 'sous' ? L.sous : (who === 'headchef' || who === 'head-chef') ? L.chef : stations.get(who)?.pos ? [stations.get(who).pos.x, stations.get(who).pos.y - 0.6] : L.sous;
  function walk(f, [x, y], then) {
    const d = Math.hypot(x - f.x, y - f.y); f.root.style.transition = `left ${Math.max(.4, d / 4)}s linear, top ${Math.max(.4, d / 4)}s linear`;
    f.root.classList.add('walking'); f.place(x, y);
    clearTimeout(f.walkT); f.walkT = setTimeout(() => { f.root.classList.remove('walking'); then?.(); }, Math.max(.4, d / 4) * 1000);
  }
  function startHelper(h) {
    if (!HELPER[h.kind]) return;
    let f = residents[h.kind];
    if (f.busy) { f = figure({ id: h.kind, name: h.kind, role: h.kind }); f.meta = HELPER[h.kind].role; f.extra = true; addFig(f, ...L.homes[h.kind]); extras.add(f); }
    f.busy = true; f.note = h.note || ''; f.meta = `${HELPER[h.kind].role} · ${f.note || 'working'}`;
    const from = posOf(h.from), at = [from[0] + 0.8, from[1] + 0.2];
    const target = h.kind === 'commis' ? [L.record[0] + 0.3, L.record[1] + 0.8]
      : h.kind === 'runner' ? [L.check[0] - 1, L.check[1] + 0.2]
      : h.kind === 'taster' ? (() => { const p = posOf(h.note?.match(/station-\d+/)?.[0] || h.from); return [p[0] + 0.8, p[1] + 0.2]; })()
      : at;
    f.glyph.hidden = false; f.glyph.textContent = GLYPH.running;
    walk(f, target, () => { f.bb.dataset.activity = 'running'; });
    helpers.set(h.id, f);
  }
  function endHelper(id) {
    const f = helpers.get(id); if (!f) return; helpers.delete(id);
    f.busy = false; f.note = ''; f.meta = HELPER[f.role].role; f.glyph.hidden = true; f.bb.dataset.activity = '';
    walk(f, L.homes[f.role], () => { if (f.extra) { f.root.remove(); extras.delete(f); } });
  }

  // --- what is said: a bubble over the speaker, cut at three lines (the whole text is in
  // the popover and the console); a paper flies from sender to receiver for every message
  const BUBBLE_MAX = 110;
  function say(who, text, ttl) {
    const f = figs.get(who === 'head-chef' ? 'headchef' : who); if (!f) return;
    f.said = text;
    let short = text.length > BUBBLE_MAX ? text.slice(0, BUBBLE_MAX).replace(/\s+\S*$/, '') + ' …' : text;
    f.bubble.textContent = short; f.bubble.hidden = false;
    clearTimeout(f.bubbleT); f.bubbleT = setTimeout(() => { f.bubble.hidden = true; }, (ttl ?? Math.min(9, 3 + text.length / 25)) * 1000);
  }
  const papers = [];
  function flyMessage({ from, to, kind, text }) {
    const a = posOf(from), b = posOf(to);
    const p = { el: el('paper', kind.replace(/[[\]]/g, '')), t: 0, a, b, dur: Math.max(.9, Math.hypot(b[0] - a[0], b[1] - a[1]) / 9) };
    p.el.style.transform = `translateZ(var(--z,60px)) rotateZ(${-rot}deg) rotateX(${-TILT}deg)`; p.el.style.left = px(a[0]); p.el.style.top = px(a[1]);
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
    applySnapshot, say, camera, fps, layout: () => L,
    figure: (id) => figs.get(id) || null,
    recordAbout: () => record.about,
    onHover(fn) { hoverCb = fn; }, onSelect(fn) { selectCb = fn; }, onCamera(fn) { cameraCb = fn; },
    setSelected(who) {
      selected = who && figs.has(who) ? who : null;
      for (const f of allFigs()) f.root.classList.toggle('selected', f.id === selected);
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
