// Element 10 — M3.2 / M3.2.1 regression test. Drives real supabase-js + PostgREST + JWT against the live
// RPCs with disposable admin + member. Covers item 4 (server-derived show ref + session-ownership +
// tamper rejection), consume-draws-the-show's-reservations, reverse reconstructs, and ad-hoc null draw.
// Credentials from the environment ONLY (no committed defaults):
//   E10_ADMIN_EMAIL/E10_ADMIN_PW, E10_MEMBER_EMAIL/E10_MEMBER_PW; optional E10_URL/E10_ANON.
//   Run: E10_ADMIN_EMAIL=… E10_ADMIN_PW=… E10_MEMBER_EMAIL=… E10_MEMBER_PW=… node tests/m32_test.js
// Client-side items 2 (no format→show inference) and 3 (LIVE_SEED lifecycle) are verified in the browser
// against the deployed bundle (see the build report) — they are not reachable from a node RPC test.
const { createClient } = require('@supabase/supabase-js');
const URL = process.env.E10_URL || 'https://ddhkkumiyidorzmajwde.supabase.co';
const ANON = process.env.E10_ANON || 'sb_publishable_wRoaFNiqpZJaEJkQvLpnUw_7bpcXllv';
const ADMIN = process.env.E10_ADMIN_EMAIL, ADMIN_PW = process.env.E10_ADMIN_PW;
const MEMBER = process.env.E10_MEMBER_EMAIL, MEMBER_PW = process.env.E10_MEMBER_PW;
if (!ADMIN || !ADMIN_PW || !MEMBER || !MEMBER_PW) { console.error('Set E10_ADMIN_EMAIL/PW and E10_MEMBER_EMAIL/PW.'); process.exit(2); }

function client() { return createClient(URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } }); }
async function signIn(e, p) { const c = client(); const { error } = await c.auth.signInWithPassword({ email: e, password: p }); if (error) throw new Error('signin ' + e + ': ' + error.message); return c; }
const rpc = (c, fn, a) => c.rpc(fn, a).then(r => r.error ? { ok: false, msg: r.error.message, _err: true } : r.data);
let pass = 0, fail = 0;
const T = (n, ok, d) => ok ? (pass++, console.log('  PASS ' + n)) : (fail++, console.log('  FAIL ' + n + (d !== undefined ? '  → ' + JSON.stringify(d) : '')));

(async () => {
  const A = await signIn(ADMIN, ADMIN_PW), M = await signIn(MEMBER, MEMBER_PW);
  const meUid = (await M.auth.getUser()).data.user.id;
  const admUid = (await A.auth.getUser()).data.user.id;
  const ID = 'zzm32' + Date.now().toString(36), SHOW = 'zzshow_' + Date.now().toString(36);
  console.log('\nElement 10 — M3.2.1 (item ' + ID + ', show ' + SHOW + ')\n');
  const sumRes = async () => ((await M.from('e10_inventory_reservations').select('qty').eq('item_id', ID).eq('show_ref', SHOW).eq('status', 'active')).data || []).reduce((s, x) => s + (+x.qty || 0), 0);

  const add = await rpc(M, 'e10_inv_add_item', { p_item: { id: ID, name: 'ZZ m32', qty: 8, cost: 2, cat: 'Box' }, p_idempotency_key: 'zzm32:add:' + ID });
  T('setup: member adds item', add && add.ok === true, add);
  await rpc(M, 'e10_inv_set_reservations', { p_show_ref: SHOW, p_show_label: 'ZZ Show', p_targets: [{ item_id: ID, qty: 5 }], p_idempotency_key: 'zzm32:res:' + ID });
  T('setup: reserved 5 to the show', (await sumRes()) === 5);

  // A session born from a show carries source_show_ref (explicit-launch stamp).
  const { data: sM, error: se1 } = await M.from('e10_break_sessions').insert({ streamer_uid: meUid, name: 'ZZ show session', source_show_ref: SHOW }).select().maybeSingle();
  T('explicit show launch stamps ref on session', !se1 && sM && sM.source_show_ref === SHOW, se1 || sM);

  // ITEM 4 — tamper: a non-null client ref that disagrees with the session is rejected.
  T('item4: tampered p_source_show_ref rejected', (await rpc(M, 'e10_inv_consume', { p_id: ID, p_break_session_id: sM.id, p_source_show_ref: 'zzWRONG', p_qty: 2, p_idempotency_key: 'zzm32:tamper:' + ID })).ok === false);
  T('item4: tamper left reservations intact (5)', (await sumRes()) === 5);

  // ITEM 4 — derive: null client ref → server value used → draws the show's reservations.
  const cons = await rpc(M, 'e10_inv_consume', { p_id: ID, p_break_session_id: sM.id, p_source_show_ref: null, p_qty: 3, p_idempotency_key: 'zzm32:consume:' + ID });
  T('item4: consume with null client ref uses the server value', cons && cons.ok === true, cons);
  T('consume drew the show reservation (5→2)', (await sumRes()) === 2);
  const mv = (await M.from('e10_inventory_movements').select('meta,reserved_delta').eq('idempotency_key', 'zzm32:consume:' + ID).single()).data;
  T('movement meta records the SERVER show ref + drawdown', mv && mv.meta && mv.meta.source_show_ref === SHOW && +mv.reserved_delta === -3, mv && mv.meta);

  // reverse reconstructs the reservation.
  const rev = await rpc(M, 'e10_inv_reverse_consumption', { p_id: ID, p_reverses_movement_id: cons.movement_id, p_idempotency_key: 'zzm32:reverse:' + ID });
  T('reverse ok', rev && rev.ok === true, rev);
  T('reverse reconstructed the reservation (→5)', (await sumRes()) === 5);

  // ITEM 4 — ownership: admin may consume a member's session (override); a member may not consume another's.
  const admCons = await rpc(A, 'e10_inv_consume', { p_id: ID, p_break_session_id: sM.id, p_source_show_ref: SHOW, p_qty: 1, p_idempotency_key: 'zzm32:admcons:' + ID });
  T('item4: admin may consume a member session (override)', admCons && admCons.ok === true, admCons);
  const { data: sA } = await A.from('e10_break_sessions').insert({ streamer_uid: admUid, name: 'ZZ adm session', source_show_ref: SHOW }).select().maybeSingle();
  T('item4: member cannot consume an admin-owned session', (await rpc(M, 'e10_inv_consume', { p_id: ID, p_break_session_id: sA.id, p_source_show_ref: null, p_qty: 1, p_idempotency_key: 'zzm32:foreign:' + ID })).ok === false);

  // Ad-hoc session (source_show_ref null) → unreserved draw, reservations untouched.
  const { data: sAd } = await M.from('e10_break_sessions').insert({ streamer_uid: meUid, name: 'ZZ adhoc', source_show_ref: null }).select().maybeSingle();
  const before = await sumRes();
  const adhoc = await rpc(M, 'e10_inv_consume', { p_id: ID, p_break_session_id: sAd.id, p_source_show_ref: null, p_qty: 1, p_idempotency_key: 'zzm32:adhoc:' + ID });
  T('ad-hoc consume ok', adhoc && adhoc.ok === true, adhoc);
  const adMv = (await M.from('e10_inventory_movements').select('reserved_delta').eq('idempotency_key', 'zzm32:adhoc:' + ID).single()).data;
  T('ad-hoc consume reserved_delta = 0', adMv && +adMv.reserved_delta === 0, adMv);
  T('ad-hoc left the show reservations untouched', (await sumRes()) === before);

  // teardown (rows + blob via RPC; sessions/ledger/receipts swept by SQL afterward).
  await rpc(M, 'e10_inv_delete_item', { p_id: ID, p_idempotency_key: 'zzm32:del:' + ID });
  await A.from('e10_break_sessions').delete().in('id', [sM.id, sA.id, sAd.id]);

  console.log('\n  ' + pass + ' pass · ' + fail + ' fail\n');
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(3); });
