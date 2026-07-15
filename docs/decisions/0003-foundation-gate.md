# ADR 0003 — Adopt the Foundation Gate; pause the feature roadmap

**Date:** 2026-07-15 · **Status:** accepted, in progress (Track A)

## Context
The M4 incidents (ADR 0002) exposed that the platform had no reproducible database blueprint, no non-production environments, and no safety rails — a local client could (and did) mutate production, and a security-regressing migration reached prod. Separately, the frontend is a single 440 KB `index.html` whose workflows are page-thinking, not outcome-thinking.

## Decision
**Pause the feature roadmap at a Foundation Gate.** No new production modules on the old global model. Two parallel tracks:
- **Track A (backend/platform):** 1. DB blueprint + repo consolidation → 2. local + staging environments → 3. safety rails (CI, packaging, backups, branch protection) → … 6. org/membership contract → 7. isolation proof → 8. bounded reads → 9. realtime strategy → 10. prod cutover.
- **Track B (frontend):** controlled replatform — UX prototype → domain/module map → navigation prototype → 5 critical journeys → tenant-aware skeleton → first slice → progressive migration.

`index.html` becomes a behavioral/calculation **oracle and fallback**, not the navigation spec. 2.10/2.11/2.12 are built later in the new shell, not as `index.html` modules. Phase 2's remaining plumbing (M4, 2.12) still closes in the current world.

## Consequences
- Track A steps 1–3 execute now (this pass): production becomes reproducible, tests leave production, and a fail-closed schema-version handshake makes the M4-style accident structurally impossible.
- Two money-gates require explicit approval: a hosted staging project (A2), PITR backups (A3).
