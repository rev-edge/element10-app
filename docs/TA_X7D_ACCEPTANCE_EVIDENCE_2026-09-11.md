# TA-X7d acceptance evidence

Date: 2026-09-11

Scope: governed market facets, canonical market projection, bounded screener and drilldown reads, and the X7d.3 concurrency closure. Production remained read-only.

## Source revision

- Branch: `foundation-a6`
- X7d.3 concurrency commit: `2daf81ac784a17869509f9911a1d98c068ab8923`
- Exact-head CI: run `34630659927`, success, 4m49s
- Prior drilldown commit: `09b96508cdb627b9945fc490dca7ba1c2160f7b6`, CI run `34629927744`, success

## Independent review

The outside reviewer independently ran the X7d.3 test and accepted the exact-PID revision-lock, source-snapshot, screener query-state, drilldown query-state, bounded completion, cursor-order, and rollback-residue proofs. The final empty-owned and current-copy-versus-historical-fact cases were then added to the drilldown suite.

## Local evidence

- Clean `supabase db reset`: PASS through `20260911183000_e10_ta_x7d2_public_drilldown.sql`.
- Complete X7d gate: PASS for facet governance and writers, market evidence and writers, canonical projection, source helpers, query contexts and caps, read snapshot, catalog entity projection, request validation, cohort engine, public screener, public drilldown, and X7d.3 concurrency.
- X7d.3 exact reader backend waits: catalog revision, organization revision, source snapshot, screener query-state advisory lock, and drilldown query-state advisory lock all established against the intended blocker PID.
- Source proof: the response returned the complete new singleton source universe at the matching post-update organization revision.
- Cursor proof: positive screener and drilldown cursors were required before their denial races; two drill pages preserved distinct-microsecond order.
- Authorization proof: capability or membership revocation while blocked produced SQLSTATE `42501` after the wait.
- Rollback proof: denied screener and drilldown calls did not change either context or cursor counts.
- `tests/a7_hostile_matrix_test.sql`: PASS, 29/29.
- `tests/probe_defpriv.sql`: PASS, born-locked 4/4 and zero anonymous or PUBLIC executable functions.

## Staging evidence

- Explicit target: Supabase project `csmbjfmoxkexcyssntbg`.
- Guarded path: Supabase project-ID migration and SQL operations only. No linked or bare database push was used.
- Applied in dependency order: all X7d migrations from facet governance through public drilldown.
- Transactional staging runs: all eleven SQL suites from facet governance through public drilldown passed and rolled back their fixtures.
- Final inventory: screener present, drilldown present, anonymous EXECUTE false for both.
- Residue: `e10_market_query_contexts=0`, `e10_market_query_cursors=0`.
- Security advisors after apply: zero ERROR. Existing warning classes remain `authenticated_security_definer_function_executable` and `auth_leaked_password_protection`; authenticated public RPC exposure is intentional and covered by internal authorization tests.

## Production read-only proof

Project `ddhkkumiyidorzmajwde` was queried read-only after staging verification:

- `e10` schema: absent
- migration count: 12
- inventory items: 35
- inventory movements: 41

No production write occurred.

## Acceptance boundary

X7d changes only. No X7e implementation, production deployment, UI work, live-feed integration, monitor, chatbot, secret, or unresolved commercial rule was introduced.
