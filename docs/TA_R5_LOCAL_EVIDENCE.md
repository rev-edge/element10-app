# TA-R5 local evidence

Status: implemented and locally verified. Hosted staging and exact-head CI are
deferred to the consolidated R8 gate.

R5 closes the X1 integration boundary with additive migrations only:

- configuration-version content is immutable, deletion is denied and state may
  move only from draft to active or retired, or active to retired;
- provider-mapping meaning is immutable and undeletable; changing the current
  mapping requires an appended successor revision and preserves its predecessor;
- organization callers with `catalog.propose` have bounded, idempotent writers
  for product masters, configurations, configuration versions and unique items;
- platform administrators have bounded, idempotent writers for releases,
  variants with ordered subjects and reviewed provider-mapping revisions;
- command receipts are private, append-only and authority is rechecked after
  command and entity locks, including replay paths.

Local clean replay and self-failing tests prove valid creation and replay,
changed-payload mismatch, stale version refusal, cross-organization denial,
non-admin platform denial, malformed subject refusal, immutable-history guards,
single-current mapping history across three revisions, rejection of direct
historical resurrection and client ACL closure. The two-connection suite proves
exact lock-holder overlap for same-key convergence, competing configuration
version CAS, tenant-authority revocation and platform-admin revocation, with
zero denied-write residue.

No hosted environment or production was contacted.
