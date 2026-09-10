// TA-X5b two-connection idempotency proof for every mutator.
const { Client } = require('pg');
const { randomUUID } = require('crypto');
const CONN = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const org='e1000000-0000-4000-8000-0000000000a6';
const x={user:randomUUID(),role:randomUUID(),product:randomUUID(),run:randomUUID()}; x.item=`x5b-${x.run}`;
const jwt=JSON.stringify({sub:x.user,role:'authenticated'});
async function cleanup(c){
  await c.query('set session_replication_role=replica');
  await c.query("delete from public.e10_integration_outbox where commercial_event_id in(select id from public.e10_commercial_events where idempotency_key like $1)",[`${x.run}-%`]);
  await c.query("delete from public.e10_commercial_events where idempotency_key like $1",[`${x.run}-%`]);
  await c.query("delete from public.e10_intake_resolver_decisions where idempotency_key like $1",[`${x.run}-%`]);
  await c.query('set session_replication_role=origin');
  await c.query("delete from public.e10_intake_rows where batch_id in(select id from public.e10_intake_batches where idempotency_key like $1)",[`${x.run}-%`]);
  await c.query("delete from public.e10_intake_batches where idempotency_key like $1",[`${x.run}-%`]);
  await c.query('delete from public.e10_inventory_items where id=$1',[x.item]);
  await c.query('delete from public.e10_product_masters where id=$1',[x.product]);
  await c.query('delete from public.e10_organization_memberships where organization_id=$1 and user_id=$2',[org,x.user]);
  await c.query('delete from public.e10_organization_roles where id=$1',[x.role]);
  await c.query('delete from auth.users where id=$1',[x.user]);
}
async function main(){
  const s=new Client({connectionString:CONN}),a=new Client({connectionString:CONN}),b=new Client({connectionString:CONN});
  await s.connect();await a.connect();await b.connect();
  try{
    await cleanup(s);
    await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[x.user,`x5b-${x.run}@x.invalid`]);
    await s.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X5b Race',false)",[x.role,org,`x5b-${x.run}`]);
    await s.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,'act.manage_intake',true),($1,$2,'act.record_commercial_events',true)",[org,x.role]);
    await s.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')",[org,x.user,x.role]);
    await s.query("insert into public.e10_product_masters(id,organization_id,name) values($1,$2,'X5b Product')",[x.product,org]);
    await s.query("insert into public.e10_inventory_items(id,name,qty,organization_id) values($1,'X5b Item',0,$2)",[x.item,org]);
    for(const c of[a,b])await c.query('select set_config($1,$2,false)',['request.jwt.claims',jwt]);
    const stageSql="select public.e10_org_stage_intake($1,'manual',null,null,null,'fp',jsonb_build_array(jsonb_build_object('raw_payload',jsonb_build_object('x',1),'observation_kind','asking_price','occurred_at','2026-09-10T20:00:00Z','amount',1)),$2) r";
    const [sa,sb]=await Promise.all([a.query(stageSql,[org,`${x.run}-stage`]),b.query(stageSql,[org,`${x.run}-stage`])]);
    const stage=[sa.rows[0].r,sb.rows[0].r]; if(stage.filter(v=>!v.replay).length!==1||stage[0].batch_id!==stage[1].batch_id)throw new Error('stage race not idempotent '+JSON.stringify(stage));
    const row=(await s.query('select id from public.e10_intake_rows where batch_id=$1',[stage[0].batch_id])).rows[0].id;
    for(const c of[a,b])await c.query('select set_config($1,$2,false)',['request.jwt.claims',jwt]);
    const resolveSql="select public.e10_org_resolve_intake_row($1,$2,'match_product',$3,'race',null,$4) r";
    const [ra,rb]=await Promise.all([a.query(resolveSql,[org,row,x.product,`${x.run}-resolve`]),b.query(resolveSql,[org,row,x.product,`${x.run}-resolve`])]);
    const resolved=[ra.rows[0].r,rb.rows[0].r];if(resolved.filter(v=>!v.replay).length!==1||resolved[0].decision_id!==resolved[1].decision_id)throw new Error('resolve race not idempotent '+JSON.stringify(resolved));
    for(const c of[a,b])await c.query('select set_config($1,$2,false)',['request.jwt.claims',jwt]);
    const eventSql="select public.e10_org_record_commercial_event($1,'listing_created','inventory_item',$2,'2026-09-10T21:00:00Z','manual',null,'{\"listing_id\":\"race-listing\",\"channel\":\"race\"}',null,array['dormant'],$3) r";
    const [ea,eb]=await Promise.all([a.query(eventSql,[org,x.item,`${x.run}-event`]),b.query(eventSql,[org,x.item,`${x.run}-event`])]);
    const events=[ea.rows[0].r,eb.rows[0].r];if(events.filter(v=>!v.replay).length!==1||events[0].event_id!==events[1].event_id)throw new Error('event race not idempotent '+JSON.stringify(events));
    const proof=(await s.query("select (select count(*) from public.e10_intake_batches where idempotency_key=$1) batches,(select count(*) from public.e10_intake_resolver_decisions where idempotency_key=$2) decisions,(select count(*) from public.e10_commercial_events where idempotency_key=$3) events,(select count(*) from public.e10_integration_outbox o join public.e10_commercial_events e on e.id=o.commercial_event_id where e.idempotency_key=$3) outbox",[`${x.run}-stage`,`${x.run}-resolve`,`${x.run}-event`])).rows[0];
    if(Object.values(proof).some(v=>Number(v)!==1))throw new Error('race duplicates '+JSON.stringify(proof));
    console.log('TA-X5b concurrent writers: PASS (stage, resolve, event+outbox each exactly once)');
  }finally{for(const c of[a,b])await c.query('rollback').catch(()=>{});await s.query('rollback').catch(()=>{});await cleanup(s);await a.end();await b.end();await s.end();}
}
main().catch(e=>{console.error('TA-X5b concurrent test ERROR: '+(e.stack||e.message));process.exit(1);});
