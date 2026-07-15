// Element 10 — P1R persistence: the tri-state custom_name_override round-trips through the REAL RPC save
// path (e10_inv_add_item / e10_inv_edit_item), relational row `extra` and the canonical projection
// (e10_inv_get — post-M4 the blob no longer holds inventory) AGREE, an
// unrelated edit that omits the flag PRESERVES it (absent-in-patch ≠ cleared), and a type-switch
// p_remove_keys list reaches the RPC and sheds the structured key WITHOUT clearing its dual-field twin.
// Real supabase-js + JWT. Service-role teardown from finally. Credentials from env ONLY:
//   E10_MEMBER_EMAIL/PW  + E10_URL/SUPABASE_SERVICE_KEY/E10_CLEANUP_PROJECT_REF (for serviceCleanup).
//   Run: (source .env.local) node tests/genname_persist_test.js
const { createClient } = require('@supabase/supabase-js');
const { serviceCleanup } = require('./cleanup');
const { requireLocal } = require('./env');
const { url: URL, anon: ANON } = requireLocal('genname_persist_test'); // LOCAL by default; prod refused (mutating suite)
const MEMBER = process.env.E10_MEMBER_EMAIL, MEMBER_PW = process.env.E10_MEMBER_PW;
if (!MEMBER || !MEMBER_PW) { console.error('Set E10_MEMBER_EMAIL / E10_MEMBER_PW.'); process.exit(2); }

const rpc = (c, fn, a) => c.rpc(fn, a).then(r => r.error ? { ok: false, msg: r.error.message } : r.data);
let pass = 0, fail = 0;
const T = (n, ok, d) => ok ? (pass++, console.log('  PASS ' + n)) : (fail++, console.log('  FAIL ' + n + (d !== undefined ? '  → ' + JSON.stringify(d) : '')));

(async () => {
  const M = createClient(URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error: se } = await M.auth.signInWithPassword({ email: MEMBER, password: MEMBER_PW });
  if (se) { console.error('sign-in failed:', se.message); process.exit(2); }

  const PFX = 'zzgn' + Date.now().toString(36), ID = PFX + 'it';
  const manifest = { itemIds: [ID] };
  console.log('\nElement 10 — P1R persistence (item ' + ID + ')\n');

  // read helpers: relational row extra + the canonical projection (e10_inv_get — post-M4 the blob is gone)
  const rowExtra = async () => ((await M.from('e10_inventory_items').select('extra,card_set').eq('id', ID).maybeSingle()).data) || {};
  const getItem = async () => (await M.rpc('e10_inv_get', { p_id: ID })).data || {};

  try {
    // ── ADD in generated mode (custom_name_override:false) ──
    const add = await rpc(M, 'e10_inv_add_item', { p_item: { id: ID, name: '2026 Topps Chrome', qty: 3, cost: 2, cat: 'Box', inventory_type: 'sealed_product', product_line: 'Chrome', set: 'Chrome', manufacturer: 'Topps', product_year: '2026', custom_name_override: false }, p_idempotency_key: PFX + ':add' });
    T('add ok', add && add.ok === true, add);
    T('add: returned flag === false', add && add.item && add.item.custom_name_override === false, add && add.item);
    T('add: relational row extra flag === false', (await rowExtra()).extra && (await rowExtra()).extra.custom_name_override === false, await rowExtra());
    T('add: projection flag === false', (await getItem()).custom_name_override === false, await getItem());

    // ── EDIT → custom (true) round-trips ──
    const e1 = await rpc(M, 'e10_inv_edit_item', { p_id: ID, p_patch: { name: 'My custom name', custom_name_override: true }, p_remove_keys: [], p_idempotency_key: PFX + ':toTrue' });
    T('edit→true ok + returned true', e1 && e1.ok === true && e1.item && e1.item.custom_name_override === true, e1 && e1.item);
    T('edit→true: row + projection agree (true)', (await rowExtra()).extra.custom_name_override === true && (await getItem()).custom_name_override === true);

    // ── UNRELATED edit that OMITS the flag PRESERVES it (absent-in-patch ≠ cleared) ──
    const e2 = await rpc(M, 'e10_inv_edit_item', { p_id: ID, p_patch: { value: 9 }, p_remove_keys: [], p_idempotency_key: PFX + ':unrel' });
    T('unrelated edit ok', e2 && e2.ok === true, e2);
    T('unrelated edit PRESERVES flag (still true)', e2.item.custom_name_override === true && (await rowExtra()).extra.custom_name_override === true, e2.item);
    T('unrelated edit preserved the name', e2.item.name === 'My custom name', e2.item.name);

    // ── EDIT → generated (false) round-trips the other way ──
    const e3 = await rpc(M, 'e10_inv_edit_item', { p_id: ID, p_patch: { custom_name_override: false }, p_remove_keys: [], p_idempotency_key: PFX + ':toFalse' });
    T('edit→false: round-trips back to false', e3 && e3.ok === true && e3.item.custom_name_override === false && (await getItem()).custom_name_override === false, e3 && e3.item);

    // ── TYPE-SWITCH removal: p_remove_keys sheds structured keys; the dual-field twin (set) survives ──
    const e4 = await rpc(M, 'e10_inv_edit_item', { p_id: ID, p_patch: {}, p_remove_keys: ['manufacturer', 'product_line'], p_idempotency_key: PFX + ':switch' });
    T('type-switch removal ok', e4 && e4.ok === true, e4);
    const rx = await rowExtra();
    T('removed structured keys gone from extra', !(rx.extra && ('manufacturer' in rx.extra)) && !(rx.extra && ('product_line' in rx.extra)), rx.extra);
    T('dual-field twin preserved (set/card_set intact)', rx.card_set === 'Chrome', rx.card_set);
    T('flag untouched by the removal (still false)', rx.extra.custom_name_override === false, rx.extra);

    // ── reconciliation drift 0 for this item ──
    const drift = ((await M.from('e10_inventory_reserved_recon').select('item_id,drift').eq('item_id', ID)).data || []).filter(r => +r.drift !== 0).length;
    T('reserved-recon drift = 0 for the item', drift === 0, drift);
  } finally {
    let res, cerr;
    try { res = await serviceCleanup(manifest); } catch (e) { cerr = e; }
    T('teardown: service cleanup ran', !cerr, cerr && cerr.message);
    if (res) T('teardown: 0 residue (manifest-scoped)', res.clean, res.residue);
  }

  console.log('\n  ' + pass + ' pass · ' + fail + ' fail\n');
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(3); });
