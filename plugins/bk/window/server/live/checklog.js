// The check log: `kitchen.sh check` appends one line per real run to <checkout>/.claude/check.log,
//   2026-11-03T12:00:00Z tree=<hash> rc=<n> secs=<n> cmd=<id>[ moved]
// A call that found a recorded green and ran nothing writes no line, so every line is a run.
// The budget and the Window both read it here, so they count the same runs.
import fs from 'node:fs';
import path from 'node:path';

const LINE = /^(\S+) tree=(\S+) rc=(\d+) secs=(\d+) cmd=(\S+)( moved)?$/;

export function parseCheckLog(text) {
  const runs = [];
  for (const l of String(text || '').split('\n')) {
    const m = l.match(LINE);
    if (m && !Number.isNaN(Date.parse(m[1]))) runs.push({ at: Date.parse(m[1]), tree: m[2], rc: +m[3], ok: +m[3] === 0, secs: +m[4], moved: !!m[6] });
  }
  return runs;
}

export function readCheckLog(dir) {
  try { return parseCheckLog(fs.readFileSync(path.join(dir, '.claude', 'check.log'), 'utf8')); } catch { return []; }
}
