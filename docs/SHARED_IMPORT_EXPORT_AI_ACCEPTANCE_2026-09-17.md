# Shared import, export, and AI acceptance contract

Status: required future acceptance cases. No case is marked implemented by this
document.

| ID | Scenario | Required result |
| --- | --- | --- |
| IEA-A01 | Cards-only checklist, no configuration evidence | Checklist draft and approval work; configuration and applicability remain unknown; sealed purchasing/receiving remains unblocked. |
| IEA-A02 | Multi-sheet release/configuration/checklist workbook | Explicit sheet/header selection and routing preserve all source lineage; no sheet is silently ignored. |
| IEA-A03 | Missing or contradictory packaging evidence | Missing stays unknown; conflicts are visible and reviewable; configuration names do not invent quantities, SKU, barcode, or exclusivity. |
| IEA-A04 | Existing release/card/configuration matches | Reviewed matching reuses stable identities and creates no duplicate catalog or organization record. |
| IEA-A05 | Optional subjects and unresolved applicability | Product/checklist can proceed; unresolved names/evidence remain visible; no subject or configuration link is fabricated. |
| IEA-A06 | Mapping revision after row review | Only dependent reviews become stale; stale approval cannot commit changed prepared results. |
| IEA-A07 | Save/resume, identical and corrected re-import | Draft resumes at the same revision; identical import replays; corrected import links a new revision without rewriting source or approved history. |
| IEA-A08 | Approved version N while N+1 is reviewed | N remains operational and reproducible; N+1 is visibly newer draft; no silent replacement. |
| IEA-A09 | AI unavailable, limited, or revoked | Manual mapping/review/commit/export remains complete; draft work is preserved. |
| IEA-A10 | Managed AI job | Job records Element 10 funding, pinned pricing policy, usage estimate/report, allowance/billable event, and actor without duplicate charge on retry. |
| IEA-A11 | Organization-funded AI job | Job records connection/version and organization funding; no Element 10 consumption is claimed; provider failure does not silently use managed AI. |
| IEA-A12 | Explicit fallback consent | A failed organization-funded attempt can create a managed attempt only under approved policy plus explicit consent; both attempts remain auditable. |
| IEA-A13 | Revoked connection or unauthorized user | New/queued attempts fail before source disclosure; existing draft remains; in-flight outcome and any provider cost remain auditable. |
| IEA-A14 | Connector creates a mapping draft | Tool uses explicit org context and current capability; result is an ordinary untrusted revision requiring native review and normal approval. |
| IEA-A15 | Connector tries to approve, publish, post, receive, or send | Unsupported or unauthorized action fails; no generic mutation or authority bypass exists. |
| IEA-A16 | Provider timeout, retry, partial output, delayed usage | Attempts and usage observations reconcile without duplicate business records or billable events; partial output cannot masquerade as approved result. |
| IEA-A17 | Prompt injection in source or assistant output | Text remains source/proposal data and cannot change org, operation, permission, provider, funding, approval, or destination. |
| IEA-A18 | Selected-row export | Exact reviewed IDs are reauthorized at generation; restricted/missing rows are reported, not substituted. |
| IEA-A19 | All-filtered export beyond page one | Artifact uses the complete authorized cohort and same filters/totals as the grid; field restrictions and query revision are preserved. |
| IEA-A20 | Large export and later reproduction | Asynchronous job is bounded; checksum, specification, dataset revision, expiry, and retention are recorded; reproduction semantics are explicit. |
| IEA-A21 | File generation versus transmission | Download succeeds without sending; any later destination action requires separate configuration, authority, preview, receipt, and failure handling. |
| IEA-A22 | Multi-tenant and multi-membership actor | Explicit organization context is required; no other organization's source, mapping, credential, job, usage, artifact, or template leaks. |
| IEA-A23 | Presentation changes Everyday to Advanced | Permissions, provider route, funding, pricing policy, and committed data do not change. |
| IEA-A24 | Checklist approval side effects | Zero inventory, receipt, acquisition-cost, listing, sale, customer-spend, payment, or external-publication records are created. |

Acceptance requires local replay, focused hostile/concurrency tests, exact-head
CI, explicit staging evidence, security review, and independent verdict. A
browser demonstration or provider response alone is insufficient.
