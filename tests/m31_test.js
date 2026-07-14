// Element 10 — M3.1 mutation-hardening integration test. Drives the REAL supabase-js client + PostgREST
// + JWT auth against the live RPCs, using disposable admin A (m31a) + member B (m31b), password Test!23456.
// Covers: adversarial direct-RPC rejections (b6/b3/b7), foreign-release rejection (b2), the CONCURRENT
// same-key test (b3 — sequential-only is insufficient), and mid-batch failure atomicity (b4).
// Creates its own throwaway items and deletes them; a follow-up SQL sweep clears their ledger rows/receipts.
//   Run: node tests/m31_test.js
const { createClient } = require('@supabase/supabase-js');
const URL = 'https://ddhkkumiyidorzmajwde.supabase.co';
const ANON = 'sb_publishable_wRoaFNiqpZJaEJkQvLpnUw_7bpcXllv';
const PW = 'Test!23456';

function client() { return createClient(URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } }); }
async function signIn(email) { const c = client(); const { error } = await c.auth.signInWithPassword({ email, password: PW }); if (error) throw new Error('signin ' + email + ': ' + error.message); return c; }
const rpc = (c, fn, args) => c.rpc(fn, args).then(r => r.error ? { ok: false, msg: r.error.message, _err: true } : r.data);

let pass = 0, fail = 0;
const T = (n, ok, d) => ok ? (pass++, console.log('  PASS ' + n)) : (fail++, console.log('  FAIL ' + n + (d !== undefined ? '  → ' + JSON.stringify(d) : '')));

(async () => {
  const A = await signIn('m31a@example.com'), B = await signIn('m31b@example.com');
  const ID = 'zznode' + Date.now().toString(36), IDx = ID + 'x';
  console.log('\nElement 10 — M3.1 hardening (item ' + ID + ')\n');

  const add = await rpc(A, 'e10_inv_add_item', { p_item: { id: ID, name: 'ZZ node', qty: 10, cost: 2, cat: 'Box' }, p_idempotency_key: 'zznode:add:' + ID });
  T('setup add ok', add && add.ok === true, add);

  // ---- Adversarial (member B, direct RPC): every call rejected, zero mutation ----
  T('b6 negative-qty edit rejected',   (await rpc(B, 'e10_inv_edit_item', { p_id: ID, p_patch: { qty: -3 }, p_remove_keys: [], p_idempotency_key: 'zznode:neg:' + ID })).ok === false);
  T('b6 consume-past-zero rejected',   (await rpc(B, 'e10_inv_consume', { p_id: ID, p_break_session_id: 's', p_source_show_ref: null, p_qty: 9999, p_idempotency_key: 'zznode:cpz:' + ID })).ok === false);
  T('b6 negative-cost rejected',       (await rpc(B, 'e10_inv_edit_item', { p_id: ID, p_patch: { cost: -1 }, p_remove_keys: [], p_idempotency_key: 'zznode:negc:' + ID })).ok === false);
  T('b3 missing key rejected',         (await rpc(B, 'e10_inv_edit_item', { p_id: ID, p_patch: { name: 'x' }, p_remove_keys: [], p_idempotency_key: '' })).ok === false);
  T('b7 forbidden remove-key rejected',(await rpc(B, 'e10_inv_edit_item', { p_id: ID, p_patch: {}, p_remove_keys: ['qty'], p_idempotency_key: 'zznode:rmq:' + ID })).ok === false);
  T('b6 garbage numeric rejected',     (await rpc(B, 'e10_inv_edit_item', { p_id: ID, p_patch: { cost: 'abc' }, p_remove_keys: [], p_idempotency_key: 'zznode:gar:' + ID })).ok === false);
  T('b3 key-reuse altered-args rejected', (await rpc(B, 'e10_inv_edit_item', { p_id: ID, p_patch: { name: 'hack' }, p_remove_keys: [], p_idempotency_key: 'zznode:add:' + ID })).ok === false);

  // ---- Blocker 2: A reserves; B cannot release A's; B can release its own ----
  await rpc(A, 'e10_inv_reserve', { p_id: ID, p_show_ref: 'showX', p_show_label: 'Show X', p_qty: 2, p_idempotency_key: 'zznode:resA:' + ID });
  T('b2 member B cannot release A reservation', (await rpc(B, 'e10_inv_release', { p_id: ID, p_show_ref: 'showX', p_idempotency_key: 'zznode:brel:' + ID })).ok === false);
  await rpc(B, 'e10_inv_reserve', { p_id: ID, p_show_ref: 'showB', p_show_label: 'Show B', p_qty: 1, p_idempotency_key: 'zznode:resB:' + ID });
  T('b2 member B can release own reservation', (await rpc(B, 'e10_inv_release', { p_id: ID, p_show_ref: 'showB', p_idempotency_key: 'zznode:brelown:' + ID })).ok === true);

  const it1 = (await A.from('e10_inventory_items').select('qty').eq('id', ID).single()).data;
  T('adversarial left qty intact (10)', +it1.qty === 10, it1);

  // ---- Blocker 3 CONCURRENT: two simultaneous identical edits, SAME key ----
  const KEY = 'zznode:concur:' + ID;
  const [c1, c2] = await Promise.all([
    rpc(A, 'e10_inv_edit_item', { p_id: ID, p_patch: { qty: 7 }, p_remove_keys: [], p_idempotency_key: KEY }),
    rpc(A, 'e10_inv_edit_item', { p_id: ID, p_patch: { qty: 7 }, p_remove_keys: [], p_idempotency_key: KEY }),
  ]);
  T('b3 concurrent: both callers succeed', c1.ok === true && c2.ok === true, { c1, c2 });
  const it2 = (await A.from('e10_inventory_items').select('qty').eq('id', ID).single()).data;
  T('b3 concurrent: qty applied once (=7)', +it2.qty === 7, it2);
  const mvK = (await A.from('e10_inventory_movements').select('id').eq('idempotency_key', KEY)).data;
  T('b3 concurrent: exactly one movement for the key', mvK.length === 1, mvK.length);
  const rcK = (await A.from('e10_inventory_movements').select('idempotency_key').eq('idempotency_key', KEY)).data;
  T('b3 concurrent: single logical op', rcK.length === 1, rcK.length);

  // ---- Blocker 4 mid-batch failure atomicity ----
  await rpc(A, 'e10_inv_add_item', { p_item: { id: IDx, name: 'ZZx', qty: 3, cost: 1, cat: 'Box' }, p_idempotency_key: 'zznode:addx:' + ID });
  const sumRes = async id => ((await A.from('e10_inventory_reservations').select('qty').eq('item_id', id).eq('status', 'active')).data || []).reduce((s, x) => s + (+x.qty || 0), 0);
  const before = await sumRes(IDx);
  const batch = await rpc(A, 'e10_inv_set_reservations', { p_show_ref: 'batchShow', p_show_label: 'B', p_targets: [{ item_id: IDx, qty: 2 }, { item_id: ID, qty: 9999 }], p_idempotency_key: 'zznode:batch:' + ID });
  T('b4 mid-batch failure rejected (names item)', batch.ok === false && /zznode/.test(batch.msg || ''), batch);
  const after = await sumRes(IDx);
  T('b4 mid-batch: zero mutation on the passing item', before === after, { before, after });

  // ---- teardown (rows + blob via RPC; ledger/receipts cleared by the SQL sweep afterward) ----
  await rpc(A, 'e10_inv_delete_item', { p_id: ID, p_idempotency_key: 'zznode:del:' + ID });
  await rpc(A, 'e10_inv_delete_item', { p_id: IDx, p_idempotency_key: 'zznode:delx:' + ID });

  console.log('\n  ' + pass + ' pass · ' + fail + ' fail\n');
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(3); });
