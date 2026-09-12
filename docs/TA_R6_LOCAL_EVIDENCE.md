# TA-R6 deterministic robustness closure

Status: local implementation evidence. Hosted staging and exact-head CI remain required before acceptance.

## Replay authority decision

Owner approval on 2026-09-12 selects shared, capability-authorized replay for the existing X3 and X4 command families. An identical idempotency-key replay may be returned to a different actor only while that actor currently holds the same organization membership and capability required to perform the operation. Payload mismatch remains denied. The original `created_by` is immutable audit provenance, not an exclusive replay secret. Cross-organization replay remains impossible because organization is part of every lookup and lock key. This avoids changing established same-organization retry coordination into actor-private commands.

## Corrections

- Draft activity currency, required finite amounts, and duplicate activity validation fail before persistence.
- Typed query UUIDs and integers are validated before casts and expose stable `22023` errors.
- X4 duplicate active reservation, duplicate batch lot code, cross-writer key reuse, and numeric fingerprints have stable contracts.
- V1 commercial-event timestamps fingerprint their UTC value.
- Client-supplied purchasing and financial line UUIDs that collide only in another tenant are remapped before legacy global checks, so foreign and unused IDs have the same create-new behavior.
- F4 and X1b malformed identities fail as validation errors. Customer search treats `%`, `_`, and `\\` literally.
- V1 spend retains full-cohort totals on a trailing empty page.
- X7e signed cursors bind `p_limit`; lifecycle and evidence totals come from the complete ranked cohort rather than the current page.

## Local verification

The clean replay and the R6, X3, X4, X6, X7e, and X8 targeted suites are the acceptance commands. Each test rolls back or removes exact fixtures. Production is out of scope and must remain untouched.
