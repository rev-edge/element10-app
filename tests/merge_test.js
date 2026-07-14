// Element 10 — pure-helper test for the H2 workspace section merge.
//
// The tests/ pure-helper convention (est. H1): a plain node script that extracts a PURE function from
// index.html by source and asserts it — no supabase, no DOM, no network, nothing stubbed. It proves
// the decision logic in isolation from the single-file app.
//   Run:  node tests/merge_test.js
//
// mergeWorkspace(base, local, remote, keys) → { merged, conflicts[] }. Per top-level section:
//   local == base            → take remote   (this tab didn't touch it; adopt the other tab's change)
//   remote == base           → take local    (the other tab didn't touch it; keep our change)
//   local == remote          → keep          (both landed on the same value)
//   both changed, differ     → TRUE conflict  (default to local; the app surfaces it, never silent)

const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const m = src.match(/function mergeWorkspace\([\s\S]*?\n return\{merged,conflicts\};\}/);
if (!m) { console.error('mergeWorkspace not found in index.html'); process.exit(2); }
eval(m[0]); // defines mergeWorkspace in scope — pure, safe

let pass = 0, fail = 0;
const T = (name, cond, detail) => cond
  ? (pass++, console.log('  PASS  ' + name))
  : (fail++, console.log('  FAIL  ' + name + (detail ? '\n          → ' + detail : '')));

console.log('\nElement 10 — workspace section merge\n');

// Four cell states across four sections, one section per state:
const base   = { a: 1, b: 1, c: 1, d: 1 };
const local  = { a: 1, b: 2, c: 1, d: 2 };   // a unchanged, b changed, c unchanged, d changed
const remote = { a: 9, b: 1, c: 1, d: 8 };   // a changed, b unchanged, c unchanged, d changed (differently)
const r = mergeWorkspace(base, local, remote, ['a', 'b', 'c', 'd']);
T('local==base, remote changed → take remote', r.merged.a === 9, 'got ' + r.merged.a);
T('remote==base, local changed → take local',  r.merged.b === 2, 'got ' + r.merged.b);
T('both unchanged → keep',                     r.merged.c === 1, 'got ' + r.merged.c);
T('both changed differently → conflict',       r.conflicts.length === 1 && r.conflicts[0] === 'd', 'conflicts=' + JSON.stringify(r.conflicts));
T('conflict defaults to local',                r.merged.d === 2, 'got ' + r.merged.d);
T('non-conflicting sections are NOT flagged',  !r.conflicts.includes('a') && !r.conflicts.includes('b') && !r.conflicts.includes('c'));

// Both tabs changed a section to the SAME value → not a conflict.
const s = mergeWorkspace({ x: 1 }, { x: 5 }, { x: 5 }, ['x']);
T('both changed to same value → no conflict',  s.conflicts.length === 0 && s.merged.x === 5);

// Deep structural comparison (arrays/objects), not identity.
const d1 = mergeWorkspace({ t: [1, 2] }, { t: [1, 2] }, { t: [1, 2, 3] }, ['t']);
T('array: local==base takes remote (deep)',    d1.conflicts.length === 0 && JSON.stringify(d1.merged.t) === JSON.stringify([1, 2, 3]));
const d2 = mergeWorkspace({ t: [1] }, { t: [1, 2] }, { t: [1, 3] }, ['t']);
T('array: both changed differently → conflict', d2.conflicts.includes('t'));

// A section absent from base/remote but present in local (a brand-new local-only section) → kept, no conflict.
const n = mergeWorkspace({}, { q: [7] }, {}, ['q']);
T('new local-only section kept (remote==base==undefined)', n.conflicts.length === 0 && JSON.stringify(n.merged.q) === JSON.stringify([7]));

// Purity: inputs are not mutated.
const bi = { a: 1 }, li = { a: 2 }, ri = { a: 1 };
mergeWorkspace(bi, li, ri, ['a']);
T('inputs not mutated', JSON.stringify(bi) === '{"a":1}' && JSON.stringify(li) === '{"a":2}' && JSON.stringify(ri) === '{"a":1}');

console.log('\n  ' + pass + ' pass · ' + fail + ' fail\n');
process.exit(fail ? 1 : 0);
