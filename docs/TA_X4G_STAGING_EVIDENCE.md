# TA-X4g staging evidence

Status: pending independent staging acceptance

## Immutable inputs

- Branch: `foundation-a6`
- Exact implementation head: `670115076f2919197500ce357ed73c3ffbd3eeef`
- Exact-head CI: run `34666053283`, success
- Implementation/local review: accepted against the same head
- Target: staging project `csmbjfmoxkexcyssntbg` (`element10-staging`, `ACTIVE_HEALTHY`)
- Production was not used as a write target.

## Apply and ledger

The migration was applied through the Supabase migration API with the explicit
staging project ID. The generated ledger version was transactionally reconciled
to the repository filename after asserting both the generated row and absence of
the repository version.

```text
20260912000365,e10_ta_x4g_receipt_disposition
```

## Staging verification

All tests used the explicit staging session-pooler identity. SQL fixtures rolled
back. JavaScript concurrency fixtures were explicitly removed.

```text
TA-X4g reviewed receipt disposition: PASS
TA-X4g fail-closed ACL: PASS
TA-X4g disposition races: PASS
TA-X4f atomic receipt reversal: PASS
TA-X4f fail-closed ACL: PASS
TA-X4f reversal races: PASS
TA-X4b atomic lot reserve: PASS
TA-X4b/X4c concurrency: PASS
TA-X3e authenticated writer/read/projection behavior: PASS
TA-X3e durable lineage, approval preservation and ACL: PASS
TA-X3e concurrent single-successor and post-lock authorization: PASS
TA-X3f supplier workspace PASS
TA-X5c native action linkage: PASS
TA-X5c.1 source time + legacy reversal linkage: PASS
A7 hostile matrix gate: PASS (29/29)
A7 anon: PASS
default-privileges probe: PASS
```

The X4g race suite established actual lock waits and covered competing initial
decisions, same-head CAS, initial and corrective disposition versus reversal in
both directions, capability/destination/organization revocation rereads, exact
replay, and reserve-capability revocation after the canonical lot lock but before
projection inspection.

## Definition parity and access surface

Full `pg_get_functiondef` MD5 values matched local and staging:

```text
e10.assert_receipt_lot_projection,8c6524ccdc1606bc260b3922e1bbc51a
e10.normalize_commercial_event_envelope,20b5c2d9770af67d65d915472c6732a8
e10.receipt_line_effective_quantities,6148313c70b87bfc8c6a23ef5bf72c26
public._e10_org_lot_reserve_x4b,f8865fd6725d79f44ab444898860b565
public._e10_org_reverse_receipt_batch_x4f,5572e391c56851224040beb47674b9a7
public.e10_org_lot_reserve,81d0d9d3a3d877cc66e5f4e483f29b40
public.e10_org_reverse_receipt_batch,a5ad4337d15ec17b2c7d1153a61852fa
public.e10_org_review_receipt_disposition,510e8e46a25dec5e9edf3f93e78c89f3
```

The two internal helpers and two renamed implementations are executable only by
`postgres` and `service_role`. The three public writers are executable by
`postgres`, `service_role`, and `authenticated`, with no `anon` or `PUBLIC`
execution. Both new disposition tables have RLS enabled and grants only for
`postgres` and `service_role`; authenticated clients have no direct table grant.

## Cleanup and baseline

```text
items=35
movements=41
reservations=9
x4g_decisions=0
x4g_commands=0
x4g_users=0
```

## Advisors

No advisor ERROR was reported. Counts after X4g, with delta from the accepted
X4f staging snapshot in parentheses:

```text
security: rls_enabled_no_policy INFO 108 (+2 intentional client-closed tables)
security: authenticated_security_definer_function_executable WARN 145 (+1 reviewed public writer)
security: auth_leaked_password_protection WARN 1 (unchanged)
performance: unindexed_foreign_keys INFO 232 (+6 new immutable-ledger FKs)
performance: auth_rls_initplan WARN 14 (unchanged)
performance: unused_index INFO 57 (-1; usage-dependent advisor observation)
performance: auth_db_connections_absolute INFO 1 (unchanged)
```

Advisor reference: <https://supabase.com/docs/guides/database/database-linter>

## Production read-only proof

An explicit production pooler connection executed only a `BEGIN READ ONLY`
baseline query and rolled back:

```text
transaction_read_only=on
e10_schema=0
migrations=12
latest=20260716110000
items=35
movements=41
```

No production write occurred.
