const { Client } = require('pg');
const { randomUUID } = require('crypto');

const db = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const org = 'e1000000-0000-4000-8000-0000000000a6';
const id = () => randomUUID();
const x = {
  run: id(), operator: id(), buyer: id(), nonowner: id(), viewer: id(), noCap: id(),
  operatorRole: id(), nonownerRole: id(), noCapRole: id(),
  customerVerified: id(), customerOther: id(), customerArchived: id(), claim: id(),
  session: id(), noCapSession: id(),
  verifiedSlot: id(), conflictSlot: id(), revokedSlot: id(), archivedSlot: id(), noCapSlot: id(),
};
const commitSql = 'select public.e10_org_commit_native_break_sale($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::jsonb,$13::jsonb,$14) r';
const claims = user => JSON.stringify({ sub: user, role: 'authenticated' });

async function asUser(client, user) {
  await client.query('reset role');
  await client.query('select set_config($1,$2,false)', ['request.jwt.claims', claims(user)]);
  await client.query('set role authenticated');
}

function saleArgs(session, slot, buyer, handle, key) {
  return [org, session, slot, 0, buyer, handle, 1, 25, 'CAD', 'auction', new Date().toISOString(), '[]', '{}', key];
}

async function expect42501(promise, label) {
  let denied = false;
  try { await promise; } catch (e) { denied = e.code === '42501'; }
  if (!denied) throw new Error(`${label} was not denied`);
}

async function main() {
  const s = new Client({ connectionString: db });
  const c = new Client({ connectionString: db });
  await Promise.all([s.connect(), c.connect()]);
  const errors = [];
  let success = false;
  try {
    for (const [user, suffix] of [[x.operator, 'operator'], [x.buyer, 'buyer'], [x.nonowner, 'nonowner'], [x.viewer, 'viewer'], [x.noCap, 'nocap']]) {
      await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())", [user, `${x.run}-${suffix}@x.invalid`]);
    }
    await s.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$4,$5,'X6g operator',false),($2,$4,$6,'X6g nonowner',false),($3,$4,$7,'X6g no cap',false)", [x.operatorRole, x.nonownerRole, x.noCapRole, org, `${x.run}-op`, `${x.run}-other`, `${x.run}-none`]);
    await s.query("insert into public.e10_organization_role_permissions values($1,$2,'act.live_run',true),($1,$2,'act.manage_customers',true),($1,$2,'act.record_commercial_events',true),($1,$3,'act.live_run',true)", [org, x.operatorRole, x.nonownerRole]);
    await s.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active'),($1,$4,$5,'active'),($1,$6,$7,'active')", [org, x.operator, x.operatorRole, x.nonowner, x.nonownerRole, x.noCap, x.noCapRole]);
    await s.query("insert into public.e10_customers(id,organization_id,display_name,status) values($1,$4,'Verified','active'),($2,$4,'Other','active'),($3,$4,'Archived','active')", [x.customerVerified, x.customerOther, x.customerArchived, org]);
    await s.query("insert into public.e10_viewer_handle_claims(id,user_id,whatnot_handle,status,evidence,verified_at,expires_at) values($1,$2,$3,'verified','{}',now(),now()+interval '1 day')", [x.claim, x.buyer, `verified-${x.run}`]);
    await s.query("insert into public.e10_break_sessions(id,organization_id,streamer_uid,name,status) values($1,$3,$4,'Identity session','active'),($2,$3,$5,'No-cap session','active')", [x.session, x.noCapSession, org, x.operator, x.noCap]);
    const slots = [x.verifiedSlot, x.conflictSlot, x.revokedSlot, x.archivedSlot];
    for (let i = 0; i < slots.length; i++) await s.query("insert into public.e10_break_slots(id,organization_id,session_id,label,price,state,position) values($1,$2,$3,$4,10,'available',$5)", [slots[i], org, x.session, `Identity ${i}`, i + 1]);
    await s.query("insert into public.e10_break_slots(id,organization_id,session_id,label,price,state,position) values($1,$2,$3,'No cap',10,'available',1)", [x.noCapSlot, org, x.noCapSession]);
    await s.query('insert into public.e10_session_viewers(organization_id,session_id,user_id) values($1,$2,$3)', [org, x.session, x.viewer]);

    await asUser(c, x.operator);
    await c.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','whatnot',$3,null,'attach',$4,'verified buyer','{}',$5)", [org, x.customerVerified, `verified-${x.run}`, x.claim, `${x.run}-verified-identity`]);
    await c.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','whatnot',$3,null,'attach',null,'reviewed other','{}',$4)", [org, x.customerOther, `other-${x.run}`, `${x.run}-other-identity`]);
    await c.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','whatnot',$3,null,'attach',null,'reviewed archived','{}',$4)", [org, x.customerArchived, `archived-${x.run}`, `${x.run}-archived-identity`]);
    await s.query("update public.e10_customers set status='archived' where id=$1", [x.customerArchived]);

    const rowCount = Number((await s.query('select count(*) n from e10.resolve_native_break_buyer($1,$2,$3)', [org, x.buyer, `verified-${x.run}`])).rows[0].n);
    if (rowCount !== 1) throw new Error(`buyer resolver returned ${rowCount} rows`);
    const verified = (await c.query(commitSql, saleArgs(x.session, x.verifiedSlot, x.buyer, `verified-${x.run}`, `${x.run}-verified-sale`))).rows[0].r;
    if (verified.customer_id !== x.customerVerified || verified.identity_status !== 'verified_auth') throw new Error(`verified mapping failed ${JSON.stringify(verified)}`);

    await s.query("insert into public.e10_customer_resolution_decisions(organization_id,source_customer_id,revision,action,target_customer_id,source_customer_revision,target_customer_revision,review_basis,reason,evidence,idempotency_key,request_fingerprint,decided_by) values($1,$2,1,'merge',$3,0,0,'operator_review','X6g merged buyer target','{}',$4,$4,$5)", [org, x.customerVerified, x.customerOther, `${x.run}-merge`, x.operator]);
    const merged = (await s.query('select * from e10.resolve_native_break_buyer($1,$2,$3)', [org, x.buyer, `verified-${x.run}`])).rows[0];
    if (merged.customer_id !== x.customerOther || merged.identity_status !== 'verified_auth') throw new Error(`merged target was not resolved ${JSON.stringify(merged)}`);

    const conflict = (await c.query(commitSql, saleArgs(x.session, x.conflictSlot, x.buyer, `other-${x.run}`, `${x.run}-conflict-sale`))).rows[0].r;
    if (conflict.customer_id !== null || conflict.identity_status !== 'unresolved') throw new Error('conflicting uid and handle did not fail closed');

    await s.query("update public.e10_viewer_handle_claims set status='rejected' where id=$1", [x.claim]);
    const revoked = (await c.query(commitSql, saleArgs(x.session, x.revokedSlot, x.buyer, `verified-${x.run}`, `${x.run}-revoked-sale`))).rows[0].r;
    if (revoked.customer_id !== null || revoked.identity_status !== 'unresolved') throw new Error('revoked verified claim still resolved');
    const archived = (await c.query(commitSql, saleArgs(x.session, x.archivedSlot, null, `archived-${x.run}`, `${x.run}-archived-sale`))).rows[0].r;
    if (archived.customer_id !== null || archived.identity_status !== 'unresolved') throw new Error('archived customer still resolved');

    await asUser(c, x.nonowner);
    let denial;
    try { await c.query(commitSql, saleArgs(x.session, x.verifiedSlot, null, 'nonowner', `${x.run}-nonowner`)); } catch (e) { denial = e; }
    if (denial?.code !== '42501' || denial?.message !== 'native_break_session_denied') throw new Error(`same-org nonowner denial was masked: ${denial?.message}`);
    await asUser(c, x.viewer);
    denial = undefined;
    try { await c.query(commitSql, saleArgs(x.session, x.verifiedSlot, null, 'viewer', `${x.run}-viewer`)); } catch (e) { denial = e; }
    if (denial?.code !== '42501' || denial?.message !== 'native_break_sale_denied') throw new Error(`viewer denial was masked: ${denial?.message}`);
    await expect42501(c.query('select * from public.e10_native_break_sales limit 1'), 'authenticated native-sale table read');
    await asUser(c, x.noCap);
    await expect42501(c.query(commitSql, saleArgs(x.noCapSession, x.noCapSlot, null, 'nocap', `${x.run}-nocap`)), 'missing live-run capability');

    await asUser(c, x.operator);
    const valid = saleArgs(x.session, x.verifiedSlot, null, 'invalid-probe', `${x.run}-invalid`);
    const invalidCases = [
      ['null revision', 3, null], ['negative revision', 3, -1],
      ['null quantity', 6, null], ['zero quantity', 6, 0], ['negative quantity', 6, -1],
      ['NaN quantity', 6, 'NaN'], ['positive infinite quantity', 6, 'Infinity'], ['negative infinite quantity', 6, '-Infinity'],
      ['null amount', 7, null], ['negative amount', 7, -1], ['NaN amount', 7, 'NaN'],
      ['positive infinite amount', 7, 'Infinity'], ['negative infinite amount', 7, '-Infinity'],
      ['lowercase currency', 8, 'cad'], ['empty method', 9, ''], ['oversize method', 9, 'm'.repeat(101)],
      ['null occurrence', 10, null], ['infinite occurrence', 10, 'infinity'],
      ['non-array incentives', 11, '{}'], ['non-object evidence', 12, '[]'],
      ['empty key', 13, ''], ['oversize key', 13, 'k'.repeat(501)], ['missing buyer evidence', 5, null],
    ];
    for (const [label, index, value] of invalidCases) {
      const args = [...valid]; args[index] = value;
      if (label === 'missing buyer evidence') args[4] = null;
      let invalid = false;
      try { await c.query(commitSql, args); } catch (e) { invalid = e.code === '22023' && e.message === 'native_break_sale_invalid'; }
      if (!invalid) throw new Error(`${label} was not independently rejected`);
    }
    success = true;
  } finally {
    await c.query('reset role').catch(e => errors.push(e.message));
    const clean = async (sql, args = []) => { try { await s.query(sql, args); } catch (e) { errors.push(e.message); } };
    await clean('set session_replication_role=replica');
    await clean('delete from public.e10_native_break_sale_receipts where created_by=$1', [x.operator]);
    await clean('delete from public.e10_native_break_sale_transitions where created_by=$1', [x.operator]);
    await clean('delete from public.e10_native_break_sales where created_by=$1', [x.operator]);
    await clean('delete from public.e10_customer_activity_observations where created_by=$1', [x.operator]);
    await clean('delete from public.e10_integration_outbox o using public.e10_commercial_events e where o.organization_id=e.organization_id and o.commercial_event_id=e.id and e.created_by=$1', [x.operator]);
    await clean('delete from public.e10_commercial_events where created_by=$1', [x.operator]);
    await clean('delete from public.e10_break_events where actor_uid=$1', [x.operator]);
    await clean('delete from public.e10_customer_identity_decisions where created_by=$1', [x.operator]);
    await clean('delete from public.e10_customer_resolution_decisions where decided_by=$1', [x.operator]);
    await clean('delete from public.e10_customer_mutation_receipts where created_by=$1', [x.operator]);
    await clean('delete from public.e10_session_viewers where session_id=$1', [x.session]);
    await clean('delete from public.e10_break_slots where session_id=any($1::uuid[])', [[x.session, x.noCapSession]]);
    await clean('delete from public.e10_break_sessions where id=any($1::uuid[])', [[x.session, x.noCapSession]]);
    await clean('delete from public.e10_customers where id=any($1::uuid[])', [[x.customerVerified, x.customerOther, x.customerArchived]]);
    await clean('delete from public.e10_viewer_handle_claims where id=$1', [x.claim]);
    await clean('delete from public.e10_organization_memberships where user_id=any($1::uuid[])', [[x.operator, x.nonowner, x.noCap]]);
    await clean('delete from public.e10_organization_role_permissions where role_id=any($1::uuid[])', [[x.operatorRole, x.nonownerRole, x.noCapRole]]);
    await clean('delete from public.e10_organization_roles where id=any($1::uuid[])', [[x.operatorRole, x.nonownerRole, x.noCapRole]]);
    await clean('delete from auth.users where id=any($1::uuid[])', [[x.operator, x.buyer, x.nonowner, x.viewer, x.noCap]]);
    await clean('set session_replication_role=origin');
    const residue = Number((await s.query("select (select count(*) from auth.users where id=any($1::uuid[]))+(select count(*) from public.e10_break_sessions where id=any($2::uuid[]))+(select count(*) from public.e10_break_slots where session_id=any($2::uuid[]))+(select count(*) from public.e10_native_break_sales where created_by=$3)+(select count(*) from public.e10_native_break_sale_transitions where created_by=$3)+(select count(*) from public.e10_native_break_sale_receipts where created_by=$3)+(select count(*) from public.e10_customer_activity_observations where created_by=$3)+(select count(*) from public.e10_commercial_events where created_by=$3)+(select count(*) from public.e10_break_events where actor_uid=$3)+(select count(*) from public.e10_customer_identity_decisions where created_by=$3)+(select count(*) from public.e10_customer_mutation_receipts where created_by=$3)+(select count(*) from public.e10_customer_resolution_decisions where decided_by=$3)+(select count(*) from public.e10_customers where id=any($4::uuid[]))+(select count(*) from public.e10_viewer_handle_claims where id=$5)+(select count(*) from public.e10_session_viewers where session_id=any($2::uuid[]))+(select count(*) from public.e10_organization_memberships where user_id=any($1::uuid[]))+(select count(*) from public.e10_organization_role_permissions where role_id=any($6::uuid[]))+(select count(*) from public.e10_organization_roles where id=any($6::uuid[]))+(select count(*) from public.e10_integration_outbox where payload->>'buyer_handle' like $7) n", [[x.operator, x.buyer, x.nonowner, x.viewer, x.noCap], [x.session, x.noCapSession], x.operator, [x.customerVerified, x.customerOther, x.customerArchived], x.claim, [x.operatorRole, x.nonownerRole, x.noCapRole], '%'+x.run+'%'])).rows[0].n);
    await Promise.all([s.end(), c.end()]);
    if (errors.length || residue) throw new Error(`X6g adversarial cleanup failed ${JSON.stringify({ errors, residue })}`);
  }
  if (success) console.log('TA-X6g adversarial identity/authorization: PASS');
}

main().catch(e => { console.error(e.stack); process.exit(1); });
