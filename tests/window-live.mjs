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

fs.rmSync(dir, { recursive: true, force: true });
console.log(`# passed ${n - failed} · failed ${failed} · total ${n}`);
process.exit(failed ? 1 : 0);
