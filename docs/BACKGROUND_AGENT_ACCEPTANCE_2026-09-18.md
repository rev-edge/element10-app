# Background agent acceptance contract

Status: future acceptance cases. This document marks none as implemented.

| ID | Scenario | Required result |
| --- | --- | --- |
| BA-A01 | Ordered 12, received 8, billed 12 | One discrepancy finding with all three fact sets and suggested follow-up; receipt and stock remain unchanged. |
| BA-A02 | Eight received now, four still expected later | Finding is awaiting delivery or no action under the approved timing rule; no unsupported shortage conclusion. |
| BA-A03 | Packaging conversion missing or conflicting | Quantity conclusion is blocked with exact missing/conflicting evidence; no guessed conversion. |
| BA-A04 | Same event delivered repeatedly or concurrently | One effective run/finding/proposal; stable replay response and no duplicate task or claim. |
| BA-A05 | Receipt corrected after a proposal | Prior proposal becomes stale and cannot execute; new run references the correction and preserves history. |
| BA-A06 | Actual supplier credit already allocated | Effective credit is included and no duplicate recovery request is proposed for the covered amount/quantity. |
| BA-A07 | Invoice and receipt currencies differ | Comparison fails closed; no silent conversion or amount conclusion. |
| BA-A08 | Freight/tax policy is unresolved | Agent reports the policy limitation and does not assert a payable discrepancy from undecided arithmetic. |
| BA-A09 | Proposed credit request | It remains distinct from submission, supplier acknowledgement, actual credit, payment, and receipt. |
| BA-A10 | High-confidence exact card candidate | Candidate and evidence are shown; no canonical or inventory link changes before authorized confirmation. |
| BA-A11 | Ambiguous subject alias | Multiple candidates and unresolved source text remain; similar name alone confirms nothing. |
| BA-A12 | Card with multiple subjects | All supported candidates/confirmed links are preserved without duplicating the owned item or financial fact. |
| BA-A13 | Human-reviewed identity exists | Automatic proposal cannot overwrite it; explicit authorized supersession is required. |
| BA-A14 | Organization-private enrichment | Tenant suggestion is visible only in its organization and does not mutate platform catalog data. |
| BA-A15 | Formatting candidate | Raw text remains intact; only approved derived normalization is proposed; protected fields are unchanged. |
| BA-A16 | Connection revoked or spending cap reached mid-run | No new provider attempt or proposal publication occurs; draft/finding evidence remains; in-flight outcome/cost is auditable. |
| BA-A17 | Agent disabled while queued | Queued work cannot start; repeated trigger does not bypass pause; existing history remains readable. |
| BA-A18 | Cross-organization run/context/reference | Access fails before target disclosure and leaves zero finding, proposal, task, usage, or action residue. |
| BA-A19 | Malicious instructions in invoice/card source | Text is retained as evidence and cannot change org, permissions, provider, funding, destination, or action. |
| BA-A20 | Source change while worker waits | Final source/policy/grant reread rejects stale work after a proven lock wait. |
| BA-A21 | Worker crash and retry | Lease expires, a new generation resumes from durable checkpoint, old owner cannot publish, and no duplicate finding/action results. |
| BA-A22 | Agent-created downstream event | Causal fingerprint prevents an identical self-trigger loop while legitimate later human/domain changes remain observable. |
| BA-A23 | Observe-and-propose policy | Zero invoice, credit, receipt, stock, reservation, cost, catalog, payment, or external-send mutation occurs. |
| BA-A24 | Later selective automation | Only the named granted action delegates to its guarded writer after current authority/state checks; unrelated effects remain impossible. |
| BA-A25 | Home task projection | One finding appears through the existing task/workspace model with stable links and no second source-of-truth task record. |
| BA-A26 | Manual/no-AI operation | Deterministic run, finding review, and resolution remain available without an AI connection or provider budget. |

Acceptance requires clean local replay, focused SQL and real two-connection
concurrency gates, exact-head CI, explicit guarded staging evidence, ACL/RLS and
advisor review, fixture-free cleanup, production read-only proof when authorized,
and an independent verdict. A prototype animation, model response, queue row, or
database acknowledgement alone is insufficient.
