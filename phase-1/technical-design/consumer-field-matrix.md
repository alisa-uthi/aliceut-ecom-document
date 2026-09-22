# Consumer Field Matrix — Phase 1

**Status:** Complete  
**Source of truth:** [BRD v1.2](../requirements/BRD.md), [kafka-events.md](kafka-events.md)

Every consumer group in Phase 1, every field it must write, and the event field that supplies it. Event schemas and per-group side effects: [kafka-events.md](kafka-events.md). Envelope, idempotency template and DLQ rules: [conventions/kafka-events.md](../../conventions/kafka-events.md). Consumer group ownership: [backend-module-architecture.md](backend-module-architecture.md#module-summary-table).

This document exists because the gap it closes was invisible without it. Three consumer families — search indexer, notification dispatcher, audit writer — were each specified against a target shape (an Elasticsearch mapping, an email template, a MongoDB collection) in a different document from the event payload that has to fill it, and no artifact compared the two. Forty-two of the 205 bindings below had no supplying field, and one required an event that did not exist.

---

## Summary

- [1. The rule this matrix enforces](#the-rule)
- [2. Consumer inventory](#consumer-inventory)
- [3. `search.*` — Elasticsearch `products`](#search-family)
- [4. `notification.*` — email and in-app](#notification-family)
- [5. `platform.audit` — MongoDB](#audit-family)
- [6. `inventory.*` and `orders.*` — Postgres](#postgres-families)
- [7. Gap ledger](#gap-ledger)
- [8. Maintenance rule](#maintenance-rule)

<a id="the-rule"></a>
## 1. The rule this matrix enforces

**A consumer's inputs are its event payload and the document or row it is updating. Nothing else.** A consumer never reads another module's Postgres tables and never makes an enrichment call to fill a gap ([kafka-events.md § Search projection](kafka-events.md), [backend-module-architecture.md § Outbox relay and consumer wiring](backend-module-architecture.md#outbox-and-consumers), [api-design/search.md § Document composition](api-design/search.md#document-composition)). Where a consumer needs a field its event does not carry, the fix is **to fatten the event**, never to add a read.

**Fattening is a producer-side concern and is not itself a cross-module read.** A producer composes its payload from the tables it owns plus values obtained through another module's exported `ApplicationService` — a module API call inside the producing transaction, not SQL against a foreign schema ([conventions/backend-module-architecture.md § 7](../../conventions/backend-module-architecture.md#7-module-dependency-rules)). `offer.changed` carrying `prices[]` from `pricing.offer_price` is the existing precedent: Catalog owns the event, Pricing owns the rows, and `PricingApplicationService` is the seam between them.

**One bounded exception, stated here so it is not generalised.** Two notification consumers fan out to *every admin* — `notification.kyc-submitted` (in-app `KYC_SUBMITTED`) and `notification.listing-flagged` (in-app `LISTING_FLAGGED`). The admin roster is not event data: it is a platform role membership that changes independently of the event and cannot be snapshotted into a payload without going stale. Those two consumers obtain it from `IdentityApplicationService.listAdminUserIds()` — a module API call, never `SELECT … FROM identity.user`. The admin **email** address for the `CC` on those templates is configuration (`ADMIN_NOTIFICATION_EMAIL`), not a lookup. No other consumer takes a non-payload input.

**Derived values are not gaps.** A field a consumer computes from payload fields it already holds is supplied: `line_total = unit_price × quantity`, `available = on_hand_qty − reserved_qty`, the Elasticsearch `in_stock` and `lowest_offer_*` rollups recomputed from `offers[]` after a merge. The matrix records the inputs, not the arithmetic.

---

<a id="consumer-inventory"></a>
## 2. Consumer inventory

**Thirty-nine consumer groups**, matching [backend-module-architecture.md § Module summary table](backend-module-architecture.md#module-summary-table) and the DLQ list in [kafka-events.md § 4](kafka-events.md#dlq-topics).

| Family | Groups | Writes | Target shape defined in |
|---|---|---|---|
| `search.*` | 12 | Elasticsearch `products` index | [api-design/search.md § Index Mapping](api-design/search.md#index-mapping) |
| `notification.*` | 21 | SMTP email + `notifications.in_app_notification` | [email-templates.md](../requirements/user-stories/email-templates.md), [api-design/notifications.md](api-design/notifications.md) |
| `platform.audit` | 1 | MongoDB `audit_logs` / `activity_events` / `pii_access_logs` | [data-model-mongodb.md](data-model-mongodb.md) |
| `inventory.*` | 4 | `inventory.stock`, `inventory.stock_reservation` | [data-model-erd.md](data-model-erd.md) |
| `orders.*` | 1 | `orders` completion check (no direct SQL — calls `OrdersApplicationService`) | [kafka-events.md § 2.9](kafka-events.md#29-ordercompleted) |

---

<a id="search-family"></a>
## 3. `search.*` — Elasticsearch `products`

Field ownership is per event ([api-design/search.md § Document composition](api-design/search.md#document-composition)): each event writes only the fields its own domain owns, as a partial update. **Every write is addressed by `product_id`** — `_update/:productId` for the by-id writes, or an `_update_by_query` match where the consumer holds no product id — so `product_id` is a required *routing* input wherever the write is by id, not merely a document field.

| Consumer group | Event | ES field it writes | Supplied by |
|---|---|---|---|
| `search.product-changed` | `product.changed` | `product_id` | `payload.product_id` |
| | | `title` | `payload.title` |
| | | `brand` | `payload.brand` |
| | | `description` | `payload.description` |
| | | `category_id` | `payload.category_id` |
| | | `category_path` | `payload.category_path` |
| | | `status` | `payload.status` |
| | | `created_at` | `payload.created_at` |
| | | `images[]` | `payload.images[]` |
| | | `variants[]` | `payload.variants[]` |
| | | document delete | `payload.change_type = REMOVED` |
| `search.offer-changed` | `offer.changed` | routing `_id` | `payload.product_id` |
| | | `offers[].offer_id` | `payload.offer_id` |
| | | `offers[].seller_profile_id` | `payload.seller_id` |
| | | `offers[].seller_name` | `payload.seller_name` |
| | | `offers[].seller_active` | `payload.seller_active` |
| | | `offers[].status` | `payload.status` |
| | | `offers[].native_currency_code` | `payload.currency_code` |
| | | `offers[].amount` | `payload.prices[].amount` (effective row) |
| | | `offers[].price_type` | `payload.prices[].price_type` |
| | | `offers[].display_prices` | `payload.display_prices` |
| | | entry removal | `payload.status != ACTIVE` |
| `search.inventory-changed` | `inventory.changed` | routing `_id` | `payload.product_id` |
| | | `offers[].available_qty` | `payload.available_qty` (absolute) |
| | | write suppressed | `payload.change_reason = SHIPMENT` |
| `search.reservation-expired` | `inventory.reservation_expired` | routing `_id` | `payload.product_id` |
| | | `offers[].available_qty` | `payload.available_qty` (absolute) |
| `search.seller-suspended` | `seller.suspended` | `offers[].seller_active = false` | `payload.offer_ids[]` (query match) |
| `search.seller-reinstated` | `seller.reinstated` | `offers[].seller_active = true` | `payload.offer_ids[]` (query match) |
| `search.suspension-expired` | `seller.suspension_expired` | `offers[].seller_active = true` | `payload.offer_ids[]` (query match) |
| `search.seller-profile-changed` | `seller.profile_changed` | `offers[].seller_name` | `payload.seller_name` (matched on `payload.seller_id`) |
| `search.listing-flagged` | `listing.flagged` | entry removal | `payload.product_id` + `payload.offer_id` |
| `search.listing-removed` | `moderation.listing.removed` | entry removal | `payload.product_id` + `payload.offer_id` |
| `search.listing-soft-deleted` | `listing.soft_deleted` | entry removal | `payload.product_id` + `payload.offer_id` |
| `search.fx-rate-updated` | `fx_rate.updated` | `display_prices[<quote>]` | `payload.base_currency` + `payload.rates[]` |

**`in_stock`, `lowest_offer_id`, `lowest_offer_price_type`, `lowest_offer_currency_code`, `lowest_offer_amount` and the product-level `display_prices` are owned by no event.** Whichever consumer changed one of their inputs recomputes them in the same update, from the document's own `offers[]` array after the merge — so the result does not depend on which consumer ran last. They are not rows in this table for that reason.

**`offers[].min_qty` is not in this table and not in the mapping.** It existed to carry `B2B_TIER` quantity breaks, and `B2B_TIER` is not a V1 price type (Wave 0 decision D-02).

---

<a id="notification-family"></a>
## 4. `notification.*` — email and in-app

Two writes per consumer at most: an SMTP send whose template variables are listed in [email-templates.md](../requirements/user-stories/email-templates.md), and an `in_app_notification` row keyed on `(recipient_user_id, source_event_id)`.

**Every email needs a recipient address and every in-app row needs a `recipient_user_id`, and neither is derivable from a domain id.** `seller_id` is a `seller_profile_id`, not an `identity.user` id, so a payload carrying only `seller_id` cannot address an in-app row; `buyer_id` *is* a user id and addresses the row, but does not supply the email address or the name the template greets. The columns below are therefore listed for every consumer, not just the interesting ones.

| Consumer group | Event | Template | Recipient address | In-app `recipient_user_id` |
|---|---|---|---|---|
| `notification.kyc-submitted` | `seller.kyc.submitted` | ET-14 seller, ET-21 admin | `payload.seller_email`; admin from `ADMIN_NOTIFICATION_EMAIL` | one row per admin — `IdentityApplicationService.listAdminUserIds()` (§1 exception) |
| `notification.kyc-decided` | `seller.kyc.decided` | ET-06 / ET-07 | `payload.seller_email` | `payload.seller_user_id` |
| `notification.seller-suspended` | `seller.suspended` | ET-10 | `payload.seller_email` | `payload.seller_user_id` |
| `notification.seller-reinstated` | `seller.reinstated` | ET-12 | `payload.seller_email` | `payload.seller_user_id` |
| `notification.suspension-expired` | `seller.suspension_expired` | ET-11 | `payload.seller_email` | `payload.seller_user_id` |
| `notification.fulfillment-placed` | `fulfillment.placed` | — (in-app only) | — | `payload.buyer_id` |
| `notification.fulfillment-seller-alert` | `fulfillment.placed` | ET-17 | `payload.seller_email` | — |
| `notification.fulfillment-shipped` | `fulfillment.shipped` | ET-02 | `payload.buyer_email` | `payload.buyer_id` |
| `notification.fulfillment-delivered` | `fulfillment.delivered` | ET-03 | `payload.buyer_email` | `payload.buyer_id` |
| `notification.fulfillment-refunded` | `fulfillment.refunded` | ET-04 | `payload.buyer_email` | `payload.buyer_id` |
| `notification.fulfillment-cancelled` | `fulfillment.cancelled` | ET-16 | `payload.buyer_email` | `payload.buyer_id` |
| `notification.refund-suspended-seller-buyer` | `fulfillment.refund_suspended_seller` | ET-13 | `payload.buyer_email` | `payload.buyer_id` |
| `notification.refund-suspended-seller-seller` | `fulfillment.refund_suspended_seller` | ET-13b | `payload.seller_email` | — |
| `notification.order-summary` | `order.finalized` | ET-01 | `payload.buyer_email` | — |
| `notification.order-completed` | `order.completed` | ET-05 | `payload.buyer_email` | `payload.buyer_id` |
| `notification.low-stock` | `inventory.low_stock` | ET-15 | `payload.seller_email` | `payload.seller_user_id` |
| `notification.listing-flagged` | `listing.flagged` | ET-08 | `payload.seller_email`; admin CC from `ADMIN_NOTIFICATION_EMAIL` | `payload.seller_user_id`, plus one row per admin (§1 exception) |
| `notification.listing-removed` | `moderation.listing.removed` | ET-09 (daily digest) | `payload.seller_email`, copied onto the `pending_listing_removal_digest` row | `payload.seller_user_id` |
| `notification.email-verification` | `auth.email_verification_requested` | ET-18 | `payload.email` | — |
| `notification.password-reset` | `auth.password_reset_requested` | ET-19 | `payload.email`; link path from `payload.portal`, `mode` hint from `payload.has_local_password` | — |
| `notification.password-changed` | `auth.password_changed` | ET-20 | `payload.email` | — |

**The digest consumer is the one place a payload field outlives its event.** `notification.listing-removed` writes no email; it writes a `pending_listing_removal_digest` row for the 23:00 scheduler ([backend-module-architecture.md § Scheduled tasks](backend-module-architecture.md#scheduled-tasks)). The row therefore has to carry `seller_email` and `seller_name` forward — the scheduler runs hours later, holds no event, and may not read `seller.seller_profile`.

### 4.1 Template body variables

Recipient identity above; this is the rest of each template. A variable rendered from configuration (`base_url`, `ttl_hours`, `ttl_minutes`, `admin.email`) or computed at send time (`review_by = submitted_at + 72h`, `line_total = unit_price × quantity`) is not listed — it needs no payload field.

| Template | Variable | Supplied by |
|---|---|---|
| ET-01 | `buyer.full_name` | `payload.buyer_name` |
| | `buyer.preferred_currency` | `payload.buyer_display_currency` |
| | `buyer.business_name`, `buyer.business_logo_url` | `payload.buyer_business_name`, `payload.buyer_business_logo_url` |
| | `order_id`, `placed_at` | `payload.display_id`, `payload.placed_at` |
| | `seller_name` | `payload.placed_fulfillments[].seller_name` |
| | `fulfillment.offer_currency` | `payload.placed_fulfillments[].currency_code` |
| | `item.*` | `payload.placed_fulfillments[].items[]` |
| | `fulfillment.subtotal_display` | `payload.placed_fulfillments[].buyer_currency_subtotal` |
| | `fulfillment.shipping_display` | `payload.placed_fulfillments[].buyer_currency_shipping_cost` |
| | `fulfillment.tax_display` | `payload.placed_fulfillments[].buyer_currency_tax_total` |
| | `fulfillment.grand_total_display` | `payload.placed_fulfillments[].buyer_currency_total` |
| | `tracking_number`, `eta` | `payload.placed_fulfillments[].tracking_number`, `.estimated_delivery_at` |
| | `session.grand_total_display` | `payload.buyer_currency_grand_total` |
| | `skipped_items[].product_title` | `payload.skipped_items[].product_title` |
| | `failed_groups[].items[].product_title`, `reason` | `payload.failed_groups[]` |
| ET-02 | `seller_name`, `tracking_number`, `eta`, `item.*` | `payload.seller_name`, `.tracking_number`, `.estimated_delivery_at`, `.items[]` |
| ET-03 | `seller_name`, `item.*` | `payload.seller_name`, `.items[]` |
| ET-04 | `seller_name`, `refunded_at`, `item.*`, totals | `payload.seller_name`, `.refunded_at`, `.items[]`, `.buyer_currency_total`, `.currency_code`, `.buyer_display_currency` |
| ET-05 | `order_id`, `placed_at` | `payload.display_id`, `payload.placed_at` |
| ET-06 / ET-07 | `seller.full_name`, `seller.business_name`, `rejection_reason` | `payload.seller_name`, `.business_name`, `.reason` |
| ET-08 | `seller.full_name`, `product_title`, `flagged_at`, `flag_reason` | `payload.seller_name`, `.product_title`, `.flagged_at`, `.flag_reason` |
| ET-09 | `seller.full_name`, `listings[].product_title`, `.removed_at`, `.removal_category`, `.removal_reason` | `payload.seller_name`, `.product_title`, `.removed_at`, `.removal_category`, `.removal_reason_text` (per event, aggregated on the digest row) |
| ET-10 | `seller.full_name`, `seller.business_name`, `suspended_at`, `is_permanent`, `duration_label`, `suspended_until`, `suspension_reason` | `payload.seller_name`, `.business_name`, `.suspended_at`, `.is_permanent`, `.duration_label`, `.suspended_until`, `.reason` |
| ET-11 | `seller.full_name`, `seller.business_name`, `reinstated_at` | `payload.seller_name`, `.business_name`, `.expired_at` |
| ET-12 | `seller.full_name`, `seller.business_name`, `reinstated_at`, `reinstatement_reason` | `payload.seller_name`, `.business_name`, `.reinstated_at`, `.reason` |
| ET-13 | `seller_name`, `item.*`, totals | `payload.seller_name`, `.items[]`, `.buyer_currency_total`, `.buyer_display_currency` |
| ET-13b | `seller.full_name`, `order_id`, `item.*`, `fulfillment.grand_total_display`, `offer_currency` | `payload.seller_name`, `.order_id`, `.items[]`, `.refund_amount`, `.currency_code` |
| ET-14 | `seller.full_name`, `seller.business_name`, `submitted_at`, `is_resubmission`, `prior_application_id`, `prior_rejection_date` | `payload.seller_name`, `.business_name`, `.submitted_at`, `.is_resubmission`, `.prior_application_id`, `.prior_rejection_date` |
| ET-15 | `product_title`, `sku_label`, `sku_id`, `on_hand`, `reserved`, `available`, `low_stock_threshold`, `seller.full_name` | `payload.product_title`, `.sku_label`, `.sku_id`, `.on_hand_qty`, `.reserved_qty`, `.available_qty`, `.low_stock_threshold`, `.seller_name` |
| ET-16 | `seller_name`, `cancelled_at`, `cancellation_reason`, `item.*`, totals | `payload.seller_name`, `.cancelled_at`, `.reason`, `.items[]`, `.buyer_currency_total` |
| ET-17 | `seller.full_name`, `order_id`, `placed_at`, `ship_by`, `item.*`, `fulfillment.grand_total_display`, `offer_currency` | `payload.seller_name`, `.display_id`, `.placed_at`, `.ship_by`, `.items[]`, `.total_amount`, `.currency_code` |
| ET-18 | `buyer.full_name`, `verification_link` | `payload.full_name`, `payload.verification_token` |
| ET-19 | `buyer.full_name`, `reset_link` | `payload.full_name`, `payload.reset_token` |
| ET-20 | `buyer.full_name`, `changed_at`, `change_method` | `payload.full_name`, `.changed_at`, `.changed_method` |
| ET-21 | `seller.business_name`, `seller.full_name`, `submitted_at`, `application_id`, `is_resubmission`, `prior_rejection_date` | `payload.business_name`, `.seller_name`, `.submitted_at`, `.kyc_application_id`, `.is_resubmission`, `.prior_rejection_date` |

**ET-01's per-seller totals are carried in the buyer's display currency, not recomputed.** A consumer multiplying a native total by a live rate would contradict FR-P-03; the four figures are snapshots taken at capture and travel as `buyer_currency_*` fields on `placed_fulfillments[]`.

**ET-13b and ET-17 state their totals in the seller's own currency** (`refund_amount` / `total_amount` with `currency_code`), which is why neither needs a `buyer_currency_*` field. The two seller-facing money templates are the only ones that do not render a buyer-currency figure.

---

<a id="audit-family"></a>
## 5. `platform.audit` — MongoDB

One group, three collections, routed on `event_type` — plus the single documented payload branch on `inventory.changed.change_reason` ([data-model-mongodb.md § Consumer routing](data-model-mongodb.md#consumer-routing)).

The envelope supplies six of every document's fields on every topic — `event_id`, `event_type`, `event_version`, `occurred_at`, `correlation_id` and the masked `payload` — so they are stated once here rather than repeated per row. What varies per event is the projection: `actor_id`, `actor_role`, `entity_type`, `entity_id`, `action` and `decision_reason`.

| Event | Collection | `entity_id` | `actor_id` | `decision_reason` |
|---|---|---|---|---|
| `seller.kyc.submitted` | `audit_logs` | `payload.seller_id` | `payload.seller_id` | — |
| `seller.kyc.decided` | `audit_logs` | `payload.seller_id` | `payload.reviewer_user_id` | `payload.reason` |
| `seller.suspended` | `audit_logs` | `payload.seller_id` | `payload.admin_user_id` | `payload.reason` |
| `seller.suspension_amended` | `audit_logs` | `payload.seller_id` | `payload.admin_user_id` | `payload.reason` |
| `seller.reinstated` | `audit_logs` | `payload.seller_id` | `payload.admin_id` | `payload.reason` |
| `seller.suspension_expired` | `audit_logs` | `payload.seller_id` | `null` (SYSTEM) | — |
| `listing.flagged` | `audit_logs` | `payload.offer_id` | `payload.admin_user_id` (null when not `ADMIN_MANUAL`) | `payload.flag_reason` |
| `moderation.listing.removed` | `audit_logs` | `payload.offer_id` | `payload.admin_user_id` | `payload.removal_reason_text` |
| `keyword_blocklist.changed` | `audit_logs` | `payload.blocklist_entry_id` | `payload.actor_user_id` | — |
| `auth.email_verification_requested` | `audit_logs` | `payload.user_id` | `payload.user_id` | — |
| `auth.password_reset_requested` | `audit_logs` | `payload.user_id` | `payload.user_id` | — |
| `auth.password_changed` | `audit_logs` | `payload.user_id` | `payload.user_id` | — |
| `inventory.changed` (`MANUAL_UPDATE`, `BULK_UPDATE`, `UNKNOWN`) | `audit_logs` | `payload.offer_id` | `payload.seller_id` | `payload.adjustment_reason` |
| `inventory.changed` (`RESERVATION`, `SHIPMENT`, `REFUND_RESTORE`, `CANCEL_RESTORE`) | `activity_events` | `payload.offer_id` | `null` (SYSTEM) | n/a |
| `inventory.low_stock` | `activity_events` | `payload.offer_id` | `null` (SYSTEM) | n/a |
| `inventory.reservation_expired` | `activity_events` | `payload.reservation_id` | `null` (SYSTEM) | n/a |
| `fulfillment.placed` | `activity_events` | `payload.fulfillment_id` | `payload.buyer_id` | n/a |
| `fulfillment.shipped` | `activity_events` | `payload.fulfillment_id` | `payload.seller_id` | n/a |
| `fulfillment.delivered` | `activity_events` | `payload.fulfillment_id` | `null` (SYSTEM) | n/a |
| `fulfillment.refunded` | `activity_events` | `payload.fulfillment_id` | `null` (SYSTEM) | n/a |
| `fulfillment.cancelled` | `activity_events` | `payload.fulfillment_id` | `payload.seller_id` | n/a |
| `fulfillment.refund_suspended_seller` | `activity_events` | `payload.fulfillment_id` | `null` (SYSTEM) | n/a |
| `order.finalized` | `activity_events` | `payload.order_id` | `payload.buyer_id` | n/a |
| `order.completed` | `activity_events` | `payload.order_id` | `null` (SYSTEM) | n/a |
| `product.changed` | `activity_events` | `payload.product_id` | `null` (SYSTEM) | n/a |
| `offer.changed` | `activity_events` | `payload.offer_id` | `payload.seller_id` | n/a |
| `listing.soft_deleted` | `activity_events` | `payload.offer_id` | `payload.seller_id` | n/a |
| `pii.accessed` | `pii_access_logs` | `payload.resource_id` | `payload.accessor_user_id` | n/a |
| `fx_rate.updated`, `seller.profile_changed` | not persisted | — | — | — |

Every projection above is supplied. The audit family was never the family that could not be built — it is in the matrix because a projection nobody had written down is one nobody can check, and because it is the family that turns an event-payload omission into a permanent hole: there is no second write path to fall back on (FR-P-11).

**`actor_id` on `offer.changed` names the owning seller, not the actor.** The payload carries no actor field, so a moderation transition performed by an admin is audited from `listing.flagged` or `moderation.listing.removed`, which carry theirs ([kafka-events.md § 2.11](kafka-events.md#211-offerchanged)).

---

<a id="postgres-families"></a>
## 6. `inventory.*` and `orders.*` — Postgres

These four groups write their own module's tables, so the matrix question is narrower: does the payload carry the scope and the quantity each write needs?

| Consumer group | Event | Write | Scope and quantity from |
|---|---|---|---|
| `inventory.fulfillment-placed` | `fulfillment.placed` | `inventory.changed` outbox row (`RESERVATION`) | `payload.items[].offer_id`, `.quantity` |
| `inventory.fulfillment-shipped` | `fulfillment.shipped` | reservations → `CONSUMED`; `on_hand_qty` and `reserved_qty` decrement | `payload.fulfillment_id`, `payload.items[].offer_id`, `.quantity` |
| `inventory.fulfillment-cancelled` | `fulfillment.cancelled` | reservations → `RELEASED`; `reserved_qty` decrement | `payload.fulfillment_id`, `payload.items[].offer_id`, `.quantity` |
| `inventory.fulfillment-refunded` | `fulfillment.refunded`, `fulfillment.refund_suspended_seller` | same as cancel, **only when** `prior_status = PENDING` | `payload.fulfillment_id`, `payload.prior_status`, `payload.items[]` |
| `orders.delivery-tracker` | `fulfillment.delivered` | `OrdersApplicationService` completion check; `order.completed` outbox row | `payload.order_id` |

Every reservation write is scoped `WHERE fulfillment_id = :fulfillment_id` and never `WHERE order_id = ?`, so one seller's fulfillment in a multi-seller checkout cannot release another's stock. `fulfillment_id` is present on all four topics.

---

<a id="gap-ledger"></a>
## 7. Gap ledger

The state this matrix found, and the state after the Wave 1 corrections. A **binding** is one field a consumer must write, or one routing input a write cannot be addressed without, paired with the payload field that supplies it — each is a row or a cell of §3–§6, so every figure below is countable in this document except the template-variable count, which is `email-templates.md`'s and is attributed below.

| Family | Consumers | Bindings | Unsupplied before | Unsupplied after |
|---|---|---|---|---|
| `search.*` | 12 | 35 index writes and routing inputs (§3) | 10 | 0 |
| `notification.*` | 21 | 20 email addresses + 15 in-app recipient ids + 101 template variables (§4) | 32 | 0 |
| `platform.audit` | 1 | 29 projection rows (§5) | 0 | 0 |
| `inventory.*` / `orders.*` | 5 | 5 scope-and-quantity sets (§6) | 0 | 0 |
| **Total** | **39** | **205** | **42** | **0** |

Six derived rollups are excluded from the search figure: they are owned by no event and recomputed from the document, so they have no supplying field by design.

**Two of those figures need their counting rule stated, because neither is the number a reader would guess.** §5 has **29 rows and 27 projected topics**: one row is the *not persisted* pair (`fx_rate.updated`, `seller.profile_changed`), which is a declaration that nothing is written rather than a projection, and `inventory.changed` takes two rows because `payload.change_reason` routes it to two different collections. The ledger counts rows, not topics, so that 29 is not the twenty-nine-topic count of [kafka-events.md § 1](kafka-events.md#topic-summary) and the two must not be reconciled — **`platform.audit` does not project every topic**, and the exceptions are named in the last row of §5 and in [data-model-mongodb.md § Consumer routing](data-model-mongodb.md#consumer-routing). The **101 template variables** are counted in [email-templates.md](../requirements/user-stories/email-templates.md) rather than here — this document binds the recipient fields, not every rendered variable — with each repeating group counted once: an order's `item.*` fields are one variable, as are its totals.

### 7.1 What the 42 were

| # | Consumer need | Was | Now |
|---|---|---|---|
| 1–2 | `category_path`, `created_at` on the product document | absent from `product.changed` | added |
| 3–5 | `offers[].seller_name`, `.seller_active`, `.display_prices` | absent from `offer.changed` | added |
| 6 | `_update/:productId` routing for `inventory.changed` | no `product_id` on the topic | added |
| 7 | `_update/:productId` routing for `inventory.reservation_expired` | no `product_id` on the topic | added |
| 8 | absolute availability on `inventory.reservation_expired` | `released_qty` — a delta, not idempotent under redelivery | replaced by `available_qty` |
| 9 | `offers[].seller_active` restore on timed expiry | `seller.suspension_expired` declared `offer_ids` and `seller_user_id` but its producer published neither, and `offer_ids` was unsuppliable because the sweep reactivated no offers | producer fixed, not just the schema: the sweep calls `CatalogApplicationService.reactivateSuspendedOffers` in its own transaction and publishes the returned ids, and takes `seller_user_id` from `IdentityApplicationService.getUsersByIds` ([cleanup-jobs.md](cleanup-jobs.md#lift-expired-suspensions)) |
| 10 | `offers[].seller_name` after a profile rename | no event at all — a renamed seller was permanently stale | new topic `seller.profile_changed` + group `search.seller-profile-changed` |
| 11–13 | `full_name` for ET-18, ET-19, ET-20 | absent from all three `auth.*` payloads | added to the three schemas **and** to the five outbox inserts in [api-design/auth.md](api-design/auth.md#endpoint-index) that publish them; the two password-change paths take it from `UPDATE identity.user … RETURNING` |
| 14–21 | `buyer_email` and `buyer_name` for ET-02, ET-03, ET-04, ET-16 | absent from all four fulfillment topics | added |
| 22 | `seller_email` for ET-13b | `fulfillment.refund_suspended_seller` named the seller but could not address them | added |
| 23–30 | ET-01's per-seller items, subtotal, shipping, tax, tracking and ETA; the buyer's business name and logo; `placed_at` | `PlacedFulfillmentRef` carried ids and two totals | added |
| 31–32 | `buyer_name`, `placed_at` for ET-05 | absent from `order.completed` | added |
| 33 | `seller_name` for ET-14 and ET-21 | `seller.kyc.submitted` carried `business_name` only | added |
| 34–36 | `seller_name`, `seller_email`, `seller_user_id` for ET-09 and its digest row | absent from `moderation.listing.removed` | added |
| 37–42 | `recipient_user_id` for the six seller-facing in-app rows — `KYC_DECIDED`, `SELLER_SUSPENDED`, `SELLER_REINSTATED`, `SUSPENSION_EXPIRED`, `LISTING_FLAGGED`, `LOW_STOCK` | payloads carried `seller_id`, a `seller_profile_id`, which cannot address `identity.user` | `seller_user_id` added to each |

**"Added" means the schema and the producer, and the schema alone does not close a row.** A required field a producer omits does not reach a consumer as null — it fails Avro serialization in the relay, so the event is never published and the consumer's write never happens at all. A row of this ledger is therefore closed only when some document names the statement that populates the field: the payload field and the `INSERT platform.outbox_event` that writes it are one change. Rows 9 and 11–13 were the three where the schema landed first and the producer did not.

Two further corrections in the same wave are producer-side rather than payload-side and so are not counted above: the `seller.kyc.submitted` partition key (`applicationId` → `seller_id`, which per-seller ordering depends on), and the six producer payload lists in `api-design/seller.md` and `api-design/admin.md` that were short of the schemas they publish against.

---

<a id="maintenance-rule"></a>
## 8. Maintenance rule

**A consumer group is not specified until it has rows here.** Adding a consumer, an email template, an Elasticsearch field or a MongoDB projection means adding its rows in §3–§6 in the same change, and the count in §2 and §7 with it. Adding a payload field means saying which row it serves — a field no row needs is a field no consumer reads.

The reverse check is the one that found the 42: for every field in the target shape, name the payload field that fills it. A row whose right-hand column cannot be filled is a design defect, and the fix is the event, never a read.
