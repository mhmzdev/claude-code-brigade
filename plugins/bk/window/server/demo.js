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
      store.helperEnd(`r1-${i}`, 'pass');
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
    store.helperEnd(`bg-r-${id}-${k}`, 'check: pass'); store.setActor(id, { activity: 'editing' });
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
