// The kitchen scene: a 2D top-down-ish room drawn with PixiJS vector graphics.
// Everything is procedural (no image assets); the scene is a fixed 1200x720 world
// scaled to fit the canvas. Frame rate is capped and drops when nothing is moving.

import { Application, Container, Graphics, Rectangle, Text } from 'pixi.js';

export const W = 1200, H = 720;
const C = {
  floorA: 0xd9c9a8, floorB: 0xcdbb97, wall: 0x6f655a, wallTop: 0x8a7f71, steel: 0x9aa5ad, steelDark: 0x6e787f,
  wood: 0x8a5a3a, woodDark: 0x5e3b25, glass: 0xbfe0ee, white: 0xf7f3ea, skin: 0xe7b58d, apron: 0x3d5a80,
  shadow: 0x000000, busy: 0x6fcf7a, idle: 0x9a9a9a, wait: 0xf0b84a, off: 0x555555, accent: 0xe8a33c,
  text: 0x2a2520, paper: 0xfff6d6, bubble: 0xfffdf7,
};
const HELPER = {
  commis: { cap: 0x4f86d9, label: 'commis', home: [148, 392], about: 'The junior who fetches for the line. Before any question goes up, searches the record for a decision already made or a fact already written. Reads only; decides nothing.' },
  taster: { cap: 0x9b6fd9, label: 'taster', home: [842, 262], about: 'Tastes every plate before it leaves the pass. Reads a cook\'s diff, re-runs the check, walks the ticket\'s "Done when", and hands the sous a verdict with numbered findings.' },
  inspector: { cap: 0x56b27a, label: 'inspector', home: [150, 600], about: 'The health inspector: looks, never cooks. Reads a branch diff and reports what should not be there, plus dead code the diff leaves behind.' },
  runner: { cap: 0xe8873c, label: 'runner', home: [1040, 610], about: 'Runs one noisy command (the check, a test suite, a scan) and brings back only pass or fail and the lines that matter, so nobody reads the whole output.' },
};
const ABOUT = {
  sous: 'Runs the line from the pass. Assigns tickets, answers every gate the record settles, signs off bug, chore and hygiene plans, reviews every diff before it is committed, and is the only writer of the rail.',
  cook: 'Owns one station and one ticket per session: plan, implement, review, hand off for the pass, open the PR. Never asks the human; sends the commis first, then a [gate] to the sous.',
  head: 'You. Talk to the sous only. Decide what nobody has decided yet, sign off feature plans, merge, deploy.',
};
const FONT = 'ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif';
const ease = (t) => (t < .5 ? 2 * t * t : -1 + (4 - 2 * t) * t);
const lerp = (a, b, t) => a + (b - a) * t;

// ---------- actors ----------
const OUT = { width: 1.2, color: 0x3b332c, alpha: .45, alignment: 1 }; // soft outline that keeps figures readable on the floor
const ROLE = {
  cook: { scarf: 0xc7503f, apron: 0x3d5a80, toque: 18 },
  sous: { scarf: 0x2a3a57, apron: 0x2a3a57, toque: 28 },
  head: { scarf: 0x1f1f1f, apron: null, toque: 0 },
};

// A face: two eyes that blink now and then, a small mouth. Shared by chefs and helpers.
class Face extends Container {
  constructor(r = 12) {
    super();
    this.r = r; this.blink = 0; this.next = 2 + Math.random() * 4;
    this.eyes = new Graphics(); this.addChild(this.eyes);
    const mouth = new Graphics().moveTo(-2.5, r * .35).quadraticCurveTo(0, r * .5, 2.5, r * .35).stroke({ width: 1.2, color: 0x8a5a4a });
    this.addChild(mouth);
    this.draw(1);
  }
  draw(open) {
    const g = this.eyes.clear(), r = this.r, dx = r * .38, y = -r * .05;
    if (open > .3) { g.circle(-dx, y, r * .14).fill(0x2a2520).circle(dx, y, r * .14).fill(0x2a2520); }
    else { g.rect(-dx - r * .16, y, r * .32, 1.2).fill(0x2a2520).rect(dx - r * .16, y, r * .32, 1.2).fill(0x2a2520); }
  }
  update(dt) {
    this.next -= dt;
    if (this.next <= 0) { this.blink = .14; this.next = 2.5 + Math.random() * 4; this.draw(0); }
    else if (this.blink > 0) { this.blink -= dt; if (this.blink <= 0) this.draw(1); }
  }
}

// ---------- actors ----------
class Chef extends Container {
  constructor({ name, role = 'cook', scale = 1 }) {
    super();
    this.role = role; this.activity = 'idle'; this.status = 'offline'; this.t = Math.random() * 10;
    this.scale.set(scale);
    const R = ROLE[role];
    const g = new Graphics();
    g.ellipse(0, 2, 22, 8).fill({ color: C.shadow, alpha: .18 });
    this.addChild(g);
    this.ring = new Graphics(); this.addChild(this.ring);
    this.body = new Container(); this.addChild(this.body);
    const b = new Graphics();
    // legs and shoes
    b.roundRect(-10, -24, 8, 22, 3).fill(0x2b2b2b).roundRect(2, -24, 8, 22, 3).fill(0x2b2b2b);
    b.roundRect(-12, -5, 11, 6, 2).fill(0x1a1a1a).roundRect(1, -5, 11, 6, 2).fill(0x1a1a1a);
    // jacket (or the head chef's suit)
    const coat = role === 'head' ? 0x2b2b2b : C.white;
    b.roundRect(-17, -64, 34, 44, 9).fill(coat).stroke(OUT);
    if (role === 'head') {
      // suit: lapels, shirt, tie
      b.moveTo(-6, -64).lineTo(0, -48).lineTo(6, -64).fill(0xf3eee2);
      b.moveTo(-2, -60).lineTo(2, -60).lineTo(1, -44).lineTo(-1, -44).fill(0x8a2f2f);
      b.moveTo(-10, -64).lineTo(-6, -64).lineTo(0, -50).lineTo(-8, -52).fill(0x1f1f1f);
      b.moveTo(10, -64).lineTo(6, -64).lineTo(0, -50).lineTo(8, -52).fill(0x1f1f1f);
    } else {
      // double-breasted: two rows of buttons, a collar, a neckerchief
      for (let i = 0; i < 3; i++) { b.circle(-5, -56 + i * 9, 1.6).fill(0xc9c2b2); b.circle(5, -56 + i * 9, 1.6).fill(0xc9c2b2); }
      b.moveTo(-8, -64).lineTo(0, -56).lineTo(8, -64).fill(0xe8e2d4);
      b.moveTo(-7, -64).lineTo(0, -57).lineTo(7, -64).lineTo(3, -66).lineTo(0, -62).lineTo(-3, -66).fill(R.scarf);
      b.moveTo(0, -57).lineTo(-3, -50).lineTo(3, -50).fill(R.scarf);
      // apron over the lower jacket
      if (R.apron) b.roundRect(-13, -42, 26, 22, 4).fill(R.apron).stroke(OUT);
    }
    // sleeves and left hand
    b.roundRect(-21, -62, 9, 18, 4).fill(coat).stroke(OUT); b.roundRect(12, -62, 9, 18, 4).fill(coat).stroke(OUT);
    b.circle(-16, -43, 5).fill(C.skin).stroke(OUT);
    // head, ears, hair under the hat
    b.circle(0, -74, 12).fill(C.skin).stroke(OUT);
    b.circle(-12, -74, 2.5).fill(C.skin); b.circle(12, -74, 2.5).fill(C.skin);
    b.circle(-5, -78, 1.6).fill({ color: 0xe0856e, alpha: .35 }); b.circle(5, -78, 1.6).fill({ color: 0xe0856e, alpha: .35 });
    // hat: the toque (pleated, taller for the sous) or the head chef's hat
    if (role === 'head') { b.roundRect(-13, -96, 26, 14, 4).fill(0x1f1f1f).stroke(OUT); b.roundRect(-17, -85, 34, 5, 2).fill(0x1f1f1f).stroke(OUT); b.rect(-13, -88, 26, 3).fill(0x8a2f2f); }
    else {
      const h = R.toque;
      b.roundRect(-12, -84 - h + 8, 24, h + 2, 7).fill(C.white).stroke(OUT);
      for (let i = -1; i <= 1; i++) b.moveTo(i * 6, -84 - h + 12).lineTo(i * 6, -86).stroke({ width: 1, color: 0xd9d2c3 });
      b.roundRect(-14, -86, 28, 7, 3).fill(0xf3eee2).stroke(OUT);
    }
    this.body.addChild(b);
    this.face = new Face(12); this.face.position.set(0, -74); this.body.addChild(this.face);
    this.arm = new Graphics(); this.arm.circle(0, 0, 5).fill(C.skin).stroke(OUT); this.arm.position.set(16, -43); this.body.addChild(this.arm);
    this.tool = new Graphics(); this.tool.visible = false; this.tool.position.set(16, -43); this.body.addChild(this.tool);
    this.icon = new Container(); this.icon.position.set(0, -112); this.addChild(this.icon);
    this.label = new Text({ text: name, style: { fontFamily: FONT, fontSize: 12, fill: C.text, fontWeight: '600' } });
    this.label.anchor.set(.5, 0); this.label.position.set(0, 10); this.addChild(this.label);
    this.setStatus('offline'); this.setActivity('offline');
    this.eventMode = 'static'; this.cursor = 'pointer'; this.info = ''; this.hitArea = new Rectangle(-24, -118, 48, 132);
  }
  get about() { return `${this.label.text} · ${this.activity}${this.info ? ' · ' + this.info : ''}\n${this.said ? `“${this.said.length > 600 ? this.said.slice(0, 600) + '…' : this.said}”\n` : ''}${ABOUT[this.role]}`; }
  setName(n) { if (this.label.text !== n) this.label.text = n; }
  setStatus(s) {
    if (this.status === s) return; this.status = s;
    this.ringColor(this.activity === 'waiting' ? 'waiting' : s);
  }
  ringColor(s) {
    const col = s === 'busy' ? C.busy : s === 'idle' ? C.idle : s === 'waiting' ? C.wait : C.off;
    this.ring.clear().ellipse(0, 2, 24, 9).stroke({ width: 2.5, color: col, alpha: .9 });
  }
  setActivity(a) {
    if (this.activity === a) return; this.activity = a;
    this.ringColor(a === 'waiting' ? 'waiting' : this.status);
    this.icon.removeChildren().forEach((c) => c.destroy());
    this.tool.visible = false; this.tool.clear();
    this.alpha = a === 'offline' ? .35 : 1;
    const g = new Graphics(); this.icon.addChild(g); this.iconG = g;
    switch (a) {
      case 'thinking': for (let i = 0; i < 3; i++) g.circle(-10 + i * 10, 0, 3).fill(C.text); break;
      case 'editing': this.tool.visible = true; this.tool.roundRect(-2, -24, 4, 26, 2).fill(0x555555).rect(-3, -27, 6, 5).fill(0xcccccc); g.roundRect(-9, -3, 18, 6, 2).fill(C.accent); break;
      case 'running': g.circle(0, 0, 7).stroke({ width: 3, color: C.text }); for (let i = 0; i < 6; i++) { const a2 = i * Math.PI / 3; g.rect(Math.cos(a2) * 9 - 1.5, Math.sin(a2) * 9 - 1.5, 3, 3).fill(C.text); } break;
      case 'reading': g.rect(-11, -6, 10, 12).fill(0xf3eee2).rect(1, -6, 10, 12).fill(0xf3eee2).rect(-11, -6, 22, 12).stroke({ width: 1.5, color: C.text }); break;
      case 'waiting': g.circle(0, 0, 8).stroke({ width: 2, color: C.wait }).moveTo(0, 0).lineTo(0, -6).stroke({ width: 2, color: C.wait }); this.hand = new Graphics().moveTo(0, 0).lineTo(5, 0).stroke({ width: 2, color: C.wait }); this.icon.addChild(this.hand); break;
    }
  }
  update(dt, t) {
    this.t += dt;
    const breathe = Math.sin(this.t * 2) * 1.2;
    this.body.y = breathe;
    if (this.alpha > .5) this.face.update(dt);
    const a = this.activity;
    if (a === 'editing') { this.arm.y = -43 + Math.abs(Math.sin(this.t * 9)) * 8; this.tool.y = this.arm.y; this.tool.rotation = Math.sin(this.t * 9) * .3; }
    else { this.arm.y = -43 + breathe * .5; }
    // a slow look-around while idle or thinking
    this.face.x = a === 'idle' || a === 'thinking' ? Math.sin(this.t * .7) * 1.5 : 0;
    if (a === 'thinking' && this.iconG) this.iconG.alpha = .5 + Math.sin(this.t * 4) * .5;
    if (a === 'running' && this.iconG) this.iconG.rotation += dt * 2.5;
    if (a === 'waiting' && this.hand) this.hand.rotation += dt * 1.2;
    this.icon.y = -112 + breathe;
  }
}

class Helper extends Container {
  constructor(kind, note) {
    super();
    this.kind = kind; this.t = 0; this.path = []; this.speed = 240; this.onArrive = null; this.dead = false;
    const cap = HELPER[kind].cap;
    const sh = new Graphics().ellipse(0, 1, 11, 4).fill({ color: C.shadow, alpha: .18 }); this.addChild(sh);
    this.g = new Container(); this.addChild(this.g);
    // legs swing separately while walking
    this.legL = new Graphics().roundRect(-2, 0, 4, 12, 2).fill(0x2b2b2b).roundRect(-3, 9, 6, 3.5, 1.5).fill(0x1a1a1a); this.legL.position.set(-3, -12);
    this.legR = new Graphics().roundRect(-2, 0, 4, 12, 2).fill(0x2b2b2b).roundRect(-3, 9, 6, 3.5, 1.5).fill(0x1a1a1a); this.legR.position.set(3, -12);
    this.g.addChild(this.legL, this.legR);
    const g = new Graphics();
    g.roundRect(-9, -34, 18, 24, 6).fill(C.white).stroke(OUT);           // jacket
    g.roundRect(-7, -22, 14, 11, 2).fill(cap);                            // short apron in the kind's colour
    g.circle(-3, -29, 1.2).fill(0xc9c2b2).circle(3, -29, 1.2).fill(0xc9c2b2);
    g.circle(0, -40, 7).fill(C.skin).stroke(OUT);                         // head
    g.roundRect(-8, -50, 16, 8, 3).fill(cap).stroke(OUT);                 // cap
    g.roundRect(-9, -44, 18, 3, 1.5).fill(cap);                            // brim
    if (kind === 'inspector') g.roundRect(6, -34, 8, 11, 1).fill(0xf3eee2).stroke(OUT).rect(7, -31, 6, 1.5).fill(C.text).rect(7, -28, 6, 1.5).fill(C.text);
    if (kind === 'taster') g.circle(9, -30, 3).fill(0xdddddd).stroke(OUT).rect(8.5, -30, 1.5, 9).fill(0xdddddd);
    if (kind === 'runner') g.roundRect(6, -36, 7, 9, 1).fill(0x444444).stroke(OUT);
    if (kind === 'commis') g.roundRect(-14, -32, 7, 9, 1).fill(0xb5533c).stroke(OUT);
    this.g.addChild(g);
    this.face = new Face(7); this.face.position.set(0, -40); this.g.addChild(this.face);
    const label = new Text({ text: HELPER[kind].label, style: { fontFamily: FONT, fontSize: 10, fill: C.text } });
    label.anchor.set(.5, 0); label.y = 5; this.addChild(label);
    this.note = note; this.busy = false;
    this.eventMode = 'static'; this.cursor = 'help'; this.hitArea = new Rectangle(-14, -54, 28, 66);
  }
  goTo(points, onArrive) { this.path = points.slice(); this.onArrive = onArrive; }
  get about() { return `${HELPER[this.kind].label} · ${this.busy ? 'working: ' + (this.note || '…') : 'ready'}\n${HELPER[this.kind].about}`; }
  update(dt) {
    this.t += dt; this.face.update(dt);
    if (this.path.length) {
      const [tx, ty] = this.path[0];
      const dx = tx - this.x, dy = ty - this.y, d = Math.hypot(dx, dy), step = this.speed * dt;
      if (d <= step) { this.position.set(tx, ty); this.path.shift(); if (!this.path.length && this.onArrive) { const f = this.onArrive; this.onArrive = null; f(); } }
      else { this.x += dx / d * step; this.y += dy / d * step; }
      const sw = Math.sin(this.t * 14);
      this.g.y = -Math.abs(sw) * 3; this.legL.rotation = sw * .6; this.legR.rotation = -sw * .6;
      this.g.scale.x = dx < 0 ? -1 : 1;
    } else { this.g.y = Math.sin(this.t * 3) * 1; this.legL.rotation = this.legR.rotation = 0; }
  }
}

class Paper extends Container {
  constructor(kind, from, to) {
    super();
    this.from = from; this.to = to; this.t = 0; this.dur = Math.max(.9, Math.hypot(to[0] - from[0], to[1] - from[1]) / 700);
    const g = new Graphics(); g.roundRect(-20, -11, 40, 22, 3).fill(C.paper).stroke({ width: 1, color: 0xc9b98a });
    this.addChild(g);
    const l = new Text({ text: kind.replace(/[[\]]/g, ''), style: { fontFamily: 'ui-monospace, Menlo, monospace', fontSize: 9.5, fill: C.text } });
    l.anchor.set(.5); this.addChild(l);
  }
  update(dt) {
    this.t += dt; const u = Math.min(1, this.t / this.dur), e = ease(u);
    const cx = (this.from[0] + this.to[0]) / 2, cy = Math.min(this.from[1], this.to[1]) - 120;
    this.x = (1 - e) ** 2 * this.from[0] + 2 * (1 - e) * e * cx + e ** 2 * this.to[0];
    this.y = (1 - e) ** 2 * this.from[1] + 2 * (1 - e) * e * cy + e ** 2 * this.to[1];
    this.rotation = Math.sin(this.t * 6) * .15;
    if (u >= 1) this.alpha -= dt * 4;
    return this.alpha <= 0;
  }
}

class Bubble extends Container {
  // side 'up': the bubble floats over the speaker, tail down. side 'right': it sits to the speaker's right, tail left,
  // for the two who stand under the window where there is no room above.
  constructor(text, ttl = 5, side = 'up') {
    super();
    this.ttl = ttl; this.age = 0;
    const l = new Text({ text, style: { fontFamily: FONT, fontSize: 11.5, fill: C.text, wordWrap: true, wordWrapWidth: 200, lineHeight: 14 } });
    const w = l.width + 16, h = l.height + 10;
    this.w = w; this.h = h; this.side = side;
    const g = new Graphics();
    if (side === 'right') {
      g.roundRect(0, -h / 2, w, h, 7).fill(C.bubble).stroke({ width: 1, color: 0xd6cdb8 });
      g.moveTo(0, -5).lineTo(-7, 0).lineTo(0, 5).fill(C.bubble);
      l.position.set(8, -h / 2 + 5);
    } else {
      g.roundRect(-w / 2, -h, w, h, 7).fill(C.bubble).stroke({ width: 1, color: 0xd6cdb8 });
      g.moveTo(-5, 0).lineTo(0, 7).lineTo(5, 0).fill(C.bubble);
      l.position.set(-w / 2 + 8, -h + 5);
    }
    this.addChild(g, l);
  }
  // Place the tail at (x, y) and keep the whole bubble inside the world.
  placeAt(x, y, W, H) {
    if (this.side === 'right') { this.position.set(Math.min(x, W - this.w - 8), Math.min(Math.max(y, this.h / 2 + 8), H - this.h / 2 - 8)); return; }
    this.position.set(Math.min(Math.max(x, this.w / 2 + 8), W - this.w / 2 - 8), Math.max(y, this.h + 8));
  }
  rect() { return this.side === 'right' ? { x: this.x, y: this.y - this.h / 2, w: this.w, h: this.h } : { x: this.x - this.w / 2, y: this.y - this.h, w: this.w, h: this.h }; }
  // Slide up until this bubble overlaps none of the others, so a crowded line stays legible.
  avoid(others) {
    for (let i = 0; i < 8; i++) {
      const me = this.rect();
      const hit = others.find((o) => o !== this && !o.destroyed && o.alpha > 0 && (({ x, y, w, h }) => x < me.x + me.w + 4 && x + w + 4 > me.x && y < me.y + me.h + 4 && y + h + 4 > me.y)(o.rect()));
      if (!hit) return;
      const r = hit.rect(); this.y -= (me.y + me.h) - r.y + 8;
      if (this.y - (this.side === 'right' ? this.h / 2 : this.h) < 8) return;
    }
  }
  update(dt) { this.age += dt; if (this.age > this.ttl - .6) this.alpha = Math.max(0, (this.ttl - this.age) / .6); return this.age >= this.ttl; }
}

class Steam {
  constructor(layer) { this.layer = layer; this.parts = []; this.acc = 0; }
  emit(x, y, dt, rate = 6) {
    this.acc += dt * rate;
    while (this.acc >= 1 && this.parts.length < 40) {
      this.acc -= 1;
      const g = new Graphics().circle(0, 0, 3 + Math.random() * 3).fill({ color: 0xffffff, alpha: .55 });
      g.position.set(x + (Math.random() - .5) * 24, y); g.vx = (Math.random() - .5) * 10; g.life = 0;
      this.layer.addChild(g); this.parts.push(g);
    }
  }
  update(dt) {
    for (let i = this.parts.length - 1; i >= 0; i--) {
      const p = this.parts[i]; p.life += dt; p.y -= dt * 28; p.x += p.vx * dt; p.alpha = Math.max(0, .55 - p.life * .4); p.scale.set(1 + p.life * .6);
      if (p.life > 1.4) { this.layer.removeChild(p); p.destroy(); this.parts.splice(i, 1); }
    }
  }
}

// ---------- the scene ----------
export async function createKitchen(canvas, host) {
  const app = new Application();
  await app.init({ canvas, resizeTo: host, antialias: true, backgroundColor: 0x1b1a17, resolution: Math.min(window.devicePixelRatio || 1, 2), autoDensity: true });
  app.ticker.maxFPS = 30;

  const world = new Container(); app.stage.addChild(world);
  const floor = new Container(), furniture = new Container(), actors = new Container(), fx = new Container(), ui = new Container();
  world.addChild(floor, furniture, actors, fx, ui);
  actors.sortableChildren = true;

  // Floor and walls.
  const fg = new Graphics();
  for (let y = 130; y < H; y += 60) for (let x = 0; x < W; x += 60) fg.rect(x, y, 60, 60).fill(((x / 60 + y / 60) & 1) ? C.floorA : C.floorB);
  fg.rect(0, 0, W, 130).fill(C.wall).rect(0, 0, W, 14).fill(C.wallTop).rect(0, 126, W, 6).fill(0x4e463d);
  // The window to the dining room (where the head chef stands).
  fg.roundRect(410, 26, 380, 92, 6).fill(0x3a332c).roundRect(418, 34, 364, 76, 4).fill(C.glass);
  fg.rect(598, 34, 4, 76).fill(0x3a332c);
  floor.addChild(fg);
  const sign = new Text({ text: 'THE WINDOW', style: { fontFamily: FONT, fontSize: 9, fill: 0xd8cfbf, letterSpacing: 3, fontWeight: '600' } });
  sign.anchor.set(.5, 1); sign.position.set(600, 24); floor.addChild(sign);

  const places = {
    headchef: [600, 112], pass: [600, 175], sous: [600, 262],
    record: [78, 330], walkin: [1122, 330], check: [1122, 580],
  };
  // The pass: a steel counter under the window.
  const pg = new Graphics();
  pg.roundRect(300, 150, 600, 50, 6).fill(C.steel).rect(300, 150, 600, 8).fill(0xc3ccd2).rect(300, 192, 600, 8).fill(C.steelDark);
  for (let i = 0; i < 6; i++) pg.circle(330 + i * 110, 176, 2).fill(0x6e787f);
  // The record (bookshelf), the walk-in (fridge), the check (a dish machine).
  pg.roundRect(1074, 250, 96, 170, 6).fill(0xb9c2c8).rect(1082, 258, 80, 154).fill(0xd6dde2).rect(1150, 300, 6, 60).fill(0x6e787f).rect(1082, 335, 80, 3).fill(0xb9c2c8);
  pg.roundRect(1074, 520, 96, 110, 6).fill(C.steelDark).rect(1082, 528, 80, 60).fill(0x3b4247).circle(1122, 558, 22).stroke({ width: 4, color: 0x9aa5ad }).rect(1082, 596, 80, 26).fill(0x8a949b);
  furniture.addChild(pg);
  const lbl = (t, x, y) => { const l = new Text({ text: t, style: { fontFamily: FONT, fontSize: 10.5, fill: 0x4e463d, letterSpacing: 1.5, fontWeight: '600' } }); l.anchor.set(.5, 0); l.position.set(x, y); furniture.addChild(l); };
  lbl('THE WALK-IN', 1122, 426); lbl('THE CHECK', 1122, 636); lbl('THE PASS', 345, 206);
  // The record: a bookshelf that grows with what the kitchen has written down. One book per page,
  // six books a shelf, up to six shelves; past that the count on the label keeps climbing.
  const recordG = new Graphics(); furniture.addChild(recordG);
  const recordL = new Text({ text: 'THE RECORD', style: { fontFamily: FONT, fontSize: 10.5, fill: 0x4e463d, letterSpacing: 1.5, fontWeight: '600' } }); recordL.anchor.set(.5, 0); recordL.position.set(78, 426); furniture.addChild(recordL);
  const recordHit = new Container(); recordHit.eventMode = 'static'; recordHit.cursor = 'help'; recordHit.about = ''; furniture.addChild(recordHit);
  const BOOK = { specs: 0x4f86d9, backlog: 0xb5533c, plans: 0x56b27a, checklists: 0xe8a33c, journal: 0x9b6fd9, decisions: 0xd8cfbf, questions: 0xf0b84a, research: 0x3fa9a3, brainstorm: 0xe8873c, conventions: 0x8a7f71, knowledge: 0x6b8e9f, lessons: 0xc9a227, claude: 0x2a2520 };
  const BOOK_NAME = { claude: 'CLAUDE.md', knowledge: 'domains' };
  let recordKey = '';
  // The record stands against the left wall and grows like a library: a cupboard fills
  // downward six books a shelf, three shelves; a second cupboard opens beneath it, then the count climbs.
  const REC_X = 30, REC_TOP = 172, CUP_W = 96, CUP_GAP = 10, PER_SHELF = 6, MAX_SHELVES = 3, PER_CUP = PER_SHELF * MAX_SHELVES, MAX_CUPS = 2;
  function drawRecord(rec) {
    const key = JSON.stringify(rec); if (key === recordKey) return; recordKey = key;
    const total = rec?.total || 0, kinds = rec?.kinds || {};
    const cups = Math.min(MAX_CUPS, Math.max(1, Math.ceil(total / PER_CUP)));
    const books = []; for (const [k, n] of Object.entries(kinds)) for (let i = 0; i < n; i++) books.push(k);
    const g = recordG.clear();
    let y0 = REC_TOP;
    for (let c = 0; c < cups; c++) {
      const mine = Math.max(0, Math.min(PER_CUP, total - c * PER_CUP));
      const shelves = Math.min(MAX_SHELVES, Math.max(1, Math.ceil(mine / PER_SHELF))), hgt = shelves * 38 + 14;
      g.roundRect(REC_X, y0, CUP_W, hgt, 4).fill(C.woodDark).rect(REC_X + 6, y0 + 6, CUP_W - 12, hgt - 12).fill(C.wood);
      for (let r = 0; r < shelves; r++) {
        const y = y0 + 12 + r * 38;
        g.rect(REC_X + 6, y + 30, CUP_W - 12, 4).fill(C.woodDark);
        for (let b = 0; b < PER_SHELF; b++) {
          const k = books[c * PER_CUP + r * PER_SHELF + b]; if (!k) break;
          const h = 26 + ((r * 7 + b * 3 + c) % 3) * 1.5;
          g.rect(REC_X + 10 + b * 13, y + 28 - h, 10, h).fill(BOOK[k] || 0x8a7f71).rect(REC_X + 10 + b * 13, y + 28 - h + 3, 10, 1.5).fill({ color: 0xffffff, alpha: .35 });
        }
      }
      y0 += hgt + CUP_GAP;
    }
    const bottom = y0 - CUP_GAP, shown = Math.min(total, MAX_CUPS * PER_CUP);
    if (total > shown) g.roundRect(REC_X + CUP_W - 30, bottom - 8, 30, 16, 4).fill(C.accent);
    recordL.text = total ? `THE RECORD · ${total}` : 'THE RECORD';
    recordL.position.set(REC_X + CUP_W / 2, bottom + 6);
    recordHit.hitArea = new Rectangle(REC_X, REC_TOP, CUP_W, bottom - REC_TOP);
    places.record = [REC_X + CUP_W / 2, Math.min(330, (REC_TOP + bottom) / 2)];
    const parts = Object.entries(kinds).sort((a, b) => b[1] - a[1]).map(([k, n]) => `${BOOK_NAME[k] || k} ${n}`).join(' · ');
    recordHit.about = `The record · ${total} page${total === 1 ? '' : 's'}${total > shown ? ` (the shelves show the first ${shown})` : ''}
${parts || 'Nothing written down yet.'} What the kitchen remembers: specs, tickets, plans, checklists, journals, decisions. The commis reads here before any question goes up.`;
  }
  drawRecord({ total: 0, kinds: {} });
  const checkLight = new Graphics().circle(1122, 558, 14).fill({ color: C.busy, alpha: 0 }); furniture.addChild(checkLight);

  // Actors.
  const sous = new Chef({ name: 'Sous Chef', role: 'sous' }); sous.position.set(...places.sous); sous.zIndex = places.sous[1]; actors.addChild(sous);
  const head = new Chef({ name: 'Head Chef', role: 'head', scale: .8 }); head.position.set(...places.headchef); head.zIndex = 1; head.label.visible = false; head.setStatus('idle'); head.setActivity('idle'); floor.addChild(head);
  const attention = new Graphics(); attention.visible = false; ui.addChild(attention);
  const attentionText = new Text({ text: '', style: { fontFamily: FONT, fontSize: 12, fill: 0x1b1a17, fontWeight: '700' } }); attentionText.anchor.set(.5); attention.addChild(attentionText);

  const stations = new Map(); // id → { bench, cook, steam, pos }
  const helpers = new Map();  // id → Helper (a resident on a job, or an extra hand)
  const residents = {};       // kind → the Helper that lives in the kitchen
  for (const kind of Object.keys(HELPER)) { const r = new Helper(kind); r.position.set(...HELPER[kind].home); r.zIndex = HELPER[kind].home[1]; actors.addChild(r); residents[kind] = r; }
  let hoverCb = null, selectCb = null, selected = null;
  const selRing = new Graphics(); selRing.visible = false; ui.addChild(selRing);
  const select = (obj, who) => { obj.on('pointertap', (e) => { e.stopPropagation(); selectCb?.(who); }); };
  app.stage.eventMode = 'static'; app.stage.hitArea = app.screen; app.stage.on('pointertap', () => selectCb?.(null));
  app.renderer.on('resize', () => { app.stage.hitArea = app.screen; });
  const hover = (obj) => { obj.on('pointerover', (e) => hoverCb?.(obj.about, e.global)); obj.on('pointermove', (e) => hoverCb?.(obj.about, e.global)); obj.on('pointerout', () => hoverCb?.(null)); };
  Object.values(residents).forEach(hover); hover(sous); hover(head); hover(recordHit); select(sous, 'sous'); select(head, 'headchef');
  const papers = [], bubbles = new Map(), plates = new Map(), steams = [];

  function posOf(who) {
    if (who === 'sous') return places.sous;
    if (who === 'headchef' || who === 'head-chef') return places.headchef;
    if (places[who]) return places[who];
    const s = stations.get(who); return s ? s.pos : places.sous;
  }
  // The line: stations share the floor between the record and the walk-in. Past four, the
  // benches and cooks shrink to keep their spacing, so a kitchen of eight still fits one row.
  function layoutStations(ids) {
    const n = ids.length || 1, left = 215, right = 985, gap = (right - left) / n, k = Math.min(1, gap / 165);
    ids.forEach((id, i) => {
      const x = left + gap * (i + .5), st = stations.get(id);
      st.pos = [x, 500]; st.cook.position.set(x, 500); st.cook.zIndex = 500; st.cook.scale.set(k);
      st.bench.position.set(x, 500 + 30 * k); st.bench.scale.set(k);
    });
    return k;
  }
  function makeStation(id, name) {
    const bench = new Container();
    const g = new Graphics();
    g.roundRect(-70, 0, 140, 70, 6).fill(C.steel).rect(-70, 0, 140, 8).fill(0xc3ccd2).rect(-70, 62, 140, 8).fill(C.steelDark);
    g.roundRect(-58, 12, 56, 40, 4).fill(0x2f3338); g.circle(-44, 32, 10).stroke({ width: 3, color: 0x555c62 }); g.circle(-16, 32, 10).stroke({ width: 3, color: 0x555c62 });
    g.roundRect(8, 14, 50, 36, 3).fill(0xe4d9c3); // cutting board
    g.rect(-70, 70, 6, 30).fill(C.steelDark).rect(64, 70, 6, 30).fill(C.steelDark);
    bench.addChild(g);
    const burner = new Graphics(); burner.circle(-44, 32, 6).fill({ color: 0xff7a3c, alpha: 0 }); bench.addChild(burner);
    const nameL = new Text({ text: name, style: { fontFamily: FONT, fontSize: 11, fill: 0x4e463d, letterSpacing: 1.5, fontWeight: '600' } }); nameL.anchor.set(.5, 0); nameL.y = 104; bench.addChild(nameL);
    const tag = new Graphics(); bench.addChild(tag); tag.y = 117;
    const ticketL = new Text({ text: '', style: { fontFamily: 'ui-monospace, Menlo, monospace', fontSize: 10.5, fill: C.text } }); ticketL.anchor.set(.5, 0); ticketL.y = 119; bench.addChild(ticketL);
    furniture.addChild(bench);
    const cook = new Chef({ name, role: 'cook' }); actors.addChild(cook); hover(cook); select(cook, id);
    const st = { id, bench, cook, burner, nameL, ticketL, tag, pos: [0, 0], steam: new Steam(fx) };
    stations.set(id, st); steams.push(st);
    return st;
  }

  function applySnapshot(s) {
    const ids = s.stations.map((x) => x.id);
    for (const id of [...stations.keys()]) if (!ids.includes(id)) { const st = stations.get(id); furniture.removeChild(st.bench); actors.removeChild(st.cook); st.bench.destroy({ children: true }); st.cook.destroy({ children: true }); stations.delete(id); steams.splice(steams.indexOf(st), 1); }
    let relayout = false;
    for (const x of s.stations) { if (!stations.has(x.id)) { makeStation(x.id, x.cook?.name || x.name || x.id); relayout = true; } }
    if (relayout) layoutStations(ids);
    drawRecord(s.record);
    for (const x of s.stations) {
      const st = stations.get(x.id);
      st.cook.setName(x.cook?.name || x.name); st.cook.setStatus(x.cook?.status || 'offline'); st.cook.setActivity(x.cook?.activity || 'offline');
      st.cook.info = [x.id, x.ticket, x.branch, x.cook?.model].filter(Boolean).join(' · ');
      const t = x.ticket ? `${x.ticket}${x.branch ? '' : ''}` : (x.branch || ''); if (st.ticketL.text !== t) st.ticketL.text = t;
      st.tag.clear(); if (x.ticket) st.tag.roundRect(-st.ticketL.width / 2 - 6, 0, st.ticketL.width + 12, 16, 3).fill({ color: C.paper, alpha: .9 });
    }
    sous.setName(s.sous.name || 'Sous Chef'); sous.setStatus(s.sous.status); sous.setActivity(s.sous.activity); sous.info = [s.sous.session, s.sous.model].filter(Boolean).join(' · ');
    const n = s.headChef.pending.length;
    attention.visible = n > 0;
    if (n) { attention.clear().roundRect(-14, -12, 28, 24, 6).fill(C.accent); attentionText.text = String(n); attention.position.set(places.headchef[0] + 36, places.headchef[1] - 70); }
    head.setActivity(n ? 'thinking' : 'idle');
    for (const id of [...helpers.keys()]) if (!s.helpers.find((h) => h.id === id)) endHelper(id);
    for (const h of s.helpers) if (!helpers.has(h.id)) startHelper(h);
    wake();
  }

  function startHelper(h) {
    if (!HELPER[h.kind]) return;
    const from = posOf(h.from), at = [from[0] + 44, from[1] + 12];
    let hp = residents[h.kind];
    if (hp.busy) { // the resident is out on a job: an extra hand steps in from the same spot
      hp = new Helper(h.kind, h.note); hp.position.set(...HELPER[h.kind].home); hp.extra = true; actors.addChild(hp); hover(hp);
    }
    hp.busy = true; hp.note = h.note; hp.working = false;
    // Where the job happens: the commis hears the question, then reads at the record;
    // the runner takes the command to the check; the taster and inspector work at the station.
    const path = h.kind === 'commis' ? [at, [places.record[0] + 60, places.record[1] + 70]]
      : h.kind === 'runner' ? [at, [places.check[0] - 60, places.check[1] + 10]]
      : h.kind === 'taster' ? [(() => { const p = posOf(h.note?.match(/station-\d+/)?.[0] || h.from); return [p[0] + 44, p[1] + 12]; })()]
      : [at];
    hp.goTo(path, () => { hp.working = true; });
    helpers.set(h.id, hp); wake();
  }
  function endHelper(id) {
    const hp = helpers.get(id); if (!hp) return; helpers.delete(id);
    hp.busy = false; hp.working = false; hp.note = '';
    hp.goTo([HELPER[hp.kind].home], () => { if (hp.extra) hp.dead = true; }); wake();
  }
  function flyMessage({ from, to, kind, text }) {
    const a = posOf(from), b = posOf(to);
    const p = new Paper(kind, [a[0], a[1] - 70], [b[0], b[1] - 36]); // lands at the hands, not on the face p.position.set(...p.from); fx.addChild(p); papers.push(p);
    if (text) say(from, `${kind} ${text}`);
    if (kind === '[handoff]') plateTo(from, 'pass');
    if (kind === '[go]') plateTo(to, 'window');
    if (kind === '[served]') plateTo(from, 'gone');
    wake();
  }
  // A bubble shows about three lines; a live kitchen's messages run to paragraphs, so the
  // rest is cut with an ellipsis and the whole text shows on hover (and in the console).
  const BUBBLE_MAX = 110;
  function say(who, text, ttl) {
    const old = bubbles.get(who); if (old) { bubbles.delete(who); ui.removeChild(old); old.destroy({ children: true }); }
    const speaker = who === 'sous' ? sous : who === 'headchef' ? head : stations.get(who)?.cook;
    if (speaker) speaker.said = text;
    if (text.length > BUBBLE_MAX) text = text.slice(0, BUBBLE_MAX).replace(/\s+\S*$/, '') + ' …';
    const side = who === 'headchef' || who === 'sous' ? 'right' : 'up';
    const b = new Bubble(text, ttl ?? Math.min(9, 3 + text.length / 25), side); const p = posOf(who);
    if (side === 'right') b.placeAt(p[0] + (who === 'headchef' ? 34 : 30), p[1] - (who === 'headchef' ? 50 : 70), W, H);
    else b.placeAt(p[0], p[1] - 118, W, H);
    b.avoid([...bubbles.values()]);
    ui.addChild(b); bubbles.set(who, b); wake();
  }
  function plateTo(station, where) {
    let pl = plates.get(station);
    if (where === 'pass') {
      if (!pl) { pl = new Graphics().ellipse(0, 0, 16, 6).fill(0xf7f3ea).ellipse(0, -4, 11, 8).fill(0xb9c2c8).circle(0, -12, 2).fill(0x6e787f); pl.position.set(...posOf(station)); pl.y -= 30; fx.addChild(pl); plates.set(station, pl); }
      const slot = [...stations.keys()].indexOf(station); pl.target = [360 + slot * 90, 168];
    } else if (pl) { pl.target = where === 'window' ? [600, 95] : null; pl.fade = where === 'gone' || where === 'window'; }
  }

  // Frame budget: 30 fps while something moves, 10 when the room is still.
  let awake = 0;
  function wake() { awake = 6; app.ticker.maxFPS = 30; }
  document.addEventListener('visibilitychange', () => (document.hidden ? app.ticker.stop() : app.ticker.start()));

  function fit() {
    const sw = app.screen.width, sh = app.screen.height, k = Math.min(sw / W, sh / H);
    world.scale.set(k); world.position.set((sw - W * k) / 2, (sh - H * k) / 2);
  }
  app.renderer.on('resize', fit); fit();

  let tt = 0;
  app.ticker.add((tk) => {
    const dt = Math.min(.1, tk.deltaMS / 1000); tt += dt;
    sous.update(dt, tt); head.update(dt, tt);
    for (const st of steams) {
      st.cook.update(dt, tt);
      const a = st.cook.activity;
      st.burner.alpha = a === 'running' || a === 'editing' ? .6 + Math.sin(tt * 10) * .3 : 0;
      if (a === 'running') st.steam.emit(st.pos[0] - 44 * st.bench.scale.x, st.pos[1] + 50 * st.bench.scale.x, dt, 8);
      else if (a === 'editing') st.steam.emit(st.pos[0] - 44 * st.bench.scale.x, st.pos[1] + 50 * st.bench.scale.x, dt, 2);
      st.steam.update(dt);
    }
    checkLight.alpha = [...helpers.values()].some((h) => h.kind === 'runner' && h.working) ? .4 + Math.sin(tt * 6) * .3 : 0;
    for (const hp of [...actors.children]) if (hp instanceof Helper) { hp.update(dt); hp.zIndex = hp.y; if (hp.dead) { actors.removeChild(hp); hp.destroy({ children: true }); } }
    for (let i = papers.length - 1; i >= 0; i--) if (papers[i].update(dt)) { fx.removeChild(papers[i]); papers[i].destroy({ children: true }); papers.splice(i, 1); }
    for (const [who, b] of bubbles) if (b.update(dt)) { ui.removeChild(b); b.destroy({ children: true }); bubbles.delete(who); }
    for (const [k, pl] of plates) {
      if (pl.target) { pl.x = lerp(pl.x, pl.target[0], Math.min(1, dt * 4)); pl.y = lerp(pl.y, pl.target[1], Math.min(1, dt * 4)); }
      if (pl.fade) { pl.alpha -= dt * 1.5; if (pl.alpha <= 0) { fx.removeChild(pl); pl.destroy(); plates.delete(k); } }
    }
    attention.visible && (attention.scale.set(1 + Math.sin(tt * 5) * .08));
    if (selected) { const p = posOf(selected); selRing.visible = true; selRing.position.set(p[0], p[1] + 2); selRing.scale.set(1 + Math.sin(tt * 4) * .05); } else selRing.visible = false;
    if (awake > 0) { awake -= dt; if (awake <= 0) app.ticker.maxFPS = 10; }
    ticks++;
  });
  // Real ticks per second, measured between calls, so the readout reflects the cap and the idle drop.
  let ticks = 0, tickAt = performance.now();
  function measuredFps() { const now = performance.now(), s = (now - tickAt) / 1000; const f = s > 0 ? ticks / s : 0; ticks = 0; tickAt = now; return Math.round(f); }

  return {
    app, applySnapshot, flyMessage, say, startHelper, endHelper, posOf, wake,
    fps: measuredFps,
    onHover(fn) { hoverCb = fn; },
    onSelect(fn) { selectCb = fn; },
    setSelected(who) {
      selected = who && (who === 'sous' || who === 'headchef' || stations.has(who)) ? who : null;
      selRing.clear(); if (selected) selRing.ellipse(0, 0, who === 'headchef' ? 22 : 30, who === 'headchef' ? 8 : 12).stroke({ width: 3, color: C.accent, alpha: .95 });
      wake();
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
