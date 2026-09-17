# Shared import, export, and AI dependencies

Status: dependency and decision register, 2026-09-17.

## Existing contracts to reuse

- Tenant spine, module entitlement, capability registry, and final-lock authority.
- X5 immutable intake, raw/typed separation, correction lineage, and replay.
- X8a explicit organization query contexts and closed typed dispatcher.
- X8b immutable proposal revisions, preview, approval, delegated commit, and replay.
- X8c dormant outbox protocol, without claiming provider delivery.
- Product/configuration versions and packaging contracts.
- Organization checklist, subject, and configuration-applicability proposals.
- Existing inventory, purchasing, receiving, customer transaction, and catalog publication writers.
- Full-authorized-dataset grid/query rules in `EXPANSION_FRAMEWORK.md`.

## Blocking owner decisions

- capability vocabulary and default grants;
- secret manager and supported credential methods;
- first managed provider/model families;
- data classes, minimization, retention, and support visibility;
- allowance/credit/spend-limit behavior and pricing-policy owner;
- fallback consent policy;
- checklist completeness and approval separation;
- export size, retention, expiry, saved-spec ownership, and destinations;
- first organization-funded provider and first external connector host;
- first post-checklist domain adapters.

## Provider launch dependencies

Before activation, verify current official API terms, model availability, rate
limits, data controls, regional processing, usage/cost fields, credential
rotation, connector distribution/review, OAuth requirements, and incident
handling. A consumer assistant subscription is not an API credential or funding
source for Element 10 calls.

## Security and operations dependencies

- server-only credential storage with opaque database references;
- tenant and actor-bound jobs, artifacts, templates, and usage reports;
- RLS plus explicit grants and closed functions for every exposed object;
- secret redaction in logs, errors, audit, exports, and model payloads;
- queue limits, concurrency controls, cancellation, timeouts, and dead-letter review;
- usage/cost reconciliation and idempotent billable events;
- artifact storage, malware/content checks, checksum, expiry, and purge;
- provider and connector kill switches;
- no production activation until threat model, privacy review, exact-head CI,
  staging evidence, advisor review, and independent acceptance complete.

## Non-blocking first-slice dependencies

The checklist-led manual slice does not require AI credentials, pricing, MCP,
external connectors, or outbound delivery. It does require approved checklist
ownership/publication rules, the product/configuration/checklist data contracts,
immutable source storage, deterministic parser/mapping validation, and revision-
bound review.
