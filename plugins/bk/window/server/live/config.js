// Reads what kitchen.sh reads: the repo root, .claude/brigade.md's flat keys and docs map,
// the kitchen mode and where the stations live. Mirrors kitchen.sh, never calls it.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

function git(cwd, ...args) {
  try { return execFileSync('git', ['-C', cwd, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return ''; }
}

export function readConfig(startDir) {
  let root = git(startDir, 'rev-parse', '--show-toplevel') || startDir;
  // Started inside a station? Climb to the main checkout like kitchen.sh does.
  const common = git(root, 'rev-parse', '--path-format=absolute', '--git-common-dir');
  const gitDir = git(root, 'rev-parse', '--absolute-git-dir');
  if (common && common !== gitDir && path.basename(common) === '.git') root = path.dirname(common);
  else if (/^station-/.test(path.basename(root))) {
    const owner = git(path.dirname(path.dirname(root)), 'rev-parse', '--show-toplevel');
    if (owner && fs.existsSync(path.join(owner, '.claude', 'brigade.md'))) root = owner;
  }
  const file = path.join(root, '.claude', 'brigade.md');
  const flat = {}, docs = {};
  if (fs.existsSync(file)) {
    const lines = fs.readFileSync(file, 'utf8').split('\n');
    if (lines[0] === '---') {
      let inDocs = false;
      for (const raw of lines.slice(1)) {
        if (raw === '---') break;
        const line = raw.replace(/\s+#.*$/, '');
        if (/^docs:/.test(line)) { inDocs = true; continue; }
        if (/^[^\s]/.test(line)) inDocs = false;
        const m = inDocs ? line.match(/^ {2}(\w+):\s*(.*)$/) : line.match(/^(\w+):\s*(.*)$/);
        if (!m) continue;
        (inDocs ? docs : flat)[m[1]] = m[2].replace(/^"|"$/g, '');
      }
    }
  }
  const repo = path.basename(root);
  const trunk = process.env.BRIGADE_TRUNK || flat.trunk || (git(root, 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD').replace(/^origin\//, '')) || 'main';
  const mode = process.env.BRIGADE_KITCHEN_MODE || flat.kitchen_mode || 'clone';
  let kitchenRel = process.env.BRIGADE_KITCHEN || flat.kitchen || (mode === 'worktree' ? `../${repo}-stations` : 'stations');
  const kitchen = path.resolve(root, kitchenRel);
  const docsDir = (key, dflt) => path.resolve(root, docs[key] || dflt || `docs/${key}`);
  const railAdapter = (fs.existsSync(file) ? (fs.readFileSync(file, 'utf8').match(/^rail:\n(?:[ \t]+.*\n)*?[ \t]+adapter:\s*(\w+)/m) || [])[1] : null) || 'markdown';
  return {
    root, repo, trunk, mode, kitchen, hasConfig: fs.existsSync(file), flat, docs, docsDir, railAdapter,
    sousNameFile: path.join(root, '.claude', 'sous'),
    stations() {
      try { return fs.readdirSync(kitchen).filter((d) => /^station-\d+$/.test(d) && fs.existsSync(path.join(kitchen, d, '.git'))).map((d) => path.join(kitchen, d)).sort((a, b) => a.localeCompare(b, undefined, { numeric: true })); } catch { return []; }
    },
  };
}

export const realpath = (p) => { try { return fs.realpathSync(p); } catch { return p; } };
