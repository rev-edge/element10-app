# TA-R3 local evidence

Status: implemented and locally verified. This is not hosted-staging or
exact-head CI acceptance evidence.

Migration `20260912193000_e10_ta_r3_intake_provenance_identity.sql` provides:

- authenticated intake cannot assert `native` or `system` provenance;
- durable connection IDs, source references and payload `source_event_id`
  values are trimmed before persistence and lineage lookup;
- ordinary durable commits serialize and reject a duplicate current stable
  source event;
- reviewed corrected commits may replace that exact stable event only when the
  classification names its current predecessor;
- manual correction and reviewed reimport share the organization lineage lock,
  so concurrent attempts produce exactly one successor;
- committed intake batches cannot be deleted or moved to an editable status;
- the internal `corrected:` commit-receipt namespace is reserved from ordinary
  client commit keys.

Connection-less and manual rows intentionally do not receive an automatic
identity rule. Identical fingerprints remain review evidence rather than an
implicit merge because no owner-approved replay identity exists for those
sources.

Local proof after a clean database replay:

```text
TA-X5d intake commit: PASS
TA-X5d concurrent commit: PASS
TA-X5e observation lineage: PASS
TA-X5e concurrent correction: PASS
TA-X5e concurrent reverse-link cycle: PASS
TA-X5f atomic corrected-file import: PASS
TA-X5f atomic visibility: PASS
TA-X5g explicit source-less correction: PASS
TA-X5g concurrent predecessor: PASS
TA-R3 intake provenance/identity: PASS
```

The R3 proof includes native/system rejection, normalization persistence,
ordinary duplicate denial, reviewed replacement, committed-batch lifecycle
denial and a manual-correction versus reviewed-reimport race with one winner.
No hosted environment or production was contacted.

Independent-review hardening replaced the caller-controlled transaction-setting
prototype with service-only authorization rows bound to transaction ID, backend
PID, organization, batch and source row. Ordinary commits clear any such context.
The proof forges the retired setting and still receives
`stable_source_event_duplicate`. It also proves authenticated commit denial for
a service-staged native batch, reserved `corrected:` key denial, exact-PID
overlap on a held lineage lock, an exact stale-predecessor loser, one current
successor and fail-closed cleanup including tagged C7 audit rows.
