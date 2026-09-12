const {Client}=require('pg');const {randomUUID}=require('crypto');
const db=process.env.E10_DB_URL||'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const x={org:randomUUID(),events:[randomUUID(),randomUUID(),randomUUID(),randomUUID()],rows:[randomUUID(),randomUUID(),randomUUID(),randomUUID()],consumers:[randomUUID(),randomUUID()]};
async function settled(p){try{return{ok:true,value:await p}}catch(error){return{ok:false,error}}}
async function blocked(observer,pid,label){for(let n=0;n<120;n++){const r=await observer.query("select count(*)::int n from pg_locks where pid=$1 and not granted",[pid]);if(r.rows[0].n>0){console.log(`[proof] ${label}: backend ${pid} owns an ungranted database lock`);return}await new Promise(r=>setTimeout(r,25))}throw Error(`${label} did not establish the exact lock wait`)}
async function main(){const s=new Client({connectionString:db}),a=new Client({connectionString:db}),b=new Client({connectionString:db}),lock=new Client({connectionString:db}),observer=new Client({connectionString:db});await Promise.all([s.connect(),a.connect(),b.connect(),lock.connect(),observer.connect()]);let pending=[];
 try{
  for(const c of[s,a,b,lock,observer])await c.query("set statement_timeout='10s'");
  await s.query("insert into e10_organizations(id,slug,name)values($1,$2,'X8c concurrency')",[x.org,'x8cc-'+x.org.slice(0,8)]);
  for(let i=0;i<4;i++)await s.query("insert into e10_commercial_events(id,organization_id,event_type,subject_type,subject_id,occurred_at,idempotency_key,source_kind,payload,request_fingerprint)values($1,$2,'listing_created','inventory_item',$3::text,now(),$4::text,'manual',jsonb_build_object('listing_id',$3::text,'channel','manual'),$4::text)",[x.events[i],x.org,`x8c-${i}`,`x8c-${x.events[i]}`]);
  await s.query("insert into e10_outbox_consumers(id,organization_id,consumer_key,allowed_destination_keys)values($1,$3,'worker-1',array['destination-a']),($2,$3,'worker-2',array['destination-a'])",[x.consumers[0],x.consumers[1],x.org]);
  for(let i=0;i<4;i++)await s.query("insert into e10_integration_outbox(id,organization_id,commercial_event_id,destination_key,payload,next_attempt_at)values($1,$2,$3,'destination-a',jsonb_build_object('event',$4::text),case when $5::boolean then now()+interval '1 hour' end)",[x.rows[i],x.org,x.events[i],String(i),i>0]);

  const [oneA,oneB]=await Promise.all([
    a.query('select e10_claim_outbox($1,$2,1,60,$3)j',[x.org,x.consumers[0],'single-a-'+x.org]),
    b.query('select e10_claim_outbox($1,$2,1,60,$3)j',[x.org,x.consumers[1],'single-b-'+x.org])]);
  const single=[oneA.rows[0].j,oneB.rows[0].j];if(single.reduce((n,j)=>n+Number(j.count),0)!==1)throw Error('one-row claim race had other than one owner '+JSON.stringify(single));
  const wi=Number(single[0].count)===1?0:1,winnerConsumer=x.consumers[wi],claim=single[wi].claims[0];
  console.log('[proof] two consumers racing one eligible row produced one active owner');

  const ackKey='exact-ack-'+x.org;
  const [ackA,ackB]=await Promise.all([
    a.query("select e10_ack_outbox($1,$2,$3,$4,$5,'delivered',null,null,$6)j",[x.org,winnerConsumer,x.rows[0],claim.claim_token,claim.claim_generation,ackKey]),
    b.query("select e10_ack_outbox($1,$2,$3,$4,$5,'delivered',null,null,$6)j",[x.org,winnerConsumer,x.rows[0],claim.claim_token,claim.claim_generation,ackKey])]);
  const acks=[ackA.rows[0].j,ackB.rows[0].j];if(acks.filter(j=>j.replay===false).length!==1||acks.filter(j=>j.replay===true).length!==1)throw Error('exact ack race was not one transition plus replay '+JSON.stringify(acks));
  const receipt=await s.query('select count(*)::int n from e10_outbox_acknowledgements where organization_id=$1 and outbox_id=$2',[x.org,x.rows[0]]);if(receipt.rows[0].n!==1)throw Error('exact ack race duplicated receipt');
  console.log('[proof] concurrent exact acknowledgements produced one immutable receipt and one replay');

  await s.query('update e10_integration_outbox set next_attempt_at=null where organization_id=$1 and id=any($2::uuid[])',[x.org,x.rows.slice(1,3)]);
  const [batchA,batchB]=await Promise.all([
    a.query('select e10_claim_outbox($1,$2,1,60,$3)j',[x.org,x.consumers[0],'batch-a-'+x.org]),
    b.query('select e10_claim_outbox($1,$2,1,60,$3)j',[x.org,x.consumers[1],'batch-b-'+x.org])]);
  const batches=[batchA.rows[0].j,batchB.rows[0].j],ids=batches.flatMap(j=>j.claims.map(c=>c.outbox_id));
  if(ids.length!==2||new Set(ids).size!==2)throw Error('disjoint bounded claims duplicated or omitted work '+JSON.stringify(batches));
  console.log('[proof] concurrent bounded batches claimed two disjoint rows without duplication');

  const revoked=batches[0].claims[0],revokedConsumer=x.consumers[0];
  await lock.query('begin');await lock.query('select 1 from e10_integration_outbox where organization_id=$1 and id=$2 for update',[x.org,revoked.outbox_id]);
  const pid=(await a.query('select pg_backend_pid()pid')).rows[0].pid;
  const waiting=settled(a.query("select e10_ack_outbox($1,$2,$3,$4,$5,'delivered',null,null,$6)j",[x.org,revokedConsumer,revoked.outbox_id,revoked.claim_token,revoked.claim_generation,'revoked-'+x.org]));pending.push(waiting);
  await blocked(observer,pid,'revoked acknowledgement');
  await s.query('update e10_outbox_consumers set enabled=false where organization_id=$1 and id=$2',[x.org,revokedConsumer]);
  await lock.query('commit');const denied=await waiting;if(denied.ok||denied.error.code!=='42501'||denied.error.message!=='outbox_destination_denied')throw Error('post-row-lock revocation did not fail closed');
  const state=await s.query('select status,delivered_at from e10_integration_outbox where organization_id=$1 and id=$2',[x.org,revoked.outbox_id]);if(state.rows[0].status!=='pending'||state.rows[0].delivered_at!==null)throw Error('revoked ack changed row');
  console.log('[proof] row-lock waiter rechecked revoked authority and left no acknowledgement');

  const removed=batches[1].claims[0],removedConsumer=x.consumers[1];
  await lock.query('begin');await lock.query('select 1 from e10_integration_outbox where organization_id=$1 and id=$2 for update',[x.org,removed.outbox_id]);
  const bpid=(await b.query('select pg_backend_pid()pid')).rows[0].pid;
  const removedAck=settled(b.query("select e10_ack_outbox($1,$2,$3,$4,$5,'delivered',null,null,$6)j",[x.org,removedConsumer,removed.outbox_id,removed.claim_token,removed.claim_generation,'removed-'+x.org]));pending.push(removedAck);
  await blocked(observer,bpid,'destination-removed acknowledgement');
  await s.query("update e10_outbox_consumers set allowed_destination_keys='{}' where organization_id=$1 and id=$2",[x.org,removedConsumer]);
  await lock.query('commit');const removedDenied=await removedAck;if(removedDenied.ok||removedDenied.error.code!=='42501'||removedDenied.error.message!=='outbox_destination_denied')throw Error('post-row-lock destination removal did not fail closed');
  const removedState=await s.query('select status,delivered_at from e10_integration_outbox where organization_id=$1 and id=$2',[x.org,removed.outbox_id]);if(removedState.rows[0].status!=='pending'||removedState.rows[0].delivered_at!==null)throw Error('destination-removed ack changed row');
  console.log('[proof] row-lock waiter rechecked removed destination entitlement with no acknowledgement');
 }finally{
  await Promise.allSettled(pending);await lock.query('rollback').catch(()=>{});await s.query('set session_replication_role=replica').catch(()=>{});
  for(const table of['e10_outbox_acknowledgements','e10_outbox_claim_commands','e10_integration_outbox','e10_outbox_consumers','e10_commercial_events'])await s.query(`delete from ${table} where organization_id=$1`,[x.org]).catch(()=>{});
  await s.query('delete from e10_organizations where id=$1',[x.org]).catch(()=>{});await s.query('set session_replication_role=origin').catch(()=>{});for(const c of[s,a,b,lock,observer])await c.end().catch(()=>{});
 }
 console.log('TA-X8c outbox concurrency: PASS');
}
main().catch(e=>{console.error(e.stack);process.exit(1)});
