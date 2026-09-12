# TA-X8b staging acceptance evidence

Date: 2026-09-12

Scope: inert, revisioned and reviewable action drafts for the two approved
ordinary-writer delegations. The checkpoint adds no autonomous execution,
external dispatch, scheduler, UI, live feed or production change.

## Source revision and CI

- Branch: `foundation-a6`
- Implementation head: `c989ff74aef860dd7eb41f00d3e524a68a7840cf`
- Independent local-review verdict: `APPROVED TA-X8b LOCAL IMPLEMENTATION` at
  that exact commit.
- Exact-head CI: run `34671333029`, success in 6m47s.
- CI URL: https://github.com/rev-edge/element10-app/actions/runs/34671333029
- The test job passed the complete registered suite, the TA-X8b gate, A7
  hostile isolation, predecessor-schema compatibility, clean schema replay and
  the born-locked default-privilege probe. Production-only schema and deploy
  jobs were skipped.

## Guarded staging apply

- Explicit target: Supabase staging project `csmbjfmoxkexcyssntbg` through
  `postgres.csmbjfmoxkexcyssntbg` on the session pooler at port 5432.
- Preflight returned database `postgres`, PostgreSQL `17.6`, the `e10` schema
  and `e10_organizations` present, prior ledger head `20260912000381`, no X8b
  table or RPC, and tenant-zero inventory `35/41/9`.
- Each migration ran in its own fail-closed transaction. The exact repository
  version and name were inserted into the migration ledger in the same
  transaction. No bare or linked-project push was used.
- Applied ledger rows:
  - `20260912000390 | e10_ta_x8b_action_draft_storage`
  - `20260912000391 | e10_ta_x8b_proposal_validation`
  - `20260912000392 | e10_ta_x8b_action_draft_rpcs`
  - `20260912000393 | e10_ta_x8b_preview_redaction`
  - `20260912000394 | e10_ta_x8b_transition_hardening`
  - `20260912000395 | e10_ta_x8b_reference_locks`
  - `20260912000396 | e10_ta_x8b_review_boundary`
  - `20260912000397 | e10_ta_x8b_unstructured_projection`

## Staging functional, authorization and concurrency gates

All fixtures were rollback-contained or explicitly removed. The following
passed through the explicit staging session pooler:

- `tests/ta_x8b_action_draft_test.sql`
- `tests/ta_x8b_commit_delegation_test.sql`
- `tests/ta_x8b_permission_matrix_test.sql`
- `tests/ta_x8b_customer_preview_permissions_test.sql`
- `tests/ta_x8b_concurrent_test.js`
- `tests/a7_hostile_matrix_test.sql`: PASS `29/29`
- `tests/probe_defpriv.sql`: PASS, born-locked `4/4` and zero anonymous or
  `PUBLIC`-executable functions

The exact-backend concurrency suite proved post-wait revocation for exact
create replay and non-replay amendment, post-wait supplier and customer
reference invalidation with zero residue, coherent cancel-versus-commit and
amend-versus-approve serialization, and one ordinary effect plus one replay
for competing exact commits.

## Definition identity

Local and staging `pg_get_functiondef` outputs matched exactly for all fifteen
X8b functions. Full SHA-256 values from staging:

| Function | SHA-256 |
| --- | --- |
| `e10.reject_action_draft_history_change()` | `f223820b29b068f51f81aaf5759990e7c8abc1aaa795f50d43b880bc6d3a2737` |
| `e10.x8b_authorized(uuid,uuid,text)` | `8df2bb0bab2a428d4b92fcb7aa784bee8c0b0a337d36838facc3304ca386795e` |
| `e10.x8b_capability(text,text)` | `5ffee94f254391c934af54bc7f99a88fe8adfce7f7f805e805ae3e9f5c4f533b` |
| `e10.x8b_command(uuid,text,text,uuid,text)` | `96fa87b91929686c46f8c0d2f1863c05a4100a86d6971bae454f2c4cfa666dc2` |
| `e10.x8b_lock_references(uuid,text,jsonb)` | `fee0834c4fea9bc846dae8b47aa258ca5dd881ca224e8fcaf6b214a2f06618da` |
| `e10.x8b_preview_values(uuid,text,jsonb,boolean,boolean)` | `161fd3ae64c8d80400ffe4f5ec8cfb512d905253f6f9f8534dc37e7945c083d1` |
| `e10.x8b_proposal_snapshot(uuid,text,jsonb,jsonb,jsonb)` | `4a60c9f19148645db9ca408e6b71f72c23f9370568abfc1030cc5d8ef8810328` |
| `e10.x8b_redact_json(jsonb,boolean,boolean)` | `ee9c4507317ad672f1eccf76d5779ef1b52e1080023a118dffdea4bd7a7f31fc` |
| `e10.x8b_validate_provenance(text,jsonb,jsonb,jsonb)` | `3a71e839a60950bde36826e9bcef1e31f9bdcbfededacafd0fc3ce1be6de5685` |
| `public.e10_org_amend_action_draft(uuid,uuid,integer,jsonb,jsonb,jsonb,text)` | `7fff0cd8e63ea11e5ed5b35ba94372e8151fabd181f1c27ff606135bbf511fad` |
| `public.e10_org_approve_action_draft(uuid,uuid,integer,text)` | `5fa0b7b410a3955ea41a46aef0191bd3679a547172066593e7767b32c29c46b6` |
| `public.e10_org_cancel_action_draft(uuid,uuid,integer,text,text)` | `0f8879cb5dab3445ea85bdc6088a166fe7559df562d68ae63c0a93a4e2cafef5` |
| `public.e10_org_commit_action_draft(uuid,uuid,integer,text)` | `a7a6cd15f9072d399552253a0d32e51ec33568da98641ab505ce11211ba234b6` |
| `public.e10_org_create_action_draft(uuid,text,jsonb,jsonb,jsonb,text)` | `8888f1fa6171529c0e04d13f43ae4c45cd7b333c5e5ea2d9405a8b5d8f659eb9` |
| `public.e10_org_preview_action_draft(uuid,uuid,integer)` | `b28b5c3b63ac09c7d6e8e3aa013ff69fb4c5526ce2c0e7597f25c21c16212991` |

## RLS, ACLs and advisors

- `e10_action_drafts`, `e10_action_draft_revisions`,
  `e10_action_draft_decisions` and `e10_action_draft_commands` all have RLS
  enabled, zero policies, no `anon` or `authenticated` table privileges, and
  limited service-role access. Drafts grant `SELECT`, `INSERT` and `UPDATE`;
  revision, decision and command history grant `SELECT` and `INSERT`. None of
  the four grants `DELETE`.
- All nine internal `e10` functions are `SECURITY DEFINER`, fix
  `search_path=public`, deny `PUBLIC`, `anon` and `authenticated`, and grant
  only `service_role`.
- All six public RPCs are `SECURITY DEFINER`, fix `search_path=public`, deny
  `PUBLIC` and `anon`, and grant `authenticated` and `service_role`.
- Security advisors: ERROR `0`; INFO `114` deny-by-default RLS tables; WARN
  `155`, consisting of `154` intentional authenticated `SECURITY DEFINER`
  API notices and the existing leaked-password-protection notice. Relative to
  X8a this is exactly four new deny-by-default tables and six reviewed public
  RPC notices. Remediation references:
  https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy
- Performance advisors: ERROR `0`; WARN `14` existing RLS init-plan notices;
  INFO `297`, consisting of `240` unindexed-FK notices, `56` unused-index
  notices and one Auth connection-setting notice. Relative to X8a, only the
  five expected X8b foreign-key notices are new. Remediation reference:
  https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys

## Cleanup and tenant-zero sentinels

The post-suite census returned:

- action drafts/revisions/decisions/commands: `0/0/0/0`;
- X8b fixture organizations/users: `0/0`;
- orphan revisions/decisions/commands: `0/0/0`; and
- tenant-zero inventory items/movements/reservations: `35/41/9`.

## Production read-only proof

An explicit `BEGIN READ ONLY` transaction against production project
`ddhkkumiyidorzmajwde` returned:

- database `postgres`;
- `e10` schema absent;
- migration count `12`, latest `20260716110000`;
- inventory items/movements/reservations `35/41/9`;
- `e10_action_drafts` absent; and
- `e10_org_create_action_draft` absent.

The transaction rolled back. No production write, `main` merge, UI change,
live-feed work, scheduled monitor, chatbot behavior, secret or unresolved
commercial-rule implementation occurred.

## Acceptance boundary

This packet requests independent TA-X8b staging acceptance. It does not close
TA-X8c or the final TA-X1 through TA-X8 requirements and contracts matrix.
