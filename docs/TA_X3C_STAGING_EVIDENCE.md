# TA-X3c purchase-order lifecycle acceptance evidence

Date: 2026-09-11

Scope: governed purchase-order create, amend, submit, approve, cancel, and close workflows. Production remained read-only.

## Source revision

- Branch: `foundation-a6`
- Accepted implementation head: `e69a8a42d60b25a5091d83300bc8a307d6936624`
- Exact-head CI: run `34638678932`, attempt 2, success. Attempt 1 failed before migrations because the GitHub runner could not bind local port 54322.
- Independent review: accepted the exact implementation head after independently rerunning the functional and exact-lock concurrency suites.

## Local evidence

- Clean `supabase db reset`: PASS through `20260911185500_e10_ta_x3c_purchase_order_lifecycle.sql`.
- TA-X3a purchasing-document regression: PASS.
- TA-X3b immutable-revision regression: PASS.
- TA-X3c functional suite: PASS.
- TA-X3c concurrency suite: PASS with exact blocker-PID evidence for command idempotency, authority and organization revocation, invoice-allocation cancellation, expected-commitment cancellation, amend-versus-submit CAS, and receipt-versus-amend quantity serialization.
- TA-X4d receipt posting and reversal regressions: PASS.
- Default-privilege probe: PASS, including zero anonymous or PUBLIC-executable functions.
- Local security advisors: no issues.
- The database linter retained only pre-existing findings outside the X3c migration.

## Staging evidence

- Explicit target: Supabase project `csmbjfmoxkexcyssntbg`, confirmed as `element10-staging`, PostgreSQL 17.6.
- Guarded apply path: Supabase project-ID migration operation. No bare or linked database push was used.
- Staging-assigned migration ledger: `20260911193142`, `e10_ta_x3c_purchase_order_lifecycle`.
- Transactional functional suite: PASS and ROLLBACK.
- Two-connection concurrency suite through the explicit staging session pooler: PASS and fixture-free.
- Post-test X3c fixture census: zero X3c organizations, purchase orders, and command rows. The concurrency suite's exact generated auth user residue assertion also returned zero. Four unrelated `@x.invalid` users dated 2026-09-10 pre-existed this checkpoint and were preserved.
- ACL inventory: all five `e10` helpers are closed to anon and authenticated and executable by service role; the three bounded public writers are closed to anon and executable by authenticated and service role.
- Security advisors: ERROR 0; WARN 120, comprising 119 intentional authenticated `SECURITY DEFINER` notices and one project-level leaked-password-protection notice; INFO 91 deny-by-default RLS tables without client policies.
- Performance advisors: ERROR 0; WARN 14 pre-existing RLS init-plan notices; INFO 265, comprising 220 unindexed-foreign-key notices, 44 unused-index notices, and one connection-setting notice.

## Behavioral closure

- Every lifecycle command uses a server-derived request fingerprint, an organization-scoped idempotency key, deterministic advisory locks, post-lock authorization rereads, expected-revision CAS, an immutable revision, and a linked commercial event in the same transaction.
- Generic commercial-event insertion cannot forge `purchase_order_changed`; its event must match the retained command receipt, subject, operation, status, and revision.
- Cancellation rejects non-reversed receipt allocations, active invoice-to-PO allocations, and open expected-supply allocations. It never silently releases an allocation.
- Quantity reduction respects invoice allocation and net received plus remaining expected supply. Fulfilled expected supply no longer contributes to the remaining floor.
- A configuration remains historically bound after receipt reversal or expected-allocation completion.
- Historical receipt and terminal-command replays remain available after later lifecycle state changes.
- New receipts reject cancelled PO lines.

## Integration contract

- `e10_org_amend_purchase_order` requires an explicit stable `id` on every submitted line, including newly added lines. Callers must generate and retain that UUID before the first amendment attempt.
- Cancelled PO line numbers remain reserved because uniqueness covers all line states. Callers must not reuse a cancelled line number.
- Invoice-allocation release and correction remain an additive, auditable TA-X3d responsibility. X3c cancellation does not release or rewrite invoice allocations.

## Production read-only proof

Project `ddhkkumiyidorzmajwde` was queried read-only after staging verification:

- `e10` schema: absent
- migration count: 12
- latest migration: `20260716110000`
- inventory items: 35
- inventory movements: 41

No production write occurred.

## Acceptance boundary

TA-X3c is accepted through staging. TA-X3d, TA-X3e, and TA-X3f remain required. No production deployment, main-branch change, UI work, live feed, monitor, chatbot behavior, showcase work, secret, or unresolved commercial rule was introduced.
