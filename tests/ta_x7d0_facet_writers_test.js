const {Client}=require('pg');const {randomUUID}=require('crypto');
const db=process.env.E10_DB_URL||'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
async function denied(p,code,msg){try{await p;return false}catch(e){return e.code===code&&e.message===msg}}
async function actor(id){const c=new Client({connectionString:db});await c.connect();await c.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id,role:'authenticated'})]);await c.query('set role authenticated');return c}
async function main(){const s=new Client({connectionString:db});await s.connect();const x={org:randomUUID(),admin:randomUUID(),user:randomUUID(),role:randomUUID(),release:randomUUID(),variant:randomUUID(),run:randomUUID()};let p,a,termKey,ok=false;
 try{
  for(const [id,email]of[[x.admin,'pa'],[x.user,'u']])await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[id,`${email}-${x.run}@x.invalid`]);
  await s.query('insert into public.e10_platform_admins(user_id)values($1)',[x.admin]);
  await s.query("insert into public.e10_organizations(id,slug,name)values($1,$2,'X7d writers')",[x.org,'x7dw-'+x.run.slice(0,8)]);
  await s.query("insert into public.e10_organization_roles(organization_id,id,key,name)values($1,$2,$3,'reviewer')",[x.org,x.role,x.run]);
  await s.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values($1,$2,$3,'active')",[x.org,x.user,x.role]);
  await s.query("insert into public.e10_catalog_releases(id,release_name)values($1,'X7d')",[x.release]);await s.query('insert into public.e10_catalog_variants(id,release_id)values($1,$2)',[x.variant,x.release]);
  [p,a]=await Promise.all([actor(x.admin),actor(x.user)]);
  const term=(...z)=>p.query('select public.e10_platform_review_catalog_facet_term($1,$2,$3,$4,$5,$6,$7,$8) r',z);
  let r=(await term(null,0,'color_family','Blue','assert','initial',{},x.run+'-term1')).rows[0].r;termKey=r.term_key;if(r.replay||r.revision!==1)throw Error('term create failed');
  if(!(await term(null,0,'color_family','Blue','assert','initial',{},x.run+'-term1')).rows[0].r.replay)throw Error('term replay failed');
  if(!(await denied(term(null,0,'color_family','Blue','assert','changed',{},x.run+'-term1'),'22023','idempotency_key_mismatch')))throw Error('term mismatch accepted');
  if(!(await denied(a.query('select public.e10_platform_review_catalog_facet_term(null,0,$1,$2,$3,$4,$5,$6)',['finish_family','Chrome','assert','tenant',{},x.run+'-tenant-global']),'42501','platform_catalog_curation_denied')))throw Error('tenant changed global taxonomy');
  r=(await p.query('select public.e10_platform_review_catalog_facet_alias(null,0,$1,$2,$3,$4,$5,$6,$7) r',['color_family','blue','assert',termKey,'alias',{},x.run+'-alias'])).rows[0].r;if(r.revision!==1)throw Error('alias failed');
  if(!(await p.query('select public.e10_platform_review_catalog_facet_alias(null,0,$1,$2,$3,$4,$5,$6,$7) r',['color_family','blue','assert',termKey,'alias',{},x.run+'-alias'])).rows[0].r.replay)throw Error('alias replay failed');
  if(!(await denied(p.query('select public.e10_platform_review_catalog_facet_alias(null,0,$1,$2,$3,$4,$5,$6,$7)',['color_family','blue','assert',termKey,'changed',{},x.run+'-alias']),'22023','idempotency_key_mismatch')))throw Error('alias mismatch accepted');
  if(!(await denied(a.query('select public.e10_platform_review_catalog_facet_alias(null,0,$1,$2,$3,$4,$5,$6,$7)',['color_family','tenant','assert',termKey,'x',{},x.run+'-tenant-alias']),'42501','platform_catalog_curation_denied')))throw Error('tenant changed global alias');
  r=(await p.query('select public.e10_platform_review_catalog_variant_facet(null,$1,null,$2,0,$3,null,null,$4,$5,$6,$7) r',[x.variant,'color_family','assert',termKey,'facet',{},x.run+'-facet'])).rows[0].r;const globalKey=r.decision_key;if(r.revision!==1)throw Error('global facet failed');
  if(!(await p.query('select public.e10_platform_review_catalog_variant_facet(null,$1,null,$2,0,$3,null,null,$4,$5,$6,$7) r',[x.variant,'color_family','assert',termKey,'facet',{},x.run+'-facet'])).rows[0].r.replay)throw Error('global facet replay failed');
  if(!(await denied(p.query('select public.e10_platform_review_catalog_variant_facet($1,$2,null,$3,0,$4,null,null,null,$5,$6,$7)',[globalKey,x.variant,'color_family','revoke','stale',{},x.run+'-facet-stale']),'40001','catalog_variant_facet_revision_conflict')))throw Error('global facet stale CAS accepted');
  if(!(await denied(a.query('select public.e10_platform_review_catalog_variant_facet(null,$1,null,$2,0,$3,null,null,$4,$5,$6,$7)',[x.variant,'color_family','assert',termKey,'tenant',{},x.run+'-tenant-facet']),'42501','platform_catalog_curation_denied')))throw Error('tenant changed global facet');
  const orgCall=(key,expected,action,val,idk)=>a.query('select public.e10_org_review_catalog_variant_facet_override($1,$2,$3,null,$4,$5,$6,$7,null,null,$8,$9,$10) r',[x.org,key,x.variant,'rookie_designation',expected,action,val,'org',{},idk]);
  if(!(await denied(orgCall(null,0,'assert',true,x.run+'-nocap'),'42501','market_facet_curation_denied')))throw Error('missing capability accepted');
  await s.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values($1,$2,'act.curate_market_analytics',true)",[x.org,x.role]);
  r=(await orgCall(null,0,'mask',null,x.run+'-org1')).rows[0].r;const key=r.decision_key;if(r.revision!==1||r.action!=='mask')throw Error('root mask failed');
  if(!(await orgCall(null,0,'mask',null,x.run+'-org1')).rows[0].r.replay)throw Error('org replay failed');
  if(!(await denied(orgCall(key,0,'clear',null,x.run+'-stale'),'40001','market_facet_override_revision_conflict')))throw Error('stale CAS accepted');
  r=(await orgCall(key,1,'clear',null,x.run+'-clear')).rows[0].r;if(r.revision!==2||r.action!=='clear')throw Error('clear failed');
  r=(await orgCall(key,2,'assert',false,x.run+'-assert')).rows[0].r;if(r.revision!==3||r.action!=='assert')throw Error('positive org assert failed');
  r=(await orgCall(key,3,'mask',null,x.run+'-mask2')).rows[0].r;if(r.revision!==4||r.action!=='mask')throw Error('second mask failed');
  if(!await denied(a.query("select public.e10_org_review_catalog_variant_facet_override($1,null,$2,null,'rookie_designation',0,'mask',null,null,null,'foreign','{}',$3)",[randomUUID(),x.variant,x.run+'-foreign']),'42501','market_facet_curation_denied'))throw Error('cross-org write accepted');
  await s.query("update public.e10_organizations set status='suspended' where id=$1",[x.org]);if(!(await denied(orgCall(key,4,'assert',false,x.run+'-suspended'),'42501','market_facet_curation_denied')))throw Error('suspended org accepted');await s.query("update public.e10_organizations set status='active' where id=$1",[x.org]);
  const before=(await s.query('select revision from public.e10_market_org_revisions where organization_id=$1',[x.org])).rows[0].revision;
  await s.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.curate_market_analytics'",[x.org,x.role]);
  if(!(await denied(orgCall(key,4,'assert',false,x.run+'-revoked-cap'),'42501','market_facet_curation_denied')))throw Error('revoked capability accepted');
  const after=(await s.query('select revision from public.e10_market_org_revisions where organization_id=$1',[x.org])).rows[0].revision;if(before!==after)throw Error('denied call changed revision');
  const acl=(await s.query("select has_function_privilege('anon','public.e10_org_review_catalog_variant_facet_override(uuid,uuid,uuid,uuid,text,bigint,text,boolean,integer,uuid,text,jsonb,text)','execute') org_anon,has_function_privilege('anon','public.e10_platform_review_catalog_facet_term(uuid,bigint,text,text,text,text,jsonb,text)','execute') term_anon,has_function_privilege('anon','public.e10_platform_review_catalog_facet_alias(uuid,bigint,text,text,text,uuid,text,jsonb,text)','execute') alias_anon,has_function_privilege('anon','public.e10_platform_review_catalog_variant_facet(uuid,uuid,uuid,text,bigint,text,boolean,integer,uuid,text,jsonb,text)','execute') facet_anon,has_table_privilege('authenticated','public.e10_market_org_revisions','select') direct")).rows[0];if(Object.values(acl).some(Boolean))throw Error('ACL leak');
  const global=Number((await s.query('select revision from public.e10_market_catalog_revision where singleton')).rows[0].revision),org=Number(after);if(global<=1||org<=1)throw Error('revisions not advanced');ok=true;
 }finally{
  for(const c of[p,a])if(c){await c.query('reset role').catch(()=>{});await c.end()}
  await s.query('set session_replication_role=replica');for(const t of['e10_org_catalog_variant_facet_overrides','e10_organization_role_permissions','e10_organization_memberships','e10_organization_roles','e10_market_org_revisions'])await s.query(`delete from public.${t} where organization_id=$1`,[x.org]);
  await s.query('delete from public.e10_catalog_variant_facet_decisions where variant_id=$1',[x.variant]);await s.query('delete from public.e10_catalog_variants where id=$1',[x.variant]);await s.query('delete from public.e10_catalog_releases where id=$1',[x.release]);
  await s.query("delete from public.e10_catalog_facet_taxonomy_aliases where idempotency_key like $1",[x.run+'%']);await s.query("delete from public.e10_catalog_facet_taxonomy_terms where idempotency_key like $1",[x.run+'%']);if(termKey)await s.query('delete from public.e10_catalog_facet_term_keys where id=$1',[termKey]);
  await s.query('delete from public.e10_platform_admins where user_id=$1',[x.admin]);await s.query('delete from public.e10_organizations where id=$1',[x.org]);await s.query('set session_replication_role=origin');await s.query('delete from auth.users where id=any($1)',[[x.admin,x.user]]);await s.end();
 }
 if(ok)console.log('TA-X7d.0 facet writers and revisions: PASS');
}
main().catch(e=>{console.error(e.stack);process.exit(1)});
