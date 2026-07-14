// Element 10 — inventory GATE. Asserts the production baseline is intact after an inventory pass:
// 35 items / 223 on-hand / $29,486 capital, ledger 35 openings summing 223/21, reserved-recon drift 0.
// Reads through REAL member RLS via supabase-js (not a service key). Exit non-zero on any HARD failure.
//   Credentials come from the environment ONLY (no committed defaults):
//     E10_GATE_EMAIL / E10_GATE_PW  — the standing gate member (provisioned once, permanent).
//     E10_URL / E10_ANON            — optional; default to the app's public project URL + publishable key.
//   Run: E10_GATE_EMAIL=… E10_GATE_PW=… node tests/verify_inventory.js
const { createClient } = require('@supabase/supabase-js');
const URL = process.env.E10_URL || 'https://ddhkkumiyidorzmajwde.supabase.co';
const ANON = process.env.E10_ANON || 'sb_publishable_wRoaFNiqpZJaEJkQvLpnUw_7bpcXllv';
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

  const { data: mv } = await c.from('e10_inventory_movements').select('movement_type,on_hand_delta,reserved_delta');
  const oh = mv.reduce((s, m) => s + (+m.on_hand_delta || 0), 0);
  const rd = mv.reduce((s, m) => s + (+m.reserved_delta || 0), 0);
  const openings = mv.filter(m => m.movement_type === 'opening_balance').length;
  H('ledger on_hand sum = 223', oh === 223, 'got ' + oh);
  H('ledger reserved sum = 21', rd === 21, 'got ' + rd);
  H('opening_balance rows = 35', openings === 35, 'got ' + openings);

  const { data: rec } = await c.from('e10_inventory_reserved_recon').select('drift');
  const drift = rec.filter(r => +r.drift !== 0).length;
  H('reserved-recon drift = 0', drift === 0, drift + ' drifting item(s)');

  console.log('\n  ' + (hard ? ('GATE FAIL — ' + hard + ' HARD') : 'GATE PASS — 0 HARD') + '\n');
  process.exit(hard ? 1 : 0);
})().catch(e => { console.error(e); process.exit(3); });
