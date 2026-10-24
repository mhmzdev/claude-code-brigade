// The markdown rail: ticket frontmatter under docs/backlog and each spec's folder,
// grouped by status. Re-read when those folders change.
import fs from 'node:fs';
import path from 'node:path';

const COLS = ['backlog', 'todo', 'in-progress', 'rfr', 'done'];

function frontmatter(file) {
  let text; try { text = fs.readFileSync(file, 'utf8'); } catch { return null; }
  if (!text.startsWith('---')) return null;
  const end = text.indexOf('\n---', 3); if (end < 0) return null;
  const fm = {};
  for (const raw of text.slice(4, end).split('\n')) {
    const m = raw.replace(/\s+#.*$/, '').match(/^(\w+):\s*(.*)$/); if (!m) continue;
    fm[m[1]] = m[2].replace(/^"|"$/g, '');
  }
  return fm;
}

export function watchRail(cfg, store) {
  const specs = cfg.docsDir('specs'), backlog = cfg.docsDir('backlog');
  function files() {
    const out = [];
    try { for (const f of fs.readdirSync(backlog)) if (/^(BKLG|HYG)-\d+.*\.md$/.test(f)) out.push(path.join(backlog, f)); } catch { /* none */ }
    try { for (const d of fs.readdirSync(specs)) { const dir = path.join(specs, d); let st; try { st = fs.statSync(dir); } catch { continue; } if (!st.isDirectory()) continue; for (const f of fs.readdirSync(dir)) if (/^\d\d-.*\.md$/.test(f)) out.push(path.join(dir, f)); } } catch { /* none */ }
    return out;
  }
  function read() {
    if (cfg.railAdapter !== 'markdown' && cfg.railAdapter !== 'mixed') { store.setRail({}); return; }
    const rail = Object.fromEntries(COLS.map((c) => [c, []]));
    for (const f of files()) {
      const fm = frontmatter(f); if (!fm?.id) continue;
      const status = fm.status === 'blocked' ? 'backlog' : (COLS.includes(fm.status) ? fm.status : 'backlog');
      rail[status].push({ id: fm.id, title: fm.title || fm.id, kind: fm.id.startsWith('HYG') ? 'hygiene' : fm.lane === 'A' ? 'feature' : (fm.kind || 'item'), lane: fm.lane, priority: fm.priority, cook: fm.cook === 'null' ? null : fm.cook, blocked: fm.status === 'blocked', path: f });
    }
    for (const c of COLS) rail[c].sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
    store.setRail(rail);
  }
  read();
  const watchers = [];
  for (const dir of [backlog, specs]) { try { watchers.push(fs.watch(dir, { persistent: false, recursive: true }, () => setTimeout(read, 150))); } catch { /* folder absent */ } }
  const timer = setInterval(read, 15000); timer.unref();
  return { read, close() { watchers.forEach((w) => w.close()); clearInterval(timer); } };
}
