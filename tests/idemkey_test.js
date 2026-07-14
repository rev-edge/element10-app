// Element 10 — pure-helper test for the Chain M / M3 inventory idempotency-key builder.
// invIdemKey(op, entity, item, nonce) must be DETERMINISTIC (same inputs -> same key) so a retry of
// the same logical mutation collapses to one movement, and it must follow the schema.sql convention
// '<op>:shared:<entity>:<item>[:<nonce>]'. Extracts the function from index.html by source; no DOM,
// no network. Run: node tests/idemkey_test.js
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const m = src.match(/function invIdemKey\([\s\S]*?\}\s*(?=\nlet _invSeq)/) || src.match(/function invIdemKey\(op,entity,item,nonce\)\{[^\n]*\}/);
if (!m) { console.error('invIdemKey not found in index.html'); process.exit(2); }
eval(m[0]);

let pass = 0, fail = 0;
const T = (name, cond, detail) => cond
  ? (pass++, console.log('  PASS  ' + name))
  : (fail++, console.log('  FAIL  ' + name + (detail ? '  → ' + detail : '')));

console.log('\nElement 10 — invIdemKey (M3)\n');

T('convention shape',            invIdemKey('reservation', 'show1', 'itemA') === 'reservation:shared:show1:itemA');
T('nonce appended',              invIdemKey('sale', 'i9', 'i9', 'n3') === 'sale:shared:i9:i9:n3');
T('null entity -> empty',        invIdemKey('intake', null, 'i9') === 'intake:shared::i9');
T('null item -> empty',          invIdemKey('correction', 'i9', null) === 'correction:shared:i9:');
T('deterministic (same in=out)', invIdemKey('reservation', 's', 'i') === invIdemKey('reservation', 's', 'i'));
T('distinct events differ',      invIdemKey('reservation', 's', 'i', 'a') !== invIdemKey('reservation', 's', 'i', 'b'));
T('op distinguishes',            invIdemKey('reservation', 's', 'i') !== invIdemKey('reservation_release', 's', 'i'));
T('no nonce omits trailing sep', invIdemKey('intake', 'i', 'i').split(':').length === 4);
// M3.1 batch set-reservations: keyed by show (entity), empty item slot, per-action nonce.
T('set_reservations batch shape', invIdemKey('set_reservations', 'show9', '') === 'set_reservations:shared:show9:');
T('set_reservations batch nonce', invIdemKey('set_reservations', 'show9', '', 'n1') === 'set_reservations:shared:show9::n1');

console.log('\n  ' + pass + ' pass · ' + fail + ' fail\n');
process.exit(fail ? 1 : 0);
