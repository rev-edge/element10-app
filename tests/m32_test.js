// Element 10 — M3.2 / M3.2.1 / M3.2.2 regression test. Real supabase-js + PostgREST + JWT against the live
// RPCs. Covers: item 1 (unknown-session reject / null bypass / owned draw), item 2 (reverse ownership),
// plus M3.2.1 derive/validate/tamper, consume-draws, reverse-reconstructs, ad-hoc null draw.
// SELF-CONTAINED teardown via the e10_test_cleanup helper (removes its own ledger rows + receipts, which
// are otherwise append-only / client-undeletable) — no external SQL sweep. Credentials from env ONLY:
//   E10_ADMIN_EMAIL/PW (admin), E10_MEMBER_EMAIL/PW (member A / owner), E10_GATE_EMAIL/PW (member B).
//   Run: (source .env.local) node tests/m32_test.js
const { createClient } = require('@supabase/supabase-js');
const { serviceCleanup } = require('./cleanup');
const URL = process.env.E10_URL || 'https://ddhkkumiyidorzmajwde.supabase.co';
const ANON = process.env.E10_ANON || 'sb_publishable_wRoaFNiqpZJaEJkQvLpnUw_7bpcXllv';
const ADMIN = process.env.E10_ADMIN_EMAIL, ADMIN_PW = process.env.E10_ADMIN_PW;
const MEMBER = process.env.E10_MEMBER_EMAIL, MEMBER_PW = process.env.E10_MEMBER_PW;
const MEMBER2 = process.env.E10_GATE_EMAIL, MEMBER2_PW = process.env.E10_GATE_PW;   // second member (non-owner)
if (!ADMIN || !ADMIN_PW || !MEMBER || !MEMBER_PW || !MEMBER2 || !MEMBER2_PW) {
  console.error('Set E10_ADMIN_EMAIL/PW, E10_MEMBER_EMAIL/PW and E10_GATE_EMAIL/PW.'); process.exit(2);
}
function client() { return createClient(URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } }); }
async function signIn(e, p) { const c = client(); const { error } = await c.auth.signInWithPassword({ email: e, password: p }); if (error) throw new Error('signin ' + e + ': ' + error.message); return c; }
const rpc = (c, fn, a) => c.rpc(fn, a).then(r => r.error ? { ok: false, msg: r.error.message, _err: true } : r.data);
let pass = 0, fail = 0;
const T = (n, ok, d) => ok ? (pass++, console.log('  PASS ' + n)) : (fail++, console.log('  FAIL ' + n + (d !== undefined ? '  → ' + JSON.stringify(d) : '')));

(async () => {
  const A = await signIn(ADMIN, ADMIN_PW), M = await signIn(MEMBER, MEMBER_PW), B = await signIn(MEMBER2, MEMBER2_PW);
  const meUid = (await M.auth.getUser()).data.user.id;
  const admUid = (await A.auth.getUser()).data.user.id;
  const PFX = 'zzm32' + Date.now().toString(36);           // per-run test namespace (>=4, starts 'zz')
  const ID = PFX + 'it', SHOW = PFX + 'sh';
  const sessIds = [];
  console.log('\nElement 10 — M3.2.2 (prefix ' + PFX + ')\n');
  const sumRes = async () => ((await M.from('e10_inventory_reservations').select('qty').eq('item_id', ID).eq('show_ref', SHOW).eq('status', 'active')).data || []).reduce((s, x) => s + (+x.qty || 0), 0);
  const mkSession = async (cli, uid, ref) => { const { data } = await cli.from('e10_break_sessions').insert({ streamer_uid: uid, name: 'ZZ ' + PFX, source_show_ref: ref }).select().maybeSingle(); if (data) sessIds.push(data.id); return data; };
  // set_reservations writes a receipt with item_id = null (a batch op) — item-scoped cleanup can't catch it,
  // so the manifest must carry that key explicitly.
  const manifest = { itemIds: [ID], sessionIds: sessIds, idempotencyKeys: [PFX + ':res'] };   // sessIds mutated in-place

  try {
  const add = await rpc(M, 'e10_inv_add_item', { p_item: { id: ID, name: 'ZZ m32', qty: 10, cost: 2, cat: 'Box' }, p_idempotency_key: PFX + ':add' });
  T('setup: member adds item', add && add.ok === true, add);
  await rpc(M, 'e10_inv_set_reservations', { p_show_ref: SHOW, p_show_label: 'ZZ Show', p_targets: [{ item_id: ID, qty: 5 }], p_idempotency_key: PFX + ':res' });
  T('setup: reserved 5 to the show', (await sumRes()) === 5);
  const sM = await mkSession(M, meUid, SHOW);
  T('explicit show launch stamps ref on session', sM && sM.source_show_ref === SHOW, sM);

  // ── ITEM 1 ──
  T('item1: well-formed UUID with no session → rejected', (await rpc(M, 'e10_inv_consume', { p_id: ID, p_break_session_id: '11111111-2222-3333-4444-555555555555', p_source_show_ref: null, p_qty: 1, p_idempotency_key: PFX + ':unknown' })).ok === false);
  T('item1: unknown-session left reservations intact (5)', (await sumRes()) === 5);
  const nul = await rpc(M, 'e10_inv_consume', { p_id: ID, p_break_session_id: null, p_source_show_ref: null, p_qty: 1, p_idempotency_key: PFX + ':null' });
  T('item1: null session → unreserved draw ok', nul && nul.ok === true, nul);
  const nulMv = (await M.from('e10_inventory_movements').select('reserved_delta').eq('idempotency_key', PFX + ':null').single()).data;
  T('item1: null session reserved_delta 0', nulMv && +nulMv.reserved_delta === 0, nulMv);

  // ── M3.2.1 tamper + derive ──
  T('tampered p_source_show_ref rejected', (await rpc(M, 'e10_inv_consume', { p_id: ID, p_break_session_id: sM.id, p_source_show_ref: 'zzWRONG', p_qty: 2, p_idempotency_key: PFX + ':tamper' })).ok === false);
  const cons = await rpc(M, 'e10_inv_consume', { p_id: ID, p_break_session_id: sM.id, p_source_show_ref: null, p_qty: 3, p_idempotency_key: PFX + ':consume' });
  T('owned session consume (null client ref uses server value)', cons && cons.ok === true, cons);
  T('consume drew the show reservation (5→2)', (await sumRes()) === 2);
  const mv = (await M.from('e10_inventory_movements').select('meta').eq('idempotency_key', PFX + ':consume').single()).data;
  T('meta records server show ref', mv && mv.meta && mv.meta.source_show_ref === SHOW, mv && mv.meta);

  // ── ITEM 2 (reverse ownership) ──
  T('item2: member B cannot reverse member A consumption', (await rpc(B, 'e10_inv_reverse_consumption', { p_id: ID, p_reverses_movement_id: cons.movement_id, p_idempotency_key: PFX + ':revB' })).ok === false);
  T('item2: reservation still drawn after rejected reverse (2)', (await sumRes()) === 2);
  const revA = await rpc(M, 'e10_inv_reverse_consumption', { p_id: ID, p_reverses_movement_id: cons.movement_id, p_idempotency_key: PFX + ':revA' });
  T('item2: owner (member A) can reverse own', revA && revA.ok === true, revA);
  T('reverse reconstructed the reservation (→5)', (await sumRes()) === 5);

  // ── ownership (consume) + admin override ──
  const admCons = await rpc(A, 'e10_inv_consume', { p_id: ID, p_break_session_id: sM.id, p_source_show_ref: SHOW, p_qty: 1, p_idempotency_key: PFX + ':admcons' });
  T('admin may consume a member session (override)', admCons && admCons.ok === true, admCons);
  const sAdm = await mkSession(A, admUid, SHOW);
  T('member cannot consume an admin-owned session', (await rpc(M, 'e10_inv_consume', { p_id: ID, p_break_session_id: sAdm.id, p_source_show_ref: null, p_qty: 1, p_idempotency_key: PFX + ':foreign' })).ok === false);

  // ── ad-hoc (null source_show_ref) ──
  const sAd = await mkSession(M, meUid, null);
  const before = await sumRes();
  const adhoc = await rpc(M, 'e10_inv_consume', { p_id: ID, p_break_session_id: sAd.id, p_source_show_ref: null, p_qty: 1, p_idempotency_key: PFX + ':adhoc' });
  T('ad-hoc consume ok', adhoc && adhoc.ok === true, adhoc);
  const adMv = (await M.from('e10_inventory_movements').select('reserved_delta').eq('idempotency_key', PFX + ':adhoc').single()).data;
  T('ad-hoc reserved_delta 0 + reservations untouched', adMv && +adMv.reserved_delta === 0 && (await sumRes()) === before, adMv);

  } finally {
    // Service-role teardown (manifest-scoped): item rows + their movements/receipts/reservations + the
    // break sessions this run created. Runs even after an assertion or exception in the body.
    let res, cerr;
    try { res = await serviceCleanup(manifest); } catch (e) { cerr = e; }
    T('teardown: service cleanup ran', !cerr, cerr && cerr.message);
    if (res) T('teardown: 0 residue (items / movements / sessions)', res.clean, res.residue);
  }

  console.log('\n  ' + pass + ' pass · ' + fail + ' fail\n');
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(3); });
