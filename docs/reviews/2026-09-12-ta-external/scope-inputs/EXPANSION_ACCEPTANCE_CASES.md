# Expanded vision acceptance cases

Contract tests to implement with the corresponding feature. These are worked cases, not claims that the features already exist. See EXPANSION_FRAMEWORK.md for scope and immutable boundaries.

| Case | Input / action | Required outcome |
|---|---|---|
| Identity across releases | Same maker/line/number/parallel, two distinct release IDs | Two canonical variants; never merged solely by display strings. |
| Identity across copies | One exact variant, serial 3/50 and 4/50 | One catalog variant, two observed copies. Serial filter 3/50 returns only supported copy evidence. |
| Alias uncertainty | Gold title with unknown finish vs verified true-gold mapping | Unknown stays unresolved; broad color query may show it with qualification, exact true-gold query does not silently include it. |
| Multiple subjects | Dual-player card including the queried player | Subject relationship query finds it without inventing two physical cards. |
| Rookie distinction | Release year differs from athlete's rookie season | Filter follows the selected verified designation/season dimension, not a silent year equality. |
| Optional sales threshold | Matching catalog entry has no observed sales; min-sales is unset | Entry remains visible with unavailable price, not zero price. |
| Correct aggregate order | Four qualifying sales: $500, $1500, $500, $1500; mean filter below $1000 | Mean is $1000 and group is excluded. Do not remove the $1500 sales before calculating this mean. |
| Optional transaction filter | Same data, user explicitly limits individual sale price to $800 | Two sales and $500 mean, visibly labeled as a filtered transaction cohort. |
| Mixed evidence | One active ask $1500 and one completed sale $900 | Ask does not enter completed-sale mean/count; both have source/time and price type. |
| Syndicated duplicate | Same external sale imported from two licensed datasets | One deduplicated sale contribution, both provenance links preserved. |
| Exposure vs age | Receipt Jan 1; list Jan 3; pause Jan 4; resume Jan 6; sale Jan 9 | Inventory age 8 days; intake delay 2; first-list-to-sale 6; active exposure 4, with consistent timestamp boundaries. |
| Concurrent listings | Two channels list the same copy during overlapping days | Item-level exposure is union of intervals; one copy in stock, not two. |
| Unsold cohort | Five received copies, one sold in six days and four unsold | "Mean among sold: 6 days, n=1" plus four unsold and window/age; not "this card moves in six days." |
| Late correction | Cost/identity correction arrives after a sale report | Additive evidence retained; affected aggregate invalidated/rebuilt, cutoff/version visible; prior immutable evidence not rewritten. |
| Invoice-only intake | Invoice for 12 boxes, no PO; operator receives 10 | No fabricated PO; 10 accepted physical boxes, invoice review separate, 2-box discrepancy explicit. |
| Duplicate document | Identical invoice delivered twice, then same ID with changed content | First replay creates no duplicate receipt/charge; changed fingerprint requires reconciliation rather than silent replay. |
| Split matching | Two invoices against one PO and one invoice across two POs | Explicit allocated quantities and amounts conserve document/line totals; no duplication in vendor spend. |
| Location restriction | Actor can order only to Store B; types Store A as text | Writer refuses forbidden ID; text cannot override it. B preselected and locked when sole eligible destination. |
| Historical cost | Same vendor, hobby box and hobby case with different conversion versions | No unqualified cross-unit autofill. Source/date/currency/conversion shown; unknown or unreceived estimate not labeled last paid. |
| Manual price | Operator types one-off price then changes vendor | Manual value preserved and flagged for review; new suggestion never silently replaces it. |
| Notes audience | Internal note contains a secret deal note; vendor comment contains delivery instruction | Vendor projection contains only explicitly allowed vendor comment/fields, no internal note even in hidden metadata. |
| Wishlist only | Save wanted card with monitoring off | No stock, PO, reservation, scheduled check or notification created. |
| Pause monitor | Enable weekly checks, then disable | Entry/preferences remain; no future check/alert while off; in-flight completion follows explicit cancellation policy. |
| New-match tracking | First scan has two matches; next repeats both and adds one | Baseline existing matches, one new alert only; no duplicates on retry. |
| Auction truth | Listing currently bids at $500 then disappears | $500 remains an observed bid, not final paid price; disappearance is not a sale. |
| Workspace question | User asks stock or margin without write intent | Read-only bounded query with scope, units, metric and sources; no mutation. Missing cost yields provisional/unavailable margin. |
| Draft by chat | Ambiguous product and no vendor/qty; user requests a PO | Clarification/ordinary draft, no guessed committed order; later commit rechecks permissions and revision. |
| Scope switch | Chat/query cache or draft created in org A; operator switches to B | A's data/draft is not used under B's authority; explicit context check and no private-cache leakage. |
| Multi-membership | One user belongs to two companies | Actual selected/explicit-org server context is validated; no arbitrary first-org fallback. Prototype toggle alone does not pass. |
| Cross-shop privacy | Similar cards sold by 100 shops | Private sales remain per-tenant unless separate explicit consent/rights and aggregation controls authorize a shared product. |
| Non-card core | Apparel variant with carton/each; unique used camera with serial | Same receiving/reservation/cost core; no card catalog dependency, player/parallel prompts or card-specific defaults. |
| Player affiliation | Player changes teams; older card depicts prior team | Same subject ID, dated affiliations and preserved card context; historical card not relabeled to current team. |
| AI identity ambiguity | Two people have the same display name; model suggests merge | Candidate with evidence/confidence only; no automatic canonical merge. Review can reject without losing either identity. |
| Full-dataset grid | Matching customer is beyond page one; apply spend and channel filters | Customer appears, totals match full authorized query, export uses identical semantics. |
| Customer net spend | Completed merchandise lines total $200 after discounts; $50 merchandise refund; $20 shipping; $10 tax | Under a net-merchandise metric, spend is $150, with shipping/tax separately reported and definition visible. |
| Customer duplicate sources | Same sale appears in live capture and marketplace import | One reconciled sale contributes once to customer spend/order count. |
| Customer identity correction | Two customer records merged, then an erroneous association corrected | Source transactions unchanged, auditable links and derived metrics corrected; no double counting. |
| Customer coverage/privacy | Partial imported history, restricted contact access, user queries lifetime spend | Coverage disclosed; authorized financial result only; no hidden contact data in grid/export/chat. |
| Retail/break dimensions | Posted $100 retail box and two provisional $30 break slots | Official spend $100; provisional break activity $60 separately. After authorized posting, official retail $100, break $60, combined $160. |
| Native then imported | Two native $30 slot sales later appear in marketplace import | Linked evidence for two sales, not four; neither capture nor import alone posts spend. After review/posting, $60 contributes once. |
| Hold vs sale | Slot assigned/held for a customer, then sold for $30 | Hold creates no spend; board sale creates one provisional activity record, no official spend; retry adds nothing. |
| Refund/resale | Posted $30 break sale has posted full refund; slot later sold and posted to another customer for $40 | First customer's net break spend $0; second $40; separate sale IDs and additive refund history. |
| Buyer resolution | Native break sale initially has unresolved channel handle | Sale retained in attribution queue; reviewed customer link does not create another sale. |
| Mixed/unclassified import | Order includes retail and break lines plus an ambiguous line | Separate known kinds, visible unclassified remainder; no channel-based guessing. |

| Posting permission/retry | Board operator lacks posting permission; authorized reviewer later posts twice | Operator cannot post; authorized review creates one linked financial transaction. Posting does not assert settlement. |
| Attendance overlap | Same customer has two tabs overlapping for ten minutes; disconnect missing | Overlap counted once; expiry bounds duration. Labeled companion presence, not video watch time. |
| Weekly attendance | Four distinct sessions in a fully observed two-week window, all in week one | Average two sessions/week including zero week; reconnects do not add sessions. Partial coverage disclosed. |
| Spend denominators | Customer attends four breaks and has two posted $30 purchases across two breaks | $15 per attended break and $30 per purchasing break, explicitly labeled; provisional purchases excluded from official averages. |
| Multi-product break | Posted $60 participation covers two products | Explicit allocations sum to $60, or show mixed/unallocated; never $60 attributed in full to both products. |

| No-connector analytics | All feeds disabled; local catalog, acquisitions and manually imported sale observations exist | Facet screening and eligible history/valuation reports work; scope and evidence shown without connector requirement. |
| Observation kind separation | Spreadsheet mixes cost, ask, estimate and completed sale rows | Typed mapping preserves kinds; market observations create neither inventory nor posted customer spend. Invalid/ambiguous rows remain reviewable. |
| Import replay/correction | Same observation file uploaded twice, then corrected | No duplicated observations; source rows and correction lineage retained; reports recompute from eligible interpretation. |
| Valuation coverage | Holdings include recent sale evidence, stale estimates and unmatched cards | Cost basis separate from estimate; dated method and valued/unvalued coverage visible; unknown never zero or invented trend. |
| Feed independence | Feed is disconnected after local records and permitted external observations exist | Local reporting remains functional; retained external evidence follows source rights and freshness rules; no overwrite of local facts. |

| Grading granularity | PSA 10, BGS special ten and unspecified-grader aggregate bucket | Distinct series; unspecified source bucket never promoted to exact PSA evidence. |
| Copy regrade | One verified physical card receives a new certificate/grade | Assessment history retained; no second owned card or duplicated acquisition. |
| Language/edition | Same set/card number appears in distinct language editions | Distinct canonical variants or releases as appropriate; no title-only merge. |
| Portfolio attribution | Collection value rises solely because another card was acquired | Acquisition contribution shown, not reported as market appreciation of prior holdings. Missing cost yields unknown return. |
| Index/population evidence | Index estimate changes without new sale; population source is stale | No fabricated sale; valuation method/version and population snapshot date visible; population not treated as print run. |

| Cross-catalog Yamal query | Subject Lamine Yamal + rookie-card designation + PSA + card grade 9 across several products | One query returns every eligible variant/grade cohort, including matches beyond page one; no per-card navigation required. Unknown rookie evidence excluded visibly; no name-derived year assumption. |
| Query grain and drill-down | Same variant has two owned copies and three historical sale observations | Catalog cohort count one, owned count two, sale count three within defined scope; joins do not multiply sales. Detail/back preserves filters, grouping and sort. |

For each implemented case, attach baseline/adversarial execution, committed state, negative controls and source/candidate identities. Numerical examples are test fixtures, not product defaults. Larger market/AI tests are not run by the current PO-comments browser suite.
