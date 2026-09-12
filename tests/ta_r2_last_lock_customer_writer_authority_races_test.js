const { Client } = require('pg');
const { randomUUID } = require('crypto');

const db = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const org = 'e1000000-0000-4000-8000-0000000000a6';
const x = { run: randomUUID(), user: randomUUID(), role: randomUUID(), session: randomUUID(), slot: randomUUID() };
const jwt = JSON.stringify({ sub: x.user, role: 'authenticated' });
const bounded = (p, label) => Promise.race([p, new Promise((_, reject) => setTimeout(() => reject(new Error(`${label} timeout`)), 8000))]);

async function waitBlocked(observer, waiter, holder, label) {
  for (let i = 0; i < 100; i++) {
    const q = await observer.query("select wait_event_type='Lock' and $2::int=any(pg_blocking_pids($1::int)) waiting from pg_stat_activity where pid=$1", [waiter, holder]);
    if (q.rows[0]?.waiting) return;
    await new Promise(resolve => setTimeout(resolve, 40));
  }
  throw new Error(`${label}: exact writer never blocked on exact final-lock holder`);
}

async function main() {
  const admin = new Client({ connectionString: db });
  const holder = new Client({ connectionString: db });
  const writer = new Client({ connectionString: db });
  await Promise.all([admin.connect(), holder.connect(), writer.connect()]);
  const draftIds = [];
  const txIds = [];
  try {
    await admin.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())", [x.user, `${x.run}@x.invalid`]);
    await admin.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'R2 last lock',false)", [x.role, org, x.run]);
    const caps = ['act.record_commercial_events','act.manage_customers','act.prepare_customer_transactions','act.approve_customer_transactions','act.post_customer_transactions','act.adjust_customer_transactions','act.reconcile_customer_transactions','act.live_run'];
    for (const cap of caps) await admin.query('insert into public.e10_organization_role_permissions values($1,$2,$3,true)', [org, x.role, cap]);
    await admin.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')", [org, x.user, x.role]);
    await admin.query("insert into public.e10_break_sessions(id,organization_id,streamer_uid,name,status) values($1,$2,$3,'R2 last lock','active')", [x.session, org, x.user]);
    await admin.query("insert into public.e10_break_slots(id,organization_id,session_id,label,price,state,position) values($1,$2,$3,'R2 last lock',1,'available',1)", [x.slot, org, x.session]);
    await writer.query('select set_config($1,$2,false)', ['request.jwt.claims', jwt]);
    await writer.query('set role authenticated');
    const writerPid = Number((await writer.query('select pg_backend_pid() pid')).rows[0].pid);
    const holderPid = Number((await holder.query('select pg_backend_pid() pid')).rows[0].pid);

    const customer = (await writer.query('select public.e10_org_create_customer($1,$2,$3) r', [org, `R2 ${x.run}`, `${x.run}-control-customer`])).rows[0].r.customer_id;
    await writer.query("select public.e10_org_update_customer($1,$2,0,$3,'active',$4)", [org, customer, `R2 updated ${x.run}`, `${x.run}-control-update`]);
    await writer.query("select public.e10_org_decide_customer_identity($1,$2,'alias',null,null,$3,'attach',null,'control','{}',$4)", [org, customer, `control-${x.run}`, `${x.run}-control-identity`]);
    const activity = (await writer.query("select public.e10_org_record_customer_activity($1,'retail',$2,null,'r2',null,null,1,10,0,0,0,'CAD','manual',now(),'exact','manual',null,$3,$4,'{}','operator_asserted',$5) r", [org, customer, `${x.run}-control-ref`, `${x.run}-control-event`, `${x.run}-control-activity`])).rows[0].r.activity_id;
    await writer.query("select public.e10_org_attribute_customer_activity($1,$2,$3,'control','{}',$4)", [org, activity, customer, `${x.run}-control-attribute`]);

    async function makeDraft(suffix, lines, approve = false) {
      const d = (await writer.query("select public.e10_org_create_customer_transaction_draft($1,$2,'CAD',now(),'exact',$3,$4,$5) r", [org, customer, suffix, JSON.stringify(lines), `${x.run}-${suffix}-draft`])).rows[0].r.draft_id;
      draftIds.push(d);
      if (approve) await writer.query('select public.e10_org_approve_customer_transaction_draft($1,$2,1,$3)', [org, d, `${x.run}-${suffix}-approve`]);
      return d;
    }
    const baseDraft = await makeDraft('base', [{ purchase_kind:'retail', capture_source:'manual', source_line_id:`${x.run}-base-line`, quantity:1, merchandise_gross:5, merchandise_discount:0 }], true);
    const baseTx = (await writer.query('select public.e10_org_post_customer_transaction_draft($1,$2,1,$3) r', [org, baseDraft, `${x.run}-base-post`])).rows[0].r.transaction_id;
    txIds.push(baseTx);
    const baseLine = (await admin.query('select id from public.e10_customer_transaction_lines where transaction_id=$1', [baseTx])).rows[0].id;
    await writer.query("select public.e10_org_adjust_customer_transaction($1,$2,$3,'correction','increase','CAD',1,null,null,now(),'exact','control','manual',null,$4,$5,null,'{}',$6)", [org, baseTx, baseLine, `${x.run}-control-adjust-event`, `${x.run}-control-adjust-component`, `${x.run}-control-adjust`]);
    await writer.query("select public.e10_org_finalize_customer_transaction_component($1,$2,$3,'shipping',0,'CAD','control','manual',null,$4,$5,'{}',$6)", [org, baseTx, baseLine, `${x.run}-control-final-event`, `${x.run}-control-final-component`, `${x.run}-control-final`]);

    const amendLines = [{ purchase_kind:'retail', capture_source:'manual', source_line_id:`${x.run}-amend-line`, quantity:1, merchandise_gross:2 }];
    const amendDraft = await makeDraft('amend', amendLines);
    await writer.query("select public.e10_org_amend_customer_transaction_draft($1,$2,1,$3,'CAD',now(),'exact','control amend',$4,$5)", [org, amendDraft, customer, JSON.stringify(amendLines), `${x.run}-control-amend`]);
    const approveDraft = await makeDraft('approve', [{ purchase_kind:'retail', capture_source:'manual', source_line_id:`${x.run}-approve-line`, activity_observation_id:activity, quantity:1, merchandise_gross:10 }]);
    const reopenDraft = await makeDraft('reopen', [{ purchase_kind:'retail', capture_source:'manual', source_line_id:`${x.run}-reopen-line`, quantity:1, merchandise_gross:3 }], true);
    await writer.query("select public.e10_org_reopen_customer_transaction_draft($1,$2,1,'control',$3)", [org, reopenDraft, `${x.run}-control-reopen`]);
    await writer.query('select public.e10_org_approve_customer_transaction_draft($1,$2,1,$3)', [org, reopenDraft, `${x.run}-control-reapprove`]);
    const postActivity = (await writer.query("select public.e10_org_record_customer_activity($1,'break',$2,null,'r2',$3,$4,1,7,0,0,0,'CAD','manual',now(),'exact','manual',null,$5,$6,'{}','operator_asserted',$7) r", [org, customer, x.session, x.slot, `${x.run}-post-ref`, `${x.run}-post-event`, `${x.run}-post-activity`])).rows[0].r.activity_id;
    const postDraft = await makeDraft('post', [{ purchase_kind:'break', capture_source:'manual', source_line_id:`${x.run}-post-line`, activity_observation_id:postActivity, quantity:1, merchandise_gross:7 }], true);

    const tests = [
      { name:'record', cap:'act.record_commercial_events', message:'record_customer_activity_denied', lock:{kind:'advisory',key:`${org}|customer-activity|${x.run}-race-record`}, sql:"select public.e10_org_record_customer_activity($1,'retail',$2,null,'r2',null,null,1,1,0,0,0,'CAD','manual',now(),'exact','manual',null,$3,$4,'{}','operator_asserted',$5)", args:[org,customer,`${x.run}-race-record-ref`,`${x.run}-race-record-event`,`${x.run}-race-record`], effect:"select count(*)::int n from public.e10_customer_activity_observations where idempotency_key=$1", effectArgs:[`${x.run}-race-record`] },
      { name:'create_customer', cap:'act.manage_customers', message:'manage_customer_denied', lock:{kind:'advisory',key:`${org}|customer-mutation|${x.run}-race-create`}, sql:'select public.e10_org_create_customer($1,$2,$3)', args:[org,'R2 denied',`${x.run}-race-create`], effect:"select count(*)::int n from public.e10_customer_mutation_receipts where idempotency_key=$1", effectArgs:[`${x.run}-race-create`] },
      { name:'update_customer', cap:'act.manage_customers', message:'manage_customer_denied', lock:{kind:'row',table:'e10_customers',id:customer}, sql:"select public.e10_org_update_customer($1,$2,1,'denied','active',$3)", args:[org,customer,`${x.run}-race-update`], effect:'select count(*)::int n from public.e10_customer_mutation_receipts where idempotency_key=$1', effectArgs:[`${x.run}-race-update`] },
      { name:'decide_identity', cap:'act.manage_customers', message:'manage_customer_identity_denied', lock:{kind:'row',table:'e10_customers',id:customer}, sql:"select public.e10_org_decide_customer_identity($1,$2,'alias',null,null,$3,'attach',null,'denied','{}',$4)", args:[org,customer,`denied-${x.run}`,`${x.run}-race-identity`], effect:'select count(*)::int n from public.e10_customer_identity_decisions where idempotency_key=$1', effectArgs:[`${x.run}-race-identity`] },
      { name:'attribute', cap:'act.manage_customers', message:'attribute_customer_activity_denied', lock:{kind:'advisory',key:`${org}|activity-attribution|${activity}`}, sql:"select public.e10_org_attribute_customer_activity($1,$2,null,'denied','{}',$3)", args:[org,activity,`${x.run}-race-attribute`], effect:'select count(*)::int n from public.e10_customer_activity_attribution_decisions where idempotency_key=$1', effectArgs:[`${x.run}-race-attribute`] },
      { name:'create_draft', cap:'act.prepare_customer_transactions', message:'prepare_customer_transaction_denied', lock:{kind:'advisory',key:`${org}|customer-commercial|${x.run}-race-draft`}, sql:"select public.e10_org_create_customer_transaction_draft($1,$2,'CAD',now(),'exact','denied','[]',$3)", args:[org,customer,`${x.run}-race-draft`], effect:'select count(*)::int n from public.e10_customer_commercial_receipts where idempotency_key=$1', effectArgs:[`${x.run}-race-draft`] },
      { name:'amend_draft', cap:'act.prepare_customer_transactions', message:'prepare_customer_transaction_denied', lock:{kind:'row',table:'e10_customer_transaction_drafts',id:amendDraft}, sql:"select public.e10_org_amend_customer_transaction_draft($1,$2,2,$3,'CAD',now(),'exact','denied','[]',$4)", args:[org,amendDraft,customer,`${x.run}-race-amend`], effect:'select count(*)::int n from public.e10_customer_commercial_receipts where idempotency_key=$1', effectArgs:[`${x.run}-race-amend`] },
      { name:'approve_draft', cap:'act.approve_customer_transactions', message:'approve_customer_transaction_denied', lock:{kind:'advisory',key:`${org}|activity-attribution|${activity}`}, sql:'select public.e10_org_approve_customer_transaction_draft($1,$2,1,$3)', args:[org,approveDraft,`${x.run}-race-approve`], effect:'select count(*)::int n from public.e10_customer_transaction_draft_decisions where idempotency_key=$1', effectArgs:[`${x.run}-race-approve`] },
      { name:'reopen_draft', cap:'act.approve_customer_transactions', message:'reopen_customer_transaction_denied', lock:{kind:'row',table:'e10_customer_transaction_drafts',id:reopenDraft}, sql:"select public.e10_org_reopen_customer_transaction_draft($1,$2,1,'denied',$3)", args:[org,reopenDraft,`${x.run}-race-reopen`], effect:'select count(*)::int n from public.e10_customer_transaction_draft_decisions where idempotency_key=$1', effectArgs:[`${x.run}-race-reopen`] },
      { name:'post_draft', cap:'act.post_customer_transactions', message:'post_customer_transaction_denied', lock:{kind:'row',table:'e10_break_slots',id:x.slot}, sql:'select public.e10_org_post_customer_transaction_draft($1,$2,1,$3)', args:[org,postDraft,`${x.run}-race-post`], effect:'select count(*)::int n from public.e10_customer_transactions where source_draft_id=$1', effectArgs:[postDraft] },
      { name:'adjust', cap:'act.adjust_customer_transactions', message:'adjust_customer_transaction_denied', lock:{kind:'advisory',key:`${org}|customer-adjustment|${baseLine}`}, sql:"select public.e10_org_adjust_customer_transaction($1,$2,$3,'correction','increase','CAD',1,null,null,now(),'exact','denied','manual',null,$4,$5,null,'{}',$6)", args:[org,baseTx,baseLine,`${x.run}-race-adjust-event`,`${x.run}-race-adjust-component`,`${x.run}-race-adjust`], effect:'select count(*)::int n from public.e10_customer_transaction_adjustments where idempotency_key=$1', effectArgs:[`${x.run}-race-adjust`] },
      { name:'finalize', cap:'act.reconcile_customer_transactions', message:'finalize_customer_component_denied', lock:{kind:'advisory',key:`${org}|customer-adjustment|${baseLine}`}, sql:"select public.e10_org_finalize_customer_transaction_component($1,$2,$3,'tax',0,'CAD','denied','manual',null,$4,$5,'{}',$6)", args:[org,baseTx,baseLine,`${x.run}-race-final-event`,`${x.run}-race-final-component`,`${x.run}-race-final`], effect:'select count(*)::int n from public.e10_customer_transaction_component_finalizations where idempotency_key=$1', effectArgs:[`${x.run}-race-final`] },
    ];

    for (const test of tests) {
      await holder.query('begin');
      if (test.lock.kind === 'advisory') await holder.query('select pg_advisory_xact_lock(hashtextextended($1,0))', [test.lock.key]);
      else await holder.query(`select 1 from public.${test.lock.table} where id=$1 for update`, [test.lock.id]);
      const pending = writer.query(test.sql, test.args).then(value => ({ ok:true,value }), error => ({ ok:false,error }));
      await waitBlocked(admin, writerPid, holderPid, test.name);
      await admin.query('delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability=$3', [org,x.role,test.cap]);
      await holder.query('commit');
      const result = await bounded(pending, test.name);
      if (result.ok || result.error.code !== '42501' || result.error.message !== test.message) throw new Error(`${test.name}: ${result.ok?'mutated':result.error.message}`);
      const residue = Number((await admin.query(test.effect,test.effectArgs)).rows[0].n);
      if (residue !== 0) throw new Error(`${test.name}: domain residue ${residue}`);
      await admin.query('insert into public.e10_organization_role_permissions values($1,$2,$3,true)', [org,x.role,test.cap]);
      console.log(`[proof] ${test.name}: valid path blocked at final lock, writer=${writerPid}, holder=${holderPid}, denied 42501, domain delta=0`);
    }
    console.log('TA-R2 all twelve valid-path last-lock authority races: PASS');
  } finally {
    await holder.query('rollback').catch(() => {});
    await writer.query('reset role').catch(() => {});
    await admin.query('set session_replication_role=replica').catch(() => {});
    await admin.query('delete from public.e10_commercial_events where created_by=$1', [x.user]).catch(() => {});
    await admin.query('delete from public.e10_customer_transaction_component_finalizations where idempotency_key like $1', [`${x.run}%`]).catch(() => {});
    await admin.query('delete from public.e10_customer_transaction_adjustments where idempotency_key like $1', [`${x.run}%`]).catch(() => {});
    await admin.query('delete from public.e10_customer_transaction_lines where source_line_id like $1', [`${x.run}%`]).catch(() => {});
    await admin.query('delete from public.e10_customer_transactions where id=any($1::uuid[])', [txIds]).catch(() => {});
    await admin.query('delete from public.e10_customer_transaction_source_claims where source_line_id like $1', [`${x.run}%`]).catch(() => {});
    await admin.query('delete from public.e10_customer_transaction_draft_decisions where idempotency_key like $1', [`${x.run}%`]).catch(() => {});
    await admin.query('delete from public.e10_customer_transaction_draft_lines where draft_id=any($1::uuid[])', [draftIds]).catch(() => {});
    await admin.query('delete from public.e10_customer_transaction_draft_revisions where draft_id=any($1::uuid[])', [draftIds]).catch(() => {});
    await admin.query('delete from public.e10_customer_transaction_drafts where id=any($1::uuid[])', [draftIds]).catch(() => {});
    await admin.query('delete from public.e10_customer_commercial_receipts where idempotency_key like $1', [`${x.run}%`]).catch(() => {});
    await admin.query('delete from public.e10_customer_activity_attribution_decisions where idempotency_key like $1', [`${x.run}%`]).catch(() => {});
    await admin.query('delete from public.e10_customer_activity_observations where idempotency_key like $1', [`${x.run}%`]).catch(() => {});
    await admin.query('delete from public.e10_customer_identity_decisions where idempotency_key like $1', [`${x.run}%`]).catch(() => {});
    await admin.query('delete from public.e10_customer_mutation_receipts where idempotency_key like $1', [`${x.run}%`]).catch(() => {});
    await admin.query('delete from public.e10_customers where organization_id=$1 and display_name like $2', [org,`%${x.run}%`]).catch(() => {});
    await admin.query('delete from public.e10_break_events where slot_id=$1', [x.slot]).catch(() => {});
    await admin.query('delete from public.e10_break_slots where id=$1', [x.slot]).catch(() => {});
    await admin.query('delete from public.e10_break_sessions where id=$1', [x.session]).catch(() => {});
    await admin.query('set session_replication_role=origin').catch(() => {});
    await admin.query('delete from public.e10_organization_memberships where user_id=$1', [x.user]).catch(() => {});
    await admin.query('delete from public.e10_organization_role_permissions where role_id=$1', [x.role]).catch(() => {});
    await admin.query('delete from public.e10_organization_roles where id=$1', [x.role]).catch(() => {});
    await admin.query('delete from auth.users where id=$1', [x.user]).catch(() => {});
    await Promise.all([admin.end(),holder.end(),writer.end()]);
  }
}

main().catch(error => { console.error(error.stack); process.exit(1); });
