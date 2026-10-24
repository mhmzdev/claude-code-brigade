// Each station's git state: branch, dirty, commits ahead of trunk, and the ticket id the
// branch name carries. Cheap, serialized, every few seconds.
import { execFile } from 'node:child_process';
import path from 'node:path';

const run = (cwd, args) => new Promise((res) => execFile('git', ['-C', cwd, ...args], { encoding: 'utf8' }, (e, out) => res(e ? '' : out.trim())));
const TICKET = /^(s\d{3}-\d{2}|bklg-\d{3}|hyg-\d{3})/i;

export function watchStations(cfg, store, every = 5000) {
  let running = false, stopped = false;
  async function tick() {
    if (running || stopped) return; running = true;
    try {
      const dirs = cfg.stations(), ids = dirs.map((d) => path.basename(d));
      for (const s of [...store.state.stations]) if (!ids.includes(s.id)) store.removeStation(s.id);
      for (const dir of dirs) {
        const id = path.basename(dir);
        const [branch, porcelain, ahead] = await Promise.all([
          run(dir, ['rev-parse', '--abbrev-ref', 'HEAD']), run(dir, ['status', '--porcelain']), run(dir, ['rev-list', '--count', `origin/${cfg.trunk}..HEAD`]),
        ]);
        const detached = branch === 'HEAD' || !branch;
        const m = !detached && branch.match(TICKET);
        store.upsertStation(id, { name: id, path: dir, branch: detached ? null : branch, dirty: porcelain.length > 0, ahead: Number(ahead) || 0, ticket: m ? m[1].toUpperCase() : null });
      }
    } finally { running = false; }
  }
  tick();
  const timer = setInterval(tick, every); timer.unref();
  return { tick, close() { stopped = true; clearInterval(timer); } };
}
