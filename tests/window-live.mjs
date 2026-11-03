// Behaviour checks for the Window's live reader (plugins/bk/window/server/live/transcripts.js):
// how a helper in flight is seen. Claude Code 2.1.x writes the assistant line that holds an
// Agent call only once the result is in, so a helper is read from the sub-agent's own files
// beside the transcript (agent-<id>.meta.json: agentType, description, toolUseId, `finished`),
// with the older line shape kept as a fallback. Run by tests/window.test.sh; prints TAP lines.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const { tailTranscript } = await import(path.join(here, '..', 'plugins', 'bk', 'window', 'server', 'live', 'transcripts.js'));

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'brigade-window-'));
const line = (o) => JSON.stringify(o) + '\n';
const asst = (content) => line({ type: 'assistant', timestamp: new Date().toISOString(), message: { id: 'm' + Math.random(), model: 'claude-sonnet-5-5', content } });
const result = (id, agentId) => line({ type: 'user', timestamp: new Date().toISOString(), message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: id, content: 'pass' }] }, toolUseResult: { agentId } });
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
let n = 0, failed = 0;
const ok = (name, pass) => { n++; if (!pass) failed++; console.log(`${pass ? 'ok' : 'not ok'} ${n} - ${name}`); };
let started = [], ended = [], verdict = null;
let model = null;
const store = { setActor(who, p) { if (p.model !== undefined) model = p.model; }, say() {}, message() {}, ask() {}, answer() {}, helperStart: (h) => started.push(h.id + ':' + h.kind), helperEnd: (id, v) => { ended.push(id); verdict = v; }, state: {} };
const POLL = 2600; // the tail polls every 2s

console.log('# the older line shape: the Agent call written as it goes out');
const f1 = path.join(dir, 's1.jsonl');
fs.writeFileSync(f1, asst([{ type: 'tool_use', id: 't1', name: 'Agent', input: { subagent_type: 'bk:runner', description: 'check 1' } }]) + result('t1') + asst([{ type: 'tool_use', id: 't2', name: 'Agent', input: { subagent_type: 'bk:runner', description: 'check 2' } }]));
let t = tailTranscript({ file: f1, who: 'station-1', store, resolve: () => null });
ok('a helper still out at the end of the replayed tail is started; the finished one is not', started.join() === 't2:runner' && ended.length === 0);
fs.appendFileSync(f1, result('t2'));
await wait(POLL);
ok('its tool_result, arriving live, ends it', ended.join() === 't2');
t.close();

console.log('# the 2.1.x shape: the sub-agent meta file beside the transcript');
const f2 = path.join(dir, 's2.jsonl'); fs.writeFileSync(f2, asst([{ type: 'text', text: 'hello' }]));
const sub = path.join(dir, 's2', 'subagents'); fs.mkdirSync(sub, { recursive: true });
started = []; ended = [];
t = tailTranscript({ file: f2, who: 'sous', store, resolve: () => null });
ok('nothing out before any meta file', started.length === 0);
fs.writeFileSync(path.join(sub, 'agent-abc.meta.json'), JSON.stringify({ agentType: 'bk:taster', description: 'taste #13 in station-1', toolUseId: 'tu9' }));
fs.writeFileSync(path.join(sub, 'agent-abc.jsonl'), line({ type: 'user', isSidechain: true, agentId: 'abc', message: { role: 'user', content: 'go' } }));
await wait(POLL);
ok('a meta file with no `finished` starts the helper, keyed by its tool_use id, with the description as the note', started.join() === 'tu9:taster');
ok('…and nothing has ended', ended.length === 0);
fs.appendFileSync(f2, asst([{ type: 'tool_use', id: 'tu9', name: 'Agent', input: { subagent_type: 'bk:taster', description: 'taste #13 in station-1' } }]) + result('tu9', 'abc'));
await wait(POLL);
ok('the Agent line that arrives with the result does not start it a second time', started.length === 1);
ok('the tool_result ends it', ended.join() === 'tu9');
fs.writeFileSync(path.join(sub, 'agent-def.meta.json'), JSON.stringify({ agentType: 'bk:runner', description: 'the check', toolUseId: 'tu10' }));
fs.writeFileSync(path.join(sub, 'agent-def.jsonl'), line({ type: 'user', isSidechain: true, agentId: 'def', message: { role: 'user', content: 'go' } }) + asst([{ type: 'text', text: 'all green: pass' }]));
await wait(POLL);
ok('a second meta starts a second helper', started.join() === 'tu9:taster,tu10:runner');
fs.writeFileSync(path.join(sub, 'agent-def.meta.json'), JSON.stringify({ agentType: 'bk:runner', description: 'the check', toolUseId: 'tu10', finished: true }));
await wait(POLL);
ok('`finished` on the meta ends it, with the verdict read from the sub-agent transcript', ended.join() === 'tu9,tu10' && verdict === 'all green: pass');
fs.writeFileSync(path.join(sub, 'agent-ghi.meta.json'), JSON.stringify({ agentType: 'Explore', description: 'a search', toolUseId: 'tu11' }));
await wait(POLL);
ok('a sub-agent that is not one of the four helpers is not a helper', started.length === 2);
t.close();

console.log('# attaching to a session with sub-agents already on disk');
const f3 = path.join(dir, 's3.jsonl'); fs.writeFileSync(f3, asst([{ type: 'text', text: 'hi' }]));
const sub3 = path.join(dir, 's3', 'subagents'); fs.mkdirSync(sub3, { recursive: true });
fs.writeFileSync(path.join(sub3, 'agent-old.meta.json'), JSON.stringify({ agentType: 'bk:runner', description: 'done long ago', toolUseId: 'tu1', finished: true }));
fs.writeFileSync(path.join(sub3, 'agent-now.meta.json'), JSON.stringify({ agentType: 'bk:commis', description: 'searching', toolUseId: 'tu2' }));
started = []; ended = [];
t = tailTranscript({ file: f3, who: 'station-2', store, resolve: () => null });
ok('a finished meta is ignored; an unfinished one is already out', started.join() === 'tu2:commis');
t.close();

console.log('# the model: the assistant line, and a typed /model before the next turn');
// A typed /model (in the pane, or from the Window's own control) writes two user lines and no
// assistant line until the next turn: <command-name>/model</command-name> with the argument,
// then <local-command-stdout>Set model to `Sonnet 5.5`…</local-command-stdout>.
const cmd = (name, args) => line({ type: 'user', timestamp: new Date().toISOString(), message: { role: 'user', content: `<command-name>${name}</command-name>\n<command-message>${name.slice(1)}</command-message>\n<command-args>${args}</command-args>` } });
const out = (text) => line({ type: 'user', timestamp: new Date().toISOString(), message: { role: 'user', content: `<local-command-stdout>${text}</local-command-stdout>` } });
const f4 = path.join(dir, 's4.jsonl');
fs.writeFileSync(f4, asst([{ type: 'text', text: 'hi' }]) + line({ type: 'assistant', timestamp: new Date().toISOString(), message: { id: 'm-op', model: 'claude-opus-5-5', content: [{ type: 'text', text: 'now on opus' }] } }));
model = null;
t = tailTranscript({ file: f4, who: 'station-1', store, resolve: () => null });
ok('on attach, the model is the last assistant line’s', model === 'opus');
fs.appendFileSync(f4, cmd('/model', 'sonnet'));
await wait(POLL);
ok('a typed /model sonnet sets the model at once, before any assistant line', model === 'sonnet');
fs.appendFileSync(f4, out('Set model to `Haiku 5.5` and saved as your default for new sessions'));
await wait(POLL);
ok('the command’s own output names the model that was actually set', model === 'haiku');
fs.appendFileSync(f4, cmd('/clear', '') + out('cleared'));
await wait(POLL);
ok('another command leaves it alone', model === 'haiku');
t.close();
model = null;
const f5 = path.join(dir, 's5.jsonl');
fs.writeFileSync(f5, asst([{ type: 'text', text: 'hi' }]) + cmd('/model', 'opus') + out('Set model to `Opus 5.5`'));
t = tailTranscript({ file: f5, who: 'station-2', store, resolve: () => null });
ok('on attach, a /model after the last assistant line wins', model === 'opus');
t.close();

console.log('# the check machine reads the check log');
const { parseCheckLog, readCheckLog } = await import(path.join(here, '..', 'plugins', 'bk', 'window', 'server', 'live', 'checklog.js'));
const { createState } = await import(path.join(here, '..', 'plugins', 'bk', 'window', 'server', 'state.js'));
const { watchChecks } = await import(path.join(here, '..', 'plugins', 'bk', 'window', 'server', 'live', 'index.js'));
const tree = 'a'.repeat(40);
const parsed = parseCheckLog(`2026-11-03T12:00:00Z tree=${tree} rc=0 secs=41 cmd=0123456789ab\n2026-11-03T12:05:00Z tree=${tree} rc=1 secs=7 cmd=0123456789ab moved\nnot a run\n2026-11-03T12:06:00Z tree=${tree} rc=x secs=1 cmd=z\n`);
ok('a log line is a run: time, exit code, seconds, moved or not', parsed.length === 2 && parsed[0].ok === true && parsed[0].secs === 41 && parsed[0].moved === false && parsed[1].ok === false && parsed[1].moved === true && parsed[0].at === Date.parse('2026-11-03T12:00:00Z'));
ok('a line that is not a run, or has no real exit code, is ignored', parseCheckLog('hello\n\n').length === 0 && parseCheckLog(null).length === 0);
const sv = createState({});
const runner = (id) => { sv.helperStart({ id, kind: 'runner', from: 'station-1', note: 'npm test' }); sv.helperEnd(id, 'fail: 2 tests'); };
runner('r1');
ok('until a log speaks, a runner’s reply is a check result', sv.state.check.runs === 1 && sv.state.check.failed === 1 && sv.state.check.source === 'runner');
const station = path.join(dir, 'station-1'); fs.mkdirSync(path.join(station, '.claude'), { recursive: true });
const today = new Date().toISOString().replace(/\.\d+Z$/, 'Z'), old = '2020-01-01T00:00:00Z';
const L = (at, rc, extra = '') => `${at} tree=${tree} rc=${rc} secs=3 cmd=0123456789ab${extra}\n`;
fs.writeFileSync(path.join(station, '.claude', 'check.log'), L(old, 1) + L(today, 0));
const tick = watchChecks({ stations: () => [station] }, sv, 3600000);
ok('opening the Window replays only today’s lines, and the log becomes the source', sv.state.check.runs === 2 && sv.state.check.source === 'log' && sv.state.check.last.ok === true && sv.state.check.last.who === 'station-1');
runner('r2');
ok('from then on a runner’s reply no longer counts', sv.state.check.runs === 2);
fs.appendFileSync(path.join(station, '.claude', 'check.log'), L(today, 1, ' moved'));
tick(); tick();
ok('a new log line counts once, however often the log is read', sv.state.check.runs === 3 && sv.state.check.failed === 2 && sv.state.check.last.ok === false);

console.log('# a receipt is a run with its proof; a copied one is not counted');
const sha = 'b'.repeat(64);
const R = (at, rc, st, extra = '') => `${at} tree=${tree} rc=${rc} secs=3 cmd=0123456789ab start=${at} out=${sha} station=${st}${extra} check=scripts/check.sh --all\n`;
const rp = parseCheckLog(R('2026-11-03T12:00:00Z', 0, 'station-1') + R('2026-11-03T12:05:00Z', 1, 'station-1', ' moved'));
ok('a receipt carries its station, output digest and the config line, and is marked a receipt', rp.length === 2 && rp[0].receipt === true && rp[0].station === 'station-1' && rp[0].out === sha && rp[0].check === 'scripts/check.sh --all' && rp[0].ok === true && rp[0].secs === 3 && rp[0].start === Date.parse('2026-11-03T12:00:00Z'));
ok('a moved receipt is still a moved run', rp[1].moved === true && rp[1].ok === false && rp[1].receipt === true);
ok('a line from before receipts is a run and no receipt', parsed[0].receipt === undefined && parsed[0].secs === 41);
const station5 = path.join(dir, 'station-5'); fs.mkdirSync(path.join(station5, '.claude'), { recursive: true });
fs.writeFileSync(path.join(station5, '.claude', 'check.log'), R(today, 0, 'station-5') + R(today, 0, 'station-9') + L(today, 1));
const mine = readCheckLog(station5);
ok('a receipt naming another station is dropped, a receipt for this one and an older line stay', mine.length === 2 && mine[0].station === 'station-5' && mine[1].receipt === undefined && mine[1].ok === false);
const spaced = path.join(dir, 'station 7%'); fs.mkdirSync(path.join(spaced, '.claude'), { recursive: true });
fs.writeFileSync(path.join(spaced, '.claude', 'check.log'), R(today, 0, 'station%207%25') + R(today, 0, 'station-9'));
const sp = readCheckLog(spaced);
ok('a station folder with a space and a percent sign reads its own receipts by the encoded name', sp.length === 1 && sp[0].station === 'station 7%');

console.log('# the kitchen folder: worktrees next to the repo, no mode');
const { readConfig } = await import(path.join(here, '..', 'plugins', 'bk', 'window', 'server', 'live', 'config.js'));
const cfgRoot = path.join(dir, 'cfg', 'app'); fs.mkdirSync(path.join(cfgRoot, '.claude'), { recursive: true });
fs.writeFileSync(path.join(cfgRoot, '.claude', 'brigade.md'), '---\ntrunk: main\n---\n');
const cfg0 = readConfig(cfgRoot);
ok('the stations live in ../<repo>-stations by default', cfg0.kitchen === path.join(dir, 'cfg', 'app-stations'));
ok('the config carries no kitchen mode', !('mode' in cfg0));
fs.writeFileSync(path.join(cfgRoot, '.claude', 'brigade.md'), '---\ntrunk: main\nkitchen: benches\n---\n');
ok('a kitchen: key is relative to the main checkout', readConfig(cfgRoot).kitchen === path.join(cfgRoot, 'benches'));

fs.rmSync(dir, { recursive: true, force: true });
console.log(`# passed ${n - failed} · failed ${failed} · total ${n}`);
process.exit(failed ? 1 : 0);
