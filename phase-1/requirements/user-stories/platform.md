# Platform / Cross-cutting Stories (US-P-*)

Maps to BRD FR-P-* functional requirements. See [README](README.md) for format legend and cross-role index.

---

## US-P-01 — Per-offer pricing currency model
**As a** seller, **I want** each of my offers to carry its own pricing currency, **so that** buyers see a native price for that offer without a forced canonical currency.  
Priority: Must — trace: FR-P-01, FR-P-06a

**Acceptance criteria**
- An offer has exactly one pricing currency, held on the offer itself as `catalog.offer.native_currency_code`. Every price row belonging to that offer is denominated in that currency; a price row carries no currency of its own, so there is no second copy that can diverge from the offer.
- Supported seller pricing currencies in V1: USD, THB, JPY, SGD.
- A seller who wants to sell the same product in a second currency creates a second offer. The platform is multi-currency across offers, not within a single offer.
- An offer supports multiple price rows, one per price type, each with an optional active time window. No two active prices for the same offer and price type may overlap in time.
- All active prices for an offer are returned by the API, each carrying the offer's currency code beside its amount. Each amount is also returned already converted into the buyer's display currency, as a string; the frontend renders the strings it is given and never performs currency arithmetic of its own.
- At most one active LIST price per offer may exist at any time. Attempting to create a second active LIST price for the same offer is rejected (see US-S-04b).
- **Price type resolution** — price type and current time are the only inputs. Account type and quantity are **not** inputs (`B2B_TIER` dropped from V1, BRD § Amendments):
  1. `SALE` — if current time is within `starts_at`/`ends_at`.
  2. `LIST` — default fallback.
  Only the highest-priority applicable type is used. B2B and B2C accounts resolve to the same amount; B2B differentiation is branding only (FR-P-06d).

---

## US-P-02 — FX display conversion
**As a** buyer, **I want** foreign-currency prices converted to my preferred currency as an estimate, **so that** I can compare.  
Priority: Should — trace: FR-P-02, BRD §12 Decision 5

**Acceptance criteria**
- If the offer's native currency differs from the buyer's preferred display currency → the API converts the effective amount with the cached FX rate for that pair and returns it alongside the native amount, and the UI displays it with a `≈` prefix and the tooltip "Estimated in <ccy>, actual charge in <original>".
- FX rates refreshed by a background scheduler (US-P-19) on a configurable cron interval (default every 60 minutes) via `exchangerate.host` public API for all four V1 currencies (USD, THB, JPY, SGD).
- Each rate row stores the rate value and an `as_of` timestamp — the provider's timestamp for the value currently held. The table keeps exactly one row per currency pair and is refreshed by upsert in place, so there is no rate history and no `fetched_at` column. A rate is stale when `now() - as_of` exceeds `FX_STALE_AFTER_HOURS`, an env-configurable window expressed as a whole number of hours, default `24`.
- Every response carrying a converted amount carries the rate's `as_of` as `fxAsOf` and the companion boolean `fxStale` beside it, so the client can label the amount without repeating the staleness arithmetic.
- A stale rate is still returned and still converted: the response sets `fxStale: true` and the UI presents the amount as an indicative rate rather than hiding it. The conversion is omitted only when the pair has no FX row at all, in which case the converted amount, `fxRate` and `fxAsOf` are all `null` and the UI shows the offer-currency price alone.
- Display-only at browse time; nothing shown here is captured on an order. Checkout snapshots both the offer-currency amounts and their buyer-currency equivalents at capture (FR-P-03, US-P-03).
- The `display_prices` map in the Elasticsearch index is updated by a Kafka consumer whenever a price-write event or FX-rate-updated event arrives (US-P-11, US-P-19).

---

## US-P-03 — Order price snapshot immutability
**As** the platform, **I want** order line items to snapshot price/currency/tax/fx at checkout, **so that** historical amounts never change.  
Priority: Must — trace: FR-P-03

**Acceptance criteria**
- Each order line item (`orders.fulfillment_item`) stores a snapshot of: `unit_price` in the offer currency, the offer currency code, `buyer_currency_unit_price`, `buyer_currency_tax`, the buyer display currency code, `fx_rate_used_at_capture`, `tax`, and quantity.
- `fx_rate_used_at_capture` is never null: it holds `1.00000000` when the offer currency and the buyer display currency are the same, so no reader has to branch on a missing rate. FX rates carry eight fractional digits.
- The captured `tax` is `"0.00"` in V1. Tax and shipping are structural zeroes seeded from platform configuration — there is no tax engine, no tax-rate table and no jurisdiction model behind the field anywhere in Phase 1. The snapshot column exists regardless so that FR-P-03 immutability holds unchanged if a tax engine is added later.
- Both offer-currency and buyer-currency amounts are derived from the captured FX rate — never from a live rate after order creation. Rounding happens once, at capture, using the buyer currency's `minor_unit_scale`; storage keeps four fractional digits.
- Order history totals are computed from these snapshots only — never from live pricing or current FX rates.
- Regression test: mutating a price or FX rate after order placement must not change the order total in either currency.
- **Grand total computation:** Each fulfillment's buyer-currency total is converted once, at capture, and stored as `fulfillment.buyer_currency_total`. The order's grand total is the sum of those stored values and is itself stored, as `order.buyer_currency_grand_total`. Both are snapshots rather than views: neither is recomputed from live pricing or a live FX rate after order creation, and no API response and no UI component ever converts money.
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
- Random subset: 10% of offers carry a `SALE` price alongside their `LIST` price. No `B2B_TIER` prices — not a V1 price type (BRD § Amendments).
- Seed command is idempotent (rerun does not duplicate).
- Seeded sellers: at minimum 3 seeded seller accounts are created. Each seeded seller has `seller.seller_profile.kyc_status = 'APPROVED'` and `seller.seller_profile.suspension_status = 'ACTIVE'` as set directly by the seed script (bypassing the KYC application queue — seeded sellers are pre-approved for demo purposes). These are two independent columns: the seller is approved and unsuspended, and neither value is derived from the other. One seeded seller corresponds to the "seller" demo account in BRD §11 (`seller@aliceut.dev`). The KYC onboarding flow (US-S-01) applies only to non-seeded sellers who register post-seed.
- Demo accounts (all seeded on first startup):
  - Consumer buyer:   `consumer@aliceut.dev` / `Consumer1234!`   (roles `['BUYER']`, account_type `B2C`)
  - Business buyer:   `business@aliceut.dev` / `Business1234!`   (roles `['BUYER']`, account_type `B2B`, `business_name` set)
  - Seller:           `seller@aliceut.dev`   / `Seller1234!`     (roles `['SELLER']`, account_type `B2C`, `seller_profile.kyc_status = 'APPROVED'`)
  - Admin:            `admin@aliceut.dev`    / `Admin1234!`      (roles `['ADMIN']`, account_type `B2C`)
  - `roles` and `account_type` are orthogonal columns ([data-model-erd § identity.user](../../technical-design/data-model-erd.md#table-identity-user)): `roles TEXT[]` ∈ {`BUYER`, `SELLER`, `ADMIN`} is what the account may do, `account_type` ∈ {`B2C`, `B2B`} is buyer-facing branding only (BRD §12 #2). Neither column has a `BUSINESS_BUYER` or `B2B_BUYER` value, and the seller account stays `B2C` because it carries no invoice branding of its own.
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
- A scheduled job polls for `SHIPPED` fulfillments where `estimated_delivery_at <= now()`.
- On each match: transition fulfillment to `DELIVERED`; publish `fulfillment.delivered` event via the transactional outbox (US-P-10).
- Downstream consumer sends ET-03 to the buyer. The order-completion check belongs to the Orders module and is triggered by `fulfillment.delivered`: when no non-`DELIVERED` fulfillment remains for the order, `order.completed` is published. There is no minimum fulfillment count on that condition — a single-fulfillment order completes like any other. ET-05 is then sent only for orders that had ≥ 2 fulfillments; a single-fulfillment order relies on ET-03, which already carries the same information (see the buyer notification matrix).
- `REFUNDED` and `CANCELLED` fulfillments are not pending for that check. An order whose fulfillments are all in a terminal state with at least one `DELIVERED` completes; an order whose every fulfillment is `CANCELLED` or `REFUNDED` emits no `order.completed` and lands on the derived `CANCELLED`/`REFUNDED` order status instead.
- ETA is set at order placement (mock): `estimated_delivery_at = placed_at + fulfillment_window_days`. `fulfillment_window_days` is platform-level seeded configuration with a default of 7 days — the same single value that US-P-16 uses as the ship-by window, not a second setting alongside it. It is not a real carrier estimate, and there is no randomisation: the same fulfillment always yields the same ETA.
- Tick interval configurable via env var (default: `60s`).
- Job is idempotent: re-running against already-`DELIVERED` fulfillments produces no side effects.
- Job failure does not affect API availability; unprocessed fulfillments are retried on the next tick.

---

## US-P-16 — Auto-refund monitor for suspended-seller orders
**As** the platform, **I want** to automatically refund buyers when a suspended seller's orders pass the fulfillment window unshipped, **so that** buyers are not stuck waiting on inactive sellers.  
Priority: Should — trace: FR-A-05

**Acceptance criteria**
- A scheduled job polls for `PENDING` fulfillments where the owning seller is currently `SUSPENDED` and `placed_at + fulfillment_window_days < now()`.
- `fulfillment_window_days` is platform-level seeded configuration with a default of 7 days, overridable by environment variable. It is the expected ship-by window for mock orders, and the same value drives `estimated_delivery_at` (US-P-15). It is **not** a per-seller setting: no such column exists on `seller.seller_profile` and none is being added.
- On each match:
  1. Transition the fulfillment to `REFUNDED` and write the `fulfillment.refund_suspended_seller` outbox row in the same Postgres transaction as the status change.
  2. No payment-side record is written. `payment_attempt` is a log of simulated charge attempts, not a ledger, and while payments are mocked a refund is a `fulfillment.status` change and nothing more. The accepted cost is that there is no payment-side evidence that money went back; this is revisited if V2 adds a real gateway.
  3. Stock restoration is **not** performed by this job. The Inventory module is the single writer of `inventory.*` and restores stock from the event, only for fulfillments whose prior status was `PENDING` — a `SHIPPED` fulfillment restores nothing, because its reservations were consumed at shipment. Restoration is therefore eventually consistent, bounded by consumer lag, and available-stock reads may lag briefly.
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
- A scheduled job polls for `ACTIVE` inventory reservations past their `expires_at` that never acquired a fulfillment (`fulfillment_id IS NULL`) — exactly the abandoned-checkout case. A reservation that did acquire a fulfillment is released or consumed by that fulfillment's own lifecycle, scoped on `fulfillment_id`, and is never touched by this sweep.
- `expires_at` is set when the reservation is created, from a TTL configurable via env var (default `15` minutes, matching the 15-minute TTL in US-B-09 step 4a).
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
- On each successful fetch: upsert one row per currency pair into `pricing.fx_rate` — `INSERT … ON CONFLICT (base_currency_code, quote_currency_code) DO UPDATE SET rate, as_of, provider, updated_at` — with `as_of` set to the provider's timestamp for the value fetched; publish `fx_rate.updated` via the transactional outbox (US-P-10) in the same transaction. Rates are stored with eight fractional digits.
- Downstream Kafka consumer processes `fx_rate.updated` and refreshes the `display_prices` map in the Elasticsearch index for all affected offers (US-P-11).
- On API fetch failure: retain the last known rates (do not clear or zero out rates on failure); log the error and raise an alert once `now() - as_of` exceeds `FX_STALE_AFTER_HOURS` (configurable via env var, whole hours, default `24`).
- The job is idempotent by construction: refresh is an upsert in place, so re-running overwrites each pair's existing row rather than appending a new one. The table holds exactly one row per currency pair and keeps no history, which makes it fixed-size — there is nothing to prune and no cleanup job for it.
- Job failure does not affect API availability.

---
