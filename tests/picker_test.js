// Element 10 — P1B picker-collision regression (creds-free, local file://). The product editor mounts at
// up to two surfaces at once (builder #sec-schedule stays in the DOM behind live #sec-live). Before the fix
// every mount emitted the SAME ids ('prodBox', 'prodPick' → #ep_prodPick/#epi_prodPick/#epr_prodPick and
// EP['prodPick']); $ returned the first, so the live picker's results/selection targeted the hidden builder
// (the production click-through failed at step 4). This asserts the SURFACE-specific ids never collide.
// The full operator flow (create show → reserve → live → consume → reverse) is the credentialed browser test.
//   Run: node tests/picker_test.js
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
  console.log('\nElement 10 — P1B picker collision\n');

  const r = await p.evaluate(() => {
    // Mount the builder AND live product editors simultaneously, as the real app does.
    const host = document.createElement('div');
    host.innerHTML = '<div id="prodBox_builder">' + productEditorHTML('builder') + '</div>' +
                     '<div id="prodBox_live">' + productEditorHTML('live') + '</div>';
    document.body.appendChild(host);
    const ids = [...host.querySelectorAll('[id]')].map(e => e.id);
    const dupes = ids.filter((x, i) => ids.indexOf(x) !== i);
    return {
      builderBox: document.querySelectorAll('#prodBox_builder').length,
      liveBox: document.querySelectorAll('#prodBox_live').length,
      builderInput: document.querySelectorAll('#epi_prodPick_builder').length,
      liveInput: document.querySelectorAll('#epi_prodPick_live').length,
      dupes,
      epDistinct: (typeof EP === 'object' && EP['prodPick_builder'] && EP['prodPick_live'] && EP['prodPick_builder'] !== EP['prodPick_live']),
    };
  });

  T('exactly one builder container', r.builderBox === 1, r.builderBox);
  T('exactly one live container', r.liveBox === 1, r.liveBox);
  T('builder picker input present + unique', r.builderInput === 1, r.builderInput);
  T('live picker input present + unique', r.liveInput === 1, r.liveInput);
  T('NO duplicate ids across both mounts', r.dupes.length === 0, r.dupes);
  T('distinct EP registry entries per surface', r.epDistinct === true, r.epDistinct);
  T('no page JS errors', errs.length === 0, errs);

  await b.close();
  console.log('\n  ' + pass + ' pass · ' + fail + ' fail\n');
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(3); });
