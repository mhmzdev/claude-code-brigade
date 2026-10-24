// Counts the record: one page per markdown file under each folder in the config's docs map
// (INDEX.md files excluded, since they list pages rather than being one), plus the lessons
// register and CLAUDE.md. The shelf in the Window grows with the total.
import fs from 'node:fs';
import path from 'node:path';

const KINDS = ['specs', 'backlog', 'plans', 'checklists', 'journal', 'research', 'brainstorm', 'decisions', 'conventions', 'knowledge', 'questions'];
const DEFAULTS = { knowledge: 'docs/domains' };

function countPages(dir) {
  let n = 0;
  const walk = (d, depth) => {
    let ents; try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
    for (const e of ents) {
      if (e.isDirectory()) { if (depth < 4) walk(path.join(d, e.name), depth + 1); }
      else if (/\.md$/i.test(e.name) && !/^INDEX\.md$/i.test(e.name) && !/^README\.md$/i.test(e.name)) n++;
    }
  };
  walk(dir, 0);
  return n;
}

export function countRecord(cfg) {
  const kinds = {};
  for (const k of KINDS) {
    const n = countPages(cfg.docsDir(k, DEFAULTS[k]));
    if (n) kinds[k] = n;
  }
  const lessons = path.resolve(cfg.root, cfg.docs.lessons || 'docs/lessons.md');
  if (fs.existsSync(lessons)) kinds.lessons = 1;
  if (fs.existsSync(path.join(cfg.root, 'CLAUDE.md'))) kinds.claude = 1;
  return { total: Object.values(kinds).reduce((a, b) => a + b, 0), kinds };
}

export function watchRecord(cfg, store, every = 20000) {
  let last = '';
  const tick = () => {
    const r = countRecord(cfg), key = JSON.stringify(r);
    if (key !== last) { last = key; store.setRecord(r); }
  };
  tick();
  const t = setInterval(tick, every); t.unref?.();
  return () => clearInterval(t);
}
