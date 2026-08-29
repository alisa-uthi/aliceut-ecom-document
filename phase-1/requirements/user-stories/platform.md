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

---

## US-P-02 — FX display conversion
**As a** buyer, **I want** foreign-currency prices converted to my preferred currency as an estimate, **so that** I can compare.
Priority: Should — trace: FR-P-02

**Acceptance criteria**
- If no price exists in buyer's preferred currency → convert cheapest available via cached FX rate, display with `≈` prefix and tooltip "Estimated in <ccy>, actual charge in <original>".
- FX rates refreshed periodically.
- Display-only; checkout captures the original-currency price (FR-P-03).
- FX unavailable → show last known rate if recent; otherwise hide the conversion entirely.

---

## US-P-03 — Order price snapshot immutability
**As** the platform, **I want** order line items to snapshot price/currency/tax/fx at checkout, **so that** historical amounts never change.
Priority: Must — trace: FR-P-03

**Acceptance criteria**
- Each order line item stores a snapshot of unit price, currency, tax, FX rate used, and quantity at checkout.
- Order history totals are computed from these snapshots only — never from live pricing.
- Regression test: mutating a price after order placement must not change the order total.

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
