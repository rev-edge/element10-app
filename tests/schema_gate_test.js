// Element 10 — schema-gate comparator UNIT test (pure; runs on every PR).
// Proves the client/DB CONTRACT comparator fails CLOSED: the app is locked to read-only unless the live
// schema version the DB returns exactly equals the version this client was built for. This is where the
// "gate bites" proof lives — the live production check (tests/schema_gate_live.js) only runs on `main`
// before a deploy, so a throwaway PR branch cannot exercise it. This test exercises the REAL fn extracted
// from index.html (not a copy), matching the tests/genname_test.js pattern. No DOM, no network.
//   NOTE: this proves CONTRACT compatibility (client SCHEMA_VERSION vs e10_schema_version()), NOT migration
//   completeness. Run: node tests/schema_gate_test.js
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');

const m = src.match(/function _schemaContract\([^)]*\)\{return [^\n]*\}/);
if (!m) { console.error('_schemaContract not found in index.html (the gate comparator moved or changed name)'); process.exit(2); }
eval(m[0]); // defines _schemaContract(clientVersion, data, error) → locked:boolean

let pass = 0, fail = 0;
const T = (n, ok, d) => ok ? (pass++, console.log('  PASS ' + n)) : (fail++, console.log('  FAIL ' + n + (d !== undefined ? '  → got ' + JSON.stringify(d) : '')));

const V = '2026-07-15.fg1';

// ── MATCH → unlocked (the only case that must NOT lock) ──
{ const r = _schemaContract(V, V, null); T('exact match → NOT locked', r === false, r); }
{ const r = _schemaContract(V, V, undefined); T('exact match, undefined error → NOT locked', r === false, r); }

// ── MISMATCH → locked (fail closed) ──
{ const r = _schemaContract(V, '2026-07-15.fg0', null); T('older DB version → locked', r === true, r); }
{ const r = _schemaContract(V, '2026-07-16.fg2', null); T('newer DB version → locked', r === true, r); }
{ const r = _schemaContract(V, 'totally-different', null); T('unrelated DB version → locked', r === true, r); }

// ── ERROR → locked (fail closed) ──
{ const r = _schemaContract(V, null, { message: 'permission denied' }); T('RPC error → locked', r === true, r); }
{ const r = _schemaContract(V, V, { message: 'err even if data matches' }); T('error present, data matches → still locked', r === true, r); }

// ── NULL / EMPTY / MISSING DB value → locked (fail closed; the dangerous case) ──
{ const r = _schemaContract(V, null, null); T('null DB value → locked', r === true, r); }
{ const r = _schemaContract(V, undefined, null); T('undefined DB value → locked', r === true, r); }
{ const r = _schemaContract(V, '', null); T('empty-string DB value → locked', r === true, r); }

// ── type coercion is on strings both sides (no accidental == loosening) ──
{ const r = _schemaContract('123', 123, null); T('numeric DB value vs string client → compared as strings (match)', r === false, r); }

console.log('\n  ' + pass + ' pass · ' + fail + ' fail\n');
process.exit(fail ? 1 : 0);
