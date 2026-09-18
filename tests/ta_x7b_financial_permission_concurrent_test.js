const {Client}=require('pg');const {randomUUID}=require('crypto');
const db=process.env.E10_DB_URL||'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const x={org:randomUUID(),user:randomUUID(),role:randomUUID(),location:randomUUID()};
async function main(){const a=new Client({connectionString:db}),b=new Client({connectionString:db}),c=new Client({connectionString:db});
 await Promise.all([a.connect(),b.connect(),c.connect()]);let pending=null,pid=null,success=false;
 try{
  for(const q of[a,b,c])await q.query("set statement_timeout='8s'");
  await a.query('set session_replication_role=replica');
  await a.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[x.user,x.user+'@x.invalid']);
  await a.query("insert into public.e10_organizations(id,slug,name) values($1,$2,'X7b permission race')",[x.org,'x7p-'+x.org]);
  await a.query("insert into public.e10_reporting_dataset_revisions(organization_id) values($1)",[x.org]);
  await a.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,'admin','Admin',false)",[x.role,x.org]);
  await a.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')",[x.org,x.user,x.role]);
  await a.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,'act.permissions_config',true)",[x.org,x.role]);
  await a.query("insert into public.e10_locations(id,organization_id,name,status) values($1,$2,'Race location','active')",[x.location,x.org]);
  await a.query('set session_replication_role=origin');
  await b.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:x.user,role:'authenticated'})]);await b.query('set role authenticated');
  const created=(await b.query("select public.e10_org_set_location_financial_access($1,$2,$3,null,true,'race fixture','{}',$4) r",[x.org,x.location,x.role,'create-'+x.org])).rows[0].r;
  await a.query('begin');await a.query("select 1 from public.e10_location_role_permissions where organization_id=$1 and location_id=$2 and role_id=$3 for update",[x.org,x.location,x.role]);
  pid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
  pending=b.query("select public.e10_org_set_location_financial_access($1,$2,$3,$4,false,'must fail after wait','{}',$5)",[x.org,x.location,x.role,created.updated_at,'blocked-'+x.org])
    .then(value=>({ok:true,value}),error=>({ok:false,error}));
  let waited=false;for(let n=0;n<100;n++){const row=(await c.query("select wait_event_type from pg_stat_activity where pid=$1",[pid])).rows[0];if(row&&row.wait_event_type==='Lock'){waited=true;break}await new Promise(r=>setTimeout(r,20));}
  if(!waited){await a.query('rollback');throw Error('financial permission writer did not wait on exact backend')}
  await c.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.permissions_config'",[x.org,x.role]);
  await a.query('commit');
  const outcome=await pending;const rejected=!outcome.ok&&outcome.error.code==='42501'&&outcome.error.message==='location_financial_permission_denied';pending=null;
  if(!rejected)throw Error('revoked authority survived row-lock wait');
  console.log('[proof] exact blocked financial-permission backend reread revoked authority');
  success=true;
 }finally{
  if(pending&&pid)await c.query('select pg_cancel_backend($1)',[pid]).catch(()=>{});
  await Promise.allSettled([pending].filter(Boolean));await a.query('rollback').catch(()=>{});
  await b.query('reset role').catch(()=>{});await a.query('set session_replication_role=replica');
  for(const q of['delete from public.e10_location_financial_permission_decisions where organization_id=$1','delete from public.e10_location_role_permissions where organization_id=$1','delete from public.e10_locations where organization_id=$1','delete from public.e10_organization_role_permissions where organization_id=$1','delete from public.e10_organization_memberships where organization_id=$1','delete from public.e10_organization_roles where organization_id=$1','delete from public.e10_reporting_dataset_revisions where organization_id=$1','delete from public.e10_organizations where id=$1'])await a.query(q,[x.org]);
  await a.query('set session_replication_role=origin');await a.query('delete from auth.users where id=$1',[x.user]);
  const residue=Number((await a.query("select (select count(*) from public.e10_organizations where id=$1)+(select count(*) from public.e10_location_financial_permission_decisions where organization_id=$1)+(select count(*) from public.e10_location_role_permissions where organization_id=$1)+(select count(*) from public.e10_locations where organization_id=$1)+(select count(*) from public.e10_organization_role_permissions where organization_id=$1)+(select count(*) from public.e10_organization_memberships where organization_id=$1)+(select count(*) from public.e10_organization_roles where organization_id=$1)+(select count(*) from public.e10_reporting_dataset_revisions where organization_id=$1)+(select count(*) from auth.users where id=$2) n",[x.org,x.user])).rows[0].n);
  const sentinel=Number((await a.query("select count(*) n from public.e10_organizations where id='e1000000-0000-4000-8000-0000000000a6'")).rows[0].n);
  await Promise.all([a.end(),b.end(),c.end()]);if(residue||sentinel!==1)throw Error('X7b permission race cleanup '+JSON.stringify({residue,sentinel}));
 }
 if(success)console.log('TA-X7b financial permission concurrency: PASS');
}
main().catch(e=>{console.error(e.stack);process.exit(1)});
