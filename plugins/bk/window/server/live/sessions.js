// Who is in the kitchen right now. Claude Code writes one JSON file per live session
// under <config dir>/sessions/<pid>.json: cwd, name, busy/idle, pid. We read those,
// keep the ones whose cwd is this kitchen, and drop the ones whose pid is gone.
import fs from 'node:fs';
import path from 'node:path';
import { realpath } from './config.js';

export const configDir = () => process.env.CLAUDE_CONFIG_DIR || path.join(process.env.HOME || '', '.claude');

function alive(pid) { try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; } }

export function watchSessions(cfg, onChange) {
  const dir = path.join(configDir(), 'sessions');
  const rootReal = realpath(cfg.root);
  const roleOf = (cwd) => {
    const real = realpath(cwd);
    if (real === rootReal) return 'sous';
    for (const st of cfg.stations()) if (realpath(st) === real) return path.basename(st);
    return null;
  };
  let last = '';
  function scan() {
    let files = [];
    try { files = fs.readdirSync(dir).filter((f) => f.endsWith('.json')); } catch { /* no sessions yet */ }
    const found = [];
    for (const f of files) {
      let s; try { s = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')); } catch { continue; }
      if (!s.cwd || !s.pid || !alive(s.pid)) continue;
      const role = roleOf(s.cwd); if (!role) continue;
      found.push({ role, pid: s.pid, sessionId: s.sessionId, name: s.name, status: s.status || 'idle', cwd: s.cwd, tmux: s.tmux || null, updatedAt: s.updatedAt || 0 });
    }
    found.sort((a, b) => b.updatedAt - a.updatedAt);
    const sig = JSON.stringify(found.map((s) => [s.role, s.pid, s.status, s.name]));
    if (sig !== last) { last = sig; onChange(found); }
  }
  scan();
  let watcher = null;
  try { watcher = fs.watch(dir, { persistent: false }, () => setTimeout(scan, 80)); } catch { /* dir may not exist yet */ }
  const timer = setInterval(scan, 3000); timer.unref();
  return { scan, close() { watcher?.close(); clearInterval(timer); } };
}
