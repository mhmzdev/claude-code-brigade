// The check log: `kitchen.sh check` appends one receipt per real run to <checkout>/.claude/check.log,
//   2026-11-03T12:00:00Z tree=<hash> rc=<n> secs=<n> cmd=<id> start=<time> out=<sha256> station=<folder, % as %25 and spaces as %20>[ moved] check=<the config's check: line>
// A call that found a recorded green and ran nothing writes no line, so every line is a run.
// A line from before receipts (it stops at cmd=<id> or ` moved`) is still a run, so it is read, with no
// receipt fields. The budget and the Window both read it here, so they count the same runs.
import fs from 'node:fs';
import path from 'node:path';

const LINE = /^(\S+) tree=(\S+) rc=(\d+) secs=(\d+) cmd=(\S+)(?: start=(\S+) out=([0-9a-f]{64}) station=(\S+))?( moved)?(?: check=(.*))?$/;

export function parseCheckLog(text) {
  const runs = [];
  for (const l of String(text || '').split('\n')) {
    const m = l.match(LINE);
    if (!m || Number.isNaN(Date.parse(m[1]))) continue;
    const run = { at: Date.parse(m[1]), tree: m[2], rc: +m[3], ok: +m[3] === 0, secs: +m[4], moved: !!m[9] };
    if (m[6] !== undefined && m[10] !== undefined) Object.assign(run, { receipt: true, start: Date.parse(m[6]), out: m[7], station: m[8].replace(/%20/g, ' ').replace(/%25/g, '%'), check: m[10] });
    runs.push(run);
  }
  return runs;
}

// A receipt that names another station is a copied or misfiled line, not a run that happened here.
export function readCheckLog(dir) {
  try {
    const here = path.basename(fs.realpathSync(dir));   // kitchen.sh names the folder with pwd -P
    return parseCheckLog(fs.readFileSync(path.join(dir, '.claude', 'check.log'), 'utf8')).filter((r) => !r.receipt || r.station === here);
  } catch { return []; }
}
