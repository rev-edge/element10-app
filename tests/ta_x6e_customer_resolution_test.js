const { Client } = require('pg');
const { randomUUID } = require('crypto');
const db = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const org = 'e1000000-0000-4000-8000-0000000000a6';
const x = { run: randomUUID(), user: randomUUID(), user2: randomUUID(), role: randomUUID(), c1: randomUUID(), c2: randomUUID(), c3: randomUUID(), wc1: randomUUID(), wc2: randomUUID(), vc1: randomUUID(), vc2: randomUUID(), vc3: randomUUID(), claim1: randomUUID(), claim2: randomUUID(), claim3: randomUUID(), otherOrg: randomUUID(), otherUser: randomUUID(), otherRole: randomUUID(), foreignCustomer: randomUUID(), foreignIdentity: randomUUID() };
const bounded = (p, ms = 8000) => Promise.race([p, new Promise((_, reject) => setTimeout(() => reject(new Error('X6e timeout')), ms))]);

async function main() {
  const s = new Client({ connectionString: db }), a = new Client({ connectionString: db }), b = new Client({ connectionString: db });
  await Promise.all([s.connect(), a.connect(), b.connect()]);
  let draft; let transaction; let activity; const identityIds = []; const depthCustomers = [];
  const decide = 'select public.e10_org_decide_customer_resolution($1,$2,$3,$4,$5,$6,$7,$8,$9::uuid[],$10,$11::jsonb,$12) r';
  try {
    const defaults = Number((await s.query("select count(*) n from public.e10_organization_role_permissions where capability='act.merge_customers'")).rows[0].n);
    if (defaults !== 0) throw new Error(`merge capability received ${defaults} default grants`);
    await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())", [x.user, `${x.run}@x.invalid`]);
    await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())", [x.user2, `${x.user2}@x.invalid`]);
    await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())", [x.otherUser, `${x.otherUser}@x.invalid`]);
    await s.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X6e',false)", [x.role, org, x.run]);
    await s.query("insert into public.e10_organization_role_permissions values($1,$2,'act.manage_customers',true),($1,$2,'act.merge_customers',true),($1,$2,'act.record_commercial_events',true),($1,$2,'act.prepare_customer_transactions',true),($1,$2,'act.approve_customer_transactions',true),($1,$2,'act.post_customer_transactions',true)", [org, x.role]);
    await s.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')", [org, x.user, x.role]);
    await s.query("insert into public.e10_organizations(id,name,slug) values($1,'X6e foreign',$2)", [x.otherOrg, `x6e-${x.run}`]);
    await s.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X6e foreign',false)", [x.otherRole, x.otherOrg, x.run]);
    await s.query("insert into public.e10_organization_role_permissions values($1,$2,'act.manage_customers',true),($1,$2,'act.merge_customers',true)", [x.otherOrg, x.otherRole]);
    await s.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')", [x.otherOrg, x.otherUser, x.otherRole]);
    await s.query("insert into public.e10_customers(id,organization_id,display_name) values($1,$9,'Customer A'),($2,$9,'Customer B'),($3,$9,'Separate customer'),($4,$9,'Walk-in A'),($5,$9,'Walk-in B'),($6,$9,'Verified A'),($7,$9,'Verified B'),($8,$9,'Verified C')", [x.c1, x.c2, x.c3, x.wc1, x.wc2, x.vc1, x.vc2, x.vc3, org]);
    await s.query("insert into public.e10_customers(id,organization_id,display_name) values($1,$2,'Foreign customer')", [x.foreignCustomer, x.otherOrg]);
    await s.query("insert into public.e10_customer_identity_decisions(id,organization_id,customer_id,identity_kind,channel,external_account_id,identity_action,verification_basis,reason,evidence,idempotency_key,request_fingerprint,created_by) values($1,$2,$3,'channel_account','market',$4,'attach','operator_review','foreign fixture','{}',$5,$5,$6)", [x.foreignIdentity, x.otherOrg, x.foreignCustomer, `${x.run}-foreign-account`, `${x.run}-foreign-identity`, x.otherUser]);
    for (const c of [a, b]) { await c.query('select set_config($1,$2,false)', ['request.jwt.claims', JSON.stringify({ sub: x.user, role: 'authenticated' })]); await c.query('set role authenticated'); }

    for (const [customer, account, suffix] of [[x.c1, `${x.run}-a`, 'a'], [x.c2, `${x.run}-b`, 'b'], [x.c3, `${x.run}-c`, 'c']]) {
      const r = (await a.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','market',$3,null,'attach',null,'reviewed channel','{}',$4) r", [org, customer, account, `${x.run}-identity-${suffix}`])).rows[0].r;
      identityIds.push(r.decision_id);
    }
    const aliasDecision = (await a.query("select public.e10_org_decide_customer_identity($1,$2,'alias',null,null,'name only', 'attach',null,'alias only','{}',$3) r", [org, x.c3, `${x.run}-alias`])).rows[0].r.decision_id;
    await a.query(decide, [org, x.wc1, x.wc2, 0, 0, 0, 'merge', 'operator_review', [], 'reviewed identity-less walk-ins', JSON.stringify({ evidence: 'operator record review' }), `${x.run}-walkin-merge`]);
    await a.query(decide, [org, x.wc1, null, 0, null, 1, 'split', 'operator_review', [], 'walk-in records distinct', '{}', `${x.run}-walkin-split`]);

    const ar = (await a.query("select public.e10_org_record_customer_activity($1,'retail',$2,null,'walkin',null,null,1,20,null,null,null,'CAD','manual','2026-01-01T00:00:00Z','exact','manual',null,'operator',$3,'{}','operator_asserted',$4) r", [org, x.c1, `${x.run}-activity-source`, `${x.run}-activity`])).rows[0].r;
    activity = ar.activity_id;
    const lines = [{ purchase_kind: 'retail', capture_source: 'manual', source_line_id: `${x.run}-line`, activity_observation_id: activity, quantity: 1, merchandise_gross: 20, merchandise_discount: 0 }];
    draft = (await a.query("select public.e10_org_create_customer_transaction_draft($1,$2,'CAD','2026-01-01T00:00:00Z','exact',$3,$4,$5) r", [org, x.c1, `X6e ${x.run}`, JSON.stringify(lines), `${x.run}-draft`])).rows[0].r.draft_id;
    await a.query('select public.e10_org_approve_customer_transaction_draft($1,$2,1,$3)', [org, draft, `${x.run}-approve`]);
    transaction = (await a.query('select public.e10_org_post_customer_transaction_draft($1,$2,1,$3) r', [org, draft, `${x.run}-post`])).rows[0].r.transaction_id;
    const immutableHashes = async () => (await s.query("select (select md5(string_agg(row_to_json(c)::text,'' order by c.id)) from public.e10_customers c where c.id=any($1::uuid[])) customer_hash,(select md5(string_agg(row_to_json(i)::text,'' order by i.id)) from public.e10_customer_identity_decisions i where i.customer_id=any($1::uuid[])) identity_hash,(select md5(row_to_json(o)::text) from public.e10_customer_activity_observations o where o.id=$2) activity_hash,(select md5(row_to_json(t)::text) from public.e10_customer_transactions t where t.id=$3) transaction_hash,(select md5(string_agg(row_to_json(l)::text,'' order by l.id)) from public.e10_customer_transaction_lines l where l.transaction_id=$3) line_hash,(select md5(string_agg(row_to_json(e)::text,'' order by e.id)) from public.e10_commercial_events e where e.customer_activity_observation_id=$2 or e.customer_transaction_id=$3) event_hash", [[x.c1, x.c2], activity, transaction])).rows[0];
    const before = await immutableHashes();

    const merged = (await a.query(decide, [org, x.c1, x.c2, 0, 0, 0, 'merge', 'operator_review', [], 'manual duplicate reviewed', JSON.stringify({ basis: 'operator compared records' }), `${x.run}-merge-1`])).rows[0].r;
    const replay = (await a.query(decide, [org, x.c1, x.c2, 0, 0, 0, 'merge', 'operator_review', [], 'manual duplicate reviewed', JSON.stringify({ basis: 'operator compared records' }), `${x.run}-merge-1`])).rows[0].r;
    if (!replay.replay || replay.decision_id !== merged.decision_id || merged.revenue_changed || merged.source_rows_rewritten) throw new Error('merge replay or no-rewrite contract failed');
    let denied = false;
    try { await a.query(decide, [org, x.c1, x.c2, 0, 0, 0, 'merge', 'operator_review', [], 'changed request', '{}', `${x.run}-merge-1`]); } catch (e) { denied = e.code === '22023' && e.message === 'idempotency_key_mismatch'; }
    if (!denied) throw new Error('resolution idempotency mismatch replayed');
    const mapped = await a.query('select * from public.e10_org_resolve_customers($1,$2::uuid[])', [org, [x.c1, x.c2]]);
    if (mapped.rows.length !== 2 || mapped.rows.some(r => r.effective_customer_id !== x.c2)) throw new Error(`effective merge map ${JSON.stringify(mapped.rows)}`);
    const after = await immutableHashes();
    if (JSON.stringify(before) !== JSON.stringify(after)) throw new Error(`merge rewrote immutable customer evidence ${JSON.stringify({ before, after })}`);
    denied = false;
    try { await a.query(decide, [org, x.c3, x.c1, 0, 0, 0, 'merge', 'operator_review', [], 'nonterminal target', '{}', `${x.run}-nonterminal`]); } catch (e) { denied = e.code === '22023' && e.message === 'customer_resolution_target_not_terminal'; }
    if (!denied) throw new Error('merge accepted a nonterminal target/cycle path');
    denied = false;
    try { await a.query(decide, [org, x.c2, x.c2, 0, 0, 0, 'merge', 'operator_review', [], 'self merge', '{}', `${x.run}-self`]); } catch (e) { denied = e.code === '22023'; }
    if (!denied) throw new Error('self merge accepted');
    for (let i = 0; i < 33; i++) depthCustomers.push(randomUUID());
    for (let i = 0; i < depthCustomers.length; i++) await s.query("insert into public.e10_customers(id,organization_id,display_name) values($1,$2,$3)", [depthCustomers[i], org, `Depth ${i}`]);
    for (let i = 0; i < 32; i++) await s.query("insert into public.e10_customer_resolution_decisions(organization_id,source_customer_id,revision,action,target_customer_id,source_customer_revision,target_customer_revision,review_basis,reason,evidence,idempotency_key,request_fingerprint,decided_by) values($1,$2,1,'merge',$3,0,0,'operator_review','depth fixture','{}',$4,$4,$5)", [org, depthCustomers[i], depthCustomers[i + 1], `${x.run}-depth-${i}`, x.user]);
    denied = false;
    try { await a.query(decide, [org, depthCustomers[32], x.c2, 0, 0, 0, 'merge', 'operator_review', [], 'exceeds depth', '{}', `${x.run}-depth-overflow`]); } catch (e) { denied = e.code === '54001' && e.message === 'customer_resolution_depth_exceeded'; }
    if (!denied) throw new Error('merge created a graph beyond resolver depth');
    denied = false;
    try { await a.query('select public.e10_org_update_customer($1,$2,0,$3,\'archived\',$4)', [org, x.c2, 'archive target', `${x.run}-archive-target`]); } catch (e) { denied = e.code === '22023' && e.message === 'customer_resolution_participant_cannot_archive'; }
    if (!denied) throw new Error('generic archive bypassed active incoming merge');

    await a.query(decide, [org, x.c1, null, 0, null, 1, 'split', 'operator_review', [], 'merge was mistaken', JSON.stringify({ correction: true }), `${x.run}-split-1`]);
    const restored = await a.query('select * from public.e10_org_resolve_customers($1,$2::uuid[])', [org, [x.c1]]);
    if (restored.rows[0].effective_customer_id !== x.c1) throw new Error('split did not restore source customer');
    await a.query(decide, [org, x.c1, x.c2, 0, 0, 2, 'merge', 'channel_identity', identityIds.slice(0, 2), 'reviewed channel evidence', JSON.stringify({ reviewed: true }), `${x.run}-merge-2`]);
    denied = false;
    try { await a.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','market',$3,null,'attach',null,'attach to merged source','{}',$4)", [org, x.c1, `${x.run}-late`, `${x.run}-late-attach`]); } catch (e) { denied = e.code === '42501' && e.message === 'identity_customer_not_active_terminal'; }
    if (!denied) throw new Error('new identity attached to nonterminal customer');
    await a.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','market',$3,null,'detach',null,'correct source identity after merge','{}',$4)", [org, x.c1, `${x.run}-a`, `${x.run}-detach-after-merge`]);
    const history = await a.query('select * from public.e10_org_list_customer_resolution_history($1,$2,10,null)', [org, x.c1]);
    if (history.rows.length !== 3 || history.rows.map(r => r.revision).join(',') !== '3,2,1') throw new Error(`history pagination ${JSON.stringify(history.rows)}`);
    denied = false;
    try { await a.query(decide, [org, x.c3, x.c2, 0, 0, 0, 'merge', 'channel_identity', [aliasDecision, identityIds[1]], 'alias/name is insufficient', '{}', `${x.run}-alias-citation`]); } catch (e) { denied = e.code === '22023'; }
    if (!denied) throw new Error('alias evidence authorized merge');
    await a.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','market',$3,null,'detach',null,'detach before citation','{}',$4)", [org, x.c3, `${x.run}-c`, `${x.run}-detach-citation`]);
    denied = false;
    try { await a.query(decide, [org, x.c3, x.c2, 0, 0, 0, 'merge', 'channel_identity', [identityIds[2], identityIds[1]], 'stale citation', '{}', `${x.run}-stale-citation`]); } catch (e) { denied = e.code === '22023'; }
    if (!denied) throw new Error('detached identity evidence authorized merge');
    denied = false;
    try { await a.query(decide, [org, x.c3, x.c2, 0, 0, 0, 'merge', 'operator_review', [x.foreignIdentity], 'foreign citation', '{}', `${x.run}-foreign-citation`]); } catch (e) { denied = e.code === '22023'; }
    if (!denied) throw new Error('foreign-organization identity citation authorized merge');
    denied = false;
    try { await a.query(decide, [org, x.c3, x.foreignCustomer, 0, 0, 0, 'merge', 'operator_review', [], 'foreign target', '{}', `${x.run}-foreign-target`]); } catch (e) { denied = e.code === '42501'; }
    if (!denied) throw new Error('foreign-organization customer target accepted');
    denied = false;
    try { await a.query('select * from public.e10_org_list_customer_resolution_history($1,$2,null,null)', [org, x.c1]); } catch (e) { denied = e.code === '22023'; }
    if (!denied) throw new Error('NULL history limit became unbounded');

    await s.query("insert into public.e10_viewer_handle_claims(id,user_id,whatnot_handle,status,evidence,verified_at,expires_at) values($1,$2,$3,'verified','{}',now(),now()+interval '1 day'),($4,$2,$5,'verified','{}',now(),now()+interval '1 day'),($6,$7,$8,'verified','{}',now(),now()+interval '1 day')", [x.claim1, x.user, `verified-${x.run}-a`, x.claim3, `verified-${x.run}-same`, x.claim2, x.user2, `verified-${x.run}-b`]);
    await a.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','whatnot',$3,null,'attach',$4,'verified A','{}',$5)", [org, x.vc1, `verified-${x.run}-a`, x.claim1, `${x.run}-verified-a`]);
    await a.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','whatnot',$3,null,'attach',$4,'same verified user','{}',$5)", [org, x.vc2, `verified-${x.run}-same`, x.claim3, `${x.run}-verified-same`]);
    await a.query(decide, [org, x.vc1, x.vc2, 1, 1, 0, 'merge', 'operator_review', [], 'same verified user', '{}', `${x.run}-verified-merge`]);
    denied = false;
    try { await a.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','whatnot',$3,null,'attach',$4,'conflicting future attach','{}',$5)", [org, x.vc2, `verified-${x.run}-b`, x.claim2, `${x.run}-verified-conflict-after-merge`]); } catch (e) { denied = e.code === '22023' && e.message === 'customer_effective_verified_identity_conflict'; }
    if (!denied) throw new Error('future verified identity conflicted inside merged component');
    await a.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','whatnot',$3,null,'attach',$4,'verified B','{}',$5)", [org, x.vc3, `verified-${x.run}-b`, x.claim2, `${x.run}-verified-b`]);
    denied = false;
    try { await a.query(decide, [org, x.vc2, x.vc3, 1, 1, 0, 'merge', 'operator_review', [], 'must inspect upstream verified identities', '{}', `${x.run}-verified-conflict-merge`]); } catch (e) { denied = e.code === '22023' && e.message === 'customer_resolution_verified_identity_conflict'; }
    if (!denied) throw new Error('operator merge cherry-picked around upstream verified identity conflict');
    await a.query(decide, [org, x.vc1, null, 1, null, 1, 'split', 'operator_review', [], 'restore verified records', '{}', `${x.run}-verified-split`]);

    await a.query(decide, [org, x.c1, null, 0, null, 3, 'split', 'operator_review', [], 'prepare concurrency proof', '{}', `${x.run}-split-2`]);
    const reattached = (await a.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','market',$3,null,'attach',null,'reattach for topology race','{}',$4) r", [org, x.c1, `${x.run}-a`, `${x.run}-reattach-race`])).rows[0].r.decision_id;
    const identityMergeRace = await bounded(Promise.allSettled([
      a.query(decide, [org, x.c1, x.c2, 0, 0, 4, 'merge', 'channel_identity', [reattached, identityIds[1]], 'merge against detach', '{}', `${x.run}-identity-merge-race`]),
      b.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','market',$3,null,'detach',null,'detach against merge','{}',$4)", [org, x.c1, `${x.run}-a`, `${x.run}-identity-detach-race`]),
    ]));
    if (identityMergeRace[1].status !== 'fulfilled' || !((identityMergeRace[0].status === 'fulfilled') || (identityMergeRace[0].status === 'rejected' && identityMergeRace[0].reason.code === '22023'))) throw new Error(`identity-vs-merge serialization ${JSON.stringify(identityMergeRace)}`);
    const identityAfterRace = (await s.query("select identity_action from public.e10_current_customer_identities where organization_id=$1 and identity_stream_key='channel|market|'||$2", [org, `${x.run}-a`])).rows[0];
    if (!identityAfterRace || identityAfterRace.identity_action !== 'detach') throw new Error('identity-vs-merge race lost detach correction');
    let currentResolution = 4;
    if (identityMergeRace[0].status === 'fulfilled') {
      await a.query(decide, [org, x.c1, null, 0, null, 5, 'split', 'operator_review', [], 'normalize after merge race', '{}', `${x.run}-split-race-normalize`]);
      currentResolution = 6;
    }
    const sourceRevision = 0;
    const race = await bounded(Promise.allSettled([
      a.query(decide, [org, x.c1, x.c2, sourceRevision, 0, currentResolution, 'merge', 'operator_review', [], 'race a', '{}', `${x.run}-race-a`]),
      b.query(decide, [org, x.c1, x.c3, sourceRevision, 0, currentResolution, 'merge', 'operator_review', [], 'race b', '{}', `${x.run}-race-b`]),
    ]));
    if (race.filter(v => v.status === 'fulfilled').length !== 1 || race.filter(v => v.status === 'rejected' && v.reason.code === '40001').length !== 1) throw new Error(`resolution CAS race ${JSON.stringify(race)}`);
    const winnerTarget = race.find(v => v.status === 'fulfilled').value.rows[0].r.target_customer_id;
    const current = (await s.query('select target_customer_id from public.e10_current_customer_resolutions where organization_id=$1 and source_customer_id=$2', [org, x.c1])).rows[0].target_customer_id;
    if (current !== winnerTarget) throw new Error('resolution race projection mismatch');
    const afterRaceRevision = currentResolution + 1;
    await a.query(decide, [org, x.c1, null, 0, null, afterRaceRevision, 'split', 'operator_review', [], 'normalize for chain', '{}', `${x.run}-chain-normalize`]);
    await a.query(decide, [org, x.c1, x.c2, 0, 0, afterRaceRevision + 1, 'merge', 'operator_review', [], 'chain first edge', '{}', `${x.run}-chain-a-b`]);
    await a.query(decide, [org, x.c2, x.c3, 0, 0, 0, 'merge', 'operator_review', [], 'chain second edge', '{}', `${x.run}-chain-b-c`]);
    let chainMap = await a.query('select * from public.e10_org_resolve_customers($1,$2::uuid[])', [org, [x.c1, x.c2]]);
    if (chainMap.rows.some(r => r.effective_customer_id !== x.c3)) throw new Error(`customer chain did not reach terminal ${JSON.stringify(chainMap.rows)}`);
    await a.query(decide, [org, x.c2, null, 0, null, 1, 'split', 'operator_review', [], 'split intermediate association', '{}', `${x.run}-chain-split-b`]);
    chainMap = await a.query('select * from public.e10_org_resolve_customers($1,$2::uuid[])', [org, [x.c1, x.c2]]);
    if (chainMap.rows.some(r => r.effective_customer_id !== x.c2)) throw new Error(`intermediate split did not restore subtree ${JSON.stringify(chainMap.rows)}`);

    await s.query('begin');
    await s.query("select pg_advisory_xact_lock(hashtextextended($1||'|customer-resolution-topology',0))", [x.otherOrg]);
    const prelockDenials = await Promise.allSettled([
      bounded(a.query("select public.e10_org_update_customer($1,$2,0,'foreign','active',$3)", [x.otherOrg, x.c1, `${x.run}-foreign-update`]), 500),
      bounded(a.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','market','foreign',null,'attach',null,'foreign','{}',$3)", [x.otherOrg, x.c1, `${x.run}-foreign-identity`]), 500),
    ]);
    await s.query('rollback');
    if (prelockDenials.some(v => v.status !== 'rejected' || v.reason.code !== '42501')) throw new Error(`unauthorized wrapper waited on foreign topology lock ${JSON.stringify(prelockDenials)}`);
    denied = false;
    try { await a.query('select * from public.e10_org_list_customer_resolution_history($1,$2,10,null)', [x.otherOrg, x.foreignCustomer]); } catch (e) { denied = e.code === '42501'; }
    if (!denied) throw new Error('foreign-organization history RPC allowed');
    denied = false;
    try { await a.query('select * from public.e10_customer_resolution_decisions limit 1'); } catch (e) { denied = e.code === '42501'; }
    if (!denied) throw new Error('authenticated direct resolution-table read allowed');
    denied = false;
    try { await a.query(decide, [x.otherOrg, x.c1, x.c2, 0, 0, currentResolution + 1, 'merge', 'operator_review', [], 'foreign', '{}', `${x.run}-foreign`]); } catch (e) { denied = e.code === '42501'; }
    if (!denied) throw new Error('foreign organization resolved customer');
    const acl = (await s.query("select has_function_privilege('anon','public.e10_org_decide_customer_resolution(uuid,uuid,uuid,bigint,bigint,integer,text,text,uuid[],text,jsonb,text)','execute') anon,has_function_privilege('authenticated','public.e10_org_decide_customer_resolution(uuid,uuid,uuid,bigint,bigint,integer,text,text,uuid[],text,jsonb,text)','execute') auth")).rows[0];
    if (acl.anon || !acl.auth) throw new Error(`resolution ACL ${JSON.stringify(acl)}`);
    console.log('TA-X6e customer resolution: PASS (reviewed merge/split, immutable sources, bounded history, CAS race, tenant/ACL denial)');
  } finally {
    await Promise.all([a.query('reset role').catch(() => {}), b.query('reset role').catch(() => {})]);
    await s.query('set session_replication_role=replica').catch(() => {});
    await s.query("delete from public.e10_customer_transaction_source_claims where source_line_id like $1", [`${x.run}%`]).catch(() => {});
    await s.query("delete from public.e10_commercial_events where idempotency_key like $1 or idempotency_key like $2", [`transaction-post:${x.run}%`, `activity:${x.run}%`]).catch(() => {});
    await s.query("delete from public.e10_customer_transaction_approval_activity_snapshots where activity_observation_id=$1", [activity]).catch(() => {});
    await s.query("delete from public.e10_customer_transaction_lines where source_line_id like $1", [`${x.run}%`]).catch(() => {});
    await s.query("delete from public.e10_customer_transactions where id=$1", [transaction]).catch(() => {});
    await s.query("delete from public.e10_customer_transaction_draft_decisions where idempotency_key like $1", [`${x.run}%`]).catch(() => {});
    await s.query("delete from public.e10_customer_transaction_draft_lines where draft_id=$1", [draft]).catch(() => {});
    await s.query("delete from public.e10_customer_transaction_draft_revisions where draft_id=$1", [draft]).catch(() => {});
    await s.query("delete from public.e10_customer_transaction_drafts where id=$1", [draft]).catch(() => {});
    await s.query("delete from public.e10_customer_commercial_receipts where idempotency_key like $1", [`${x.run}%`]).catch(() => {});
    await s.query("delete from public.e10_customer_activity_observations where id=$1", [activity]).catch(() => {});
    await s.query("delete from public.e10_customer_resolution_decisions where idempotency_key like $1", [`${x.run}%`]).catch(() => {});
    await s.query("delete from public.e10_customer_identity_decisions where idempotency_key like $1", [`${x.run}%`]).catch(() => {});
    await s.query("delete from public.e10_customer_mutation_receipts where idempotency_key like $1", [`${x.run}%`]).catch(() => {});
    await s.query('delete from public.e10_customers where id=any($1::uuid[])', [[x.c1, x.c2, x.c3, x.wc1, x.wc2, x.vc1, x.vc2, x.vc3, x.foreignCustomer, ...depthCustomers]]).catch(() => {});
    await s.query('delete from public.e10_viewer_handle_claims where id=any($1::uuid[])', [[x.claim1, x.claim2, x.claim3]]).catch(() => {});
    await s.query('set session_replication_role=origin').catch(() => {});
    await s.query('delete from public.e10_organization_memberships where user_id=any($1::uuid[])', [[x.user, x.otherUser]]).catch(() => {});
    await s.query('delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2', [org, x.role]).catch(() => {});
    await s.query('delete from public.e10_organization_roles where id=$1', [x.role]).catch(() => {});
    await s.query('delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2', [x.otherOrg, x.otherRole]).catch(() => {});
    await s.query('delete from public.e10_organization_roles where id=$1', [x.otherRole]).catch(() => {});
    await s.query('delete from public.e10_organizations where id=$1', [x.otherOrg]).catch(() => {});
    await s.query('delete from auth.users where id=any($1::uuid[])', [[x.user, x.user2, x.otherUser]]).catch(() => {});
    await Promise.all([s.end(), a.end(), b.end()]);
  }
}
main().catch(e => { console.error(e.stack); process.exit(1); });
