# Seller Stories (US-S-*)

Maps to BRD FR-S-* functional requirements. See [README](README.md) for format legend and cross-role index.

---

## US-S-00 — Seller dashboard overview
**As a** seller, **I want** a summary screen when I log in, **so that** I can triage pending work without navigating to every section manually.
Priority: Must — trace: FR-S-05, FR-S-08

**Acceptance criteria**
- Dashboard shows live counts: pending orders, low-stock SKUs (below threshold), active listings, flagged/removed listings.
- Each count links to the corresponding section.
- Counts update on page load (no real-time push required in V1).

---

## US-S-01 — Seller onboarding application
**As a** prospective seller, **I want** to submit business name, tax ID, and KYC documents, **so that** admin can review my eligibility.
Priority: Must — trace: FR-S-01, NFR-09

**Acceptance criteria**
- Fields: legal business name, business type (LLC / sole prop / corp), tax ID (country regex), country, business address, phone, uploads (business license PDF, ID doc, proof of address).
- On submit → application created with pending status; seller receives confirmation email (→ ET-14) that application is under review.
- Seller with a pending or approved application cannot submit a new one; rejected application shows "Update and resubmit" CTA instead of the new-application form.

---

## US-S-02 — Block listing until KYC approved
**As** the platform, **I want** to prevent sellers from listing products before KYC approval, **so that** we don't expose unvetted vendors.
Priority: Must — trace: FR-S-02

**Acceptance criteria**
- Seller cannot create or edit product listings while application is not approved.
- Seller dashboard shows "Your application is under review" banner while pending.
- On approval → banner replaced with "You're live — create your first listing" CTA.
- On rejection → banner replaced with rejection reason (from admin) and "Update and resubmit" CTA. Seller can update documents and resubmit; resubmission is linked to the prior rejection and creates a new pending application. Seller notified by email on rejection (→ ET-07).
- On suspension → seller dashboard locked with suspension reason, duration, and `suspended_until` date (if timed). Seller cannot list products or access the seller dashboard; buyer role on the same account remains active. Seller notified by email on suspension (→ ET-10) and on reinstatement (→ ET-11 auto-expiry, → ET-12 admin-lifted).

---

## US-S-03 — Create product listing
**As an** approved seller, **I want** to create a product with title, description, price(s), category, images, and variants, **so that** buyers can find and purchase it.
Priority: Must — trace: FR-S-03, FR-P-01, FR-P-06a, FR-P-06b, FR-P-06c

**Acceptance criteria**
- Fields: title (10–200 chars), description (Markdown ≤ 5000 chars), category (from taxonomy tree), images (1–10, JPEG/PNG/WebP, ≤ 5MB each), variants (name + options), inventory per SKU.
- Images are orderable (drag-to-reorder); first image = primary (shown in search results and PDP hero).
- Pricing sub-form: at least one LIST price required. Currencies: USD, THB, JPY, SGD (FR-P-06a). Optional SALE and B2B_TIER prices.
  - SALE price requires `starts_at < ends_at`; system automatically reverts to LIST price after `ends_at`.
  - B2B_TIER price requires `min_qty ≥ 2`.
- Prohibited category guard: weapons, drugs, adult content → block submit (FR-P-06c). Keyword blocklist scans title and description on every save.
- On success → product is live; search index updates within 5 seconds (NFR-13).
- Zero-stock rule: when available quantity (on_hand − reserved) for all SKUs = 0, listing is hidden from search and catalog automatically. Listing reactivates when any SKU's available quantity rises above 0.

---

## US-S-04 — Edit and delete own products
**As a** seller, **I want** to edit or delete only my own listings, **so that** I control my catalog.
Priority: Must — trace: FR-S-04

**Acceptance criteria**
- Sellers can only edit or delete their own listings; attempting to modify another seller's listing is rejected.
- On every edit save, keyword/category guard re-runs. If triggered, listing is flagged and hidden from search pending admin review; seller notified by in-app alert.
- Editing price on an Offer with PENDING orders is allowed (FR-P-03 snapshot protects existing orders); seller sees a warning that price change does not affect in-flight orders.
- Deleting a variant that has PENDING orders is blocked with an error message; all PENDING orders on that variant must be refunded or fulfilled first.
- Delete = soft delete; listing becomes invisible to buyers but historical order data is preserved.
- Removing a listing removes it from search results.

---

## US-S-04b — Manage offer pricing
**As a** seller, **I want** to add, edit, or remove prices on an existing listing without editing the product itself, **so that** I can run sales or adjust prices quickly.
Priority: Must — trace: FR-P-01, FR-P-06a, FR-P-06b

**Acceptance criteria**
- Pricing panel accessible from the listing detail page, separate from the product edit form.
- Displays all current Price rows: LIST, SALE (with `starts_at`/`ends_at`), B2B_TIER (with `min_qty`).
- Seller can add a new Price row (any supported type + currency), edit an existing row, or delete a non-LIST row. At least one LIST price must always remain.
- SALE price: `starts_at < ends_at` enforced; overlapping SALE periods for the same currency are rejected.
- B2B_TIER: `min_qty ≥ 2` enforced.
- Price changes take effect immediately; existing PENDING order snapshots are unaffected (FR-P-03). Seller sees a warning on save.
- All changes auditable.

---

## US-S-05 — Order fulfillment dashboard
**As a** seller, **I want** to see my orders grouped by status, **so that** I can prioritize what to ship.
Priority: Must — trace: FR-S-05, FR-B-10

**Acceptance criteria**
- Tabs: `Pending`, `Shipped`, `Delivered`, `Refunded`, `Cancelled`.
- Row: order_id, buyer name masked (`J. Doe`), items, total in offer currency, placed_at, action button.
- Each row is one seller/currency fulfillment and shows its own lifecycle status.
- List filterable by date range; searchable by order_id.
- Orders for removed or admin-flagged listings still appear in the relevant tab with a "Listing removed" badge so the seller retains fulfillment visibility.
- Seller notified by email when a new order is created for them (→ ET-17).

---

## US-S-05b — Order detail view
**As a** seller, **I want** to view full details of an order, **so that** I know what to ship and where to ship it.
Priority: Must — trace: FR-S-05, FR-S-06

**Acceptance criteria**
- Accessible from any row in the fulfillment dashboard (US-S-05).
- Shows: order_id, placed_at, fulfillment status, items (variant, quantity, snapshotted unit price in offer currency), buyer shipping address (full — not masked), mock tracking number.
- Ship and Refund/Cancel actions available inline (same guards as US-S-06, US-S-07, US-S-11).
- Buyer shipping address is PII; access is logged for audit (NFR-09).

---

## US-S-06 — Mark order shipped
**As a** seller, **I want** to mark an order as shipped, **so that** the buyer sees progress and a tracking number.
Priority: Must — trace: FR-S-06

**Acceptance criteria**
- Action button is available only for a `PENDING` fulfillment owned by the current seller. On confirmation it transitions the fulfillment status to `SHIPPED`.
- The tracking number was generated at order placement and is preserved on shipment; this transition must not create a second tracking number.
- Repeating a shipment action on an already-`SHIPPED` fulfillment returns the existing result without side effects; other source statuses are rejected.
- Buyer sees updated status within 5s (NFR-13).
- Email sent to buyer (→ ET-02).

---

## US-S-07 — Issue refund
**As a** seller, **I want** to refund an order (fake payment reversal), **so that** I can handle customer service.
Priority: Must — trace: FR-S-07

**Acceptance criteria**
- Refund action is available for the seller-owned `PENDING`, `SHIPPED`, or `DELIVERED` fulfillment; requires reason (≤ 500 chars).
- On confirm:
  1. Transition fulfillment status to `REFUNDED` and create the fake-payment reversal record.
  2. Buyer is notified by email (→ ET-04).
  3. Stock restored only for a `PENDING` fulfillment (goods have not shipped). Refunding a `SHIPPED` or `DELIVERED` fulfillment does not restore stock.
- Refund amount = snapshotted unit price × quantity (FR-P-03).
- Partial refunds deferred; V1 = full item refund only.
- Repeating a refund action on an already-`REFUNDED` fulfillment returns the existing result without a second reversal or stock movement.

---

## US-S-08 — Inventory + low-stock alerts
**As a** seller, **I want** to see stock per SKU and get alerted when low, **so that** I don't oversell.
Priority: Must — trace: FR-S-08

**Acceptance criteria**
- Inventory page: table of variants × on_hand, reserved, available (on_hand − reserved).
- "Reserved" = units held by PENDING orders not yet shipped. Displayed as a tooltip/legend on the column header.
- Threshold configurable per SKU (default 5). Below threshold → email (→ ET-15) + in-app banner alert.
- Manual adjust: on_hand editable inline with reason logged.
- Bulk update via CSV (US-S-09) reuses same alert logic and zero-stock deactivation rule.

---

## US-S-09 — Bulk inventory update via CSV
**As a** seller with many SKUs, **I want** to upload a CSV to update inventory in bulk, **so that** I don't click one row at a time.
Priority: Should — trace: FR-S-09

**Acceptance criteria**
- CSV columns: `sku, on_hand, low_stock_threshold` (last optional).
- Preview screen shows diff (before → after) with row-level errors highlighted.
- Rows where the new on_hand would make available (on_hand − reserved) negative are flagged as warnings in the preview; seller must explicitly confirm to proceed. Existing PENDING orders are not cancelled.
- On confirm → inventory updated; search visibility reflects updated stock (including zero-stock deactivation).
- File size cap 5MB, ≤ 10k rows.
- Malformed CSV → validation report downloadable.

---

## US-S-10 — View listing moderation status
**As a** seller, **I want** to see the status of all my listings including flagged or removed ones, **so that** I understand why a listing is not visible and what action was taken.
Priority: Must — trace: FR-A-03, FR-A-04, FR-S-04

**Acceptance criteria**
- Listings page shows all listings with a status badge: ACTIVE, FLAGGED, REMOVED, DRAFT.
- FLAGGED listings show flag reason (auto: keyword/category; or admin-flagged) and "Under admin review" label.
- REMOVED listings show admin removal reason, removal date, and admin actor (name or role). Seller cannot reactivate a removed listing; they may create a new compliant one.
- Seller receives email notification when a listing is flagged (→ ET-08, one email per flagged listing) or removed (→ ET-09, daily digest — one email per day aggregating all removals that day) (via Kafka consumer, FR-P-11).

---

## US-S-11 — Cancel unfulfillable PENDING order
**As a** seller, **I want** to cancel a PENDING order I cannot fulfill, **so that** the buyer is refunded and I'm not left with a stuck order.
Priority: Should — trace: FR-S-05, FR-S-07

**Acceptance criteria**
- Cancel action available only for `PENDING` fulfillments; requires reason (≤ 500 chars).
- On confirm:
  1. Fulfillment transitions to `CANCELLED`.
  2. Fake-payment reversal record created (full refund).
  3. Stock for the cancelled items restored to on_hand.
  4. Buyer notified by email with reason (→ ET-16).
- Repeating a cancel on an already-`CANCELLED` fulfillment is a no-op.
- Cancelled orders appear in a `Cancelled` tab on the fulfillment dashboard (US-S-05).
