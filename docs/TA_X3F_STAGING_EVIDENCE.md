# TA-X3f staging acceptance evidence

Date: 2026-09-11

Scope: bounded supplier purchasing workspace and accepted actual-cost evidence reads. Production remained read-only.

## Source revision and review

- Branch: `foundation-a6`
- Exact implementation head: `9afb7336e4ea53b8a7f17b99ca7d588f3eecc0f5`
- Exact-head CI: run `34659442363`, success
- CI URL: https://github.com/rev-edge/element10-app/actions/runs/34659442363
- Independent pre-staging review accepted the exact implementation head after independently rerunning the focused X3f suite.
- The CI test job passed X3f, all registered predecessor gates, A7 hostile isolation, predecessor-schema compatibility, clean schema replay, and the born-locked default-privilege probe.

## Guarded staging apply

- Explicit target: Supabase staging project `csmbjfmoxkexcyssntbg` only.
- The preflight immediately before the write returned database `postgres`, PostgreSQL `17.6`, the `e10` schema present, the organization table present, and prior migration head `20260911221930`.
- The migration ran in one fail-closed transaction through the explicit `postgres.csmbjfmoxkexcyssntbg` session-pooler target on port 5432. Its repository version and name were inserted in the migration ledger in the same transaction. No bare or linked-project push was used.
- Ledger row: `20260911223000 | e10_ta_x3f_supplier_workspace_reads`.

## Functional and isolation gates

The following rollback-contained suites passed through the explicit staging session pooler:

- `tests/ta_x3f_supplier_workspace_test.sql`
- `tests/a7_hostile_matrix_test.sql`: PASS 29/29, including anonymous-role checks
- `tests/probe_defpriv.sql`: PASS, born-locked 4/4 and zero anonymous/PUBLIC-executable functions

The X3f gate proves:

- active-organization and active-membership enforcement for both reads;
- operational PO and receipt visibility without financial fields for members lacking `financial.actual_cost.read`;
- invoices, credits, costs, allocations, and summaries only with financial-read authority;
- capability revocation on the next command, suspended membership denial, suspended organization denial, no-membership denial, and hostile cross-organization denial;
- header-first keyset pagination before bounded row hydration, cursor binding to organization, supplier, financial authority, required fields, and finite timestamps;
- summaries identical across pages and currencies reported separately without inferred conversion;
- explicit separation of original `ordered_estimate_*` from remaining `open_commitment_*` values;
- draft, submitted, partially received approved, cancelled, and closed PO semantics of `20/0`, `30/30`, `40/30`, `50/0`, and `60/0` for ordered/open values;
- mixed known/unknown and all-unknown commitments remain incomplete with a null total, while a fully received unknown-cost line has a genuine zero open commitment;
- actual-cost history includes only posted/corrected, accepted, non-reversed, known-cost, exact-currency, exact-configuration, supplier-matching evidence at or before the cutoff;
- two eligible actual-cost rows traverse distinct cursor pages, while reversed, zero-accepted, missing-cost, future, wrong-currency, wrong-configuration, and wrong-supplier rows are excluded; and
- payment status is explicitly unavailable/not modeled.

## ACL, structure, and cleanup

- Public `e10_org_supplier_workspace` and `e10_org_supplier_actual_cost_history` are `STABLE`, `SECURITY DEFINER`, pinned to `search_path=public`, executable by `authenticated` and `service_role`, and denied to `anon` and `PUBLIC`.
- Internal `e10.supplier_open_commitment_summary` and `e10.purchase_order_open_commitment_summary` are `STABLE`, `SECURITY DEFINER`, pinned to `search_path=public`, executable only by `service_role`, and denied to client roles.
- Both new supplier timeline indexes are ready and valid.
- Post-suite residue: X3f fixture auth users `0`; X3f fixture organizations `0`.
- Tenant-zero sentinels remain inventory items `35`, movements `41`, reservations `9`.

## Advisors

- Security: ERROR `0`; WARN `143`, comprising `142` authenticated `SECURITY DEFINER` API notices and one existing leaked-password-protection notice; INFO `104` client-closed RLS tables without policies.
- The two new public X3f APIs account for the expected two authenticated-function warnings. The internal helpers are not client-executable.
- Performance: ERROR `0`; WARN `14` existing RLS init-plan notices; INFO comprises `223` unindexed-FK notices, `58` unused-index notices, and one connection-setting notice.
- Advisor references: https://supabase.com/docs/guides/database/database-linter and https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection.

## Production read-only proof

A production connection forced `default_transaction_read_only=on`, followed by an explicit `BEGIN READ ONLY`, returned:

- project `ddhkkumiyidorzmajwde`, database `postgres`
- transaction read-only: `on`
- `e10` schema: absent
- migration count: `12`
- latest migration: `20260716110000`
- inventory items / movements: `35 / 41`

No production write, `main` merge, UI change, live-feed work, monitor, chatbot, collector showcase, secret, or unresolved commercial-rule implementation occurred.

## Current-state evidence reconciliation

This additive record does not rewrite the dirty planning documents or historical checkpoint text. The authoritative accepted evidence now reads:

| Checkpoint | Authoritative evidence | Accepted implementation |
|---|---|---|
| TA-X3d.1d | `docs/TA_X3D1D_STAGING_EVIDENCE.md` | `9d10db3af7fe2f66506ae8910021ed7e8228ee11` |
| TA-X3e | `docs/TA_X3E_STAGING_EVIDENCE.md` | `d01728dd88e692ff6f8b00d304925bd6e03dfc3a` |
| TA-X3f | this file | `9afb7336e4ea53b8a7f17b99ca7d588f3eecc0f5` |
| TA-X7e | `docs/TA_X7E_STAGING_EVIDENCE.md` | independently accepted at evidence commit `5d9da22ac3a8f7dc3d2df524909cd5706141ebba` |

Together these records supersede stale "remaining" prose inside older checkpoint documents only for current-state orchestration. Their historical claims and boundaries remain intact.

## Acceptance boundary

The outside reviewer independently accepted this staging checkpoint at exact evidence commit `612257e88c4b005cc865865d917ac5f43280d187`, with implementation `9afb7336e4ea53b8a7f17b99ca7d588f3eecc0f5`. The review independently confirmed exact-head CI run `34659442363`; the staging ledger row; valid indexes; function volatility, security mode, search path, and ACLs; stored active-organization, ordered/open split, and null-cursor-kind guards; zero X3f fixture residue; 35/41/9 tenant-zero sentinels; advisor counts; and the production read-only state. The reviewer made no file or database changes and did not claim to rerun the remote mutating suites.

This closes TA-X3f through staging. It does not declare the complete TA-X1 through TA-X8 objective finished. The approved X4 remainder, X8 seams, and final coverage/integration handoff remain.
