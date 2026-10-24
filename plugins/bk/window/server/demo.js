// A scripted service: two scripted stations (plus any number of background ones), one sous, the head chef at the window.
// Exists so the visuals can be shaped before a live kitchen runs. Loops forever.

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function runDemo(store, { stations = 2 } = {}) {
  store.setKitchen({ repo: 'demo-kitchen', mode: 'clone', trunk: 'main', demo: true });
  // The record starts small and grows a page or three with every ticket served.
  const record = { specs: 2, backlog: 4, plans: 3, checklists: 2, journal: 3, decisions: 1, claude: 1 };
  const grow = (...ks) => { for (const k of ks) record[k] = (record[k] || 0) + 1; store.setRecord({ total: Object.values(record).reduce((a, b) => a + b, 0), kinds: { ...record } }); };
  grow();
  store.setRail({
    backlog: [{ id: 'BKLG-007', title: 'Export fails on empty report', kind: 'bug', lane: 'B', priority: 'p2' }],
    todo: [{ id: 'BKLG-004', title: 'Rate-limit the webhook', kind: 'chore', lane: 'B', priority: 'p1' },
           { id: 'S001-02', title: 'Invite flow: accept page', kind: 'feature', lane: 'A', priority: 'p1' }],
    doing: [], rfr: [],
    done: [{ id: 'S001-01', title: 'Invite flow: send invite', kind: 'feature', lane: 'A' }],
  });
  store.upsertStation('station-1', { branch: null, cook: { name: 'Cook 1', model: 'opus' } });
  store.upsertStation('station-2', { branch: null, cook: { name: 'Cook 2', model: 'sonnet' } });
  const extras = [];
  for (let i = 3; i <= Math.max(2, stations); i++) { const id = `station-${i}`; extras.push(id); store.upsertStation(id, { branch: null, cook: { name: `Cook ${i}`, model: ['sonnet', 'opus', 'haiku'][i % 3] } }); }

  await sleep(800);
  store.setActor('sous', { session: 'demo-kitchen-sous', status: 'busy', activity: 'thinking', model: 'opus', startedAt: Date.now(), tmux: 'demo-kitchen-brigade:sous' });
  store.say('sous', 'Service starts. Who is on the line?');
  await sleep(1200);
  for (const id of ['station-1', 'station-2', ...extras]) {
    store.setActor(id, { session: `demo-kitchen-cook-${id.split('-')[1]}`, status: 'idle', activity: 'idle', tmux: `demo-kitchen-brigade:${id}` });
    store.message({ from: 'sous', to: id, kind: '[hello]', text: "I'm the sous, check in" });
    await sleep(900);
    store.message({ from: id, to: 'sous', kind: '[check-in]', text: `${id}, clean, fresh, waiting on nothing` });
    await sleep(600);
  }

  for (const id of extras) backgroundCook(store, id, grow);
  demoBudget(store);

  let round = 0;
  for (;;) {
    round++;
    // Brief both cooks.
    store.moveTicket('BKLG-004', 'in-progress', { cook: 'station-1' });
    store.upsertStation('station-1', { ticket: 'BKLG-004', branch: 'bklg-004-rate-limit-webhook' });
    store.message({ from: 'sous', to: 'station-1', kind: '[brief]', text: 'BKLG-004 Rate-limit the webhook. Chore: I sign the plan.' });
    store.setActor('station-1', { status: 'busy', activity: 'reading' });
    await sleep(1500);
    store.moveTicket('S001-02', 'in-progress', { cook: 'station-2' });
    store.upsertStation('station-2', { ticket: 'S001-02', branch: 's001-02-accept-page' });
    store.message({ from: 'sous', to: 'station-2', kind: '[brief]', text: 'S001-02 Invite flow: accept page. Feature: the head chef signs.' });
    store.setActor('station-2', { status: 'busy', activity: 'reading' });
    store.setActor('sous', { activity: 'idle', status: 'idle' });

    // Station 1 plans: commis, then a gate the sous answers from the record.
    await sleep(2500);
    store.setActor('station-1', { activity: 'thinking' });
    store.say('station-1', 'Two ways to do the limiter. Sending the commis first.');
    store.helperStart({ id: 'c1', kind: 'commis', from: 'station-1', note: 'rate limiting: anything decided?' });
    await sleep(4000);
    store.helperEnd('c1', 'nothing recorded in docs/decisions, journals');
    store.message({ from: 'station-1', to: 'sous', kind: '[gate]', text: 'Q1 token bucket vs sliding window; recommend token bucket. commis: nothing recorded' });
    store.setActor('station-1', { activity: 'waiting' });
    store.setActor('sous', { status: 'busy', activity: 'thinking' });
    await sleep(2500);
    store.message({ from: 'sous', to: 'station-1', kind: '[heard]', text: 'Q1: token bucket, because the gateway already ships one' });
    store.setActor('sous', { activity: 'idle', status: 'idle' });
    store.setActor('station-1', { activity: 'editing' });
    await sleep(3000);
    store.message({ from: 'station-1', to: 'sous', kind: '[plan]', text: 'docs/plans/BKLG-004-rate-limit-webhook.md' });
    store.setActor('station-1', { activity: 'waiting' });
    store.setActor('sous', { status: 'busy', activity: 'reading' });
    await sleep(2500);
    store.message({ from: 'sous', to: 'station-1', kind: '[approved]', text: 'BKLG-004 · sous, per gates.plan_approval.chore' });
    store.setActor('sous', { activity: 'idle', status: 'idle' });

    // Station 2 hits a real fork: goes up to the head chef.
    store.setActor('station-2', { activity: 'thinking' });
    store.helperStart({ id: 'c2', kind: 'commis', from: 'station-2', note: 'invite acceptance: logged-in vs guest?' });
    await sleep(3500);
    store.helperEnd('c2', 'nothing recorded');
    store.message({ from: 'station-2', to: 'sous', kind: '[gate]', text: 'Q1 accept while logged out: create account inline, or redirect to sign-up? commis: nothing recorded' });
    store.setActor('station-2', { activity: 'waiting' });
    store.setActor('sous', { status: 'busy', activity: 'thinking' });
    await sleep(2000);
    store.say('sous', 'Nobody has decided this. Asking the head chef.');
    store.ask({ id: 'S001-02-Q1', from: 'station-2', text: 'Accepting an invite while logged out: create the account inline, or redirect to sign-up? Recommend inline.', options: ['inline', 'redirect'] });
    store.setActor('sous', { activity: 'waiting' });

    // Meanwhile station 1 implements: runner for the check, inspector, review, handoff.
    store.setActor('station-1', { activity: 'editing' });
    store.upsertStation('station-1', { dirty: true });
    await sleep(2000);
    store.message({ from: 'station-1', to: 'sous', kind: '[status]', text: 'implement started (signed off)' });
    for (let i = 0; i < 2; i++) {
      await sleep(3000);
      store.helperStart({ id: `r1-${i}`, kind: 'runner', from: 'station-1', note: 'npm run check' });
      store.setActor('station-1', { activity: 'running' });
      await sleep(2500);
      store.helperEnd(`r1-${i}`, Math.random() < .25 ? 'FAIL: 2 of 48 tests failed' : 'pass: 48 tests');
      store.setActor('station-1', { activity: 'editing' });
    }
    // The head chef answers (demo: after a while).
    await sleep(1500);
    store.answer('S001-02-Q1');
    store.setActor('sous', { activity: 'thinking', status: 'busy' });
    await sleep(1200);
    store.message({ from: 'sous', to: 'station-2', kind: '[heard]', text: 'Q1: inline (head chef), because sign-up loses half the invitees' });
    store.setActor('sous', { activity: 'idle', status: 'idle' });
    store.setActor('station-2', { activity: 'editing' });

    await sleep(2500);
    store.helperStart({ id: 'i1', kind: 'inspector', from: 'station-1', note: 'clean check' });
    store.setActor('station-1', { activity: 'waiting' });
    await sleep(3000);
    store.helperEnd('i1', '0 findings');
    store.setActor('station-1', { activity: 'editing' });
    await sleep(2000);
    store.moveTicket('BKLG-004', 'rfr');
    store.upsertStation('station-1', { ahead: 3 });
    store.message({ from: 'station-1', to: 'sous', kind: '[handoff]', text: 'ready for the pass: 4 files, check pass, inspector 0, checklist written' });
    store.setActor('station-1', { activity: 'waiting' });
    store.setActor('sous', { status: 'busy', activity: 'thinking' });
    await sleep(1000);
    store.helperStart({ id: 't1', kind: 'taster', from: 'sous', note: 'the pass: station-1' });
    await sleep(5000);
    store.helperEnd('t1', 'ship: 0 findings');
    store.message({ from: 'sous', to: 'station-1', kind: '[go]', text: 'commit and open the PR' });
    store.setActor('sous', { activity: 'idle', status: 'idle' });
    store.setActor('station-1', { activity: 'running' });
    await sleep(3000);
    store.upsertStation('station-1', { dirty: false });
    store.message({ from: 'station-1', to: 'sous', kind: '[served]', text: 'https://github.com/demo/demo-kitchen/pull/42' });
    store.moveTicket('BKLG-004', 'done'); grow('plans', 'checklists', 'journal');
    store.setActor('station-1', { activity: 'idle', status: 'idle' });
    await sleep(1500);
    store.message({ from: 'sous', to: 'station-1', kind: '[heard]', text: 'end of shift: clear and check in fresh' });

    // Wind station 2 down for the loop.
    await sleep(4000);
    store.message({ from: 'station-2', to: 'sous', kind: '[handoff]', text: 'ready for the pass' });
    store.setActor('station-2', { activity: 'waiting' });
    await sleep(2500);
    store.message({ from: 'sous', to: 'station-2', kind: '[go]', text: 'commit and open the PR' });
    await sleep(2000);
    store.message({ from: 'station-2', to: 'sous', kind: '[served]', text: 'https://github.com/demo/demo-kitchen/pull/43' });
    store.moveTicket('S001-02', 'done'); grow('plans', 'checklists', 'journal', 'decisions');
    store.setActor('station-2', { activity: 'idle', status: 'idle' });
    store.upsertStation('station-1', { ticket: null, branch: null, ahead: 0 });
    store.upsertStation('station-2', { ticket: null, branch: null, ahead: 0 });
    await sleep(3000);
    // Put the tickets back so the loop reads the same each round.
    store.moveTicket('BKLG-004', 'todo', { cook: null });
    store.moveTicket('S001-02', 'todo', { cook: null });
    store.say('sous', `Round ${round} done. Next service.`);
    if (round % 2 === 0) { // every few PRs the sous files the record and writes its handoff, as the skill says
      await sleep(2500);
      store.say('sous', '/bk:handoff'); store.setActor('sous', { activity: 'editing', status: 'busy' });
      await sleep(4000);
      grow('decisions'); store.setActor('sous', { handoffAt: Date.now(), activity: 'idle', status: 'idle' });
      store.say('sous', 'Handoff written: .claude/sous-handoff.md. Clear me when you like.', 8);
    }
    await sleep(3000);
  }
}

// A background cook: an unscripted station that cycles through a ticket on its own clock,
// so a kitchen of five or six stations can be looked at without writing five scripts.
const TITLES = ['Retry the email queue', 'Fix the date picker on Safari', 'Index the audit table', 'Trim the bundle', 'Paginate the members list', 'Cache the pricing page', 'Rotate the webhook secret', 'Lint the migrations'];
async function backgroundCook(store, id, grow) {
  const n = Number(id.split('-')[1]);
  const jitter = (ms) => sleep(ms * (.7 + Math.random() * .8));
  await jitter(4000 + n * 900);
  let k = 0;
  for (;;) {
    const ticket = `BKLG-${String(10 + n * 3 + (k++ % 3)).padStart(3, '0')}`, title = TITLES[(n + k) % TITLES.length];
    const slug = title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').split('-').slice(0, 3).join('-');
    store.setRail({ ...store.state.rail, todo: [...store.state.rail.todo, { id: ticket, title, kind: n % 2 ? 'chore' : 'bug', lane: 'B', priority: 'p2' }] });
    await jitter(1500);
    store.moveTicket(ticket, 'in-progress', { cook: id });
    store.upsertStation(id, { ticket, branch: `${ticket.toLowerCase()}-${slug}` });
    store.message({ from: 'sous', to: id, kind: '[brief]', text: `${ticket} ${title}. ${n % 2 ? 'Chore' : 'Bug'}: I sign the plan.` });
    store.setActor(id, { status: 'busy', activity: 'reading' });
    await jitter(5000);
    store.setActor(id, { activity: 'thinking' });
    if (Math.random() < .5) { store.helperStart({ id: `bg-c-${id}-${k}`, kind: 'commis', from: id, note: `${ticket}: anything decided?` }); await jitter(3500); store.helperEnd(`bg-c-${id}-${k}`, 'nothing recorded'); }
    store.message({ from: id, to: 'sous', kind: '[plan]', text: `docs/plans/${ticket}-${slug}.md` });
    store.setActor(id, { activity: 'waiting' });
    await jitter(3000);
    store.message({ from: 'sous', to: id, kind: '[approved]', text: `${ticket} · sous` });
    store.setActor(id, { activity: 'editing' }); store.upsertStation(id, { dirty: true });
    await jitter(9000);
    store.helperStart({ id: `bg-r-${id}-${k}`, kind: 'runner', from: id, note: 'npm run check' }); store.setActor(id, { activity: 'running' });
    await jitter(3500);
    store.helperEnd(`bg-r-${id}-${k}`, Math.random() < .2 ? 'check: FAIL, lint errors' : 'check: pass'); store.setActor(id, { activity: 'editing' });
    await jitter(5000);
    store.upsertStation(id, { ahead: 1 + (k % 3) });
    store.message({ from: id, to: 'sous', kind: '[handoff]', text: 'ready for the pass' }); store.setActor(id, { activity: 'waiting' });
    await jitter(6000);
    store.message({ from: 'sous', to: id, kind: '[go]', text: 'commit and open the PR' }); store.setActor(id, { activity: 'running' });
    await jitter(3000);
    store.upsertStation(id, { dirty: false });
    store.message({ from: id, to: 'sous', kind: '[served]', text: `https://github.com/demo/demo-kitchen/pull/${50 + n * 10 + k}` });
    store.moveTicket(ticket, 'done'); grow('journal');
    store.setActor(id, { activity: 'idle', status: 'idle' }); store.upsertStation(id, { ticket: null, branch: null, ahead: 0 });
    await jitter(6000);
    // Retire the ticket from the rail so the board stays readable.
    store.setRail({ ...store.state.rail, done: store.state.rail.done.filter((t) => t.id !== ticket) });
  }
}

// The budget in the demo: every actor spends at a rate that follows what it is doing, each
// ticket on the floor accrues what its cook spends, a served ticket keeps its total.
function demoBudget(store, every = 1000) {
  const RATE = { thinking: 0.9, editing: 1.4, running: 0.4, reading: 0.7, waiting: 0.05, idle: 0, offline: 0 }; // cents per second
  const PRICE = { opus: 1, sonnet: 0.5, haiku: 0.03, fable: 2.5 };
  const actors = {}, tickets = new Map(), since = Date.now();
  const tok = (usd) => Math.round(usd / 2.6 * 1e6); // mostly cache reads at $0.20 to $0.25 per million, as in a real session
  const zero = () => ({ in: 0, out: 0, read: 0, w5: 0, w1: 0 });
  const tick = () => {
    const s = store.state;
    const who = [['sous', s.sous, null], ...s.stations.map((st) => [st.id, st.cook, st.ticket])];
    for (const [id, a, ticket] of who) {
      const x = (actors[id] ||= { sessions: 1, cost: 0, total: 0, secs: 0, activeSecs: 0, helpers: {}, current: { role: id, model: a.model, tokens: zero(), total: 0, cost: 0, priced: true, helpers: {}, helperCost: 0, allCost: 0, allTotal: 0, secs: 0, activeSecs: 0, startedAt: since } });
      const d = (RATE[a.activity] || 0) * (PRICE[a.model] || 1) / 100 * (every / 1000);
      x.cost += d; x.total += tok(d); x.secs += every / 1000; if (d) x.activeSecs += every / 1000;
      x.current.helpers = x.helpers; x.current.cost = x.cost; x.current.allCost = x.cost; x.current.total = x.total; x.current.allTotal = x.total; x.current.secs = x.secs; x.current.activeSecs = x.activeSecs; x.current.model = a.model;
      x.current.tokens.read += tok(d) * 0.9; x.current.tokens.w5 += tok(d) * 0.08; x.current.tokens.out += tok(d) * 0.02;
      if (ticket) {
        const t = tickets.get(ticket) || { id: ticket, cook: id, session: a.session, status: 'open', startedAt: Date.now(), servedAt: null, tokens: zero(), total: 0, cost: 0, helpers: {}, helperCost: 0, allCost: 0, phases: { plan: null, wait: null, build: null, pass: null, ship: null }, secs: 0 };
        tickets.set(ticket, t);
        t.cost += d; t.allCost = t.cost; t.total += tok(d); t.tokens.read += tok(d) * 0.9; t.tokens.out += tok(d) * 0.02; t.secs = Math.round((Date.now() - t.startedAt) / 1000);
      }
    }
    for (const h of s.helpers) { const x = actors[h.from]; if (!x) continue; const k = (x.helpers[h.kind] ||= { runs: 0, cost: 0, total: 0, secs: 0 }); if (!h._counted) { h._counted = true; k.runs++; } k.cost += 0.004; x.cost += 0.004; x.current.helperCost = (x.current.helperCost || 0) + 0.004; x.current.allCost = x.cost; }
    for (const t of tickets.values()) if (t.status === 'open' && !s.stations.some((st) => st.ticket === t.id)) { t.status = 'served'; t.servedAt = Date.now(); t.phases = { plan: 9, wait: 6, build: Math.max(10, t.secs - 30), pass: 8, ship: 7 }; t.ci = { minutes: 4.5, cost: 0.036, runs: 2, branch: `${t.id.toLowerCase()}-x`, public: false }; }
    const shift = { tokens: zero(), total: 0, cost: 0, secs: 0, activeSecs: 0, helperCost: 0, ci: { minutes: 0, cost: 0 } };
    for (const x of Object.values(actors)) { shift.cost += x.cost; shift.total += x.total; shift.secs += x.secs; shift.activeSecs += x.activeSecs; for (const k of Object.keys(shift.tokens)) shift.tokens[k] += x.current.tokens[k]; }
    for (const t of tickets.values()) if (t.ci) { shift.ci.minutes += t.ci.minutes; shift.ci.cost += t.ci.cost; }
    store.setBudget({ asOf: '2026-10-24', since, computedAt: Date.now(), shift, sessions: Object.values(actors).map((x) => x.current), tickets: [...tickets.values()], actors, unknownModels: [] });
  };
  const t = setInterval(tick, every); t.unref?.();
}
