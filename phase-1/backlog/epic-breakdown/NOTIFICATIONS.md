# EPIC: NOTIFICATIONS — Notifications Module

**Sprint:** 7
**Total Tasks:** 25

In-app and email notifications driven entirely by Kafka consumers (event-driven writes rule — no sync sends from API handlers). MongoDB stores in-app notifications; SMTP via nodemailer. One granular consumer task per event→template mapping, per `phase-1/technical-design/kafka-events.md` (topic catalog) and `phase-1/requirements/user-stories/email-templates.md` (ET-01..21, plus the ET-13b variant — template subjects/bodies/recipients defined there, not duplicated here).

---

## NOTIFICATIONS-001 — Notifications Schema Migrations

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** PLATFORM-001
- **Spec References:** `phase-1/technical-design/data-model-mongodb.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- Raw-SQL/schema migration creating: `in_app_notification` (Mongo collection, per `data-model-mongodb.md`), `email_template` (Postgres table — one row per ET-* code, Handlebars subject/html/text), `pending_listing_removal_digest` (Postgres staging table — accumulates `moderation.listing.removed` events per seller until NOTIFICATIONS-017's daily digest flush)

**Done Criteria**

- All three structures exist and accept the columns/fields their consuming tasks (NOTIFICATIONS-002, 005, 016, 017) require

---

## NOTIFICATIONS-002 — InAppNotification Entity + Repository

- **US Ref:** US-P-12
- **Estimate:** M
- **Dependencies:** NOTIFICATIONS-001
- **Spec References:** `phase-1/technical-design/data-model-mongodb.md`

**Implementation Notes**

- File: `libs/notifications/src/in-app/in-app-notification.entity.ts`
- Repository interface (NFR-18 portability) behind DI token; Mongoose implementation
- Fields: `userId`, `type`, `title`, `message`, `isRead`, `link`, `metadata`, `createdAt`, `readAt`

**Done Criteria**

- Repository CRUD covered by unit tests against the interface

---

## NOTIFICATIONS-003 — Notifications Controller

- **US Ref:** US-P-12
- **Estimate:** M
- **Dependencies:** NOTIFICATIONS-002
- **Spec References:** `phase-1/technical-design/api-design/notifications.md`

**Implementation Notes**

- `GET /notifications` — `@JwtAuthGuard`; paginated unread-first list for the authenticated user
- `POST /notifications/:id/read` — marks a single notification read; ownership check (`userId` must match authenticated user, else 404)
- Exact response shape per `api-design/notifications.md`

**Done Criteria**

- `GET /notifications` returns only the authenticated user's notifications
- `POST /notifications/:id/read` sets `isRead = true`; rejects another user's notification with 404

---

## NOTIFICATIONS-004 — SMTP Adapter

- **US Ref:** US-P-12
- **Estimate:** L
- **Dependencies:** INFRA-001
- **Spec References:** `phase-1/technical-design/api-design/notifications.md`

**Implementation Notes**

- File: `libs/notifications/src/email/email.service.ts` — nodemailer, connection pool
- Async queue: send calls are non-blocking to callers (fire-and-forget from the consumer's perspective, but internally queued so bursts don't overwhelm the SMTP gateway)
- Failure-isolated: a send failure never fails the consumer's Kafka side-effect transaction — only the notification send is affected
- Retry on transient failures (connection/timeout errors) with backoff; permanent failures logged, not retried indefinitely

**Done Criteria**

- Transport failure is logged, never thrown to the calling consumer
- Transient failure triggers at least one retry before giving up

---

## NOTIFICATIONS-005 — EmailTemplate Seed

- **US Ref:** US-B-12
- **Estimate:** L
- **Dependencies:** NOTIFICATIONS-001
- **Spec References:** `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Seeds `email_template` rows for the full canonical set defined in `email-templates.md` (ET-01 through ET-21, plus the ET-13b variant) — Handlebars subject + HTML body + text body per template, content sourced from that doc rather than re-authored here

**Done Criteria**

- Every ET-* code in `email-templates.md` has a corresponding seeded row
- All templates render without Handlebars errors on sample data

---

## NOTIFICATIONS-006 — Consumer: order.finalized → ET-01

- **US Ref:** US-B-12
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Extends `BaseKafkaConsumer` (PLATFORM-007); consumer group `notifications.order-finalized`
- On `order.finalized`: sends ET-01 to the buyer using the price snapshot carried in the event payload (never re-derives amounts from live pricing — order-immutability rule)

**Done Criteria**

- `order.finalized` event → buyer receives ET-01 with the snapshotted amounts
- Duplicate delivery of the same `event_id` produces no duplicate email

---

## NOTIFICATIONS-007 — Consumer: fulfillment.shipped → ET-02

- **US Ref:** US-B-12
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.fulfillment-shipped`; sends ET-02 to the buyer with tracking number/carrier and ETA from the event payload

**Done Criteria**

- `fulfillment.shipped` event → buyer receives ET-02 with tracking info

---

## NOTIFICATIONS-008 — Consumer: fulfillment.delivered → ET-03 + ET-05

- **US Ref:** US-B-12
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.fulfillment-delivered`; sends ET-03 to the buyer for the delivered fulfillment
- Additionally sends ET-05 (order completed) when the order has ≥2 fulfillments and **all** are now delivered — requires a lookup of sibling fulfillment statuses for the same order before deciding whether to fire ET-05

**Done Criteria**

- Single-fulfillment order delivered → ET-03 only
- Multi-fulfillment order, last fulfillment delivered → ET-03 and ET-05 both fire; earlier fulfillments' delivery does not fire ET-05 prematurely

---

## NOTIFICATIONS-009 — Consumer: fulfillment.refunded → ET-04

- **US Ref:** US-B-12
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.fulfillment-refunded`; sends ET-04 to the buyer confirming the refund

**Done Criteria**

- `fulfillment.refunded` event → buyer receives ET-04

---

## NOTIFICATIONS-010 — Consumer: fulfillment.cancelled → ET-16

- **US Ref:** US-S-11
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.fulfillment-cancelled`; sends ET-16 to the buyer with the cancellation reason from the event payload

**Done Criteria**

- `fulfillment.cancelled` event → buyer receives ET-16 with the correct reason text

---

## NOTIFICATIONS-011 — Consumer: fulfillment.placed → ET-17

- **US Ref:** US-S-05
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.fulfillment-placed-seller-alert`; sends ET-17 to the seller ("new order received")

**Done Criteria**

- `fulfillment.placed` event → seller receives ET-17

---

## NOTIFICATIONS-012 — Consumer: seller.kyc.decided (APPROVED) → ET-06

- **US Ref:** US-A-02
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.kyc-decided-approved`; filters `decision = APPROVED`; sends ET-06 to the seller, CC admin per `email-templates.md`

**Done Criteria**

- `seller.kyc.decided` with `decision=APPROVED` → seller (and admin CC) receive ET-06
- `decision=REJECTED` events are ignored by this consumer (handled by NOTIFICATIONS-013)

---

## NOTIFICATIONS-013 — Consumer: seller.kyc.decided (REJECTED) → ET-07

- **US Ref:** US-A-02
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.kyc-decided-rejected`; filters `decision = REJECTED`; sends ET-07 to the seller (with rejection reason), CC admin per `email-templates.md`

**Done Criteria**

- `seller.kyc.decided` with `decision=REJECTED` → seller receives ET-07 with the reason; admin CC'd

---

## NOTIFICATIONS-014 — Consumer: seller.kyc.submitted → ET-14 + ET-21

- **US Ref:** US-S-01
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.kyc-submitted`; sends ET-14 (seller confirmation) to the seller and ET-21 (new-application admin alert) to admins — same source event, two recipients/templates

**Done Criteria**

- `seller.kyc.submitted` event → seller receives ET-14 and admins receive ET-21 from the same event delivery

---

## NOTIFICATIONS-015 — Consumer: listing.flagged → ET-08

- **US Ref:** US-S-10
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.listing-flagged`; sends ET-08 to the seller, CC admin per `email-templates.md`

**Done Criteria**

- `listing.flagged` event → seller (and admin CC) receive ET-08

---

## NOTIFICATIONS-016 — Consumer: moderation.listing.removed → Digest Staging

- **US Ref:** US-A-04
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`

**Implementation Notes**

- Consumer group `notifications.moderation-listing-removed`; does **not** send an email directly — inserts a row into `pending_listing_removal_digest` (NOTIFICATIONS-001) keyed by seller, for NOTIFICATIONS-017's daily aggregation into ET-09

**Done Criteria**

- `moderation.listing.removed` event → one row appended to the digest staging table for the affected seller
- No direct email is sent by this consumer

---

## NOTIFICATIONS-017 — Daily Digest Scheduler → ET-09

- **US Ref:** US-S-10
- **Estimate:** M
- **Dependencies:** NOTIFICATIONS-001
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Cron: 23:00 UTC daily
- Aggregates `pending_listing_removal_digest` rows per seller into a single ET-09 email (seller, CC admin, per `email-templates.md`), then deletes the aggregated rows

**Done Criteria**

- Sellers with ≥1 removal that day receive exactly one ET-09 email summarizing all of that day's removals
- Digest rows are deleted after a successful send; a failed send leaves rows intact for the next run

---

## NOTIFICATIONS-018 — Consumer: seller.suspended → ET-10 + In-App

- **US Ref:** US-A-05
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.seller-suspended`; sends ET-10 to the seller (CC admin) and writes an in-app notification via NOTIFICATIONS-002's repository

**Done Criteria**

- `seller.suspended` event → seller receives ET-10 and an in-app notification

---

## NOTIFICATIONS-019 — Consumer: seller.suspension_expired → ET-11 + In-App

- **US Ref:** US-P-18
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.suspension-expired`; sends ET-11 to the seller (CC admin) and writes an in-app notification

**Done Criteria**

- `seller.suspension_expired` event → seller receives ET-11 and an in-app notification

---

## NOTIFICATIONS-020 — Consumer: seller.reinstated → ET-12

- **US Ref:** US-A-05b
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.seller-reinstated`; sends ET-12 to the seller (CC admin)

**Done Criteria**

- `seller.reinstated` event → seller receives ET-12

---

## NOTIFICATIONS-021 — Consumer: fulfillment.refund_suspended_seller → ET-13 + ET-13b

- **US Ref:** US-P-16
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.refund-suspended-seller`; sends ET-13 to the buyer and ET-13b to the seller (CC admin) from the same event delivery — two distinct templates, same source event

**Done Criteria**

- `fulfillment.refund_suspended_seller` event → buyer receives ET-13 and seller receives ET-13b from the same delivery

---

## NOTIFICATIONS-022 — Consumer: inventory.low_stock → ET-15 + In-App

- **US Ref:** US-S-08
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.inventory-low-stock`; sends ET-15 to the seller and writes an in-app notification

**Done Criteria**

- `inventory.low_stock` event → seller receives ET-15 and an in-app notification

---

## NOTIFICATIONS-023 — Consumer: auth.email_verification_requested → ET-18

- **US Ref:** US-B-01
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.auth-email-verification`; sends ET-18 with the verification link built from the token in the event payload
- No in-app notification (user may not be authenticated yet)

**Done Criteria**

- `auth.email_verification_requested` event → user receives ET-18 with a working verification link

---

## NOTIFICATIONS-024 — Consumer: auth.password_reset_requested → ET-19

- **US Ref:** US-B-13
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.auth-password-reset`; sends ET-19 with the reset link built from the token in the event payload

**Done Criteria**

- `auth.password_reset_requested` event → user receives ET-19 with a working reset link

---

## NOTIFICATIONS-025 — Consumer: auth.password_changed → ET-20

- **US Ref:** US-B-13
- **Estimate:** M
- **Dependencies:** PLATFORM-007
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/requirements/user-stories/email-templates.md`

**Implementation Notes**

- Consumer group `notifications.auth-password-changed`; sends ET-20 as a security notification (no in-app; no action link)

**Done Criteria**

- `auth.password_changed` event → user receives ET-20
