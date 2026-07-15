// Element 10 — P1R browser coverage (creds-free, local file://). Mounts the real Add form and drives
// MULTIPLE contributing controls through their REAL inline handlers (no manual invFormSync()), asserting
// the generated Name updates on the same tick, and that the tri-state holds: typing → custom (true) that a
// later structured edit never clobbers; "Use generated name" → generated (false).  Run: node tests/genname_ui_test.js
const puppeteer = require('puppeteer');
let pass = 0, fail = 0;
const T = (n, ok, d) => ok ? (pass++, console.log('  PASS ' + n)) : (fail++, console.log('  FAIL ' + n + (d !== undefined ? '  → ' + JSON.stringify(d) : '')));

(async () => {
  const b = await puppeteer.launch({ headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'] });
  const p = await b.newPage();
  const errs = [];
  p.on('pageerror', e => errs.push(e.message));
  await p.goto('file://' + require('path').resolve(__dirname, '..', 'index.html'), { waitUntil: 'domcontentloaded', timeout: 20000 });
  await new Promise(r => setTimeout(r, 1200));
  console.log('\nElement 10 — P1R form coverage\n');

  const r = await p.evaluate(() => {
    try { if (typeof ME === 'undefined') window.ME = 'tester'; } catch (e) {}
    const modal = document.getElementById('modal') || (() => { const d = document.createElement('div'); d.id = 'modal'; document.body.appendChild(d); return d; })();
    modal.innerHTML = invFormBodyHTML('add', {}, '', '');
    // mirror invFormOpen('add') setup (generated mode)
    INVEDIT = { id: null, mode: 'add', typeExplicit: true, catDirty: false, cardLink: { cardId: null, playerId: null, setId: null }, _prevType: '', nameOverride: false, cardMeta: null, cardMetaLoading: false, removeKeys: [], _userTouched: false, _genLive: false };
    invFormSync(); INVEDIT.baseline = invEditSnapshot(); INVEDIT._genLive = true;

    const nm = () => document.getElementById('ivf_name').value;
    const fire = (id, val, evt) => { const el = document.getElementById(id); if (!el) return; el.value = val; el.dispatchEvent(new Event(evt, { bubbles: true })); };

    // ≥4 contributing controls, each via its own real handler; capture Name after each
    const seq = [];
    fire('ivf_type', 'sealed_product', 'change'); seq.push(nm());
    fire('ivf_domain', 'Sports cards', 'change'); seq.push(nm());
    fire('ivf_brand', 'Topps', 'input'); seq.push(nm());
    fire('ivf_year', '2026', 'input'); seq.push(nm());
    fire('ivf_line', 'Chrome', 'input'); seq.push(nm());
    fire('ivf_sport', 'Baseball', 'input'); seq.push(nm());
    fire('ivf_config', 'Hobby', 'input'); seq.push(nm());
    fire('ivf_package', 'case', 'change'); seq.push(nm());
    const generated = nm();

    // tri-state: type over the Name → custom(true); a later structured edit must NOT clobber it
    fire('ivf_name', 'My Custom', 'input');
    const afterType = nm(), ovAfterType = INVEDIT.nameOverride;
    fire('ivf_brand', 'Panini', 'input');
    const afterEditWhileCustom = nm();
    // "Use generated name" → generated(false), regenerated from current fields (brand now Panini)
    invNameUseGenerated();
    const afterReset = nm(), ovAfterReset = INVEDIT.nameOverride;

    // count how many of the driven controls changed the Name (proves multi-handler wiring)
    let updates = 0; for (let i = 1; i < seq.length; i++) if (seq[i] !== seq[i - 1]) updates++;
    return { seq, generated, afterType, ovAfterType, afterEditWhileCustom, afterReset, ovAfterReset, updates };
  });

  T('generated name assembles from the fields', r.generated === '2026 Topps Chrome Baseball Hobby Case', r.generated);
  T('>=4 contributing controls each refreshed the Name', r.updates >= 4, r.updates);
  T('typing sets custom (override true)', r.ovAfterType === true && r.afterType === 'My Custom', { ov: r.ovAfterType, name: r.afterType });
  T('structured edit does NOT clobber a custom name', r.afterEditWhileCustom === 'My Custom', r.afterEditWhileCustom);
  T('"Use generated name" → generated (override false), regenerated', r.ovAfterReset === false && r.afterReset === '2026 Panini Chrome Baseball Hobby Case', { ov: r.ovAfterReset, name: r.afterReset });
  T('no page JS errors', errs.length === 0, errs);

  await b.close();
  console.log('\n  ' + pass + ' pass · ' + fail + ' fail\n');
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(3); });
