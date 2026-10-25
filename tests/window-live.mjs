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
const store = { setActor() {}, say() {}, message() {}, ask() {}, answer() {}, helperStart: (h) => started.push(h.id + ':' + h.kind), helperEnd: (id, v) => { ended.push(id); verdict = v; }, state: {} };
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

fs.rmSync(dir, { recursive: true, force: true });
console.log(`# passed ${n - failed} · failed ${failed} · total ${n}`);
process.exit(failed ? 1 : 0);
