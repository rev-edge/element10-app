const {Client}=require('pg');
const {randomUUID}=require('crypto');
const db=process.env.E10_DB_URL||'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
async function actor(id){const c=new Client({connectionString:db});await c.connect();await c.query("set statement_timeout='8s'");await c.query('select set_config($1,$2,false)',['request.jwt.claims',JSON.stringify({sub:id,role:'authenticated'})]);await c.query('set role authenticated');return c}
async function main(){const s=new Client({connectionString:db});await s.connect();const x={admin:randomUUID(),player:randomUUID(),team:randomUUID(),key:randomUUID()};let a,b;
 try{
  await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[x.admin,x.admin+'@x.invalid']);
  await s.query('insert into public.e10_platform_admins(user_id)values($1)',[x.admin]);
  await s.query("insert into public.e10_players(id,name,sport)values($1,$2,'soccer')",[x.player,'X1b '+x.player]);
  await s.query("insert into public.e10_teams(id,name,sport,league)values($1,$2,'soccer','league-a')",[x.team,'X1b '+x.team]);
  [a,b]=await Promise.all([actor(x.admin),actor(x.admin)]);
  const sql="select public.e10_platform_review_player_affiliation(null,$1,$2,'soccer','league-a','2020-01-01',null,0,'assert','official_source','official:race','race proof','{}',$3) r";
  const settled=await Promise.allSettled([a.query(sql,[x.player,x.team,x.key]),b.query(sql,[x.player,x.team,x.key])]);
  if(settled.some(z=>z.status!=='fulfilled'))throw settled.find(z=>z.status==='rejected').reason;
  const replay=settled.map(z=>z.value.rows[0].r.replay).sort();if(replay[0]!==false||replay[1]!==true)throw Error('expected one insert and one replay: '+JSON.stringify(replay));
  const n=Number((await s.query('select count(*) n from public.e10_player_affiliation_decisions where idempotency_key=$1',[x.key])).rows[0].n);if(n!==1)throw Error('expected one durable decision, got '+n);
  let mismatch=false;try{await a.query("select public.e10_platform_review_player_affiliation(null,$1,$2,'soccer','league-a','2020-01-01',null,0,'assert','official_source','official:race','different','{}',$3)",[x.player,x.team,x.key])}catch(e){mismatch=e.code==='22023'&&e.message==='idempotency_key_mismatch'}if(!mismatch)throw Error('changed-payload replay was not rejected');
  console.log('TA-X1b concurrent idempotency: PASS (one insert, one replay, mismatch denied)');
 }finally{
  for(const c of[a,b])if(c){await c.query('reset role').catch(()=>{});await c.end().catch(()=>{})}
  await s.query('set session_replication_role=replica');await s.query('delete from public.e10_player_affiliation_decisions where idempotency_key=$1',[x.key]);await s.query('delete from public.e10_platform_admins where user_id=$1',[x.admin]);await s.query('delete from public.e10_players where id=$1',[x.player]);await s.query('delete from public.e10_teams where id=$1',[x.team]);await s.query('set session_replication_role=origin');await s.query('delete from auth.users where id=$1',[x.admin]);
  const residue=Number((await s.query('select (select count(*)from public.e10_player_affiliation_decisions where idempotency_key=$1)+(select count(*)from auth.users where id=$2)n',[x.key,x.admin])).rows[0].n);await s.end();if(residue)throw Error('cleanup residue '+residue)
 }}
main().catch(e=>{console.error(e.stack);process.exit(1)});
