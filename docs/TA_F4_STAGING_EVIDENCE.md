# TA-F4 identity ambiguity review staging evidence

Date: 2026-09-12

## Accepted revision

- Runtime commit: `cd15b119dae9600ed673df5bb135a2ebbeb11de7`
- Closure and exact staging head: `bf99230063bd81c14b215254b7fd257fda14f399`
- Independent local review: approved against exact head `bf99230063bd81c14b215254b7fd257fda14f399`
- Exact-head CI: run `34684368998`, success
- CI URL: <https://github.com/rev-edge/element10-app/actions/runs/34684368998>

## Scope and limitations

TA-F4 provides a bounded, platform-admin-only ambiguity-review queue for player identities. It stores proposals, candidates, and rejection history. It does not approve an identity, create a canonical link, merge or split players, or generate candidates. A successful idempotent proposal replay returns the original proposal operation result. Its returned status is historical and is not a current-state read after a later rejection.

The migration removes the two global player-name uniqueness indexes so distinct people may share a name. Player UUID identity remains authoritative. The UUID primary key and trigram name-search index remain, and `(name_norm, id)` is retained as a nonunique lookup index.

## Artifact hashes

- Migration `20260912093000_e10_ta_f4_identity_ambiguity_review.sql`: `3ad290a1b7426dabb5d15c2c056abe4cde72537458e470bc05216185034930ad`
- Functional test: `921fd2af36d0fa743a93a2e2f911fb83dadc40f30f5b970f207dc548c39eafd8`
- Hostile guard test: `eab59ba84215c645b98cbdb3485dbe96a90ce66954869102d22d44b7ca96062d`
- Concurrency test: `4709e70c698f42797c29f2e2becc7e47847e22943e52a9eab4e82bbbd20984c6`

## Local verification

A clean `supabase db reset` applied every migration through `20260912093000`. The following passed after that reset:

- TA-X1 identity foundation
- TA-X1b affiliations and depicted-team context, including concurrency
- TA-F4 functional contract
- TA-F4 hostile guards
- TA-F4 proposal and rejection concurrency
- All adjacent TA-X7d governance, evidence, projection, screener, drilldown, query-context, snapshot, validation, cohort, and read-concurrency suites
- Default-privilege probe: born-locked `4/4`, zero anonymous or PUBLIC-executable functions

## Explicit staging apply

Target: staging project `csmbjfmoxkexcyssntbg`, explicit session-pooler connection. The target preflight returned `current_database=postgres`, `current_user=postgres`, and `e10_schema=true`. A bare linked-project push was not used.

The CLI dry run refused because staging contains historical ledger versions absent from the current migration directory. No ledger repair was attempted. The reviewed migration file and its ledger insert were instead executed in one `psql --single-transaction` operation through the explicit staging URL.

Exact ledger row:

`20260912093000|e10_ta_f4_identity_ambiguity_review|0`

## Staging behavioral proof

The following all passed directly against staging:

- Functional behavior, bounded reader, model provenance, cursor pagination, and cross-role authorization
- Ordinary-user proposal denial
- Duplicate and nonexistent candidate denial
- Known-confidence range and numeric validation
- Unknown-confidence null enforcement
- Required model-version validation
- Evidence-size and candidate-count bounds
- Changed idempotent rejection mismatch
- Same-source proposal under a new idempotency key denied
- Append-only update and delete denial on cases, candidates, and decisions
- Same-idempotency proposal race: one insert and one replay
- Same-source/different-key race: one winner and one source-exists denial
- Post-lock platform-admin revocation on proposal idempotency and source lock paths
- Rejection race: one winner and one revision conflict
- Post-lock platform-admin revocation on rejection
- Default-privilege probe: born-locked `4/4`, zero anonymous or PUBLIC-executable functions

All tests rolled back or removed their fixtures. Staging residue after the suite:

`cases=0|candidates=0|decisions=0|test_users=0`

### Reproducible invocation and captured output

The verification used the staging session-pooler URL only through an environment
variable. No credential was printed or recorded:

```sh
cd /Users/tsconnely/dev/element10-app
set -a
. ./.env.local
set +a
STAGING_URL="postgresql://postgres.csmbjfmoxkexcyssntbg:${SUPABASE_STAGING_DB_PASSWORD}@aws-0-us-east-1.pooler.supabase.com:5432/postgres"
psql "$STAGING_URL" -v ON_ERROR_STOP=1 -f tests/ta_f4_identity_ambiguity_review_test.sql
psql "$STAGING_URL" -v ON_ERROR_STOP=1 -f tests/ta_f4_identity_ambiguity_review_guards_test.sql
E10_DB_URL="$STAGING_URL" node tests/ta_f4_identity_ambiguity_review_concurrent_test.js
psql "$STAGING_URL" -v ON_ERROR_STOP=1 -f tests/probe_defpriv.sql
```

Captured output excerpts from that run:

```text
BEGIN
DO
ROLLBACK
TA-F4 identity ambiguity review PASS

BEGIN
DO
ROLLBACK
TA-F4 identity ambiguity guards PASS

TA-F4 identity ambiguity concurrency: PASS (proposal idempotency/source races; proposal/reject post-lock revocation; one reject winner; zero denied residue)

NOTICE: default-privileges probe: PASS (born-locked 4/4 + zero anon/PUBLIC-executable functions)
DO
```

The explicit migration apply used the same `STAGING_URL` and one transaction:

```sh
cd /Users/tsconnely/dev/element10-app
psql "$STAGING_URL" -v ON_ERROR_STOP=1 --single-transaction \
  -f supabase/migrations/20260912093000_e10_ta_f4_identity_ambiguity_review.sql \
  -c "insert into supabase_migrations.schema_migrations(version,statements,name) values('20260912093000',array[]::text[],'e10_ta_f4_identity_ambiguity_review')"
```

Its captured terminal result completed every DDL statement, the final ledger
insert returned `INSERT 0 1`, and the subsequent exact query returned:

```text
20260912093000|e10_ta_f4_identity_ambiguity_review|0
```

## Function parity and access control

Local and staging function-definition SHA-256 values match:

- `e10_platform_player_identity_review_cases`: `cff60b85d3df34dcccce6eba1786a2fb8e0771635918790011b61844f1d61d7d`
- `e10_platform_propose_player_identity_review`: `d14dfce3a453d3c24e65751211cdedf1227acc172d00681edd030f85ea34f2c9`
- `e10_platform_reject_player_identity_review`: `2c2dfce13795b3564f3b887b6ebc42f28099630d77edbf30670ed6fe35d7759a`

All three functions are `SECURITY DEFINER`, pin `search_path=public`, and have EXECUTE only for `postgres`, `service_role`, and `authenticated`. There is no anonymous or PUBLIC execution.

All three storage tables have RLS enabled and expose table privileges only to `postgres` and `service_role`:

- `e10_catalog_identity_review_cases`
- `e10_catalog_identity_review_candidates`
- `e10_catalog_identity_review_decisions`

## Index proof

Player indexes present:

- `e10_players_pkey`, unique UUID primary key
- `e10_players_name_trgm`, trigram search
- `e10_players_name_norm_idx`, nonunique `(name_norm, id)` lookup

Player indexes absent:

- `e10_players_name_norm_uidx`
- `e10_players_name_uidx`

The redundant review-cases `id` pagination index is absent; the primary-key index supplies that ordering.

## Production untouched

The production check ran inside a read-only transaction and returned:

`e10_schema=false|f4_cases=false|migration_count=12|latest=20260716110000|f4_propose_function=false`

No production write occurred.

## Advisor disclosure

Current staging advisors were captured after F4. Neither security nor
performance advisors report an `ERROR`.

Security totals:

- `rls_enabled_no_policy`: INFO 120. Three are the intentionally client-closed
  F4 cases, candidates and decisions tables. Direct authenticated table grants
  are absent, so adding permissive policies would weaken the reviewed contract.
- `authenticated_security_definer_function_executable`: WARN 159. Three are the
  intended F4 authenticated entry points. Each pins `search_path=public`,
  validates current platform-admin authority before and after its locks, and is
  covered by ordinary/hostile/revocation tests.
- `auth_leaked_password_protection`: WARN 1. This is the existing project-level
  Auth setting and was not changed by F4.

Performance totals:

- `unindexed_foreign_keys`: INFO 242. F4 contributes the cases `created_by` and
  decisions `reviewed_by` references to `auth.users`. They are audit references,
  not reader predicates in the bounded F4 contract; no speculative index was
  added at this staging-only, zero-production-traffic checkpoint.
- `auth_rls_initplan`: WARN 14, pre-existing and unrelated to F4.
- `unused_index`: INFO 57. The F4 candidate-to-player lookup index is new and
  necessarily unused before real traffic. It supports the bounded candidate
  projection and is retained.
- `auth_db_connections_absolute`: INFO 1, an existing project configuration
  notice unrelated to F4.

References: [RLS with no policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
[authenticated security-definer execution](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
and [unindexed foreign keys](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys).
