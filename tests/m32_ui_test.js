// Element 10 — M3.2.2 BROWSER test (item 4). Drives the DEPLOYED client's real functions in a headless
// browser and asserts against the DB session rows — covering the three behaviors bundle inspection can't:
//   A) showStartLive from a real show → the created session carries source_show_ref = that show's id.
//   B) a generic launch (no show) → session source_show_ref null.
//   C) an abandoned show-start (open show → start-live → navigate away → start another way) → null.
// The prerequisite throwaway show is created through the client's OWN newShow/saveShow (shows are scoped
// to the signed-in member's workspace). Teardown runs from finally via the service-role serviceCleanup
// (tests/cleanup.js): sessions (events/slots cascade) + the throwaway show from the member workspace.
//   Credentials from env ONLY: E10_MEMBER_EMAIL/PW, plus E10_URL/SUPABASE_SERVICE_KEY/E10_CLEANUP_PROJECT_REF.
//   Run: (source .env.local) node tests/m32_ui_test.js
const puppeteer = require('puppeteer');
const { createClient } = require('@supabase/supabase-js');
const { serviceCleanup } = require('./cleanup');
const { target } = require('./env');
const { url: URL, anon: ANON } = target(); // LOCAL by default; the browser client (file://) also connects to LOCAL
const APP = process.env.E10_APP_URL || ('file://' + require('path').resolve(__dirname, '..', 'index.html'));
const MEMBER = process.env.E10_MEMBER_EMAIL, MEMBER_PW = process.env.E10_MEMBER_PW;
if (!MEMBER || !MEMBER_PW) { console.error('Set E10_MEMBER_EMAIL / E10_MEMBER_PW.'); process.exit(2); }

let pass = 0, fail = 0;
const T = (n, ok, d) => ok ? (pass++, console.log('  PASS ' + n)) : (fail++, console.log('  FAIL ' + n + (d !== undefined ? '  → ' + JSON.stringify(d) : '')));
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  const sb = createClient(URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error: se } = await sb.auth.signInWithPassword({ email: MEMBER, password: MEMBER_PW });
  if (se) { console.error('supabase sign-in failed:', se.message); process.exit(2); }
  const meUid = (await sb.auth.getUser()).data.user.id;
  const uws = 'user:' + meUid;
  const PFX = 'zzui' + Date.now().toString(36);
  const SHOWNAME = 'ZZ ' + PFX + ' show';
  const t0 = new Date(Date.now() - 3000).toISOString();
  console.log('\nElement 10 — M3.2.2 UI (prefix ' + PFX + ')\n');

  const newest = async () => { const { data: d } = await sb.from('e10_break_sessions').select('id,source_show_ref,created_at').eq('streamer_uid', meUid).gt('created_at', t0).order('created_at', { ascending: false }).limit(1); return d && d[0]; };
  const findShowId = async () => { const { data: w } = await sb.from('e10_workspace').select('data').eq('id', uws).maybeSingle(); const sh = (w && w.data && w.data.shows) || {}; for (const k of Object.keys(sh)) { const hit = (sh[k] || []).find(s => s && s.name === SHOWNAME); if (hit) return hit.id; } return null; };

  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'] });
  let SHOWID = null;
  try {
    const page = await browser.newPage();
    await page.goto(APP, { waitUntil: 'networkidle2', timeout: 30000 });
    await page.type('#auEmail', MEMBER);
    await page.type('#auPass', MEMBER_PW);
    await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => /sign in/i.test(x.textContent)); if (b) b.click(); });
    await page.waitForFunction(() => !document.querySelector('#auEmail') && typeof window.saveShow === 'function', { timeout: 25000 });
    await sleep(3500); // let loadAll settle (scoped workspace + MEID)

    // create a throwaway show through the client's own path (scoped to this member)
    await page.evaluate(nm => { window.newShow(); const n = document.querySelector('#mname'); if (n) n.value = nm; window.saveShow(); }, SHOWNAME);
    for (let i = 0; i < 15 && !SHOWID; i++) { await sleep(1000); SHOWID = await findShowId(); }
    T('setup: show created in member scoped workspace', !!SHOWID, SHOWID);
    if (!SHOWID) throw new Error('show not created');

    // A — explicit show launch stamps the ref
    await page.evaluate(async id => { window.showStartLive(id); const n = document.querySelector('#liveName'); if (n) n.value = 'ZZ A'; await window.liveStart(); }, SHOWID);
    await sleep(2000);
    let s = await newest();
    T('A: explicit show launch stamps source_show_ref = show id', s && s.source_show_ref === SHOWID, s);

    // C — abandoned show-start → null
    await page.evaluate(async id => { window.showStartLive(id); window.go('home'); window.go('live'); const n = document.querySelector('#liveName'); if (n) n.value = 'ZZ C'; await window.liveStart(); }, SHOWID);
    await sleep(2000);
    s = await newest();
    T('C: abandoned show-start → source_show_ref null', s && s.source_show_ref === null, s);

    // B — generic launch (no show) → null
    await page.evaluate(async () => { window.go('live'); const n = document.querySelector('#liveName'); if (n) n.value = 'ZZ B'; await window.liveStart(); });
    await sleep(2000);
    s = await newest();
    T('B: generic launch (no show) → source_show_ref null', s && s.source_show_ref === null, s);
  } finally {
    await browser.close();
    // Service-role teardown from finally — runs even if the browser flow threw. Removes the sessions this
    // run created (their events/slots cascade) and the throwaway 'ZZ …' show from the member workspace.
    const { data: sess } = await sb.from('e10_break_sessions').select('id').eq('streamer_uid', meUid).gt('created_at', t0);
    const manifest = { sessionIds: (sess || []).map(x => x.id), showIds: SHOWID ? [SHOWID] : [], workspaceId: uws };
    let res, cerr;
    try { res = await serviceCleanup(manifest); } catch (e) { cerr = e; }
    T('teardown: service cleanup ran', !cerr, cerr && cerr.message);
    if (res) T('teardown: 0 residue (sessions + show)', res.clean, res.residue);
  }

  console.log('\n  ' + pass + ' pass · ' + fail + ' fail\n');
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(3); });
