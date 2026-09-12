# TA-X7e consolidated review checklist

Prepared 2026-09-11 from `TA_X7_REPORTING_PLAN.md` X7e and
`EXPANSION_ACCEPTANCE_CASES.md`. This is a pre-implementation review checklist,
not acceptance, a new product scope, or permission to bypass X7d dependencies.

| Area | Required proof |
|---|---|
| Lifecycle arithmetic | Jan 1 receipt, Jan 3 published, Jan 4 pause, Jan 6 resume, Jan 9 sale yields age 8 days, intake delay 2, first-list-to-sale 6, active exposure 4 using documented boundaries. |
| Exposure grain | Overlapping channel intervals union per physical copy; simultaneous listings never create another item or double-count exposure. |
| Unsold and unknown | Unsold duration is censored at the requested cutoff, not a completed sale duration. Missing timestamps yield unavailable measures and explicit exclusions. Listing disappearance alone never implies sale or closure. |
| Eligible history | Corrections/supersessions select current eligible interpretation without altering original evidence; occurrence time and recorded time remain distinct. |
| Grading | Append-only assessments and regrades retain one physical copy; source, dates, review state and supersession are traceable. |
| Population | Dated, scoped population snapshots retain provenance and freshness; population is never substituted for print run. |
| Value evidence | Actual cost, asking price, completed sale and estimate/index remain separate kinds; an estimate cannot fabricate a sale. |
| Valuation contract | Explicit method/version, currency, cutoff and freshness bound; valued/unvalued counts, evidence age/source, unknown cost and population date. Missing or stale evidence is disclosed, never silently zero. |
| Portfolio movement | Acquisition contribution is separate from market appreciation; adding a card does not masquerade as a price increase. No implicit currency conversion. |
| Feed independence | Eligible local/manual/imported evidence supports the same reporting without enabled connectors. Sparse and absent evidence are covered. |
| Access and bounds | Organization isolation, explicit authority, bounded reads and affected revision/cursor rules; relevant revocation and concurrent mutation cases have positive controls. |
| Release gate | Additive migrations, clean replay, focused tests, predecessor regressions, A7, default privileges, exact-head CI, explicit staging verification, advisor disposition and fixture cleanup. |

Before implementation, the builder should map these cases to proposed contracts
and planned tests, including any genuinely unresolved business decision. Do not
invent a valuation or costing rule just to satisfy a fixture. Technical choices
should be recorded with their boundary and tested implications.

Submit one milestone packet containing exact commit, changed files, test case
mapping/results, local-to-staging migration mapping, baseline and cleanup proof,
advisor disposition and remaining requirements. Detailed logs stay linked rather
than repeated in prompts. Reviewer returns consolidated findings; further review
focuses on the affected delta. Full Track A X1-X8 completion remains separate.
