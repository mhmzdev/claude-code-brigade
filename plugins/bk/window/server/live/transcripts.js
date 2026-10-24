// Tails one session's transcript (<config>/projects/<cwd slug>/<sessionId>.jsonl) and turns
// the lines Claude Code appends into kitchen events: a tool call says what the actor is
// doing, an Agent call is a helper leaving, a SendMessage is a ticket flying to someone,
// an AskUserQuestion in the sous is a question for the head chef.
import fs from 'node:fs';
import path from 'node:path';
import { configDir } from './sessions.js';
import { realpath } from './config.js';

const slug = (p) => p.replace(/[^A-Za-z0-9]/g, '-');
const ACTIVITY = { Edit: 'editing', Write: 'editing', MultiEdit: 'editing', NotebookEdit: 'editing', Bash: 'running', Read: 'reading', Grep: 'reading', Glob: 'reading', WebFetch: 'reading', WebSearch: 'reading' };
const kindOf = (text) => (String(text || '').match(/^\s*(\[[a-z-]+\])/i) || [])[1] || '[note]';

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
  const pendingAgents = new Map(); // tool_use id → helper id
  const pendingAsks = new Set();
  let busy = false;

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
          if (!replaying && ['commis', 'taster', 'inspector', 'runner'].includes(kind)) { pendingAgents.set(b.id, b.id); store.helperStart({ id: b.id, kind, from: who, note: inp.description || '' }); }
          else if (!replaying) store.setActor(who, { activity: 'waiting' });
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
          const reply = typeof b.content === 'string' ? b.content : (Array.isArray(b.content) ? b.content.filter((x) => x.type === 'text').map((x) => x.text).join(' ') : '');
          store.helperEnd(b.tool_use_id, String(reply || '').slice(0, 600)); store.setActor(who, { activity: 'thinking' });
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
  const watcher = fs.watch(file, { persistent: false }, () => setTimeout(read, 40));
  const timer = setInterval(read, 2000); timer.unref();
  return { read, close() { watcher.close(); clearInterval(timer); }, get busy() { return busy; } };
}

export function shortModel(m) {
  const s = String(m || '').toLowerCase();
  for (const n of ['fable', 'opus', 'sonnet', 'haiku']) if (s.includes(n)) return n + (s.includes('[1m]') || s.includes('1m') ? '[1m]' : '');
  return m || null;
}
