# Element 10 — PRODUCT_FIRST_MERGE_MANIFEST.md
## Canonical product-first documentation merge — manifest & verification record

**Pass type:** documentation-only. No prototype HTML/CSS/JS, screens 01–07, source/live mirrors, archives, application code, schema, migrations, or A6b rows changed. A6b remains frozen and independent. **Awaiting the literal approval "Product-first workflow approved."**

**Lifecycle-alignment addendum (2026-07-27):** the original merge record below
remains historical evidence; the workflow was subsequently approved. This
revision adds cross-references to `../OPERATOR_LIFECYCLE.md` and
`../UX_WORKFLOW_CONTRACT.md` without changing the accepted product-first model,
arithmetic, capability, D3, or security decisions. See the package-level
`REVISION_MANIFEST.md` and regenerated `HASHES.txt`.

---

## 1. Input verification (SHA-256 checked before editing)

| Input | Expected hash (prefix) | Result |
|---|---|---|
| PRODUCT_SUPPLY_MODEL.md | `398e4b7a…33df` | **OK** |
| PRODUCT_SUPPLY_MODEL_TEST_MATRIX.md | `a4d5e645…58bd` | **OK** (latest corrected copy — Examples D `req_required=6`, K PO-cancel, L substitution, direct-vs-promotion rule) |
| PF_M1_DELTA.md | `ccf5cc06…6d53` (…b576d537) | **OK** |
| D3_INPUT_CONTRACT.md (approved base) | `9f69c219…5733` | **OK** (base verified before applying the §1a/§10a governance extension) |
| PRODUCT_FIRST_GOVERNANCE.md | `89980d3e…6f30` | **OK** |
| CAPABILITY_CROSSWALK.md | `3333a2a0…6aab` | **OK** |
| PRODUCT_FIRST_CHECKPOINTS.md | `3ac3e8f8…f408` | **OK** |
| GOVERNANCE_MERGE_DELTA.md | `bd0bf531…b3c6` | **OK** |

**No input was missing or had an unexpected hash. No version was silently substituted.** The latest corrected test matrix was used; no older matrix from another archive was reintroduced.

### 1a. Consistency closure pass (status-only edits to approved supporting docs)

In the initial merge the seven approved supporting documents were **described** as approved in the canonical workflow, but their **own headers still read PROPOSAL / awaiting an already-granted approval** — a status contradiction, not a substance one. This closure pass edits **only their status/provenance framing** (no model, arithmetic, capability, governance, or checkpoint substance changed). Because content changed, **their hashes are regenerated** (see §7 / HASHES.txt) — the earlier package left these headers stale, which is corrected here.

| Document | Old header | New framing | Class |
|---|---|---|---|
| PRODUCT_SUPPLY_MODEL.md | "PROPOSAL … awaiting 'Product supply model approved.'" | Approved input; semantics unchanged during merge | STA |
| PRODUCT_SUPPLY_MODEL_TEST_MATRIX.md | "PROPOSAL" | Approved input (worked examples); arithmetic unchanged | STA |
| PF_M1_DELTA.md | "PROPOSAL … deltas to apply … not edited" | Approved input; delta fully applied; retained as history | STA |
| PRODUCT_FIRST_GOVERNANCE.md | "PROPOSAL … Awaiting 'Product-first governance approved.'" | Approved input (governance v3); substance unchanged | STA |
| CAPABILITY_CROSSWALK.md | "PROPOSAL (governance)" | Approved input (authority + v1 rulings); unchanged | STA |
| PRODUCT_FIRST_CHECKPOINTS.md | "PROPOSAL (governance)" | Approved input (PF-C1…C21); unchanged | STA |
| GOVERNANCE_MERGE_DELTA.md | "PROPOSAL (governance corrective)" | Approved input; delta fully applied; retained as history | STA |

Additional status-only / reference corrections this pass: **CONTEXT.md** (removed the active "D2-0.4 — awaiting 'D2 design approved'" claim → approved planning-foundation history; reference list points to product-first authority first; added screen `07-planning-schedule.html`; replaced the stale streaming-first spine with the canonical product-first operating sequence, Schedule-first as exception). **D2_PLAN_REVISION_PROPOSAL.md** (C1 note "Product workspace is additive in C4+" → "begins in the approved PF-C sequence"; §6 Track A handoff rewritten to the current contract — A6b frozen/independent/unblocked, no `product.read`/`program.manage`, `session.write` for programs+preparation, later-additive `session.approve`, future implementation contracts; stale leaf table retained only inside the collapsed no-authority history). **All substantive product-first content is unchanged by this closure pass.**

---

## 2. Merge map (source → destination, change class)

Change classes: **SUB** substantive · **STA** status-only · **XREF** cross-reference-only · **D3X** explicit D3 governance extension.

| Source | Section / ruling | Canonical destination | Class |
|---|---|---|---|
| PF-M1.1 model | object vocabulary, catalog seam, conservation, direct-vs-promotion | WORKFLOW §1, §3 | XREF + SUB (stated directly) |
| PF-M1.1 test matrix | Examples D/K/L, partial/multi-lot/idempotent | WORKFLOW §3 (rules), retained as evidence | XREF |
| Governance v3 | issuance→approval order (PF-C16/C17) | WORKFLOW §7 | SUB |
| Governance v3 | Attention/Recovery + resolver + I1–I17 | WORKFLOW §6 | SUB |
| Governance v3 | cost-first coverage + I14 | WORKFLOW §5 | SUB |
| Governance v3 | four-concern authority + v1 rulings | WORKFLOW §8 (crosswalk authoritative) | XREF + SUB |
| Governance v3 | cancellation/reversal placement | WORKFLOW §4, §10 | SUB |
| Governance v3 | PF-C1…PF-C21 + PA/IC/CR/AP | WORKFLOW §10 (pointer to CHECKPOINTS) | XREF |
| Governance v3 | warm/routine path + ergonomics record | WORKFLOW §9.2 | SUB |
| D3 contract (base) | Prepared vN inputs, Start Live atomic boundary, resolver, channels, trade machines, consumption | D3 §1–§10 (preserved) | XREF |
| **D3 extension (new)** | **Start Live ↔ valid approval bound to exact `prepared_version_id` + digest; maker≠checker; superseded approval cannot start; new build-acceptance 3a** | **D3 §1a, §10 (item 3a)** | **D3X** |
| D2 revision | entity-model ownership → ProductRequirement (Show-owned) | D2_PLAN_REVISION §1 (corrected); WORKFLOW §1.5, §2 | SUB |
| D2 revision | C4–C10 sequence | D2_PLAN_REVISION §3 → superseded by PF-C1…21 | SUB (superseded, retained as history) |
| D2 revision | capability-impact table | D2_PLAN_REVISION §5 → superseded by CROSSWALK v1 rulings | SUB (superseded, retained as history) |
| CONTEXT.md | pending-proposal + D2-0.4 header | CONTEXT.md canonical merge header | STA |
| all approved docs | status labels | canonical status table (WORKFLOW §status) | STA |

**Status-only vs substantive (this closure pass):** the seven supporting-doc header edits and the CONTEXT / D2_PLAN_REVISION status-and-reference corrections above are **STA**. **No substantive product-first content changed in this closure pass.** (Substantive canonical authoring remains confined to the initial merge: WORKFLOW.md authoring, the D3X extension, and the D2_PLAN_REVISION supersessions.)

---

## 3. Decision-preservation checklist (every approved decision carried, none dropped)

- [x] Catalog seam: Platform Card Catalog vs Org Product Master vs Product Configuration; org-private data never shared; no shared Product catalog built now. → WORKFLOW §1.1
- [x] ProductRequirement created on exactly one Show; optional one-Break attribution; no generic later "assign to Show"; assignment creates/updates Show-owned children. → §1.5
- [x] Cards requirements pin approved ChecklistForUse; core/cards-off expose no checklist concept. → §1.5, §13
- [x] Program Templates hold blueprints/references, not live rows; generated Shows get new instances w/ lineage; divergence doesn't mutate template/siblings. → §1.9
- [x] Both reservation paths (direct `req_planned=0` + promotion decreasing planned by exactly confirmed); allocation optional; conservation `req_planned+req_confirmed ≤ req_required`. → §3
- [x] Prepare requires `req_confirmed=req_required` and `req_planned=0`; all-or-nothing default; `allow_partial`; atomic+idempotent; reread under guard; no double-count; multi-lot. → §3
- [x] Cancellation/reversal/substitution semantics + earliest-checkpoint placement (PO cancel/reduce, receipt reversal, Show cancel, Break removal, release-and-create substitution, additive cost adj). → §4, §10
- [x] Cost-first: PO/receipt/lot evidence; additive freight/rebate/credit/correction; modeled non-authoritative recipe economics; source-lot lineage; immutable Prepared cost; pre-Live policy invalidation; post-Live additive to D6. → §5
- [x] Attention (valid-incomplete) vs Recovery (regressed/stale/failed/conflicted/interrupted); current-version scoping; no unresolved blocking Recovery past issuance/Start Live; shared resolver; closure evidence; return context; cancelled Show shows history. → §6
- [x] I1–I17 invariant set carried. → §6
- [x] PF-C16 issuance → PF-C17 approval → PF-C18 handoff (approval bound to exact version). → §7
- [x] Four authority concerns; mod.* ≠ read auth; RLS for org reads; verified ownership for participant-private; allowlisted broadcast; future *.read never replaces RLS; reporting_export ≠ money/cost read; prototype gating ≠ production auth. → §8
- [x] v1 rulings: no product.read; no program.manage; session.write for programs + preparation; chase via checklist authority; format.approve deferred; receive/purchasing/checklist.approve distinct; money.read/cost.read need privacy ruling; trade.commit/offer.buyback later. → §8
- [x] session.approve distinct, later-additive, A6b-unaffected, not persisted, human ruling required; session.write never the production checker. → §8
- [x] Four workflow paths (cold-start, warm routine, same-night fast, schedule-first exception); warm-path ergonomics record. → §9
- [x] PF-C1…PF-C21 adopted; no reuse of old C4/C5/C6; C1–C3 valid where they refer to accepted planning prototype; future comments use object/workflow names. → §10
- [x] Screens 01–07 = accepted pre-pivot evidence, frozen; PF-0 after approval; PF-C1 first impl checkpoint. → §11
- [x] Approved D3 behavior preserved except the explicit governance extension. → D3 (all sections retained; §1a/§10 extended)
- [x] A6b frozen and independent. → all status blocks

---

## 4. Stale-term & stale-reference sweep report

| # | Sweep | Result |
|---|---|---|
| 3 | product-first C4/C5/C6 presented as current | **clean** — only PF-C, accepted C1–C3, or clearly-marked historical/superseded blocks |
| 4 | Schedule-first framing | **clean** — **no document presents Schedule-first as the sole or canonical origin.** The Schedule-first **exception** is intentionally preserved (WORKFLOW §9.4, CONTEXT spine), and valid exception references remain. The canonical origin is the product-first operating sequence. |
| 5 | conflicting ProductRequirement ownership (session-owned) | **clean** — only the corrective note that explicitly supersedes the phrase |
| 6 | single-product-per-Break / inventory-per-Break | **clean** — only negations ("not a generic inventory per Break") |
| 7 | PlannedAllocation mandatory | **clean** — only the "no PlannedAllocation required" statement |
| 8 | approval-before-Prepared | **clean** — 0 hits (order is issuance→approval) |
| 9 | session.write as production checker | **clean** — all hits state the prohibition |
| 10 | mod.* as read authorization | **clean** — 0 hits |
| 11 | reporting_export as money/cost read | **clean** — all hits are negations |
| 12 | missing Attention/Recovery definitions | **present** — WORKFLOW §6 |
| 13 | missing cost provenance | **present** — WORKFLOW §5, I14 |
| 14 | cards terminology in core/cards-off paths | **clean** — only the cards-off-never-surfaces rule |
| 15 | PF-C dependencies + stop phrases | **verified** — CHECKPOINTS matrix (PF-C1…C21, each with stop phrase) |
| 16 | internal links / section references | **verified** — cross-doc references resolve to existing files/sections |
| 17 | approved D3 behavior preserved except extension | **verified** — only §1a/§10 approval-binding added; all else unchanged |
| 18 | no prototype / source / live / archive changed | **verified** — only 4 docs edited |
| 19 | no Track A / schema file changed | **verified** — none touched |
| 20 | no approved decision dropped | **verified** — see §3 checklist |

---

## 5. Remaining open human rulings

1. **`session.approve`** — production maker-checker authority: approve the distinct leaf name + its additive migration. Until then PF-C17 production cannot be operational (prototype may only simulate). Later-additive; does not affect A6b.
2. **`money.read` / `cost.read`** — explicit financial-privacy ruling (who reads money vs cost; `act.reporting_export` is not equivalent).
3. **`format.approve`** — defer confirmed until a maker-checker format-approval boundary is actually built.
4. **`trade.commit` / `offer.buyback`** — ruling needed only before those participant-facing features become operational.
5. **Future post-A6 additive capability migrations** — any finer product-first leaves are **later-additive decisions** taken after the appropriate foundation gates. **A6b is frozen, independent, and unblocked**; the frozen catalog is unchanged and product-first does not block it.

---

## 6. Intentionally deferred implementation / security proofs (not claimed by prototypes)

Browser prototypes (PA/CR) may demonstrate workflow, visible permission/entitlement states, deterministic conflict fixtures, terminology, return context, accessibility, responsive behavior. They **do not** prove, and the following are deferred to authoritative integration/security acceptance (AP):

- RLS / tenant-isolation enforcement (PF-C20 *simulates* two orgs; not a hostile RLS proof).
- Transaction atomicity, concurrency safety, compare-and-set guards.
- Idempotent server execution (reservation, promotion, Start Live, consume/reverse, trade commit).
- Realtime channel privacy (companion/OBS payload separation).
- Production maker-checker authorization (`session.approve`).
- Authoritative landed-cost computation and immutable-snapshot persistence.

---

## 7. Canonical package files & hashes

See `HASHES.txt` in the archive for the full SHA-256 list of every delivered file (regenerated this pass).
