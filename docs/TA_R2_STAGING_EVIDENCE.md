# TA R2 staging evidence

Date: 2026-09-12

Status: submitted for independent review, not self-accepted.

## Scope

- Runtime and tests: `d1a2b44785f9775c6e3eb27beebdf3fc85878ed7`
- Migration: `20260912151500_e10_ta_r2_customer_truth_authority.sql`
- SHA-256: `9739549b4b97989ae0d3df13ee4228f28dd31f084c47e097dfc5a8e3b8ef1095`
- Staging: `csmbjfmoxkexcyssntbg`, explicit session-pooler target only.
- Production and `main`: not contacted or changed.

## Corrections

The twelve X6a through X6d public mutator signatures are preserved. Their prior
bodies are service-only delegates. Public wrappers acquire the applicable
command, entity, activity, posted-source and slot locks, then reread active
organization, active membership and exact capability immediately before the
delegate runs. Posting was proved with an authenticated caller whose exact PID
waited on the draft row while its capability was revoked; it returned `42501`
with zero transaction effect.

Draft lines now reject missing/non-finite amounts, duplicate activity IDs and
activity/header currency mismatches before storage. The same currency,
duplicate, released-native-sale and slot-import checks run again under the
posting locks for pre-migration drafts. Released native sales remain immutable
evidence but are excluded from actionable provisional activity and cannot be
drafted or posted. Slot-bearing imports with native evidence require the
reviewed reconciliation path. Native resale remains valid because no blanket
`(session,slot)` uniqueness was added.

## Verification

Clean local reset applied all migrations through R2. Local and staging both
passed:

```text
TA-X6a customer activity: PASS
TA-X6a concurrent activity: PASS
TA-X6b customer identity: PASS
TA-X6b concurrent customer identity: PASS
TA-X6c customer posting: PASS
TA-X6c concurrent posting: PASS (post-lock revoke, exact PID, zero effect)
TA-X6d.3 customer reconciliation: PASS
TA-X6e customer resolution: PASS
TA-X6f posted customer attribution: PASS
TA-X6g native break sale: PASS
default-privileges probe: PASS (born-locked 4/4, zero anon/PUBLIC executable)
```

Staging ledger contains:

```text
20260912151500|e10_ta_r2_customer_truth_authority
```

Staging ACL census for the corrected surface:

```text
public_wrappers=12|anon_executable=0|authenticated_executable=12
service_only_delegates_authenticated_executable=0
```

CI run for the exact runtime SHA:

```text
https://github.com/rev-edge/element10-app/actions/runs/34701803452
```

R3 was not started.

## Local closure addendum, 2026-09-12

Status: R2 is ready for renewed independent review. This addendum records local
evidence only. Hosted staging and exact-head CI remain R8 work and are not
claimed here.

Migration `20260912184933_e10_ta_r2_distinct_resale_reconciliation.sql` closes
the remaining same-slot reconciliation gap. An import that overlaps native sale
history remains denied unless its exact source claim has a latest reviewed
`new_transaction` decision. That review permits a distinct resale contribution
without weakening the default duplicate guard. Released managed native sales
remain ineligible, while trusted native observations not owned by the managed
sale subsystem are no longer falsely classified as released sales.

Executable proof now covers:

- all twelve corrected customer writers, each with the exact writer PID blocked
  by the exact advisory-lock holder, mid-wait capability revocation, `42501`
  after release and zero mutation residue;
- native-first unreviewed import denial and import-first native-post denial;
- a reviewed same-slot `new_transaction` resale, with three official
  transactions, three official lines and exact CAD gross 65 across one managed
  native contribution and two import contributions;
- altered activity scope denied and omitted activity scope derived from the
  locked native observation;
- released-after-approval denial, successful-post replay after later release,
  and distinct native resale identity;
- trusted non-managed native activity accepted by the draft guard without
  acquiring managed-sale identity;
- the pre-existing reviewed `new_transaction` promotion, current-decision
  revocation race, source-claim serialization and one-contribution proofs.

Clean local replay through the new migration passed. The focused R2 authority,
X6d reconciliation, X6g native-sale, X6g adversarial and trusted non-managed
native suites passed. C6 introduced organization-transition history after the
original X6d/X6g tests; their fixture cleanup now removes that history before
deleting temporary organizations. This is test cleanup only and does not alter
runtime behavior.
