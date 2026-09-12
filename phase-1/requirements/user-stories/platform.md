# Platform / Cross-cutting Stories (US-P-*)

Maps to BRD FR-P-* functional requirements. See [README](README.md) for format legend and cross-role index.

---

## US-P-01 — Multi-currency offer model
**As a** seller, **I want** to price my offer in multiple currencies simultaneously, **so that** buyers see native pricing without forced conversion.  
Priority: Must — trace: FR-P-01, FR-P-06a

**Acceptance criteria**
- An offer supports multiple prices, each in a different currency with an optional active time window.
- Supported currencies in V1: USD, THB, JPY, SGD.
- No two active prices for the same offer, currency, and price type may overlap in time.
- All active prices for an offer are returned by the API; frontend shows the buyer's preferred currency.
- At most one active LIST price per offer per currency may exist at any time. Attempting to create a second LIST price in the same currency as an existing active LIST price is rejected (see US-S-04b).
- **Price type resolution priority** (when multiple types are simultaneously applicable for the same offer, currency, and buyer context):
  1. `B2B_TIER` — if buyer account type is B2B and selected quantity ≥ `min_qty`.
  2. `SALE` — if current time is within `starts_at`/`ends_at`.
  3. `LIST` — default fallback.
  Only the highest-priority applicable type is used; lower-priority types are ignored. This ensures B2B buyers always receive their contracted tier rate even during active sales.

---

## US-P-02 — FX display conversion
**As a** buyer, **I want** foreign-currency prices converted to my preferred currency as an estimate, **so that** I can compare.  
Priority: Should — trace: FR-P-02, BRD §12 Decision 5

**Acceptance criteria**
- If no price exists in buyer's preferred currency → convert cheapest available via cached FX rate, display with `≈` prefix and tooltip "Estimated in <ccy>, actual charge in <original>".
- FX rates refreshed by a background scheduler (US-P-19) on a configurable cron interval (default every 60 minutes) via `exchangerate.host` public API for all four V1 currencies (USD, THB, JPY, SGD).
- Each rate row stores the rate value and a `fetched_at` timestamp. "Recent" is defined as: `fetched_at >= now() - staleness_threshold` where `staleness_threshold` is configurable via env var (default 4 hours).
- FX unavailable at display time → show last known rate if within staleness threshold; otherwise hide the conversion entirely and show only the offer-currency price.
- Display-only; checkout captures the original-currency price (FR-P-03).
- The `display_prices` map in the Elasticsearch index is updated by a Kafka consumer whenever a price-write event or FX-rate-updated event arrives (US-P-11, US-P-19).

---

## US-P-03 — Order price snapshot immutability
**As** the platform, **I want** order line items to snapshot price/currency/tax/fx at checkout, **so that** historical amounts never change.  
Priority: Must — trace: FR-P-03

**Acceptance criteria**
- Each order line item stores a snapshot of: unit price in offer currency, offer currency code, unit price in buyer's preferred currency (computed from offer price × FX rate captured at checkout), buyer currency code, FX rate used at capture, tax, and quantity.
- Both offer-currency and buyer-currency amounts are derived from the captured FX rate — never from a live rate after order creation.
- Order history totals are computed from these snapshots only — never from live pricing or current FX rates.
- Regression test: mutating a price or FX rate after order placement must not change the order total in either currency.
- **Grand total computation:** The order's grand total in buyer's preferred currency is computed as the sum of `(fulfillment_offer_currency_total × fulfillment_fx_rate_captured_at_checkout)` for each placed fulfillment. Where offer currency equals buyer preferred currency, `fx_rate = 1.000000`. This computation is performed at checkout and stored as `order.buyer_currency_grand_total` snapshot. It is never recomputed from live data after order creation.
- The buyer's preferred currency is resolved at checkout submission time and stored as `fulfillment.buyer_display_currency` on each fulfillment. If preferred currency was "AUTO", the resolved currency from the browser's `Accept-Language` header at checkout submission time is stored. This value is immutable after order creation.

---

## US-P-04 — Decimal money handling end-to-end
**As** the platform, **I want** all monetary math to use precise decimal arithmetic at every boundary, **so that** rounding drift and float bugs cannot occur.  
Priority: Must — trace: FR-P-04, FR-P-04a, FR-P-04b

**Acceptance criteria**
- All monetary storage uses fixed-precision decimal (not float/double).
- Backend services use a decimal library for all money math; float/double arithmetic on monetary fields is prohibited.
- API JSON amounts are strings, never numbers.
- Frontend parses amounts as decimal and formats for display only at the presentation boundary.
- Test: `"0.1"` + `"0.2"` yields `"0.30"`.

---

## US-P-05 — Multi-seller offer selection
**As a** buyer, **I want** to see all sellers offering the same product with prices, **so that** I can pick the cheapest or preferred seller.  
Priority: Should — trace: FR-P-05

**Acceptance criteria**
- PDP has "Other sellers" section listing offers ordered by cheapest available price in buyer's preferred currency.
- Each row: seller name, price, currency, availability, "Select this seller".
- Selecting an offer updates the primary Buy Box.

---

## US-P-06 — Seed 100 curated products
**As** the platform, **I want** a 100-product seed from Kaggle "Amazon Product Data" across categories, **so that** demos and load tests are realistic.  
Priority: Must — trace: FR-P-06, NFR-03

**Acceptance criteria**
- Seed: 100 products across ≥ 6 top-level categories (electronics, books, home, apparel, kitchen, sports).
- Each product has ≥ 1 offer from a seeded seller with ≥ 1 price (mix of USD, THB, JPY, SGD).
- Random subset: 10% SALE prices, 5% B2B_TIER prices.
- Seed command is idempotent (rerun does not duplicate).
- Seeded sellers: at minimum 3 seeded seller accounts are created. Each seeded seller has `KYC_STATUS = APPROVED` and `ACCOUNT_STATUS = ACTIVE` as set directly by the seed script (bypassing the KYC application queue — seeded sellers are pre-approved for demo purposes). One seeded seller corresponds to the "seller" demo account in BRD §11 (`seller@aliceut.dev`). The KYC onboarding flow (US-S-01) applies only to non-seeded sellers who register post-seed.
- Demo accounts (all seeded on first startup):
  - Consumer buyer:   `consumer@aliceut.dev` / `Consumer1234!`   (account_type: BUYER)
  - Business buyer:   `business@aliceut.dev` / `Business1234!`   (account_type: B2B_BUYER)
  - Seller:           `seller@aliceut.dev`   / `Seller1234!`     (account_type: SELLER, KYC status: APPROVED)
  - Admin:            `admin@aliceut.dev`    / `Admin1234!`       (role: ADMIN)
  - All passwords meet the password policy (8–128 chars, ≥ 1 letter, ≥ 1 digit).

---

## US-P-07 — B2B account branding differentiation
**As a** business buyer, **I want** my account visibly marked as business, **so that** invoices carry business branding while the shopping UX stays the same.  
Priority: Must — trace: FR-P-06d

**Acceptance criteria**
- Register form checkbox "This is a business account" → marks account as business type.
- Header shows "Business" tag next to user menu.
- Order confirmation and email invoice include optional business logo (uploadable in account settings).
- No functional divergence from B2C.

---

## US-P-08 — Secrets in env only
**As** the platform, **I want** all secrets injected via environment variables, **so that** no credential leaks into version control.  
Priority: Must — trace: FR-P-07, NFR-10

**Acceptance criteria**
- An example env file is checked in; the real env file is gitignored.
- App fails to start if required env vars are missing.
- CI rejects commits containing common secret patterns.

---

## US-P-09 — DTO validation on every endpoint
**As** the platform, **I want** every API endpoint to validate its input, **so that** malformed input is rejected uniformly.  
Priority: Must — trace: FR-P-08, NFR-07

**Acceptance criteria**
- Every API endpoint validates its input against a defined schema.
- Unknown fields in requests are rejected (not silently ignored).
- Validation errors return HTTP 400 with a structured `{ field, message }` array.

---

## US-P-10 — Transactional outbox for domain events
**As** the platform, **I want** every state-change to reliably trigger its downstream event even if the server crashes mid-operation, **so that** no events are lost.  
Priority: Must — trace: FR-P-09, NFR-14

**Acceptance criteria**
- Domain state changes and their associated events are committed atomically.
- Crash simulation test: kill the server between state write and event publish → event is eventually delivered on restart.
- No event is published outside the atomic commit path.

---

## US-P-11 — Async search index update
**As** the platform, **I want** the search index updated asynchronously from product/offer/inventory changes, **so that** search failures don't block catalog writes.  
Priority: Must — trace: FR-P-10, NFR-13

**Acceptance criteria**
- Product, offer, and inventory write APIs return without waiting for the search index to update.
- Search index reflects changes within 5 seconds of the write (p95, NFR-13).
- Search service down → writes queue and retry; bad messages are isolated and don't stall processing.
- Search query path: if Elasticsearch is unavailable at query time, the API returns HTTP 503 with a structured error body; never an unhandled 500. The upstream handler surfaces a user-facing "Search temporarily unavailable" message (US-B-02).
- A `listing.soft_deleted` event published via the transactional outbox (US-P-10) triggers the search consumer to remove the corresponding product document from the Elasticsearch index. Document removal is idempotent: attempting to remove a document that does not exist produces no error. `listing.soft_deleted` is added to the event catalogue alongside other named domain events.

---

## US-P-12 — Notifications via async consumers
**As** the platform, **I want** email and in-app notifications decoupled from request handling, **so that** slow email delivery doesn't block user requests.  
Priority: Must — trace: FR-P-11

**Acceptance criteria**
- Notification delivery (email, in-app) never happens inline in API request handlers.
- Notification failures are retried; persistently failed messages are quarantined without blocking other notifications.
- Consumers are idempotent: delivering the same event twice must not send duplicate notifications.

---

## US-P-13 — Event envelope + idempotency
**As** the platform, **I want** every event to carry a unique ID and consumers to be idempotent, **so that** at-least-once delivery is safe.  
Priority: Must — trace: FR-P-12, NFR-14

**Acceptance criteria**
- Every event carries: unique event ID, event type, version, timestamp, correlation ID, and payload.
- Events are stored with versioned schemas; backward compatibility required.
- Consumers deduplicate on event ID: replaying the same event twice produces only one side-effect.
- Contract test: same event replayed twice → single side-effect.

---

## US-P-14 — Dead-letter topics
**As** the platform, **I want** poison messages routed to a dead-letter queue, **so that** one bad message doesn't stall all notification processing.  
Priority: Should — trace: FR-P-13, NFR-15

**Acceptance criteria**
- Unhandled consumer exceptions route the original message to a per-consumer dead-letter queue and commit the offset (no stall).
- Dead-letter queue non-empty → alert raised.
- Manual reprocessing from dead-letter queue is documented.

---

## US-P-15 — Mock delivery scheduler
**As** the platform, **I want** a background process to automatically transition `SHIPPED` fulfillments to `DELIVERED` when their ETA is reached, **so that** the order lifecycle completes without manual action.  
Priority: Must — trace: FR-B-10, FR-S-05

**Acceptance criteria**
- A scheduled job polls for `SHIPPED` fulfillments where `eta <= now()`.
- On each match: transition fulfillment to `DELIVERED`; publish `fulfillment.delivered` event via the transactional outbox (US-P-10).
- Downstream consumer sends ET-03 to buyer; if all fulfillments in the order are now `DELIVERED`, sends ET-05 (for orders with ≥ 2 fulfillments only).
- ETA is set at order placement (mock): `placed_at + mock_delivery_days`. `mock_delivery_days` is seeded configuration (e.g. 5 days); it is not a real carrier estimate.
- Tick interval configurable via env var (default: `60s`).
- Job is idempotent: re-running against already-`DELIVERED` fulfillments produces no side effects.
- Job failure does not affect API availability; unprocessed fulfillments are retried on the next tick.

---

## US-P-16 — Auto-refund monitor for suspended-seller orders
**As** the platform, **I want** to automatically refund buyers when a suspended seller's orders pass the fulfillment window unshipped, **so that** buyers are not stuck waiting on inactive sellers.  
Priority: Should — trace: FR-A-05

**Acceptance criteria**
- A scheduled job polls for `PENDING` fulfillments where the owning seller is currently `SUSPENDED` and `placed_at + fulfillment_window_days < now()`.
- `fulfillment_window_days` is seeded configuration (e.g. 7 days); this is the expected ship-by window for mock orders.
- On each match:
  1. Transition fulfillment to `REFUNDED`; create fake-payment reversal record.
  2. Restore stock (goods never shipped).
  3. Publish `fulfillment.refund_suspended_seller` event via the transactional outbox.
  4. Downstream consumers send ET-13 (buyer) and ET-13b (seller).
- Tick interval configurable via env var (default: `3600s`).
- Job is idempotent: re-running against already-`REFUNDED` fulfillments produces no side effects.
- Job failure does not affect API availability; unprocessed fulfillments are retried on the next tick.
- **SHIPPED fulfillments during suspension:** `SHIPPED` fulfillments from a suspended seller are not subject to auto-refund. Goods already in transit proceed normally through the mock delivery scheduler (US-P-15) until `DELIVERED`. Only `PENDING` fulfillments past the fulfillment window are auto-refunded by this job. Explicitly: seller suspension does not interrupt in-transit fulfillments.

---

## US-P-17 — Inventory reservation expiry scheduler
**As** the platform, **I want** expired inventory reservations from abandoned checkouts to be released automatically, **so that** low-stock SKUs do not become permanently unsellable due to abandoned sessions.  
Priority: Must — trace: FR-P-03, FR-B-09

**Acceptance criteria**
- A scheduled job polls for inventory reservations where `reserved_at + reservation_ttl_minutes < now()` and no `PENDING` fulfillment exists referencing that reservation.
- `reservation_ttl_minutes` is configurable via env var (default `15`, matching the 15-minute TTL in US-B-09 step 4a).
- On each match: release the reserved quantity back to available stock; publish `inventory.reservation_expired` event via the transactional outbox (US-P-10).
- **Concurrency safety:** The release must execute inside a Postgres transaction that verifies the reservation's current status is still `ACTIVE` using `SELECT FOR UPDATE` or an optimistic version check. This prevents a race where a concurrent checkout reserves the same stock row at the moment the scheduler is releasing it.
- The job is idempotent: re-running against an already-released reservation produces no side effects.
- Tick interval configurable via env var (default `60s`).
- Job failure does not affect API availability; unprocessed reservations are retried on the next tick.

---

## US-P-18 — Suspension expiry scheduler
**As** the platform, **I want** timed seller suspensions to auto-lift at their expiry time, **so that** sellers are not permanently blocked by a time-limited suspension.  
Priority: Should — trace: FR-A-05

**Acceptance criteria**
- A scheduled job polls for seller accounts where `suspension_status = SUSPENDED` and `suspended_until <= now()` (timed suspensions only; permanent suspensions have no `suspended_until` and are excluded).
- On each match:
  1. Set seller `suspension_status = ACTIVE`; clear `suspended_until`.
  2. Reactivate all listings whose status was changed to INACTIVE by the suspension action (tracked with `status_changed_reason = 'SUSPENSION'`). Listings in REMOVED status from admin moderation (US-A-04) are not reactivated.
  3. Publish `seller.suspension_expired` event via the transactional outbox (US-P-10).
  4. Downstream Kafka consumer sends ET-11 to the seller.
- The job is idempotent: re-running against an already-active seller produces no side effects.
- Tick interval configurable via env var (default `3600s`).
- Job failure does not affect API availability; unprocessed expirations are retried on the next tick.

---

## US-P-19 — FX rate refresh scheduler
**As** the platform, **I want** FX rates to be refreshed on a schedule from a public API, **so that** display currency conversions and the Elasticsearch price index stay reasonably current.  
Priority: Should — trace: FR-P-02, BRD §12 Decision 5

**Acceptance criteria**
- A scheduled job fetches exchange rates for all V1 currencies (USD, THB, JPY, SGD) from `exchangerate.host` (or compatible public API configured via env var).
- Cron interval configurable via env var (default: every 60 minutes).
- On each successful fetch: persist all four rates with `fetched_at = now()` to the `FxRate` table; publish `fx_rate.updated` event via the transactional outbox (US-P-10).
- Downstream Kafka consumer processes `fx_rate.updated` and refreshes the `display_prices` map in the Elasticsearch index for all affected offers (US-P-11).
- On API fetch failure: retain the last known rates (do not clear or zero out rates on failure); log the error and raise an alert if the staleness threshold is exceeded (configurable via env var, default 4 hours).
- The job is idempotent: re-running does not produce duplicate rate rows; only the latest rate per currency pair is active.
- Job failure does not affect API availability.

---
