# Seller Stories (US-S-*)

Maps to BRD FR-S-* functional requirements. See [README](README.md) for format legend and cross-role index.

---

## US-S-01 — Seller onboarding application
**As a** prospective seller, **I want** to submit business name, tax ID, and KYC documents, **so that** admin can review my eligibility.
Priority: Must — trace: FR-S-01, NFR-09

**Acceptance criteria**
- Fields: legal business name, business type (LLC / sole prop / corp), tax ID (country regex), country, business address, phone, uploads (business license PDF, ID doc, proof of address).
- Uploads stored in encrypted bucket (NFR-09); access-logged to Mongo `AuditLog`.
- On submit → `SellerProfile` created with `status=PENDING_KYC`; user gets `role=SELLER_PENDING`.
- Publish `seller.kyc.submitted` to Kafka.

---

## US-S-02 — Block listing until KYC approved
**As** the platform, **I want** to prevent sellers from listing products before KYC approval, **so that** we don't expose unvetted vendors.
Priority: Must — trace: FR-S-02

**Acceptance criteria**
- API endpoints for product create/edit reject with 403 if `sellerProfile.status != APPROVED`.
- Seller dashboard shows "Your application is under review" banner while pending.
- On approval → banner replaced with "You're live — create your first listing" CTA.

---

## US-S-03 — Create product listing
**As an** approved seller, **I want** to create a product with title, description, price(s), category, images, and variants, **so that** buyers can find and purchase it.
Priority: Must — trace: FR-S-03, FR-P-01, FR-P-06a, FR-P-06b, FR-P-06c

**Acceptance criteria**
- Fields: title (10–200 chars), description (Markdown ≤ 5000 chars), category (from taxonomy tree), images (1–10, JPEG/PNG/WebP, ≤ 5MB each), variants (name + options), inventory per SKU.
- Pricing sub-form: ≥ 1 `Price` row required. Currencies: USD, THB, JPY, SGD (FR-P-06a). Optional SALE and B2B_TIER rows.
- Prohibited category guard: category ∈ {weapons, drugs, adult content} → block submit (FR-P-06c). Keyword blocklist scans title/description.
- On success → `Product` + `Offer` + `Price` rows in same Postgres tx; `product.changed` + `offer.changed` outbox events published; ES indexer projects async (NFR-13 ≤ 5s p95).
- All prices stored `NUMERIC(19,4)`; UI validates via `decimal.js` (FR-P-04a).

---

## US-S-04 — Edit and delete own products
**As a** seller, **I want** to edit or delete only my own listings, **so that** I control my catalog.
Priority: Must — trace: FR-S-04

**Acceptance criteria**
- Edit/delete require `offer.seller_id === current_user.seller_id`; else 403.
- Delete = soft delete (`status=INACTIVE`); preserves historical `FulfillmentItem` FKs.
- Publishes `offer.changed` (INACTIVE) → search removes from index.

---

## US-S-05 — Order fulfillment dashboard
**As a** seller, **I want** to see my orders grouped by status, **so that** I can prioritize what to ship.
Priority: Must — trace: FR-S-05

**Acceptance criteria**
- Tabs: `Pending`, `Shipped`, `Delivered`, `Refunded`.
- Row: order_id, buyer name masked (`J. Doe`), items, total in offer currency, placed_at, action button.
- Read from Postgres projection populated by Kafka consumers of order events.
- p95 load ≤ 2s for ≤ 500 orders.
- Each row is one seller/currency fulfillment. Its status is the lifecycle state on `Fulfillment`, not on individual `FulfillmentItem`s.

---

## US-S-06 — Mark order shipped
**As a** seller, **I want** to mark an order as shipped, **so that** the buyer sees progress and a tracking number.
Priority: Must — trace: FR-S-06

**Acceptance criteria**
- Action button is available only for a `PENDING` fulfillment owned by the current seller. On confirmation it transitions `Fulfillment.status` from `PENDING` to `SHIPPED`.
- The tracking number was generated at order placement for buyer confirmation and is preserved on shipment; this transition must not create a second tracking number.
- The status update and one `fulfillment.shipped` outbox event commit in the same transaction with the original `correlation_id`.
- Repeating a completed shipment action on an already-`SHIPPED` fulfillment returns the existing result without publishing another event; all other source statuses are rejected.
- Buyer sees updated status within 5s (NFR-13).
- Email sent to buyer via consumer.

---

## US-S-07 — Issue refund
**As a** seller, **I want** to refund an order (fake payment reversal), **so that** I can handle customer service.
Priority: Must — trace: FR-S-07

**Acceptance criteria**
- Refund action is available for the seller-owned `PENDING`, `SHIPPED`, or `DELIVERED` fulfillment; requires reason (≤ 500 chars).
- On confirm:
  1. Transition `Fulfillment.status` to `REFUNDED` and create the fake-payment reversal record.
  2. Publish one `fulfillment.refunded` outbox event → email consumer notifies buyer.
  3. Restore stock only for a `PENDING` fulfillment, when goods have not shipped. Refunding a `SHIPPED` or `DELIVERED` fulfillment does not restore stock because a return workflow is out of scope.
- Refund amount = snapshotted `unit_price × quantity` (FR-P-03).
- Partial refunds deferred; V1 = full item refund only.
- Repeating a completed refund action on an already-`REFUNDED` fulfillment returns the existing result without a second reversal, stock movement, or event.

---

## US-S-08 — Inventory + low-stock alerts
**As a** seller, **I want** to see stock per SKU and get alerted when low, **so that** I don't oversell.
Priority: Must — trace: FR-S-08

**Acceptance criteria**
- Inventory page: table of variants × `on_hand`, `reserved`, `available = on_hand − reserved`.
- Threshold configurable per SKU (default 5). Below threshold → `inventory.low_stock` event → email + in-app banner.
- Manual adjust: `on_hand` editable inline with reason logged.
- Bulk update via CSV (US-S-09) reuses same event pipeline.

---

## US-S-09 — Bulk inventory update via CSV
**As a** seller with many SKUs, **I want** to upload a CSV to update inventory in bulk, **so that** I don't click one row at a time.
Priority: Should — trace: FR-S-09

**Acceptance criteria**
- CSV columns: `sku, on_hand, low_stock_threshold` (last optional).
- Preview screen shows diff (before → after) with row-level errors highlighted.
- On confirm → single Postgres tx; publishes one `inventory.changed` event per SKU.
- File size cap 5MB, ≤ 10k rows.
- Malformed CSV → validation report downloadable.
