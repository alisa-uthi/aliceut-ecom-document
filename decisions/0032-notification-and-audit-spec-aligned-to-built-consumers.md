# ADR-0032: Notification and audit spec aligned to the built consumers

**Status:** Accepted  
**Date:** 2026-10-22  
**Affects:** `phase-1/technical-design/data-model-erd.md`, `consumer-field-matrix.md`, `data-model-mongodb.md`, `kafka-events.md`, `cleanup-jobs.md`; `conventions/kafka-events.md`; `phase-1/requirements/user-stories/email-templates.md`; `phase-1/ui-design/seller-portal.md`; `phase-1/diagrams/02-seller-lifecycle.md`, `04-admin-moderation.md`; `phase-1/requirements/BRD.md` (section 12 #14 note); `phase-1/tasks.csv` (DB-10)  
**Implemented by:** none needed; consumers were built to this behaviour (backend#64-#66). Two code gaps are recorded below.  

## Context

Entry 5 of `spec-compliance.md` listed design documents out of step with the consumers built in wave 6. The owner authorized applying defaults (closest to built, least disruptive).

## Decision

1. `notifications.pending_listing_removal_digest` carries `seller_email` and `seller_name` (migration 0018), written by the consumer from the event.
2. **Email templates are code.** `notifications.email_template` is removed from the V1 design (ERD section, index, cleanup-jobs reference, DB-10 seed row). Migration 0011 created the table; it is unused and may be dropped by a later migration.
3. **ET-21 omits the review-by line in V1.** `seller.kyc.submitted` carries no `review_due_at` and a consumer may not read `seller.kyc_application`. The deadline remains the source for the admin SLA badge. The matrix, template variable table, diagrams and BRD note say so.
4. **ET-13 / ET-13b show the order UUID** (`order_id`), since `fulfillment.refund_suspended_seller` carries no `display_id`.
5. **SMTP retry is 4 attempts in all** (first send plus 3 retries; 100 ms, 500 ms, 2 s). `conventions/kafka-events.md` and `kafka-events.md` section 4 say so exactly.
6. **Seller in-app `ORDER_PLACED` and `KYC_SUBMITTED` are removed** from the seller-portal notification table, per the matrix (the seller is told by ET-17 and ET-14 e-mails; in-app `KYC_SUBMITTED` goes to admins).
7. **Portal links** keep the `/seller/...` and `/admin/...` prefixes of navigation-routing.md; the apps serve routes at root and must redirect. The seller app redirects `verify-email` and `reset-password` (frontend#31). Documented as an open code gap for the other seller links and all admin links.
8. `inventory.changed` `UNKNOWN` is audited with a SYSTEM actor (`actor_id` null), as data-model-mongodb.md says.
9. `audit_logs.actor_id` is the literal matrix field, which for `seller.kyc.submitted` and seller stock edits is `payload.seller_id` (a seller_profile id); the user id is `seller_user_id`.
10. KYC payloads do not carry `tax_id`; those claims are removed. Masking of `tax_id` stays as defence in depth.
11. A `listing.flagged` whose `source` is not `ADMIN_MANUAL` is audited as SYSTEM, now stated in the matrix.
12. **`inventory.low_stock` fires on every stock write that crosses the threshold,** including a checkout reservation (the ERD's edge-triggered rule). The spec stays; the code is the defect.

## Consequences

Items 1-11 change text only. Item 12 leaves a code defect: checkout reservation does not emit `inventory.low_stock` (reservation path in `InventoryApplicationService`). Item 7 leaves a code gap: admin links and non-auth seller links in e-mails miss until the routes are redirected (`aliceut-ecom-frontend/apps/admin-app/src/app/app.routes.ts`, `apps/seller-app/src/app/app.routes.ts`) or the template links drop the prefix. Item 2: e-mail wording changes need a deployment.

## Alternatives considered

Seed `email_template` and render from rows (rejected: duplicates built code, adds runtime failure modes). Add `review_due_at` to the event (rejected: schema version bump for one line). Add `display_id` to `fulfillment.refund_suspended_seller` (rejected: an event change for a rare notice). Change the code for items 8-9 (rejected: the data model already documents the built behaviour).
