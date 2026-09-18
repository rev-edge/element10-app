# Track A purchasing authority decision proposal

Status: owner decision required before purchasing mutators or actual-cost reads are exposed.

This proposal separates five permissions that must not be inferred from one another.

| Authority | Existing approved behavior | Decision still required | Fail-closed state |
|---|---|---|---|
| Create or amend a purchase order | The prototype crosswalk carries interim `act.inventory_edit`, but explicitly says prototype flags are not persisted authority. | Approve a dedicated capability such as `purchase_order.create`, including default role grants. | No authenticated PO writer. |
| Approve a purchase order | Maker-checker requires managers to propose and admins to clear. Existing `act.approve_preparation` is about preparation, not purchasing. | Approve a dedicated capability such as `purchase_order.approve`, normally admin-only. | No authenticated PO approval writer. |
| Receive stock | `act.create_receiving` is seeded for admin and manager. Location eligibility is separately enforced by `e10.can_receive_at`. | Confirm that `act.create_receiving` remains the receipt-posting capability and define over-receipt authority separately. | No new receipt writer until over-receipt and landed-cost decisions are settled. |
| Read actual invoice, receipt cost, credits, and allocations | `act.view_financial_estimates` permits estimates. It is not approval for actual commercial-document disclosure. | Approve a distinct actual-cost or financial-document read capability and its role defaults, or explicitly broaden the existing capability. | Actual-cost relations are server-only. PO estimate lines retain their existing capability gate. |
| Use a receiving location | `e10.can_receive_at(org, location)` requires an active location and either org-admin status or an explicit role-location `can_receive` grant. | Decide only whether org admins should retain the implicit all-location override. | Inactive, missing, and foreign-org locations are denied. |

Recommended configurable vocabulary:

- `purchase_order.create` and `purchase_order.amend`: independent organization-scoped grants.
- `purchase_order.approve`: independent from create/amend so separation of duty can be configured.
- `act.create_receiving`: retain as the existing receipt capability unless renamed by the later namespace reconciliation.
- `financial.actual_cost.read`: independent from estimate access.
- Location grants remain action-specific and independent from the organization capabilities. Receiving at a location does not imply PO creation, approval, or financial visibility.
- Custom roles use the existing tenant role-permission engine. Suggested admin, manager, streamer, and ops mappings are templates, not hardcoded business rules.
- Approval thresholds and maker-checker requirements belong to organization policy and may narrow capability grants. They must not be bypassed merely because a user has create/amend authority.

Safe defaults preserve all existing grants and add no new grant automatically. The owner decision is the capability vocabulary and policy shape, not a blanket assignment to role names. Organizations can then configure supported combinations without weakening tenant isolation or fail-closed behavior.

Additional decisions remain separate: over-receipt authority, landed-cost allocation method, payment/accounting recognition, and vendor-output publication. None is implied by this proposal.
