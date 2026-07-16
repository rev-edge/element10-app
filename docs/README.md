# Element 10 — docs (canonical)

This directory is the **canonical home** for Element 10's operational documents. The iCloud
`Streaming/` folder is now **non-canonical** — treat anything there as a draft/history unless it has
been promoted here.

## Contents
- **[DATABASE.md](DATABASE.md)** — the database blueprint: how production is reproduced from
  `supabase/migrations/`, the local workflow, and the reproducibility proof.
- **[ROADMAP.md](ROADMAP.md)** — product direction, the Foundation Gate, Track A/B ordering.
- **[CODING_STANDARDS.md](CODING_STANDARDS.md)** — standing engineering + UX/QA standards.
- **[Platform_Overview.md](Platform_Overview.md)** — system overview.
- **[SPIKE_storage_decision.md](SPIKE_storage_decision.md)** — the S1 storage spike behind ADR 0001.
- **[DOMAIN_MAP.md](DOMAIN_MAP.md)** / **[WORKFLOW_INVENTORY.md](WORKFLOW_INVENTORY.md)** — Track B inputs.
- **decisions/** — Architecture Decision Records:
  - [0001 — relational inventory (D1)](decisions/0001-relational-inventory.md)
  - [0002 — M4 blob retirement](decisions/0002-m4-blob-retirement.md)
  - [0003 — Foundation Gate adoption](decisions/0003-foundation-gate.md)
  - [0004 — Scale Target (v1.2: ceiling, milestones, two-principal identity + two-tier viewer contract)](decisions/0004-scale-target.md)
- **[SECURITY.md](SECURITY.md)** — the privileged-function register + advisor dispositions (A4/A5.1 acceptance artifact).
- **incidents/** — [2026-07-15 M4 blob clobber](incidents/2026-07-15-m4-blob-clobber.md).

## Conventions
- Schema ships in `supabase/migrations/`; data ships in `supabase/seed.sql` or a documented import — never in migrations.
- New/redefined views: always `security_invoker = true` + explicit `revoke … from anon`.
- Functions are **born non-executable** (A5.1a): intended-public RPCs must `grant execute … to authenticated` explicitly (see SECURITY.md).
- One-way / grant migrations ship a tested down-path (in `supabase/recovery/`) before the window closes.
- **A pass is not complete until the canonical docs describe the world it leaves behind.**
