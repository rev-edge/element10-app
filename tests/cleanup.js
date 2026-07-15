// Element 10 — service-role test teardown (Chain P — P0R).
// Replaces the dropped e10_test_cleanup RPC. Runs OFF the app's RLS surface with the service key, and
// deletes ONLY the exact identifiers in a per-run manifest — never a blanket zz% sweep, never real history.
//
// Credentials from the environment ONLY (no production defaults):
//   E10_URL                    — project URL (its ref must match E10_CLEANUP_PROJECT_REF)
//   SUPABASE_SERVICE_KEY       — service-role key (never printed)
//   E10_CLEANUP_PROJECT_REF    — the project ref this cleanup is allowed to touch
//
// Manifest shape (all optional; every id is namespace-guarded before any delete):
//   { itemIds:[], idempotencyKeys:[], sessionIds:[], showIds:[], workspaceId:'shared'|'user:<uuid>' }
//
// Usage from a test:  const { serviceCleanup } = require('./cleanup');  await serviceCleanup(manifest);
// Standalone:         node tests/cleanup.js path/to/manifest.json   (exit non-zero unless residue is 0)
const { createClient } = require('@supabase/supabase-js');

const TEST_NS = /^zz/;                                  // items / shows / idempotency keys live in the zz namespace
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function projRefFromUrl(u) { const m = /^https?:\/\/([a-z0-9]+)\.supabase\.co/i.exec(u || ''); return m && m[1]; }

async function serviceCleanup(manifest) {
  manifest = manifest || {};
  // LOCAL by default (env.js). Teardown DELETES rows, so it refuses production outright — mutating suites
  // run against the local stack, so their teardown does too.
  const { target } = require('./env');
  const t = target();
  if (t.isProd) throw new Error('serviceCleanup refuses to run against PRODUCTION (it deletes rows). Run mutating suites against the local stack.');
  const URL = t.url;
  const KEY = t.serviceKey || process.env.SUPABASE_SERVICE_KEY;
  if (!KEY) throw new Error('serviceCleanup: no service key for the local stack (is it up? `supabase start`).');

  const itemIds = [...new Set(manifest.itemIds || [])];
  const keys = [...new Set(manifest.idempotencyKeys || [])];
  const sessionIds = [...new Set(manifest.sessionIds || [])];
  const showIds = [...new Set(manifest.showIds || [])];
  const workspaceId = manifest.workspaceId || null;

  // Namespace guards — refuse anything outside the test namespace BEFORE touching the DB.
  // (Trent's real iS02 movements / sh17840… show never match /^zz/, so they can never be targeted.)
  for (const id of itemIds) if (!TEST_NS.test(id)) throw new Error('refuse non-test item id: ' + id);
  for (const k of keys) if (!TEST_NS.test(k)) throw new Error('refuse non-test idempotency key: ' + k);
  for (const s of showIds) if (typeof s !== 'string' || !s) throw new Error('refuse empty show id');
  for (const sid of sessionIds) if (!UUID.test(sid)) throw new Error('refuse non-uuid session id: ' + sid);
  if (workspaceId && workspaceId !== 'shared' && !/^user:/.test(workspaceId)) throw new Error('refuse workspace id: ' + workspaceId);

  const svc = createClient(URL, KEY, { auth: { persistSession: false, autoRefreshToken: false } });

  // Children first (movements / receipts / reservations reference item_id), then items, then sessions.
  if (itemIds.length) {
    await svc.from('e10_inventory_movements').delete().in('item_id', itemIds);
    await svc.from('e10_mutation_receipts').delete().in('item_id', itemIds);
    await svc.from('e10_inventory_reservations').delete().in('item_id', itemIds);
  }
  if (keys.length) {
    await svc.from('e10_inventory_movements').delete().in('idempotency_key', keys);
    await svc.from('e10_mutation_receipts').delete().in('idempotency_key', keys);
  }
  if (itemIds.length) await svc.from('e10_inventory_items').delete().in('id', itemIds);
  if (sessionIds.length) await svc.from('e10_break_sessions').delete().in('id', sessionIds);

  // The shared blob still mirrors inventory (until M4) — strip manifested items from it.
  if (itemIds.length) {
    const { data: w } = await svc.from('e10_workspace').select('data,rev').eq('id', 'shared').maybeSingle();
    if (w && w.data && Array.isArray(w.data.inventory)) {
      const kept = w.data.inventory.filter(it => !(it && itemIds.includes(it.id)));
      if (kept.length !== w.data.inventory.length) {
        w.data.inventory = kept;
        await svc.from('e10_workspace').update({ data: w.data, rev: (w.rev || 0) + 1 }).eq('id', 'shared');
      }
    }
  }
  // Shows are scoped to a member workspace (never the shared blob). Test shows carry app-generated
  // 'sh…' ids indistinguishable from real ones, so the safety boundary is the 'ZZ ' name marker every
  // test show uses — a show is removed only when its id is manifested AND its name starts with 'ZZ '.
  const isTestShow = s => s && showIds.includes(s.id) && /^ZZ /.test(s.name || '');
  if (showIds.length && workspaceId) {
    const { data: w } = await svc.from('e10_workspace').select('data,rev').eq('id', workspaceId).maybeSingle();
    if (w && w.data && w.data.shows) {
      const sh = w.data.shows; let changed = false;
      for (const k of Object.keys(sh)) {
        const arr = (sh[k] || []).filter(s => !isTestShow(s));
        if (arr.length !== (sh[k] || []).length) changed = true;
        if (arr.length) sh[k] = arr; else delete sh[k];
      }
      if (changed) await svc.from('e10_workspace').update({ data: w.data, rev: (w.rev || 0) + 1 }).eq('id', workspaceId);
    }
  }

  // Residue check — the exact manifest, nothing broader.
  const residue = {};
  if (itemIds.length) {
    residue.items = ((await svc.from('e10_inventory_items').select('id').in('id', itemIds)).data || []).length;
    residue.movements = ((await svc.from('e10_inventory_movements').select('id').in('item_id', itemIds)).data || []).length;
    residue.receipts = ((await svc.from('e10_mutation_receipts').select('idempotency_key').in('item_id', itemIds)).data || []).length;
    residue.reservations = ((await svc.from('e10_inventory_reservations').select('id').in('item_id', itemIds)).data || []).length;
    const { data: w } = await svc.from('e10_workspace').select('data').eq('id', 'shared').maybeSingle();
    residue.blob_items = ((w && w.data && w.data.inventory) || []).filter(it => it && itemIds.includes(it.id)).length;
  }
  if (keys.length) {
    residue.movements_by_key = ((await svc.from('e10_inventory_movements').select('id').in('idempotency_key', keys)).data || []).length;
    // set_reservations writes a receipt with item_id = null, catchable ONLY by key — verify it too.
    residue.receipts_by_key = ((await svc.from('e10_mutation_receipts').select('idempotency_key').in('idempotency_key', keys)).data || []).length;
  }
  if (sessionIds.length) residue.sessions = ((await svc.from('e10_break_sessions').select('id').in('id', sessionIds)).data || []).length;
  if (showIds.length && workspaceId) {
    const { data: w } = await svc.from('e10_workspace').select('data').eq('id', workspaceId).maybeSingle();
    const shows = (w && w.data && w.data.shows) || {};
    residue.shows = Object.keys(shows).reduce((n, k) => n + (shows[k] || []).filter(isTestShow).length, 0);
  }

  const total = Object.values(residue).reduce((s, v) => s + v, 0);
  return { residue, clean: total === 0 };
}

module.exports = { serviceCleanup, projRefFromUrl };

// Standalone: node tests/cleanup.js <manifest.json>
if (require.main === module) {
  const fs = require('fs');
  const p = process.argv[2];
  if (!p) { console.error('usage: node tests/cleanup.js <manifest.json>'); process.exit(2); }
  const manifest = JSON.parse(fs.readFileSync(p, 'utf8'));
  serviceCleanup(manifest)
    .then(r => { console.log('cleanup residue:', JSON.stringify(r.residue)); process.exit(r.clean ? 0 : 1); })
    .catch(e => { console.error('cleanup failed:', e.message); process.exit(3); });
}
