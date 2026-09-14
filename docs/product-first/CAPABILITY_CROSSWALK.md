# Element 10 — CAPABILITY_CROSSWALK.md
## Authoritative behavior → authority mapping (governance corrective pass)

**Status:** **APPROVED input** (authority vocabulary + v1 rulings) to the canonical product-first workflow. Capability substance **unchanged during the canonical merge**; retained as approved authority. Built against the approved ADR 0005 / A6b stable catalog + current D2 plan. **A6b stays independent and frozen** to its stable catalog; no product-first capability blocks it; fine-grained additions are **later additive data migrations**, never a tenancy rewrite.

**Operator-lifecycle relationship:** `../OPERATOR_LIFECYCLE.md` defines when an
operator needs an action; this document defines whether that action is authorized.
`../UX_WORKFLOW_CONTRACT.md` requires unavailable actions to explain the boundary
without implying permission. Navigation, continuation, or a visible button never
substitutes for RLS, ownership, capability, entitlement, or legal enforcement.

## Four separated concerns
1. **Identity + org/ownership-scoped DB authorization (RLS)** — the authoritative read/write boundary. Org-owned rows are org-scoped via membership/RLS; participant-private via verified ownership; public via allowlisted projection.
2. **Module entitlement + nav visibility** (`mod.*`, `core`/`cards`) — controls whether a surface appears; **not** authoritative read permission.
3. **Action capability for mutation** (`act.*` + future leaves) — controls whether a member may mutate.
4. **Legal / policy gates** — buyback legality, maker-checker approval, cost/money privacy.

`mod.*` visibility never substitutes for RLS. `act.reporting_export` is **not** money/cost read authorization. Interim prototype mappings are **not** production authorization.

## Leaf category legend
**(1)** persisted stable key (ships in A6b) · **(2)** design-approved D2 fine leaf · **(3)** newly proposed product-first leaf (NOT approved) · **(4)** no new leaf needed (reuse existing).

**Legacy stable catalog (persisted today):** actions `act.inventory_edit`, `act.lists_edit`, `act.live_run`, `act.permissions_config`, `act.reporting_export`, `act.team_manage`; modules `mod.home/inventory/reporting/schedule/settings/toolkit`; entitlements `core`/`cards`.

## v1 rulings (explicit)
| Behavior | v1 authority | Future leaf (cat) | Abuse / SoD boundary | Why existing insufficient | Milestone leaf needed | Human ruling still needed |
|---|---|---|---|---|---|---|
| View schedule/session | RLS + `mod.schedule` | `session.read` (2) | narrow role view | — (RLS authoritative) | before prod | no |
| Create/reschedule session | `act.lists_edit` | `session.write` (2) | edit plan | sufficient v1 | before prod | no |
| **Product read** | RLS + `mod.inventory` | **no `product.read` in v1 (4)** | — | inventory.read scope suffices | — | no |
| Edit product master/config | `act.inventory_edit` | `product.write` (3) | catalog edit | ok v1 | before prod | no |
| View inventory/lots | RLS + `mod.inventory` | `inventory.read` (2) | — | RLS authoritative | before prod | no |
| Reserve/allocate | `act.inventory_edit` | `inventory.reserve` (3) | commit stock hold | ok v1 | before prod | no |
| **Receive/count** | `act.inventory_edit` | **`inventory.receive` (3)** | **changes stock + authoritative cost evidence** | distinct from editing | before prod | no |
| **Create/commit PO** | `act.inventory_edit` (interim) | **`purchasing.write` (3, kept distinct)** | **commits organizational money** | money ≠ inventory movement | before prod | no |
| Stage/overlay checklist | `act.lists_edit` | `checklist.stage` (3) | private staging | ok v1 | before prod | no |
| **Chase annotation** | `act.lists_edit` (v1) | `checklist.annotate` (3, **deferred**) | — | staging authority suffices v1 | only if a real boundary emerges | no |
| **Approve checklist-for-use** | `act.lists_edit` + approver | `checklist.approve` (3) | **approval distinct from private staging/editing** | separation of duty | before prod | no |
| Configure break format/slots | `act.lists_edit` | `break.configure` (2) | edit format | ok v1 | before prod | no |
| Manage format template version | `act.lists_edit` | `format.manage` (3) | template versioning | ok v1 | before tenant | no |
| **Approve format template** | — | `format.approve` (3, **deferred**) | maker-checker | not merely because editing exists | only when maker-checker built | **yes (decision point)** |
| Program templates / recurring gen | **`session.write`** | **no `program.manage` (4)** | no distinct blast radius proven | session.write suffices | — | no |
| **Prepare a session** | **`session.write` (v1)** | `session.prepare` (2, only if prep shown to need distinct authority) | — | session.write suffices v1 | before prod (if proven) | **yes (decision point)** |
| **Approve preparation** | — (prototype may *simulate*; **`session.write` must not be the production checker**) | `session.approve` (3, **deferred**) | **maker-checker** | separate only when implemented | when maker-checker built | **yes (decision point)** |
| Run live session (all live-control mutations) | **`act.live_run`** (+ per-control entitlement/legal) | reuse legacy (4) | — | stable | — | no |
| **Buyer-to-buyer trade commit** | `act.live_run` (interim) | `trade.commit` (3) | ownership transfer | before feature operational | before participant feature live | no |
| **Buyback/store-credit offer** | `act.live_run` + **legal gate** | `offer.buyback` (3) | money/liability + legality | before feature operational | before participant feature live | **yes (legal)** |
| **View money (directional)** | — (not `act.reporting_export`) | `money.read` (3) | financial privacy | reporting_export ≠ money read | before prod | **yes (privacy ruling)** |
| **View cost basis / margins** | — (not `act.reporting_export`) | `cost.read` (3) | cost privacy | reporting_export ≠ cost read | before prod | **yes (privacy ruling)** |
| Configure permissions/team | `act.permissions_config` / `act.team_manage` | reuse legacy (4) | — | stable | — | no |

## Summary rulings
- **`purchasing.write`, `inventory.receive`, `checklist.approve` are defensibly distinct** (money commit; stock+cost evidence; approval vs staging) — separate leaves before production.
- **Deferred** until their controlling behavior is implemented: `checklist.annotate`, `format.approve`, `session.approve`, `session.prepare` (as distinct from `session.write`). Each is a **decision point**, not an assumed leaf.
- **PF-C17 maker-checker approval is real approval behavior.** A prototype may *simulate* the checker authority, but **production requires the distinct `session.approve` leaf before the workflow is operational** — `session.write` must **never** become the production checker authority. `session.approve` remains a **later additive** capability, **does not affect A6b**, and **nothing here claims it is already persisted**; a **human ruling precedes** its additive migration.
- **No `program.manage`** (no distinct blast-radius boundary). **No `product.read`** in v1 (inventory.read scope suffices).
- **`money.read` / `cost.read` require an explicit privacy ruling**; `act.reporting_export` is not equivalent.
- **A6b unaffected** — ships legacy six + six now; every category-2/3 leaf is later additive.
