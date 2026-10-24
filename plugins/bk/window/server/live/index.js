// Wires the live sources to the store for one kitchen.
import fs from 'node:fs';
import path from 'node:path';
import { readConfig } from './config.js';
import { watchSessions } from './sessions.js';
import { tailTranscript, transcriptPath } from './transcripts.js';
import { watchStations } from './stations.js';
import { watchRail } from './rail.js';
import { watchRecord } from './record.js';

export function startLive(store, startDir) {
  const cfg = readConfig(startDir);
  store.setKitchen({ repo: cfg.repo, root: cfg.root, mode: cfg.mode, trunk: cfg.trunk, configured: cfg.hasConfig, rail: cfg.railAdapter });
  if (!cfg.hasConfig) console.log(`No .claude/brigade.md in ${cfg.root}: showing stations and sessions only.`);
  console.log(`kitchen: ${cfg.root} (${cfg.mode}, trunk ${cfg.trunk}, stations in ${cfg.kitchen})`);

  watchStations(cfg, store);
  watchRail(cfg, store);
  watchRecord(cfg, store);

  const tails = new Map(); // pid → tail
  const names = new Map(); // session name → who
  const sousName = () => { try { return fs.readFileSync(cfg.sousNameFile, 'utf8').trim(); } catch { return ''; } };
  const resolve = (name) => {
    if (!name) return null;
    if (names.has(name)) return names.get(name);
    if (name === sousName()) return 'sous';
    const m = name.match(/-cook-(\d+)$/); if (m) return `station-${m[1]}`;
    return null;
  };

  watchSessions(cfg, (found) => {
    const seen = new Set();
    // The main checkout may hold several sessions (a solo chef, a stray shell). The sous
    // is the one that recorded its name; else the most recently active one.
    const recorded = sousName();
    const sousCandidates = found.filter((s) => s.role === 'sous');
    const sous = sousCandidates.find((s) => s.name === recorded) || sousCandidates[0] || null;
    for (const s of found) {
      const who = s.role === 'sous' ? (s === sous ? 'sous' : null) : s.role;
      if (!who) continue;
      seen.add(s.pid); names.set(s.name, who);
      const status = s.status === 'busy' ? 'busy' : 'idle';
      if (who === 'sous') store.setActor('sous', { session: s.name, status, activity: status === 'busy' ? (store.state.sous.activity === 'offline' || store.state.sous.activity === 'idle' ? 'thinking' : store.state.sous.activity) : 'idle', pid: s.pid, tmux: s.tmux });
      else { store.upsertStation(who, { name: who, cook: { session: s.name, status, pid: s.pid, tmux: s.tmux } }); store.setActor(who, { activity: status === 'busy' ? (['offline', 'idle'].includes(store.state.stations.find((x) => x.id === who)?.cook.activity) ? 'thinking' : undefined) : 'idle' }); }
      if (!tails.has(s.pid)) {
        const file = transcriptPath(s.cwd, s.sessionId);
        if (file) { tails.set(s.pid, tailTranscript({ file, who, store, resolve })); store.setActor(who, { startedAt: conversationStart(file) }); }
        else tails.set(s.pid, null); // no transcript yet; retried on the next change
      }
    }
    for (const [pid, t] of tails) if (!seen.has(pid)) { t?.close(); tails.delete(pid); }
    if (!sous) store.setActor('sous', { session: null, status: 'offline', activity: 'offline' });
    for (const st of store.state.stations) if (!found.some((s) => s.role === st.id)) store.setActor(st.id, { session: null, status: 'offline', activity: 'offline' });
  });
  watchHandoff(cfg, store);
  return cfg;
}

// When this conversation began: a /clear starts a new transcript file, so its first line's
// timestamp (else its creation time) marks the start.
function conversationStart(file) {
  try {
    const fd = fs.openSync(file, 'r'), buf = Buffer.alloc(4096); const n = fs.readSync(fd, buf, 0, 4096, 0); fs.closeSync(fd);
    const m = buf.toString('utf8', 0, n).match(/"timestamp":"([^"]+)"/);
    if (m) return Date.parse(m[1]);
    return fs.statSync(file).birthtimeMs || fs.statSync(file).mtimeMs;
  } catch { return null; }
}

// The sous's handoff lives in .claude/sous-handoff.md; its mtime says when it was last written.
function watchHandoff(cfg, store, every = 5000) {
  const file = path.join(cfg.root, '.claude', 'sous-handoff.md');
  let last;
  const tick = () => {
    let at = null; try { at = fs.statSync(file).mtimeMs; } catch { /* no handoff yet */ }
    if (at !== last) { last = at; store.setActor('sous', { handoffAt: at }); }
  };
  tick(); const t = setInterval(tick, every); t.unref?.();
}
