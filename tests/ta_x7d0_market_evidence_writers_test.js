const {Client}=require('pg');const {randomUUID}=require('crypto');
const db=process.env.E10_DB_URL||'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
async function denied(p,code,msg){try{await p;return false}catch(e){return e.code===code&&e.message===msg}}
async function deniedCode(p,code){try{await p;return false}catch(e){return e.code===code}}
async function actor(id){const c=new Client({connectionString:db});await c.connect();await c.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id,role:'authenticated'})]);await c.query('set role authenticated');return c}
async function main(){const s=new Client({connectionString:db});await s.connect();const x={org:randomUUID(),org2:randomUUID(),user:randomUUID(),role:randomUUID(),release:randomUUID(),variant:randomUUID(),player:randomUUID(),item:randomUUID(),item2:randomUUID(),a:randomUUID(),b:randomUUID(),c:randomUUID(),run:randomUUID()};let a,ok=false;
 try{
  await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[x.user,`x7de-${x.run}@x.invalid`]);
  await s.query("insert into public.e10_organizations(id,slug,name)values($1,$2,'X7d evidence writers'),($3,$4,'Foreign')",[x.org,'x7dew-'+x.run.slice(0,8),x.org2,'x7def-'+x.run.slice(0,8)]);
  await s.query("insert into public.e10_organization_roles(organization_id,id,key,name)values($1,$2,$3,'reviewer')",[x.org,x.role,x.run]);
  await s.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values($1,$2,$3,'active')",[x.org,x.user,x.role]);
  await s.query("insert into public.e10_catalog_releases(id,release_name)values($1,'X7d')",[x.release]);await s.query('insert into public.e10_players(id,name)values($1,$2)',[x.player,'Subject '+x.run]);await s.query('insert into public.e10_catalog_variants(id,release_id)values($1,$2)',[x.variant,x.release]);await s.query('insert into public.e10_catalog_variant_subjects(variant_id,player_id)values($1,$2)',[x.variant,x.player]);
  await s.query("insert into public.e10_unique_items(id,organization_id,catalog_variant_id,item_kind)values($1,$2,$3,'card'),($4,$5,$3,'card')",[x.item,x.org,x.variant,x.item2,x.org2]);
  await s.query("insert into public.e10_market_observations(id,organization_id,observation_kind,catalog_variant_id,occurred_at,currency,amount,quantity,source_kind,raw_payload_snapshot)values($1,$2,'completed_sale',$3,'2026-01-01T00:00:00Z','USD',500,5,'manual','{}'),($4,$2,'completed_sale',$3,'2026-01-01T00:00:00Z','USD',500,5,'csv','{}'),($5,$6,'completed_sale',$3,'2026-01-01T00:00:00Z','USD',500,5,'manual','{}')",[x.a,x.org,x.variant,x.b,x.c,x.org2]);
  a=await actor(x.user);
  const copy=(key,rev,action,idk,reason='copy')=>a.query('select public.e10_org_review_unique_item_facet($1,$2,$3,$4,$5,$6,null,null,null,null,$7,$8,$9,$10) r',[x.org,key,x.item,x.player,rev,action,action==='assert'?'factory dot':null,reason,{},idk]);
  if(!(await denied(copy(null,0,'assert',x.run+'-nocap'),'42501','market_evidence_curation_denied')))throw Error('missing capability accepted');
  await s.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values($1,$2,'act.curate_market_analytics',true)",[x.org,x.role]);
  let r=(await copy(null,0,'assert',x.run+'-copy')).rows[0].r,copyKey=r.decision_key;if(r.revision!==1||r.replay)throw Error('copy create failed');
  if(!(await copy(null,0,'assert',x.run+'-copy')).rows[0].r.replay)throw Error('copy replay failed');
  if(!(await denied(copy(null,0,'assert',x.run+'-copy','changed'),'22023','idempotency_key_mismatch')))throw Error('copy mismatch accepted');
  if(!(await denied(copy(copyKey,0,'revoke',x.run+'-copy-stale'),'40001','market_evidence_revision_conflict')))throw Error('copy stale CAS accepted');
  r=(await copy(copyKey,1,'revoke',x.run+'-copy-revoke')).rows[0].r;if(r.revision!==2)throw Error('copy revoke failed');
  if(!(await deniedCode(a.query("select public.e10_org_review_unique_item_facet($1,null,$2,$3,0,'assert',null,null,null,null,'x','foreign','{}',$4)",[x.org,x.item2,x.player,x.run+'-foreign-copy']),'23503')))throw Error('foreign copy target accepted');
  const fact=(obs,key,rev,action,idk)=>a.query('select public.e10_org_review_market_observation_fact($1,$2,$3,$4,$5,$6,null,null,null,null,null,null,null,null,null,null,$7,$8,$9,$10,$11,$12) r',[x.org,key,obs,rev,action,action==='assert'?'raw':null,action==='assert'?5:null,action==='assert'?'transaction_total':null,action==='assert'?100:null,'fact',{},idk]);
  const fa=(await fact(x.a,null,0,'assert',x.run+'-fa')).rows[0].r,fb=(await fact(x.b,null,0,'assert',x.run+'-fb')).rows[0].r;if(fa.revision!==1||fb.revision!==1)throw Error('fact create failed');
  if(!(await deniedCode(fact(x.c,null,0,'assert',x.run+'-foreign-fact'),'23503')))throw Error('foreign observation fact accepted');
  if(!(await fact(x.a,null,0,'assert',x.run+'-fa')).rows[0].r.replay)throw Error('fact replay failed');
  const eq=(dup,canon,key,rev,action,idk)=>a.query('select public.e10_org_review_market_observation_equivalence($1,$2,$3,$4,$5,$6,$7,$8,$9) r',[x.org,key,dup,canon,rev,action,'equivalence',{},idk]);
  r=(await eq(x.a,x.b,null,0,'link',x.run+'-eq')).rows[0].r;const eqKey=r.decision_key;if(r.revision!==1)throw Error('equivalence create failed');
  if(!(await eq(x.a,x.b,null,0,'link',x.run+'-eq')).rows[0].r.replay)throw Error('equivalence replay failed');
  if(!(await denied(eq(x.b,x.a,null,0,'link',x.run+'-cycle'),'23514','observation_equivalence_cycle')))throw Error('cycle accepted');
  if(!(await denied(eq(x.b,x.c,null,0,'link',x.run+'-foreign-eq'),'23514','observation_equivalence_incoherent')))throw Error('foreign equivalence accepted');
  const cov=(key,rev,action,status,idk,org=x.org)=>a.query("select public.e10_org_review_market_observation_coverage($1,$2,'completed_sale','csv','shop-a','USD','2026-01-01T00:00:00Z','2026-02-01T00:00:00Z',$3,$4,$5,'coverage','{}',$6) r",[org,key,rev,action,status,idk]);
  r=(await cov(null,0,'assert','complete',x.run+'-cov')).rows[0].r;const covKey=r.decision_key;if(r.revision!==1)throw Error('coverage create failed');
  await a.query("set timezone='America/Toronto'");if(!(await cov(null,0,'assert','complete',x.run+'-cov')).rows[0].r.replay)throw Error('coverage replay changed across timezone');
  await s.query("set timezone='UTC'");const z1=(await s.query('select e10.market_observation_fingerprint($1,$2) fp',[x.org,x.a])).rows[0].fp;await s.query("set timezone='America/Toronto'");const z2=(await s.query('select e10.market_observation_fingerprint($1,$2) fp',[x.org,x.a])).rows[0].fp;if(z1!==z2)throw Error('observation fingerprint changed across timezone');const status=(await s.query('select review_status from public.e10_market_observation_equivalence_status where organization_id=$1 and decision_key=$2',[x.org,eqKey])).rows;if(status.length!==1||status[0].review_status!=='valid')throw Error('equivalence validity changed across timezone');
  r=(await eq(x.a,null,eqKey,1,'unlink',x.run+'-unlink')).rows[0].r;if(r.revision!==2)throw Error('unlink failed');
  if(!(await denied(cov(covKey,0,'revoke',null,x.run+'-cov-stale'),'40001','market_evidence_revision_conflict')))throw Error('coverage stale CAS accepted');
  r=(await cov(covKey,1,'revoke',null,x.run+'-cov-revoke')).rows[0].r;if(r.revision!==2)throw Error('coverage revoke failed');
  if(!(await denied(cov(null,0,'assert','complete',x.run+'-foreign',x.org2),'42501','market_evidence_curation_denied')))throw Error('foreign coverage org accepted');
  await s.query("update public.e10_organization_memberships set status='suspended'where organization_id=$1 and user_id=$2",[x.org,x.user]);if(!(await denied(cov(covKey,2,'assert','complete',x.run+'-suspended'),'42501','market_evidence_curation_denied')))throw Error('suspended member accepted');
  const acl=(await s.query("select has_function_privilege('anon','public.e10_org_review_unique_item_facet(uuid,uuid,uuid,uuid,bigint,text,boolean,text,text,text,text,text,jsonb,text)','execute') a,has_function_privilege('anon','public.e10_org_review_market_observation_fact(uuid,uuid,uuid,bigint,text,text,text,text,text,integer,integer,boolean,uuid,text,text,text,numeric,text,numeric,text,jsonb,text)','execute') b,has_function_privilege('anon','public.e10_org_review_market_observation_equivalence(uuid,uuid,uuid,uuid,bigint,text,text,jsonb,text)','execute') c,has_function_privilege('anon','public.e10_org_review_market_observation_coverage(uuid,uuid,text,text,text,text,timestamp with time zone,timestamp with time zone,bigint,text,text,text,jsonb,text)','execute') d")).rows[0];if(Object.values(acl).some(Boolean))throw Error('anon execute leak');
  ok=true;
 }finally{
  if(a){await a.query('reset role').catch(()=>{});await a.end()}
  await s.query('set session_replication_role=replica');for(const t of['e10_market_observation_equivalence_decisions','e10_market_observation_fact_decisions','e10_unique_item_facet_decisions','e10_market_observation_coverage_decisions','e10_market_observations','e10_unique_items'])await s.query(`delete from public.${t} where organization_id=any($1)`,[[x.org,x.org2]]);await s.query('delete from public.e10_catalog_variant_subjects where variant_id=$1',[x.variant]);await s.query('delete from public.e10_catalog_variants where id=$1',[x.variant]);await s.query('delete from public.e10_catalog_releases where id=$1',[x.release]);await s.query('delete from public.e10_players where id=$1',[x.player]);for(const t of['e10_organization_role_permissions','e10_organization_memberships','e10_organization_roles','e10_market_org_revisions'])await s.query(`delete from public.${t} where organization_id=any($1)`,[[x.org,x.org2]]);await s.query('delete from public.e10_organizations where id=any($1)',[[x.org,x.org2]]);await s.query('set session_replication_role=origin');await s.query('delete from auth.users where id=$1',[x.user]);await s.end();
 }
 if(ok)console.log('TA-X7d.0 market evidence writers: PASS');
}
main().catch(e=>{console.error(e.stack);process.exit(1)});
