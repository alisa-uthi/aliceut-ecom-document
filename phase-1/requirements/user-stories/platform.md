# Platform / Cross-cutting Stories (US-P-*)

Maps to BRD FR-P-* functional requirements. See [README](README.md) for format legend and cross-role index.

---

## US-P-01 — Multi-currency offer model
**As a** seller, **I want** to price my offer in multiple currencies simultaneously, **so that** buyers see native pricing without forced conversion.
Priority: Must — trace: FR-P-01, FR-P-06a

**Acceptance criteria**
- `Offer` supports N `Price` rows keyed by `(currency, price_type, effective window)`.
- Currency ∈ {USD, THB, JPY, SGD} in V1.
- Uniqueness: no two active `Price` rows for same `(offer_id, currency, price_type)` overlap in time.
- API returns all active prices; frontend picks display per buyer preference.

---

## US-P-02 — FX display conversion
**As a** buyer, **I want** foreign-currency prices converted to my preferred currency as an estimate, **so that** I can compare.
Priority: Should — trace: FR-P-02

**Acceptance criteria**
- If no `Price` exists in buyer's preferred currency → convert cheapest available via `FxRate` table, display with `≈` prefix and tooltip "Estimated in <ccy>, actual charge in <original>".
- `FxRate` refreshed hourly via cron from `exchangerate.host`.
- Display-only; checkout captures original-currency `Price` snapshot (FR-P-03).
- FX failure → last-known rate ≤ 24h old; else hide conversion.

---

## US-P-03 — Order price snapshot immutability
**As** the platform, **I want** order line items to snapshot price/currency/tax/fx at checkout, **so that** historical amounts never change.
Priority: Must — trace: FR-P-03

**Acceptance criteria**
- `OrderItem` columns: `unit_price NUMERIC(19,4)`, `currency CHAR(3)`, `tax NUMERIC(19,4)`, `fx_rate_used NUMERIC(19,8) NULL`, `quantity INT`.
- Reads for order history compute totals from these fields only — no JOIN to live `Price`.
- Regression test: mutating a `Price` row after order placement must not change the order total.

---

## US-P-04 — Decimal money handling end-to-end
**As** the platform, **I want** all monetary math to use Decimal at every boundary, **so that** rounding drift and float bugs cannot occur.
Priority: Must — trace: FR-P-04, FR-P-04a, FR-P-04b

**Acceptance criteria**
- DB: `NUMERIC(19,4)` on money columns; `NUMERIC(19,8)` on `fx_rate`.
- Backend: TypeORM maps to `string`; services convert via `decimal.js`. ESLint rule bans `number` type on fields matching `/price|amount|tax|fee/i`.
- API JSON: amounts as strings, never numbers.
- Frontend: parses strings via `decimal.js`; formats via `Intl.NumberFormat` at display boundary only.
- Test: `"0.1"` + `"0.2"` yields `"0.30"`.

---

## US-P-05 — Multi-seller offer selection
**As a** buyer, **I want** to see all sellers offering the same product with prices, **so that** I can pick the cheapest or preferred seller.
Priority: Should — trace: FR-P-05

**Acceptance criteria**
- PDP has "Other sellers" section listing offers ordered by cheapest_available_price_in_buyer_currency.
- Each row: seller name, price, currency, availability, "Select this seller".
- Selecting an offer updates the primary Buy Box.

---

## US-P-06 — Seed 100 curated products
**As** the platform, **I want** a 100-product seed from Kaggle "Amazon Product Data" across categories, **so that** demos and load tests are realistic.
Priority: Must — trace: FR-P-06, NFR-03

**Acceptance criteria**
- Seed: 100 products across ≥ 6 top-level categories (electronics, books, home, apparel, kitchen, sports).
- Each product ≥ 1 `Offer` from a seeded seller with ≥ 1 `Price` (mix of USD, THB, JPY, SGD).
- Random subset: 10% SALE prices, 5% B2B_TIER prices.
- `pnpm run seed`; idempotent (rerun does not duplicate).

---

## US-P-07 — B2B account branding differentiation
**As a** business buyer, **I want** my account visibly marked as business, **so that** invoices carry business branding while the shopping UX stays the same.
Priority: Must — trace: FR-P-06d

**Acceptance criteria**
- Register form checkbox "This is a business account" → sets `User.account_type=BUSINESS`.
- Header shows "Business" tag next to user menu.
- Order confirmation and email invoice include optional business logo (uploadable in account settings).
- No functional divergence from B2C.

---

## US-P-08 — Secrets in env only
**As** the platform, **I want** all secrets injected via env vars, **so that** no credential leaks into VCS.
Priority: Must — trace: FR-P-07, NFR-10

**Acceptance criteria**
- `.env.example` checked in; `.env` gitignored.
- Startup fails fast if required env vars missing.
- CI grep for common secret patterns → build fails.

---

## US-P-09 — DTO validation on every endpoint
**As** the platform, **I want** every API DTO validated via `class-validator`, **so that** malformed input is rejected uniformly.
Priority: Must — trace: FR-P-08, NFR-07

**Acceptance criteria**
- Every controller uses a DTO class with class-validator decorators.
- Global `ValidationPipe` with `whitelist: true, forbidNonWhitelisted: true, transform: true`.
- Validation errors return 400 with structured `{ field, message }` array.
- Contract test: sending unknown field → 400.

---

## US-P-10 — Transactional outbox for domain events
**As** the platform, **I want** every state-change service to write its Kafka event in the same Postgres tx as the domain change, **so that** we lose no events on crash.
Priority: Must — trace: FR-P-09, NFR-14

**Acceptance criteria**
- Every write path uses `outbox` helper: inserts `outbox_event(id, topic, key, payload, occurred_at, published_at NULL)` within the tx.
- Relay worker polls `published_at IS NULL`, publishes to Kafka, marks `published_at`.
- Crash simulation test: kill NestJS between domain write and publish → outbox relay eventually delivers on restart.
- No direct Kafka publish outside outbox (architecture test enforces).

---

## US-P-11 — Async search index update
**As** the platform, **I want** Elasticsearch updated from Kafka events, not synchronously from API writes, **so that** ES failures don't block writes.
Priority: Must — trace: FR-P-10, NFR-13

**Acceptance criteria**
- `product.changed`, `offer.changed`, `inventory.changed`, `moderation.listing.removed` consumers project into ES.
- Write API returns without awaiting ES.
- p95 lag ≤ 5s between event and ES visibility.
- ES down → consumer retries with backoff; poison messages → DLQ.

---

## US-P-12 — Notifications via Kafka consumers
**As** the platform, **I want** email and in-app notifications driven by Kafka consumers, not inline handlers, **so that** slow SMTP doesn't block user requests.
Priority: Must — trace: FR-P-11

**Acceptance criteria**
- `order.placed`, `order.shipped`, `order.delivered`, `order.refunded`, `seller.kyc.decided`, `inventory.low_stock`, `moderation.listing.removed` each have a notification consumer.
- Consumers idempotent on `event_id` (dedupe table 7-day TTL).
- SMTP failure → retry 3× exponential; then DLQ `email.outbound.dlq` with alert.

---

## US-P-13 — Event envelope + idempotency
**As** the platform, **I want** every event to carry `event_id`, `correlation_id`, `occurred_at`, and consumers idempotent on `event_id`, **so that** at-least-once delivery is safe.
Priority: Must — trace: FR-P-12, NFR-14

**Acceptance criteria**
- Avro schema per topic in Confluent Schema Registry; envelope fields required.
- Consumer template: dedupe → handle → commit offset. Dedupe uses `processed_events(event_id, consumer_group, processed_at)` with 7-day TTL cleanup.
- Contract test: same event replayed twice → single side-effect.

---

## US-P-14 — Dead-letter topics
**As** the platform, **I want** poison messages routed to per-consumer DLQs with alerting, **so that** one bad message doesn't stall a topic.
Priority: Should — trace: FR-P-13, NFR-15

**Acceptance criteria**
- Consumer unhandled exception → publish original + error metadata to `<consumer_group>.dlq` → commit original offset.
- DLQ non-empty → alert (Kafka UI + log warn).
- Manual reprocessing tool documented in ops README.
