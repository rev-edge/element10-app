const {Client}=require('pg');
const {randomUUID}=require('crypto');
const db=process.env.E10_DB_URL||'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const x={a:randomUUID(),b:randomUUID(),c1:randomUUID(),c2:randomUUID(),c3:randomUUID(),c4:randomUUID(),c5:randomUUID()};

async function main(){
  const a=new Client({connectionString:db}),b=new Client({connectionString:db});
  await Promise.all([a.connect(),b.connect()]);
  let pass=false;
  try{
    await a.query("insert into public.e10_checklists(id,name)values($1,'C5 A'),($2,'C5 B')",[x.a,x.b]);
    await a.query("insert into public.e10_cards(id,checklist_id,name)values($1,$4,'one'),($2,$4,'two'),($3,$4,'three')",[x.c1,x.c2,x.c3,x.a]);
    if(Number((await a.query('select card_count from public.e10_checklists where id=$1',[x.a])).rows[0].card_count)!==3)throw Error('batch insert count mismatch');
    await a.query("update public.e10_cards set name=name||' revised' where checklist_id=$1",[x.a]);
    if(Number((await a.query('select card_count from public.e10_checklists where id=$1',[x.a])).rows[0].card_count)!==3)throw Error('non-key update changed count');
    await a.query('update public.e10_cards set checklist_id=$1 where id=$2',[x.b,x.c3]);
    const moved=(await a.query('select id,card_count from public.e10_checklists where id=any($1::uuid[]) order by id',[x.a<x.b?[x.a,x.b]:[x.b,x.a]])).rows;
    const byId=Object.fromEntries(moved.map(r=>[r.id,Number(r.card_count)]));
    if(byId[x.a]!==2||byId[x.b]!==1)throw Error('move count mismatch '+JSON.stringify(byId));
    await a.query('delete from public.e10_cards where id=any($1::uuid[])',[[x.c1,x.c2]]);
    if(Number((await a.query('select card_count from public.e10_checklists where id=$1',[x.a])).rows[0].card_count)!==0)throw Error('delete count mismatch');
    let denied=false;try{await a.query('update public.e10_checklists set card_count=99 where id=$1',[x.a]);}catch(e){denied=e.code==='23514'&&e.message==='checklist_card_count_is_maintained';}if(!denied)throw Error('direct count drift accepted');
    await Promise.all([
      a.query("insert into public.e10_cards(id,checklist_id,name)values($1,$2,'concurrent a')",[x.c4,x.a]),
      b.query("insert into public.e10_cards(id,checklist_id,name)values($1,$2,'concurrent b')",[x.c5,x.a])
    ]);
    const final=(await a.query('select c.card_count,(select count(*) from public.e10_cards where checklist_id=c.id) actual from public.e10_checklists c where id=$1',[x.a])).rows[0];
    if(Number(final.card_count)!==2||Number(final.actual)!==2)throw Error('concurrent count mismatch '+JSON.stringify(final));
    pass=true;
  }finally{
    await a.query('delete from public.e10_cards where checklist_id=any($1::uuid[])',[[x.a,x.b]]).catch(()=>{});
    await a.query('delete from public.e10_checklists where id=any($1::uuid[])',[[x.a,x.b]]).catch(()=>{});
    const residue=Number((await a.query('select count(*) n from public.e10_checklists where id=any($1::uuid[])',[[x.a,x.b]])).rows[0].n);
    await Promise.all([a.end(),b.end()]);
    if(residue)throw Error('C5 cleanup failed');
  }
  if(pass)console.log('schema review C5 checklist count: PASS');
}
main().catch(e=>{console.error(e.stack);process.exit(1)});
