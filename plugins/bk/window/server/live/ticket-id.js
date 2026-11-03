// A ticket's id in the form the rail uses (Contract 3 and 4), in one place so the budget and
// the Window agree. The markdown ids (S001-02, BKLG-004, HYG-003) are read on every rail; a
// github or mixed rail adds #N (and the branch issue-N-…); a jira rail adds keys like PROJ-123.
const MD = /\b(S\d{3}-\d{2}|BKLG-\d{3}|HYG-\d{3})\b/i;
// \b does not hold before "#", so: not inside a word, a URL path or an HTML entity.
// Not "PR #76" or "pull #76": that names a pull request, and the ticket is the other number.
const GH = /(?<![\w/&])(?<!\b(?:PRs?|pull) )#(\d+)\b/i;
// Case-sensitive on purpose: with the i flag "utf-8" and "sha-256" would be keys.
const JIRA = /\b([A-Z][A-Z0-9]{1,9}-\d+)\b/;

const tracker = (adapter) => adapter === 'github' || adapter === 'mixed';

// The id a free text names first, canonical (upper-case; #N), or null.
export function idOf(text, adapter = 'markdown') {
  const s = String(text || '');
  const forms = [[MD, (m) => m[1].toUpperCase()]];
  if (tracker(adapter)) forms.push([GH, (m) => `#${m[1]}`]);
  if (adapter === 'jira') forms.push([JIRA, (m) => m[1]]);
  let best = null;
  for (const [re, make] of forms) { const m = s.match(re); if (m && (!best || m.index < best.index)) best = { index: m.index, id: make(m) }; }
  return best ? best.id : null;
}

// The id a branch name carries: bklg-004-fix → BKLG-004, issue-13-x → #13 (github, mixed),
// proj-123-x → PROJ-123 (jira). Detached or unrecognised → null.
export function idOfBranch(branch, adapter = 'markdown') {
  const b = String(branch || '');
  let m = b.match(/^(s\d{3}-\d{2}|bklg-\d{3}|hyg-\d{3})(?![\d])/i);
  if (m) return m[1].toUpperCase();
  if (tracker(adapter) && (m = b.match(/^issue-(\d+)(?:-|$)/i))) return `#${m[1]}`;
  if (adapter === 'jira' && (m = b.match(/^([a-z][a-z0-9]{1,9}-\d+)(?:-|$)/i))) return m[1].toUpperCase();
  return null;
}

// What a person types after --ticket: 13 or #13 on a github or mixed rail → #13; anything else upper-cased.
export function canon(arg, adapter = 'markdown') {
  const s = String(arg || '').trim();
  if (tracker(adapter) && /^#?\d+$/.test(s)) return `#${s.replace('#', '')}`;
  return s.toUpperCase();
}
