# Shared import, export, and AI requirements

Status: owner-confirmed scope recorded 2026-09-17. Requirements only. See
`SHARED_IMPORT_EXPORT_AI_ARCHITECTURE_2026-09-17.md` for reconciliation.

| ID | Requirement |
| --- | --- |
| IEA-01 | Manual import, review, commit, and export work without AI. |
| IEA-02 | Element 10-managed AI, organization-funded AI, external assistant connectors, and manual operation share one governed draft and command lifecycle. |
| IEA-03 | Entitlement, user capability, presentation, provider, and funding source remain independent. |
| IEA-04 | Organization connections are server-side, organization-owned, rotatable, revocable, and usable without employee API keys. |
| IEA-05 | Every AI job pins execution mode, funding source, policy revision, task, actor, provider route, and data-minimization profile. |
| IEA-06 | No fallback changes provider or funding source without an approved policy and explicit consent. Draft work survives failure. |
| IEA-07 | Provider usage/cost, estimates, customer billable usage, allowances, credits, and limits remain separate and historically versioned. |
| IEA-08 | Retries, timeouts, cancellation, partial completion, and delayed usage reports cannot duplicate a logical customer charge. |
| IEA-09 | External assistant tools use organization-scoped authentication, closed typed arguments, current permissions, revision checks, and idempotency. |
| IEA-10 | Assistant or uploaded content is untrusted proposal data. Ordinary writers and approval rules remain authoritative. |
| IEA-11 | Import sources/rows are immutable; mappings, prepared results, reviews, corrections, and approvals are revisioned and attributable. |
| IEA-12 | Every source column is mapped, custom, or explicitly excluded. Full-dataset preview shows duplicates, errors, conflicts, and before/after effects. |
| IEA-13 | Identical re-import replays. Corrected input creates linked revisions. Mapping changes invalidate affected reviews. |
| IEA-14 | Checklist-led creation preserves product, release, configuration, packaging, card/variant, optional subject, and many-to-many applicability boundaries. |
| IEA-15 | Checklist publication creates no inventory or financial facts. Inventory, invoice, receipt, marketplace posting, and publication use separate governed commands. |
| IEA-16 | Exports use the complete authorized cohort with explicit selected-ID or all-filtered scope, reviewed specification, preview, artifact expiry, and reproducibility metadata. |
| IEA-17 | Generating a file is distinct from transmitting or publishing it. |
| IEA-18 | Organization corrections do not silently retrain shared models or change another organization's mappings. |
| IEA-19 | Provider-specific access, billing, data, retention, and connector limitations are verified from current official sources before activation. |
| IEA-20 | Usage and draft reporting is organization-visible by job, feature, and initiating actor under independent privacy permissions. |

Commercial rates, packages, and provider commitments remain undecided.
