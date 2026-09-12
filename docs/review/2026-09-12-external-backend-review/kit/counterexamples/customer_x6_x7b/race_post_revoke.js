const {Client}=require('/home/user/element10-app/tests/node_modules/pg');const {randomUUID}=require('crypto');
const db='postgresql://postgres:postgres@127.0.0.1:54323/postgres',org='e1000000-0000-4000-8000-0000000000a6';
const x={run:randomUUID(),u:randomUUID(),role:randomUUID(),customer:randomUUID()};
async function main(){const s=new Client({connectionString:db}),b=new Client({connectionString:db});await Promise.all([s.connect(),b.connect()]);let draft,tx=null,outcome;
 try{
  await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[x.u,x.run+'@x.invalid']);
  await s.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'race',false)",[x.role,org,x.run]);
  await s.query("insert into public.e10_organization_role_permissions values($1,$2,'act.prepare_customer_transactions',true),($1,$2,'act.approve_customer_transactions',true),($1,$2,'act.post_customer_transactions',true)",[org,x.role]);
  await s.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')",[org,x.u,x.role]);
  await s.query("insert into public.e10_customers(id,organization_id,display_name) values($1,$2,'race cust')",[x.customer,org]);
  await b.query('select set_config($1,$2,false)',['request.jwt.claims',JSON.stringify({sub:x.u,role:'authenticated'})]);await b.query('set role authenticated');
  draft=(await b.query("select public.e10_org_create_customer_transaction_draft($1,$2,'USD','2026-01-05','exact','race',$3,$4) r",[org,x.customer,JSON.stringify([{purchase_kind:'retail',capture_source:'manual',source_line_id:x.run+'-line',quantity:1,merchandise_gross:10,merchandise_discount:0}]),x.run+'-draft'])).rows[0].r.draft_id;
  await b.query('select public.e10_org_approve_customer_transaction_draft($1,$2,1,$3)',[org,draft,x.run+'-approve']);
  const bPid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
  await s.query('begin');try{await s.query('select 1 from public.e10_customer_transaction_drafts where id=$1 for update',[draft]);}catch(e){console.error('FOR UPDATE failed:',e.message);await s.query('rollback');throw e;}
  const post=b.query('select public.e10_org_post_customer_transaction_draft($1,$2,1,$3) r',[org,draft,x.run+'-post']).then(v=>({ok:true,v:v.rows[0].r}),e=>({ok:false,e:e.code+' '+e.message}));
  let waited=false;for(let i=0;i<100&&!waited;i++){waited=(await s.query("select wait_event_type='Lock' w from pg_stat_activity where pid=$1",[bPid])).rows[0].w===true;if(!waited)await new Promise(r=>setTimeout(r,50));}
  if(!waited){await s.query('rollback');throw Error('post never waited on draft row lock');}
  // revoke the posting capability AND deactivate membership while post is blocked, then commit
  try{await s.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.post_customer_transactions'",[org,x.role]);}catch(e){console.error('perm delete failed',e.message);}
  try{await s.query("update public.e10_organization_memberships set status='suspended' where organization_id=$1 and user_id=$2",[org,x.u]);}catch(e){console.error('membership update failed',e.message);}
  try{await s.query('commit');}catch(e){console.error('commit failed',e.message);}
  outcome=await post;
  tx=outcome.ok?outcome.v.transaction_id:null;
  const cap=(await s.query("select e10.has_org_cap($1,'act.post_customer_transactions') c",[org])).rows[0];
  const posted=tx?(await s.query('select count(*)::int n from public.e10_customer_transactions where id=$1',[tx])).rows[0].n:0;
  console.log(JSON.stringify({post_outcome:outcome,posted_rows_after_revocation:posted,membership_after:(await s.query("select status from public.e10_organization_memberships where organization_id=$1 and user_id=$2",[org,x.u])).rows[0]}));
 }catch(e){console.error('MAIN ERROR',e.message);}finally{
  await b.query('reset role').catch(()=>{});await s.query('rollback').catch(()=>{});
  await s.query('set session_replication_role=replica').catch(()=>{});
  const del=async(q,a)=>{try{await s.query(q,a)}catch(e){console.error('cleanup',e.message)}};
  await del("delete from public.e10_commercial_events where organization_id=$1 and created_by=$2",[org,x.u]);
  await del("delete from public.e10_customer_transaction_source_claims where organization_id=$1 and source_line_id like $2",[org,x.run+'%']);
  await del("delete from public.e10_customer_transaction_lines where organization_id=$1 and source_line_id like $2",[org,x.run+'%']);
  await del("delete from public.e10_customer_transactions where organization_id=$1 and source_draft_id=$2",[org,draft]);
  await del("delete from public.e10_customer_transaction_approval_activity_snapshots where organization_id=$1 and approval_decision_id in (select id from public.e10_customer_transaction_draft_decisions where draft_id=$2)",[org,draft]);
  await del("update public.e10_customer_transaction_drafts set approval_decision_id=null,posted_transaction_id=null where id=$1",[draft]);
  await del("delete from public.e10_customer_transaction_draft_decisions where organization_id=$1 and draft_id=$2",[org,draft]);
  await del("delete from public.e10_customer_transaction_draft_lines where organization_id=$1 and draft_id=$2",[org,draft]);
  await del("delete from public.e10_customer_transaction_draft_revisions where organization_id=$1 and draft_id=$2",[org,draft]);
  await del("delete from public.e10_customer_transaction_drafts where organization_id=$1 and id=$2",[org,draft]);
  await del("delete from public.e10_customer_commercial_receipts where organization_id=$1 and idempotency_key like $2",[org,x.run+'%']);
  await del("delete from public.e10_customers where id=$1",[x.customer]);
  await del("delete from public.e10_organization_memberships where user_id=$1",[x.u]);
  await del("delete from public.e10_organization_role_permissions where role_id=$1",[x.role]);
  await del("delete from public.e10_organization_roles where id=$1",[x.role]);
  await del("delete from auth.users where id=$1",[x.u]);
  await s.query('set session_replication_role=origin').catch(()=>{});
  const residue=(await s.query("select (select count(*) from public.e10_customer_transactions where source_draft_id=$1)+(select count(*) from public.e10_customer_transaction_drafts where id=$1)+(select count(*) from public.e10_customer_transaction_lines where source_line_id like $2)+(select count(*) from public.e10_customer_transaction_source_claims where source_line_id like $2)+(select count(*) from public.e10_commercial_events where created_by=$3)+(select count(*) from public.e10_customer_commercial_receipts where idempotency_key like $2)+(select count(*) from public.e10_customers where id=$4)+(select count(*) from auth.users where id=$3)+(select count(*) from public.e10_organization_roles where id=$5)+(select count(*) from public.e10_organization_memberships where user_id=$3) n",[draft,x.run+'%',x.u,x.customer,x.role])).rows[0].n;
  console.log('residue='+residue);
  await Promise.all([s.end(),b.end()]);
 }}
main().catch(e=>{console.error(e.stack);process.exit(1)});
