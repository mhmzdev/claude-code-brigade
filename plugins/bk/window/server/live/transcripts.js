// Tails one session's transcript (<config>/projects/<cwd slug>/<sessionId>.jsonl) and turns
// the lines Claude Code appends into kitchen events: a tool call says what the actor is
// doing, an Agent call is a helper leaving, a SendMessage is a ticket flying to someone,
// an AskUserQuestion in the sous is a question for the head chef.
//
// A helper in flight is read from beside the transcript, not from it: Claude Code (2.1.x)
// writes the assistant line that holds an Agent call only once the result is in, so from
// the transcript alone a run of a minute lasts one second. While it runs, the sub-agent's
// own files exist under <sessionId>/subagents/: agent-<id>.jsonl (its turns) and
// agent-<id>.meta.json (agentType, description, toolUseId, and `finished` once it is done).
// The meta file is the start; the tool_result in the transcript (or `finished`) is the end.
import fs from 'node:fs';
import path from 'node:path';
import { configDir } from './sessions.js';
import { realpath } from './config.js';

const slug = (p) => p.replace(/[^A-Za-z0-9]/g, '-');
const ACTIVITY = { Edit: 'editing', Write: 'editing', MultiEdit: 'editing', NotebookEdit: 'editing', Bash: 'running', Read: 'reading', Grep: 'reading', Glob: 'reading', WebFetch: 'reading', WebSearch: 'reading' };
const kindOf = (text) => (String(text || '').match(/^\s*(\[[a-z-]+\])/i) || [])[1] || '[note]';
const HELPERS = ['commis', 'taster', 'inspector', 'runner'];
// The last thing a sub-agent said, from its own transcript: a runner's verdict when the
// tool_result has not reached the transcript yet.
function lastTextOf(file) {
  let text = ''; try { text = fs.readFileSync(file, 'utf8'); } catch { return ''; }
  let last = '';
  for (const line of text.split('\n')) {
    if (!line.includes('"assistant"')) continue;
    let o; try { o = JSON.parse(line); } catch { continue; }
    if (o.type !== 'assistant') continue;
    for (const b of o.message?.content || []) if (b.type === 'text' && b.text && b.text.trim()) last = b.text.trim();
  }
  return last.slice(0, 600);
}

export function transcriptPath(cwd, sessionId) {
  const base = path.join(configDir(), 'projects');
  for (const d of [cwd, realpath(cwd)]) {
    const f = path.join(base, slug(d), `${sessionId}.jsonl`);
    if (fs.existsSync(f)) return f;
  }
  return null;
}

// who: 'sous' | 'station-N'. resolve(name) → who for a SendMessage recipient.
export function tailTranscript({ file, who, store, resolve, replayBytes = 48 * 1024 }) {
  let offset = Math.max(0, fs.statSync(file).size - replayBytes), rest = '', replaying = true;
  const pendingAgents = new Map(); // tool_use id → the helper (kind, from, note)
  const pendingAsks = new Set();
  let busy = false;
  // the session's sub-agents, by their meta file: seen once, started if still out, ended on `finished`
  const agentsDir = path.join(path.dirname(file), path.basename(file, '.jsonl'), 'subagents');
  const agents = new Map(); // meta file name → { id, started, done }
  function scanAgents() {
    let names = []; try { names = fs.readdirSync(agentsDir).filter((n) => n.endsWith('.meta.json')); } catch { return; }
    for (const n of names) {
      let m; try { m = JSON.parse(fs.readFileSync(path.join(agentsDir, n), 'utf8')); } catch { continue; }
      const kind = String(m.agentType || '').replace(/^bk:/, '');
      const id = m.toolUseId || n.replace(/^agent-|\.meta\.json$/g, '');
      let rec = agents.get(n);
      if (!rec) {
        rec = { id, started: false, done: !!m.finished }; agents.set(n, rec);
        if (!m.finished && HELPERS.includes(kind) && !pendingAgents.has(id)) {
          rec.started = true;
          const h = { id, kind, from: who, note: m.description || '' };
          pendingAgents.set(id, h);
          if (!replaying) store.helperStart(h);
        }
      }
      if (rec.started && !rec.done && m.finished) {
        rec.done = true;
        if (pendingAgents.has(id)) { pendingAgents.delete(id); store.helperEnd(id, lastTextOf(path.join(agentsDir, n.replace(/\.meta\.json$/, '.jsonl')))); store.setActor(who, { activity: 'thinking' }); }
      }
    }
  }

  function handle(o) {
    if (!o || typeof o !== 'object') return;
    const msg = o.message || {};
    const content = Array.isArray(msg.content) ? msg.content : [];
    if (o.type === 'assistant') {
      if (msg.model && !replaying) store.setActor(who, { model: shortModel(msg.model) });
      for (const b of content) {
        if (b.type === 'thinking' && !replaying) store.setActor(who, { activity: 'thinking', status: 'busy' });
        if (b.type === 'text' && !replaying && b.text && b.text.length <= 180 && b.text.trim()) store.say(who, b.text.trim());
        if (b.type !== 'tool_use') continue;
        const inp = b.input || {};
        if (b.name === 'Agent') {
          const kind = String(inp.subagent_type || '').replace(/^bk:/, '');
          // Older Claude Code wrote this line as the call went out; newer writes it with the
          // result, by which time the meta file (scanAgents) has started the helper already.
          if (HELPERS.includes(kind) && !pendingAgents.has(b.id) && ![...agents.values()].some((a) => a.id === b.id)) {
            const h = { id: b.id, kind, from: who, note: inp.description || '' };
            pendingAgents.set(b.id, h);
            if (!replaying) store.helperStart(h);   // during the replay it starts only if it is still out when the replay ends
          } else if (!HELPERS.includes(kind) && !replaying) store.setActor(who, { activity: 'waiting' });
        } else if (b.name === 'SendMessage') {
          const text = inp.message || inp.content || inp.summary || '';
          const to = resolve(inp.to || inp.recipient) || inp.to || '?';
          store.message({ from: who, to, kind: kindOf(text), text: text.replace(/^\s*\[[a-z-]+\]\s*/i, '') });
          if (!replaying && /^\s*\[(gate|plan|handoff|walk-in|check-in)\]/i.test(text)) store.setActor(who, { activity: 'waiting' });
        } else if (b.name === 'AskUserQuestion') {
          if (who === 'sous' && !replaying) {
            for (const q of inp.questions || []) { pendingAsks.add(b.id); store.ask({ id: b.id, from: 'sous', text: q.question, options: (q.options || []).map((x) => x.label) }); }
            store.setActor(who, { activity: 'waiting' });
          }
        } else if (b.name === 'Skill' && !replaying) {
          store.say(who, `/${inp.skill}${inp.args ? ' ' + inp.args : ''}`);
          store.setActor(who, { activity: 'reading' });
        } else if (!replaying && ACTIVITY[b.name]) store.setActor(who, { activity: ACTIVITY[b.name], status: 'busy' });
      }
    } else if (o.type === 'user') {
      for (const b of content) {
        if (b.type !== 'tool_result') continue;
        if (pendingAgents.has(b.tool_use_id)) {
          pendingAgents.delete(b.tool_use_id);
          if (!replaying) {
            const reply = typeof b.content === 'string' ? b.content : (Array.isArray(b.content) ? b.content.filter((x) => x.type === 'text').map((x) => x.text).join(' ') : '');
            store.helperEnd(b.tool_use_id, String(reply || '').slice(0, 600)); store.setActor(who, { activity: 'thinking' });
          }
        }
        if (pendingAsks.has(b.tool_use_id)) { pendingAsks.delete(b.tool_use_id); store.answer(b.tool_use_id); store.setActor(who, { activity: 'thinking' }); }
      }
      // The head chef typing to the sous: a plain user prompt, not a tool result.
      const typed = typeof msg.content === 'string' ? msg.content : content.filter((b) => b.type === 'text').map((b) => b.text).join(' ');
      if (who === 'sous' && typed && !content.some((b) => b.type === 'tool_result') && !o.isMeta && !/^<[a-z-]+/.test(typed.trim())) {
        store.message({ from: 'head-chef', to: 'sous', kind: kindOf(typed) === '[note]' ? '[head-chef]' : kindOf(typed), text: typed.trim().slice(0, 300) });
        if (!replaying) store.setActor('sous', { activity: 'thinking', status: 'busy' });
      }
    }
  }

  function read() {
    scanAgents();
    let size; try { size = fs.statSync(file).size; } catch { return; }
    if (size < offset) { offset = 0; rest = ''; } // truncated or rewritten
    if (size === offset) return;
    const fd = fs.openSync(file, 'r');
    try {
      const buf = Buffer.alloc(size - offset); fs.readSync(fd, buf, 0, buf.length, offset); offset = size;
      const text = rest + buf.toString('utf8'); const lines = text.split('\n'); rest = lines.pop();
      for (const line of lines) { if (!line) continue; try { handle(JSON.parse(line)); } catch { /* a partial or foreign line */ } }
    } finally { fs.closeSync(fd); }
  }
  read(); replaying = false;
  // Helpers that left in the replayed part and have not come back are still out there.
  for (const h of pendingAgents.values()) { store.helperStart(h); store.setActor(who, { activity: 'waiting' }); }
  const watcher = fs.watch(file, { persistent: false }, () => setTimeout(read, 40));
  const timer = setInterval(read, 2000); timer.unref();
  return { read, close() { watcher.close(); clearInterval(timer); }, get busy() { return busy; } };
}

export function shortModel(m) {
  const s = String(m || '').toLowerCase();
  for (const n of ['fable', 'opus', 'sonnet', 'haiku']) if (s.includes(n)) return n + (s.includes('[1m]') || s.includes('1m') ? '[1m]' : '');
  return m || null;
}
