// Element 10 — pure-helper test for the Pass 2.6 (corrected) generated-name builder.
// invGenName(item) is DETERMINISTIC and PURE (same input → same output; no mutation, no S/INVEDIT),
// null for legacy/unclassified items, and enforces the corrected contract: MINIMUM USEFULNESS
// (>=2 distinct substantive segments), case-insensitive DEDUP (shorter-inside-longer dropped; 'Box'
// never matches inside 'Boxing'), CARD # for raw AND graded, and the six-word LOT descriptor rule.
// Extracts the pure block from index.html by source; no DOM, no network. Run: node tests/genname_test.js
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');

const mTypes = src.match(/const INV_TYPES=\[[^\]]*\];/);
const mPkg = src.match(/function invPackageLabel\(p\)\{return [^\n]*\}/);
if (!mTypes) { console.error('INV_TYPES not found'); process.exit(2); }
if (!mPkg) { console.error('invPackageLabel not found'); process.exit(2); }
const start = src.indexOf('function _invGenNorm');
const endMarker = 'return invGenDedupJoin(segs);\n}';
const endIdx = src.indexOf(endMarker);
if (start < 0 || endIdx < 0) { console.error('gen block not found'); process.exit(2); }
const genBlock = src.slice(start, endIdx + endMarker.length);

// `const`/`function` from a sloppy direct eval inject into this scope so invGenName can see them.
eval('var INV_TYPES = ' + mTypes[0].match(/\[[\s\S]*?\]/)[0] + ';');
eval(mPkg[0]);
eval(genBlock);

let pass = 0, fail = 0;
const T = (name, cond, detail) => cond
  ? (pass++, console.log('  PASS  ' + name))
  : (fail++, console.log('  FAIL  ' + name + (detail !== undefined ? '  → ' + detail : '')));

console.log('\nElement 10 — invGenName (Pass 2.6 corrected)\n');

// ── Roadmap examples reproduce EXACTLY ──
const sealed = { inventory_type: 'sealed_product', product_year: '2026', manufacturer: 'Topps', product_line: 'Chrome', domain: 'Sports cards', sport: 'Baseball', configuration: 'Hobby', package_type: 'case' };
T('roadmap sealed', invGenName(sealed) === '2026 Topps Chrome Baseball Hobby Case', invGenName(sealed));
T('roadmap sealed → Mega Box', invGenName(Object.assign({}, sealed, { configuration: 'Mega', package_type: 'box' })) === '2026 Topps Chrome Baseball Mega Box', invGenName(Object.assign({}, sealed, { configuration: 'Mega', package_type: 'box' })));
const graded = { inventory_type: 'graded_card', product_year: '2023', product_line: 'Pokémon 151', subject: 'Charizard ex', parallel: 'SIR', gradingCompany: 'PSA', grade: '10' };
T('roadmap graded', invGenName(graded) === '2023 Pokémon 151 Charizard ex SIR PSA 10', invGenName(graded));
const raw = { inventory_type: 'raw_card', product_year: '2023', product_line: 'Pokémon 151', subject: 'Charizard ex', cardNumber: '199/191', parallel: 'SIR' };
T('roadmap raw (card # after subject)', invGenName(raw) === '2023 Pokémon 151 Charizard ex 199/191 SIR', invGenName(raw));

// ── Determinism + purity ──
T('deterministic', invGenName(sealed) === invGenName(sealed));
const snap = JSON.stringify(sealed); invGenName(sealed);
T('does not mutate input', JSON.stringify(sealed) === snap);

// ── Legacy / classification ──
T('legacy (no inventory_type) → null', invGenName({ name: 'Old Box', cat: 'Box', set: 'X', year: '2020' }) === null);
T('unknown inventory_type → null', invGenName({ inventory_type: 'nope', product_year: '2020' }) === null);
T('null/empty item → null', invGenName(null) === null && invGenName({}) === null);

// ── MINIMUM USEFULNESS: package or grade alone never qualifies ──
T('sealed package only (Box) → null', invGenName({ inventory_type: 'sealed_product', package_type: 'box' }) === null, invGenName({ inventory_type: 'sealed_product', package_type: 'box' }));
T('graded grade+gc only (PSA 10) → null', invGenName({ inventory_type: 'graded_card', gradingCompany: 'PSA', grade: '10' }) === null, invGenName({ inventory_type: 'graded_card', gradingCompany: 'PSA', grade: '10' }));
T('sealed package + grade → null (no substantive)', invGenName({ inventory_type: 'sealed_product', package_type: 'box', grade: '10' }) === null);
T('two substantive (year + brand) → valid', invGenName({ inventory_type: 'sealed_product', product_year: '2026', manufacturer: 'Topps' }) === '2026 Topps');
T('one substantive (year only) → null', invGenName({ inventory_type: 'sealed_product', product_year: '2026' }) === null);

// ── DEDUP (case-insensitive, shorter-inside-longer dropped, keep longer) ──
T('subject inside set: no "Pokémon 151 Pokémon"', invGenName({ inventory_type: 'graded_card', product_year: '2023', product_line: 'Pokémon 151', subject: 'Pokémon' }) === '2023 Pokémon 151', invGenName({ inventory_type: 'graded_card', product_year: '2023', product_line: 'Pokémon 151', subject: 'Pokémon' }));
T('package inside line: no "Elite Trainer Box Box"', invGenName({ inventory_type: 'sealed_product', product_year: '2024', manufacturer: 'Pokémon', product_line: 'Elite Trainer Box', package_type: 'box' }) === '2024 Pokémon Elite Trainer Box', invGenName({ inventory_type: 'sealed_product', product_year: '2024', manufacturer: 'Pokémon', product_line: 'Elite Trainer Box', package_type: 'box' }));
T('brand inside line: no "Topps Topps Chrome"', invGenName({ inventory_type: 'sealed_product', product_year: '2026', manufacturer: 'Topps', product_line: 'Topps Chrome' }) === '2026 Topps Chrome', invGenName({ inventory_type: 'sealed_product', product_year: '2026', manufacturer: 'Topps', product_line: 'Topps Chrome' }));
const boxing = invGenName({ inventory_type: 'sealed_product', product_year: '2024', manufacturer: 'Panini', product_line: 'Boxing', package_type: 'box' });
T('"Box" not swallowed by "Boxing"', boxing === '2024 Panini Boxing Box', boxing);

// ── Card # in graded (after subject) ──
T('graded includes card #', invGenName({ inventory_type: 'graded_card', product_year: '2023', product_line: 'Pokémon 151', subject: 'Charizard', cardNumber: '199', gradingCompany: 'PSA', grade: '10' }) === '2023 Pokémon 151 Charizard 199 PSA 10', invGenName({ inventory_type: 'graded_card', product_year: '2023', product_line: 'Pokémon 151', subject: 'Charizard', cardNumber: '199', gradingCompany: 'PSA', grade: '10' }));

// ── LOT descriptor rule ──
T('lot: count + descriptor + Lot', invGenName({ inventory_type: 'lot_bundle', item_count: '10', description: 'Junk wax' }) === '10× Junk wax Lot', invGenName({ inventory_type: 'lot_bundle', item_count: '10', description: 'Junk wax' }));
T('lot: exactly first six words, no later text', invGenName({ inventory_type: 'lot_bundle', description: 'one two three four five six seven eight' }) === 'one two three four five six Lot', invGenName({ inventory_type: 'lot_bundle', description: 'one two three four five six seven eight' }));
T('lot: descriptor from product_line fallback', invGenName({ inventory_type: 'lot_bundle', product_line: 'Pokémon 151' }) === 'Pokémon 151 Lot');
T('lot: "Lot" appended once only', invGenName({ inventory_type: 'lot_bundle', description: 'card lot special' }) === 'card lot special', invGenName({ inventory_type: 'lot_bundle', description: 'card lot special' }));
T('empty lot → null', invGenName({ inventory_type: 'lot_bundle' }) === null);

// ── Dual-field twins + package label + clean degrade ──
T('legacy twins (set/year) fallback', invGenName({ inventory_type: 'sealed_product', year: '2025', manufacturer: 'Panini', set: 'Prizm' }) === '2025 Panini Prizm');
T('structured wins over legacy twin', invGenName({ inventory_type: 'sealed_product', product_year: '2026', year: '1999', manufacturer: 'Topps' }) === '2026 Topps');
T('package code rendered as label', invGenName({ inventory_type: 'sealed_product', product_year: '2026', manufacturer: 'Topps', package_type: 'pack' }) === '2026 Topps Pack');
T('no double spaces / dangling separators', !/\s{2,}/.test(invGenName(sealed) + ' ' + invGenName(graded) + ' ' + invGenName(raw)) && !/^\s|\s$/.test(invGenName(sealed)));

console.log('\n  ' + pass + ' pass · ' + fail + ' fail\n');
process.exit(fail ? 1 : 0);
