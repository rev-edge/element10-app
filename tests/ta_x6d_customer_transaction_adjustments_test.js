const { Client } = require('pg');
const { randomUUID } = require('crypto');

const db = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const org = 'e1000000-0000-4000-8000-0000000000a6';
const run = randomUUID();
const ids = { user: randomUUID(), role: randomUUID(), customer: randomUUID(), otherOrg: randomUUID(), otherUser: randomUUID(), otherRole: randomUUID(), otherCustomer: randomUUID() };
const bounded = (p, ms = 8000) => Promise.race([
  p,
  new Promise((_, reject) => setTimeout(() => reject(new Error(`X6d adjustment timeout after ${ms}ms`)), ms)),
]);

function args(tx, line, suffix, kind, effect, merchandise, shipping, tax, sourceEvent = suffix, currency = 'CAD', reinstates = null, sourceComponent = suffix) {
  return [org, tx, line, kind, effect, currency, merchandise, shipping, tax,
    '2026-01-03T00:00:00Z', 'exact', `reviewed ${suffix}`, 'manual', null,
    `${run}-${sourceEvent}`, `${run}-${sourceComponent}`, reinstates, JSON.stringify({ review: suffix }), `${run}-${suffix}`];
}

async function main() {
  const admin = new Client({ connectionString: db });
  const a = new Client({ connectionString: db });
  const b = new Client({ connectionString: db });
  await Promise.all([admin.connect(), a.connect(), b.connect()]);
  let tx; let line; let line2; let otherTx; let otherLine; let secondTx; let secondLine;
  const draftIds = [];
  try {
    const baselineGrants = (await admin.query("select count(*)::int n from public.e10_organization_role_permissions where capability='act.adjust_customer_transactions'")).rows[0].n;
    if (Number(baselineGrants) !== 0) throw new Error(`adjust capability received ${baselineGrants} default grants`);
    await admin.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())", [ids.user, `${run}@x.invalid`]);
    await admin.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X6d test',false)", [ids.role, org, run]);
    await admin.query("insert into public.e10_organization_role_permissions values($1,$2,'act.prepare_customer_transactions',true),($1,$2,'act.approve_customer_transactions',true),($1,$2,'act.post_customer_transactions',true),($1,$2,'act.adjust_customer_transactions',true),($1,$2,'act.manage_customers',true)", [org, ids.role]);
    await admin.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')", [org, ids.user, ids.role]);
    await admin.query("insert into public.e10_customers(id,organization_id,display_name) values($1,$2,'X6d Customer')", [ids.customer, org]);
    for (const c of [a, b]) {
      await c.query('select set_config($1,$2,false)', ['request.jwt.claims', JSON.stringify({ sub: ids.user, role: 'authenticated' })]);
      await c.query('set role authenticated');
    }

    const lines = [
      { purchase_kind: 'retail', capture_source: 'manual', source_line_id: `${run}-known`, quantity: 1, merchandise_gross: 30, merchandise_discount: 0, shipping_amount: 5, tax_amount: 3 },
      { purchase_kind: 'retail', capture_source: 'manual', source_line_id: `${run}-unknown`, quantity: 1, merchandise_gross: 20, merchandise_discount: 0, shipping_amount: null, tax_amount: null },
    ];
    const draft = (await a.query("select public.e10_org_create_customer_transaction_draft($1,$2,'CAD','2026-01-02T00:00:00Z','exact',$3,$4,$5) r", [org, ids.customer, `X6d ${run}`, JSON.stringify(lines), `${run}-draft`])).rows[0].r.draft_id;
    draftIds.push(draft);
    await a.query('select public.e10_org_approve_customer_transaction_draft($1,$2,1,$3)', [org, draft, `${run}-approve`]);
    tx = (await a.query('select public.e10_org_post_customer_transaction_draft($1,$2,1,$3) r', [org, draft, `${run}-post`])).rows[0].r.transaction_id;
    const postedLines = (await admin.query('select id,source_line_id from public.e10_customer_transaction_lines where transaction_id=$1 order by line_no', [tx])).rows;
    line = postedLines[0].id; line2 = postedLines[1].id;

    const secondDraft = (await a.query("select public.e10_org_create_customer_transaction_draft($1,$2,'CAD','2026-01-02T00:00:00Z','exact',$3,$4,$5) r", [org, ids.customer, `X6d ${run}`, JSON.stringify([{ purchase_kind: 'retail', capture_source: 'manual', source_line_id: `${run}-second`, quantity: 1, merchandise_gross: 2 }]), `${run}-second-draft`])).rows[0].r.draft_id;
    draftIds.push(secondDraft);
    await a.query('select public.e10_org_approve_customer_transaction_draft($1,$2,1,$3)', [org, secondDraft, `${run}-second-approve`]);
    secondTx = (await a.query('select public.e10_org_post_customer_transaction_draft($1,$2,1,$3) r', [org, secondDraft, `${run}-second-post`])).rows[0].r.transaction_id;
    secondLine = (await admin.query('select id from public.e10_customer_transaction_lines where transaction_id=$1', [secondTx])).rows[0].id;

    await admin.query("insert into public.e10_organizations(id,name,slug) values($1,'X6d Foreign',$2)", [ids.otherOrg, `x6d-${run}`]);
    await admin.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())", [ids.otherUser, `${ids.otherUser}@x.invalid`]);
    await admin.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X6d foreign role',false)", [ids.otherRole, ids.otherOrg, run]);
    await admin.query("insert into public.e10_organization_role_permissions values($1,$2,'act.prepare_customer_transactions',true),($1,$2,'act.approve_customer_transactions',true),($1,$2,'act.post_customer_transactions',true)", [ids.otherOrg, ids.otherRole]);
    await admin.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')", [ids.otherOrg, ids.otherUser, ids.otherRole]);
    await admin.query("insert into public.e10_customers(id,organization_id,display_name) values($1,$2,'X6d Foreign Customer')", [ids.otherCustomer, ids.otherOrg]);
    await b.query('reset role');
    await b.query('select set_config($1,$2,false)', ['request.jwt.claims', JSON.stringify({ sub: ids.otherUser, role: 'authenticated' })]);
    await b.query('set role authenticated');
    const foreignDraft = (await b.query("select public.e10_org_create_customer_transaction_draft($1,$2,'CAD','2026-01-02T00:00:00Z','exact',$3,$4,$5) r", [ids.otherOrg, ids.otherCustomer, `X6d ${run}`, JSON.stringify([{ purchase_kind: 'retail', capture_source: 'manual', source_line_id: `${run}-foreign`, quantity: 1, merchandise_gross: 7 }]), `${run}-foreign-draft`])).rows[0].r.draft_id;
    draftIds.push(foreignDraft);
    await b.query('select public.e10_org_approve_customer_transaction_draft($1,$2,1,$3)', [ids.otherOrg, foreignDraft, `${run}-foreign-approve`]);
    otherTx = (await b.query('select public.e10_org_post_customer_transaction_draft($1,$2,1,$3) r', [ids.otherOrg, foreignDraft, `${run}-foreign-post`])).rows[0].r.transaction_id;
    otherLine = (await admin.query('select id from public.e10_customer_transaction_lines where transaction_id=$1', [otherTx])).rows[0].id;
    await b.query('reset role');
    await b.query('select set_config($1,$2,false)', ['request.jwt.claims', JSON.stringify({ sub: ids.user, role: 'authenticated' })]);
    await b.query('set role authenticated');

    const call = 'select public.e10_org_adjust_customer_transaction($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18::jsonb,$19) r';
    const first = (await a.query(call, args(tx, line, 'partial', 'refund', 'decrease', 10, null, null))).rows[0].r;
    if (first.paid_changed || first.settlement_changed || first.inventory_returned) throw new Error('adjustment asserted payment, settlement, or inventory return');
    const replay = (await a.query(call, args(tx, line, 'partial', 'refund', 'decrease', 10, null, null))).rows[0].r;
    if (!replay.replay || replay.adjustment_id !== first.adjustment_id) throw new Error('exact retry did not replay original result');
    let denied = false;
    try { await a.query(call, args(tx, line, 'duplicate-source', 'refund', 'decrease', 10, null, null, 'partial', 'CAD', null, 'partial')); } catch (e) { denied = e.code === '23505' && e.message === 'adjustment_source_component_already_recorded'; }
    if (!denied) throw new Error('duplicate source component was accepted under a new idempotency key');
    await a.query(call, args(tx, line, 'upward', 'correction', 'increase', 5, null, null));
    await a.query(call, args(tx, line, 'downward', 'correction', 'decrease', 5, null, null));
    await a.query(call, args(tx, line2, 'shared-provider-line-2', 'refund', 'decrease', 1, null, null, 'provider-refund-multi-line'));
    await a.query(call, args(tx, line, 'shared-provider-line-1', 'refund', 'decrease', 1, null, null, 'provider-refund-multi-line'));

    denied = false;
    try { await a.query(call, args(tx, line2, 'unknown-component', 'refund', 'decrease', null, 1, null)); } catch (e) { denied = e.code === '22023' && e.message === 'adjustment_component_unknown'; }
    if (!denied) throw new Error('unknown monetary component was adjusted');
    denied = false;
    try { await a.query(call, args(tx, line, 'bad-currency', 'refund', 'decrease', 1, null, null, 'bad-currency', 'USD')); } catch (e) { denied = e.code === '22023' && e.message === 'adjustment_currency_mismatch'; }
    if (!denied) throw new Error('currency mismatch was accepted');

    const race = await bounded(Promise.allSettled([
      a.query(call, args(tx, line, 'race-a', 'refund', 'decrease', 15, null, null, 'shared-refund')),
      b.query(call, args(tx, line, 'race-b', 'refund', 'decrease', 15, null, null, 'shared-refund')),
    ]));
    if (race.filter(x => x.status === 'fulfilled').length !== 1 || race.filter(x => x.status === 'rejected' && x.reason.code === '22023').length !== 1) throw new Error(`over-refund race was not serialized: ${JSON.stringify(race)}`);

    const remaining = (await admin.query("select 30 + coalesce(sum(case effect when 'increase' then merchandise_amount else -merchandise_amount end),0) balance from public.e10_customer_transaction_adjustments where transaction_line_id=$1", [line])).rows[0].balance;
    if (Number(remaining) !== 4) throw new Error(`unexpected remaining merchandise balance ${remaining}`);
    const cancellations = await bounded(Promise.allSettled([
      a.query(call, args(tx, line, 'cancel-a', 'cancellation', 'decrease', 4, 5, 3, 'shared-cancel')),
      b.query(call, args(tx, line, 'cancel-b', 'cancellation', 'decrease', 4, 5, 3, 'shared-cancel')),
    ]));
    if (cancellations.filter(x => x.status === 'fulfilled').length !== 1 || cancellations.filter(x => x.status === 'rejected' && x.reason.code === '22023').length !== 1) throw new Error(`double cancellation was not serialized: ${JSON.stringify(cancellations)}`);
    const cancellationId = cancellations.find(x => x.status === 'fulfilled').value.rows[0].r.adjustment_id;
    denied = false;
    try { await a.query(call, args(tx, line, 'increase-without-reinstate', 'correction', 'increase', 1, null, null)); } catch (e) { denied = e.code === '22023' && e.message === 'cancelled_line_requires_explicit_reinstatement'; }
    if (!denied) throw new Error('ordinary increase revived a cancelled line');
    denied = false;
    try { await a.query(call, args(tx, line, 'fake-reinstate', 'correction', 'increase', 1, null, null, 'fake-reinstate', 'CAD', randomUUID())); } catch (e) { denied = e.code === '22023' && e.message === 'reinstatement_target_invalid'; }
    if (!denied) throw new Error('reinstatement without matching cancellation was accepted');
    const reinstatements = await bounded(Promise.allSettled([
      a.query(call, args(tx, line, 'reinstate-a', 'correction', 'increase', 1, null, null, 'shared-reinstate', 'CAD', cancellationId)),
      b.query(call, args(tx, line, 'reinstate-b', 'correction', 'increase', 1, null, null, 'shared-reinstate', 'CAD', cancellationId)),
    ]));
    if (reinstatements.filter(x => x.status === 'fulfilled').length !== 1 || reinstatements.filter(x => x.status === 'rejected' && x.reason.code === '22023').length !== 1) throw new Error(`same cancellation concurrent reinstatement failed ${JSON.stringify(reinstatements)}`);

    denied = false;
    try { await a.query(call, [ids.otherOrg, otherTx, otherLine, ...args(otherTx, otherLine, 'foreign-org', 'refund', 'decrease', 1, null, null).slice(3)]); } catch (e) { denied = e.code === '42501' && e.message === 'adjust_customer_transaction_denied'; }
    if (!denied) throw new Error('real foreign-org posted line was accepted');
    denied = false;
    try { await a.query(call, args(tx, otherLine, 'foreign-line-under-local-org', 'refund', 'decrease', 1, null, null)); } catch (e) { denied = e.code === '42501' && e.message === 'adjustment_line_denied'; }
    if (!denied) throw new Error('foreign line IDs were accepted under local org');
    denied = false;
    try { await a.query(call, args(tx, secondLine, 'wrong-transaction-line-pair', 'refund', 'decrease', 1, null, null)); } catch (e) { denied = e.code === '42501' && e.message === 'adjustment_line_denied'; }
    if (!denied) throw new Error('same-org mismatched transaction and line were accepted');
    await admin.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.adjust_customer_transactions'", [org, ids.role]);
    denied = false;
    try { await a.query(call, args(tx, line, 'missing-cap', 'correction', 'increase', 1, null, null)); } catch (e) { denied = e.code === '42501' && e.message === 'adjust_customer_transaction_denied'; }
    if (!denied) throw new Error('missing-capability adjustment was accepted');
    await admin.query("insert into public.e10_organization_role_permissions values($1,$2,'act.adjust_customer_transactions',true)", [org, ids.role]);

    const proof = (await admin.query("select count(*) filter(where a.commercial_event_id=e.id)::int linked,count(*)::int adjustments,count(distinct a.idempotency_key)::int idem from public.e10_customer_transaction_adjustments a join public.e10_commercial_events e on e.organization_id=a.organization_id and e.id=a.commercial_event_id and e.customer_transaction_adjustment_id=a.id where a.transaction_id=$1", [tx])).rows[0];
    if (proof.linked !== proof.adjustments || proof.adjustments !== proof.idem) throw new Error(`atomic adjustment/event proof failed ${JSON.stringify(proof)}`);
    const acl = (await admin.query("select has_function_privilege('anon',p.oid,'execute') anon,has_function_privilege('authenticated',p.oid,'execute') auth from pg_proc p where p.oid='public.e10_org_adjust_customer_transaction(uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,timestamptz,text,text,text,text,text,text,uuid,jsonb,text)'::regprocedure")).rows[0];
    if (acl.anon || !acl.auth) throw new Error(`wrong RPC ACL ${JSON.stringify(acl)}`);
    console.log('TA-X6d.1 customer adjustments: PASS (reviewed semantics, exact retry, unknown/currency denial, atomic history, over-refund and double-cancel serialization)');
  } finally {
    await Promise.all([a.query('rollback').catch(() => {}), b.query('rollback').catch(() => {})]);
    await admin.query('begin').catch(() => {});
    await admin.query('set local session_replication_role=replica').catch(() => {});
    await admin.query("delete from public.e10_commercial_events where idempotency_key like $1 or idempotency_key like $2", [`customer-adjustment:${run}%`, `transaction-post:${run}%`]).catch(() => {});
    await admin.query('delete from public.e10_customer_transaction_adjustments where transaction_id=any($1::uuid[])', [[tx, secondTx, otherTx].filter(Boolean)]).catch(() => {});
    await admin.query("delete from public.e10_customer_transaction_lines where source_line_id like $1", [`${run}%`]).catch(() => {});
    await admin.query('delete from public.e10_customer_transactions where id=any($1::uuid[])', [[tx, secondTx, otherTx].filter(Boolean)]).catch(() => {});
    await admin.query("delete from public.e10_customer_transaction_draft_decisions where idempotency_key like $1", [`${run}%`]).catch(() => {});
    await admin.query('delete from public.e10_customer_transaction_draft_lines where draft_id=any($1::uuid[])', [draftIds]).catch(() => {});
    await admin.query('delete from public.e10_customer_transaction_draft_revisions where draft_id=any($1::uuid[])', [draftIds]).catch(() => {});
    await admin.query('delete from public.e10_customer_transaction_drafts where id=any($1::uuid[])', [draftIds]).catch(() => {});
    await admin.query("delete from public.e10_customer_commercial_receipts where idempotency_key like $1", [`${run}%`]).catch(() => {});
    await admin.query('delete from public.e10_customers where id=any($1::uuid[])', [[ids.customer, ids.otherCustomer]]).catch(() => {});
    await admin.query('delete from public.e10_organization_role_permissions where role_id=any($1::uuid[])', [[ids.role, ids.otherRole]]).catch(() => {});
    await admin.query('delete from public.e10_organization_memberships where user_id=any($1::uuid[])', [[ids.user, ids.otherUser]]).catch(() => {});
    await admin.query('delete from public.e10_organization_roles where id=any($1::uuid[])', [[ids.role, ids.otherRole]]).catch(() => {});
    await admin.query('delete from public.e10_organizations where id=$1', [ids.otherOrg]).catch(() => {});
    await admin.query('delete from auth.users where id=any($1::uuid[])', [[ids.user, ids.otherUser]]).catch(() => {});
    await admin.query('commit').catch(() => {});
    const residue = (await admin.query(`select
      (select count(*) from auth.users where id=any($1::uuid[]))+
      (select count(*) from public.e10_organization_roles where id=any($2::uuid[]))+
      (select count(*) from public.e10_organization_memberships where user_id=any($1::uuid[]))+
      (select count(*) from public.e10_customers where id=any($3::uuid[]))+
      (select count(*) from public.e10_customer_commercial_receipts where idempotency_key like $4)+
      (select count(*) from public.e10_customer_transaction_lines where source_line_id like $4)+
      (select count(*) from public.e10_organizations where id=$5) n`, [[ids.user, ids.otherUser], [ids.role, ids.otherRole], [ids.customer, ids.otherCustomer], `${run}%`, ids.otherOrg])).rows[0].n;
    await Promise.all([admin.end(), a.end(), b.end()]);
    if (Number(residue) !== 0) throw new Error(`X6d teardown residue ${residue}`);
  }
}

main().catch(e => { console.error(e.stack); process.exit(1); });
