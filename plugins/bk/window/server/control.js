// The control plane: how a click in the Window reaches a real session. Claude Code has
// no outside switch for its model or prompt, so the only honest route is typing into the
// terminal the session runs in, which tmux allows (`tmux send-keys`). Without tmux the
// Window hands back the command for the human to paste. In demo mode the store is
// updated directly so the UX can be tried without a kitchen.
import { execFile } from 'node:child_process';

const sh = (cmd, args) => new Promise((res) => execFile(cmd, args, { encoding: 'utf8' }, (e, out) => res(e ? null : out)));
const MODELS = ['fable', 'opus', 'sonnet', 'haiku'];

export function createControl(store, { demo = false } = {}) {
  let tmuxOk = null;
  const paneCache = new Map(); // session pid → pane id

  async function tmuxAvailable() {
    if (tmuxOk === null) tmuxOk = (await sh('tmux', ['-V'])) !== null;
    return tmuxOk;
  }
  // The pane whose shell is an ancestor of the session's pid.
  async function paneFor(pid) {
    if (paneCache.has(pid)) return paneCache.get(pid);
    const list = await sh('tmux', ['list-panes', '-a', '-F', '#{pane_pid}\t#{pane_id}']);
    if (!list) return null;
    const panes = new Map(list.trim().split('\n').map((l) => l.split('\t')).map(([p, id]) => [Number(p), id]));
    let cur = pid;
    for (let i = 0; i < 12 && cur > 1; i++) {
      if (panes.has(cur)) { paneCache.set(pid, panes.get(cur)); return panes.get(cur); }
      const pp = await sh('ps', ['-o', 'ppid=', '-p', String(cur)]);
      cur = Number((pp || '').trim()); if (!cur) break;
    }
    return null;
  }
  async function type(pid, text) {
    const pane = await paneFor(pid); if (!pane) return false;
    const a = await sh('tmux', ['send-keys', '-t', pane, '-l', text]); if (a === null) return false;
    await sh('tmux', ['send-keys', '-t', pane, 'Enter']);
    return true;
  }

  function actorOf(who) { return who === 'sous' ? store.state.sous : store.state.stations.find((s) => s.id === who)?.cook; }

  // → { ok, via: 'tmux' | 'demo' | 'none', command, reason }
  async function handle({ who, action, value = '' }) {
    const actor = actorOf(who);
    if (!actor) return { ok: false, via: 'none', reason: `no such actor: ${who}` };
    let command;
    switch (action) {
      case 'model': if (!/^[a-z0-9[\]\-.]+$/i.test(value)) return { ok: false, via: 'none', reason: 'bad model name' }; command = `/model ${value}`; break;
      case 'clear': command = '/clear'; break;
      case 'handoff': command = '/bk:handoff'; break;
      case 'send': if (!value.trim()) return { ok: false, via: 'none', reason: 'empty' }; command = value.trim().replace(/\r?\n/g, ' '); break;
      case 'answer': { // an AskUserQuestion option, by its 1-based number; the TUI selects on the digit and confirms on Enter
        const q = store.state.headChef.pending.find((x) => x.id === value.id);
        if (!q) return { ok: false, via: 'none', reason: 'that question is gone' };
        const n = q.options.indexOf(value.option) + 1;
        command = n > 0 ? String(n) : String(value.option);
        break;
      }
      default: return { ok: false, via: 'none', reason: `unknown action ${action}` };
    }
    if (demo) {
      if (action === 'model') store.setActor(who, { model: value });
      if (action === 'clear') { store.setActor(who, { activity: 'idle', status: 'idle', bubble: null, startedAt: Date.now(), handoffAt: null }); if (who !== 'sous') store.upsertStation(who, { ticket: null }); }
      if (action === 'handoff') { store.say(who, '/bk:handoff'); store.setActor(who, { activity: 'editing', status: 'busy' }); setTimeout(() => { store.setActor(who, { handoffAt: Date.now(), activity: 'idle', status: 'idle' }); store.say(who, who === 'sous' ? 'Handoff written: .claude/sous-handoff.md. Clear me when you like.' : 'Handoff in the journal.'); }, 4000); }
      if (action === 'answer') { store.answer(value.id); store.message({ from: 'head-chef', to: 'sous', kind: '[heard]', text: `${value.option}` }); store.setActor('sous', { activity: 'thinking', status: 'busy' }); }
      else store.message({ from: 'head-chef', to: who, kind: '[head-chef]', text: command });
      return { ok: true, via: 'demo', command };
    }
    if (!actor.pid || actor.status === 'offline') return { ok: false, via: 'none', command, reason: 'that session is not running' };
    if (!(await tmuxAvailable())) return { ok: false, via: 'none', command, reason: 'tmux is not installed; paste the command into the session' };
    const typed = await type(actor.pid, command);
    if (!typed) return { ok: false, via: 'none', command, reason: 'that session is not in a tmux pane; paste the command into it' };
    if (action !== 'answer') store.message({ from: 'head-chef', to: who, kind: action === 'send' ? '[head-chef]' : '[typed]', text: command });
    return { ok: true, via: 'tmux', command };
  }

  async function describe() { return { control: demo ? 'demo' : (await tmuxAvailable()) ? 'tmux' : 'none', models: MODELS }; }
  return { handle, describe };
}
