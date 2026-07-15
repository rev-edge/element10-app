// Element 10 — inventory GATE. Asserts the production baseline is intact after an inventory pass:
// 35 items / 223 on-hand / $29,486 capital (operational), the LEDGER reconciles to operational state
// (ledger-derived on-hand/reserved == operational; NOT a fixed sum), and reserved-recon drift 0.
// Reconciliation baseline (Chain P — P0R, agreed with Trent): the gate no longer expects an opening-only
// ledger. Legitimate reservation/consumption/reversal traffic adds non-opening movements and is EXPECTED;
// the gate proves those movements reconcile rather than pinning a fixed ledger sum. If real usage changes
// the OPERATIONAL baseline (an item consumed and not reversed, an item added), that is legitimate but the
// 35/223/$29,486 line re-baselines only with Trent's explicit written agreement — never to silence a fail.
// Reads through REAL member RLS via supabase-js (not a service key). Exit non-zero on any HARD failure.
//   Credentials come from the environment ONLY (no committed defaults):
//     E10_GATE_EMAIL / E10_GATE_PW  — the standing gate member (provisioned once, permanent).
//     E10_URL / E10_ANON            — optional; default to the app's public project URL + publishable key.
//   Run: E10_GATE_EMAIL=… E10_GATE_PW=… node tests/verify_inventory.js
const { createClient } = require('@supabase/supabase-js');
const { target } = require('./env');
// The gate verifies the PRODUCTION baseline (35/223/$29,486) read-only. It is the ONE suite allowed
// against prod — and ONLY against prod (E10_ALLOW_PROD=1 + E10_ANON). Local has different data.
const _t = target();
if (!_t.isProd) { console.error('verify_inventory checks the PRODUCTION baseline — run with E10_ALLOW_PROD=1 and E10_ANON set (read-only).'); process.exit(2); }
const URL = _t.url, ANON = _t.anon;
const EMAIL = process.env.E10_GATE_EMAIL;
const PW = process.env.E10_GATE_PW;
if (!EMAIL || !PW) { console.error('Set E10_GATE_EMAIL and E10_GATE_PW (the standing gate member) in the environment.'); process.exit(2); }

(async () => {
  const c = createClient(URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error: se } = await c.auth.signInWithPassword({ email: EMAIL, password: PW });
  if (se) { console.error('sign-in failed:', se.message); process.exit(2); }

  let hard = 0;
  const H = (n, ok, d) => ok ? console.log('  HARD ok   ' + n)
                             : (hard++, console.log('  HARD FAIL ' + n + (d ? '  → ' + d : '')));

  const { data: items, error: ie } = await c.from('e10_inventory_items').select('qty,cost');
  if (ie) { console.error('read items failed:', ie.message); process.exit(2); }
  const n = items.length;
  const onhand = items.reduce((s, x) => s + (+x.qty || 0), 0);
  const capital = Math.round(items.reduce((s, x) => s + ((+x.qty || 0) * (+x.cost || 0)), 0));
  H('items count = 35', n === 35, 'got ' + n);
  H('on-hand sum = 223', onhand === 223, 'got ' + onhand);
  H('capital = $29,486', capital === 29486, 'got ' + capital);

  // Operational reserved = sum of ACTIVE reservation qty — the reconciliation target for the ledger.
  const { data: resv } = await c.from('e10_inventory_reservations').select('qty,status');
  const opReserved = (resv || []).filter(r => r.status === 'active').reduce((s, r) => s + (+r.qty || 0), 0);

  const { data: mv } = await c.from('e10_inventory_movements').select('movement_type,on_hand_delta,reserved_delta');
  const ledgerOnHand = mv.reduce((s, m) => s + (+m.on_hand_delta || 0), 0);
  const ledgerReserved = mv.reduce((s, m) => s + (+m.reserved_delta || 0), 0);
  const openings = mv.filter(m => m.movement_type === 'opening_balance').length;
  const nonOpening = mv.length - openings;
  // RECONCILIATION (robust to legitimate operator traffic): ledger-derived totals must EQUAL current
  // operational state, not a fixed number. Non-opening movements are expected, not a failure.
  H('ledger on-hand reconciles to operational', ledgerOnHand === onhand, 'ledger ' + ledgerOnHand + ' vs op ' + onhand);
  H('ledger reserved reconciles to operational', ledgerReserved === opReserved, 'ledger ' + ledgerReserved + ' vs op ' + opReserved);
  H('opening_balance rows = 35 (one per item)', openings === 35, 'got ' + openings);
  console.log('  info      non-opening movements = ' + nonOpening + ' (real operator traffic; expected)');

  const { data: rec } = await c.from('e10_inventory_reserved_recon').select('drift');
  const drift = rec.filter(r => +r.drift !== 0).length;
  H('reserved-recon drift = 0', drift === 0, drift + ' drifting item(s)');

  console.log('\n  ' + (hard ? ('GATE FAIL — ' + hard + ' HARD') : 'GATE PASS — 0 HARD') + '\n');
  process.exit(hard ? 1 : 0);
})().catch(e => { console.error(e); process.exit(3); });
