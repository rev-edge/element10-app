# Element 10 — Standing Coding Standards

These apply to EVERY coding change, always, whether or not they're asked for. Every Claude Code prompt written for this project appends these. The point: proactively improve UI and workflows so issues don't have to be pointed out one at a time.

## Proactive UX/QA pass (every change)
On every surface a change touches (and its neighbors), audit and fix, in scope:
- **Stale renders** — any field/dropdown/toggle whose change doesn't immediately update its dependent totals, labels, or headers. (Recurring bug class in this app.)
- **Destructive-action confirms** — anything irreversible (end/delete/remove) gets a confirm.
- **Async feedback** — loading state on searches/saves/loads; disable buttons in-flight; a success/error toast on every mutation. No silent success or failure.
- **Quick-add ergonomics** — Enter-to-submit and sensible focus on add/search rows.
- **Number/currency formatting** — consistent thousands separators; negatives in red; no formatting inconsistencies.
- **Inline validation** — required fields, numeric fields reject junk, sane bounds (e.g. boxes/case ≥ 1, cost/qty ≥ 0); clear inline errors, never silent no-ops.
- **Empty states** — one concise line on what to do; terse, no noise.

Fix the in-scope, low-risk ones. Anything bigger (a redesign, or a data/RLS change): flag it for the user, don't do it silently.

## Verification & safety (every change)
- Verify on live data with throwaway data only; tear it down; never touch real inventory, the 176 rosters, seed, or backups.
- Never weaken RLS. Additive only. Migrations nullable + InitPlan-wrapped.
- **Verification is proportional to what the pass touches:** pure-helper tests where applicable (convention: plain node scripts in `tests/`, established by H1); browser verification for changed UI behavior; RLS + migration verification for server changes; retry and duplicate-action tests for mutations; concurrent-edit tests when shared, scoped, cached, or transactional state changes; production baselines when production-shaped data is involved.
- **Authoritative mutations are single-transaction server RPCs with mutation-level idempotency:** the idempotency key is checked BEFORE the mutation is applied; a replay performs zero additional mutation and returns the previously committed result. Never mutate client-side and emit separately; never treat emitter-level idempotency as mutation-level.
- **Output encoding is context-aware** (post-H1): `esc()` for HTML text/attributes, `jsq()` composed with `esc()` for values inside inline-handler JS strings, `encodeURIComponent` in URL positions. Never interpolate a raw value into template-literal HTML.
- Report: itemized change list (surface → issue → fix), screenshots of key surfaces, teardown proof, deploy status (main, Action green, live serves it), and a "flagged for follow-up" section for anything intentionally not done.

## Copy & visual tidiness (universal — applies to every screen, always)
- **Placeholders/examples**: only when the input is genuinely non-obvious. A labeled field does not need an "e.g. …" placeholder. Never duplicate the label as the placeholder. If a hint is truly needed (a non-obvious format like a dual grade "10 / 9.5"), keep it to ONE minimal example, not a list.
- **Grey instructional/helper prose is BANNED site-wide** (absolute, not "minimize"). No "load X or Y above…", no "use this to…", no how-to hints, no descriptive subtitles — anywhere. The muted-grey text style (var(--mut) et al.) is reserved strictly for genuine secondary DATA (a value, count, delta, timestamp, metadata) — never for instructions, hints, or descriptions. Functional inline feedback (e.g. a derived per-box cost when non-zero) is fine but is data, not prose.
- **No redundant info**: never repeat data already shown in an adjacent column/label/tag (e.g. a "Slab" tag next to a Category column that already says Slab). Show it once.
- **Casing**: one convention per element type, applied everywhere — section titles, field labels (sentence case), column headers, buttons. No mixed or sloppy casing within the same element type.
- **No decorative emojis** in titles, headers, or labels (e.g. "🎯 CHASE LISTS" → "Chase lists"). Functional status glyphs only, used sparingly, and only when they convey real state.
- **No "what this section is for" descriptions**: don't put a grey paragraph under a header explaining the box's purpose. A clear header plus its controls should make the purpose obvious. Empty states: ONE terse line, no how-to instructions.
- **Clean framing**: tight, consistent section/card framing — no loosely-formatted explanatory boxes.
- **Terseness**: the label carries the meaning; fewer words. When in doubt, cut. Respect the decluttered style — never re-add noise.

## Coding-agent prompt shape & decomposition
- The product-direction review is a BACKLOG, not a prompt. Never hand an agent an unbounded "redesign the app" task. Each pass quotes only the relevant requirements and EXPLICITLY states what existing functionality must not be rebuilt.
- Follow the dependency order in **`Element10_ROADMAP.md` — the single canonical sequence.** Do not let the agent choose section by section, and do not use any ordering from an older document (a previous version of this file put Whatnot orders and customers before the inventory ledger; that is obsolete). Current macro order: hotfixes (H1 encoding + cache, H2 workspace CAS) → storage spike/decision (S1/D1) → inventory foundation (2.6 naming → 2.7–2.9 transactional movements → 2.10–2.12) → break lifecycle → Home → nav review → player quality → grids → Whatnot orders → customers → revenue → analytics.
- One prompt = one reviewable migration OR one coherent UI workflow, not both unless inseparable.
- Every coding-agent prompt uses this structure: **Objective** (one narrow outcome) · **Current behavior** (what exists and must be preserved) · **In scope** (exact functions/surfaces) · **Out of scope** (explicit exclusions) · **Data changes** (migrations/tables) · **Files likely affected** (from reconnaissance, not guesses) · **Implementation requirements** · **Regression risks** · **Verification queries** · **Manual test** · **Acceptance criteria** · **Rollback**.
- Whatnot-first: model transactions extensibly but implement only Whatnot (Weekly Orders, buyer handles, shows). No eBay/multi-platform abstractions yet. Preserve current nav; add Breaks/Customers/Analytics only after their modules exist. Responsive/a11y are acceptance criteria within passes, not standalone projects.

## Independent review (Trent's side)
- Verify Claude Code's report against the live DB/site — don't take it at face value, especially security- or data-touching changes.
- Keep the build log current.
