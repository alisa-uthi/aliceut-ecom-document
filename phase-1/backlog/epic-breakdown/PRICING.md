# EPIC: PRICING — Pricing Module

**Sprint:** 7  
**Lib:** `libs/pricing/`  
**Module:** `PricingModule`  
**Controllers:** `PricingController`  
**Kafka producers:** `fx_rate.updated`  

Overview: Manages multi-currency offer prices, effective price resolution (LIST vs SALE vs B2B_TIER), FX display conversion, and FX rate refresh scheduling. Cart and checkout both call `EffectivePriceService` directly.

---

### PRICING-001 — pricing Schema Migrations

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** PLATFORM-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md` § pricing schema, `phase-1/technical-design/api-design/pricing.md`

**Implementation Notes:**
- File: `libs/pricing/src/infrastructure/migrations/0001_pricing_schema.sql`
- Tables: `pricing.currency`, `pricing.offer_price`, `pricing.fx_rate` — all three live in the `pricing` schema (not `platform`)
- Exact column list/types/constraints: see `data-model-erd.md` § pricing schema. Confirmed via `api-design/pricing.md`'s sequence diagrams: `offer_price` columns are `currency_code` (not `currency`), `starts_at`/`ends_at` (not `sale_starts_at`/`sale_ends_at`), unique constraint `(offer_id, currency_code, price_type, min_qty)`; `currency` column is `is_seller_price_allowed` (not `is_active`)
- Indexes: `offer_price(offer_id)`, `offer_price(offer_id, currency_code, price_type)`

**Done Criteria:**
- Tables created; unique constraint on `(offer_id, currency_code, price_type, min_qty)` enforced

---

### PRICING-002 — Currency Seed

- **US Ref:** US-P-06a
- **Estimate:** S
- **Dependencies:** PRICING-001
- **Spec References:** `phase-1/technical-design/api-design/pricing.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- Seed `pricing.currency` with V1 seller-allowed currencies: USD, THB, JPY, SGD (`minor_unit_scale` per currency; `is_seller_price_allowed = true`)
- Exact seed values/column names: see PRICING-001's note on `is_seller_price_allowed`
- `is_seller_price_allowed = false` currencies (if any added later) are blocked at pricing input validation

**Done Criteria:**
- `pricing.currency` has 4 rows with `is_seller_price_allowed = true` (USD, THB, JPY, SGD)

---

### PRICING-003 — OfferPrice Entity + Repository Interface

- **US Ref:** US-P-01
- **Estimate:** M
- **Dependencies:** PRICING-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md` § pricing schema

**Implementation Notes:**
- TypeORM entity for `pricing.offer_price` (fields per PRICING-001)
- `OfferPriceRepository` interface: `findByOfferId(offerId)`, `findActive(offerId, currencyCode, priceType)`, `save(price)`, `delete(id)`

**Done Criteria:**
- Repository methods covered by unit tests
- Duplicate `(offer_id, currency_code, price_type, min_qty)` → unique constraint error

---

### PRICING-004 — PUT /seller/offers/:id/prices/:type (Upsert Offer Price)

- **US Ref:** US-S-04b
- **Estimate:** L
- **Dependencies:** PRICING-003
- **Spec References:** `phase-1/technical-design/api-design/seller.md` § PUT /seller/offers/:offerId/prices/:priceType

**Implementation Notes:**
- Full contract (request/response, guard, sequence): see `api-design/seller.md`'s `PUT /seller/offers/:offerId/prices/:priceType` sequence — do not restate the full contract here.
- Single upsert endpoint per `api-design/seller.md`; listing prices is folded into `GET /seller/offers/:id` (SELLER-tasked), there is no standalone `POST`/`DELETE` for an individual price
- Guard: `@JwtAuthGuard` + `@Roles('SELLER')` + `SellerKycGuard` (SELLER_ACTIVE = approved + not suspended, per spec); ownership check — offer must belong to authenticated seller

**Done Criteria:**
- Per `api-design/seller.md`'s response/error list for `PUT /seller/offers/:offerId/prices/:priceType`
- Upsert on another seller's offer → 404

---

### PRICING-005 — Effective Price Resolution Service

- **US Ref:** US-P-01
- **Estimate:** L
- **Dependencies:** PRICING-003
- **Spec References:** `phase-1/technical-design/api-design/pricing.md` § GET /pricing/offers/:id/effective-price

**Implementation Notes:**
- File: `libs/pricing/src/application/effective-price.service.ts`
- Resolution order and field semantics: see `api-design/pricing.md`'s sequence — `B2B_TIER` (accountType=B2B, qty ≥ min_qty) → `SALE` (now between `starts_at`/`ends_at`) → `LIST` fallback. All arithmetic via `decimal.js`; no JS `number` on money.
- Used by: `GET /pricing/offers/:id/effective-price` (public), CartService, CheckoutService (ORDERS), `ProductsController` (CATALOG-007)

**Done Criteria:**
- Per `api-design/pricing.md`'s Errors + response shape for this endpoint
- Active SALE → returns SALE, not LIST; expired SALE → LIST; B2B tier match → B2B_TIER
- Decimal precision test: no floating-point drift

---

### PRICING-006 — FxRate Entity + Repository

- **US Ref:** US-P-02
- **Estimate:** M
- **Dependencies:** PRICING-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md` § pricing schema

**Implementation Notes:**
- TypeORM entity for `pricing.fx_rate` (`base_currency_code`, `quote_currency_code`, `rate NUMERIC(19,8)`, `as_of`, `updated_at`)
- `FxRateRepository` interface: `findRate(base, quote)`, `upsert(base, quote, rate, asOf)`, `findAllForBase(base)`

**Done Criteria:**
- Repository methods covered by unit tests

---

### PRICING-007 — FX Display Conversion Helper

- **US Ref:** US-P-02
- **Estimate:** M
- **Dependencies:** PRICING-006
- **Spec References:** `phase-1/technical-design/api-design/pricing.md` § GET /pricing/offers/:id/effective-price, § GET /pricing/fx-rates

**Implementation Notes:**
- FX display conversion rules (fresh vs. stale rate, same-currency passthrough, rounding to `minor_unit_scale`): see `api-design/pricing.md`'s effective-price sequence's FX display note
- Display-only — never stored; checkout always uses the seller's native price currency (`fulfillment_item.fx_rate_used_at_capture` is a separate checkout-time snapshot, not this helper)
- Backs `GET /pricing/fx-rates`: see `api-design/pricing.md` for exact response shape

**Done Criteria:**
- Per `api-design/pricing.md`'s field semantics for `displayAmount`/`displayCurrency`/`fxRate`/`fxRateStaleAt`
- Same-currency request → `fxRate = null`, `displayAmount = amount`

---

### PRICING-008 — FX Rate Refresh Scheduler (Workers)

- **US Ref:** US-P-19
- **Estimate:** M
- **Dependencies:** PRICING-006
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- Hourly cron (`0 * * * *`); first run immediately on startup; fetches rates from exchangerate.host
- On refresh: compare new rates to stored `pricing.fx_rate` rows; publish `fx_rate.updated` outbox event only when a rate changed (avoid noise)
- Consumed by SEARCH-012 (`search.fx-rate-updated` consumer group) to refresh display prices in the product index

**Done Criteria:**
- Hourly job runs; `pricing.fx_rate` updated
- Changed rate → `fx_rate.updated` outbox event written; unchanged rates → no event

---

### PRICING-009 — Outbox Event: fx_rate.updated

- **US Ref:** US-P-19
- **Estimate:** S
- **Dependencies:** PLATFORM-004
- **Spec References:** `phase-1/technical-design/kafka-events.md`

**Implementation Notes:**
- Avro schema and exact payload fields (base/quote currency pair, rate, `as_of`): see `phase-1/technical-design/kafka-events.md` § fx_rate.updated
- Written in the same transaction as the `pricing.fx_rate` upsert (PRICING-008)

**Done Criteria:**
- Schema registered in Schema Registry; event visible in Kafka UI within 2s of a changed-rate refresh

---

## Notes / Flagged Discrepancies (not silently resolved)

- **Task boundaries realigned to `backlog.md`.** The prior draft merged entity+controller work (old PRICING-003) and entity+helper work (old PRICING-005) into single tasks, and numbered the FX scheduler/outbox tasks one position off. Split back into `backlog.md`'s 9 discrete tasks (PRICING-001…009) exactly.
- **`pricing.fx_rate` lives in the `pricing` schema, not `platform`.** The prior draft assumed a `platform.fx_rate` table (defined in PLATFORM-001) and merely referenced it here. `backlog.md`'s PRICING-001 title lists `fx_rate` as part of the pricing schema migration — corrected.
- **Removed — no counterpart in `backlog.md` or `api-design/pricing.md`:** the prior draft's PRICING-008 ("Seller Pricing Sub-form Validation") and PRICING-009 ("GET /pricing/currencies"). Validation rules from the old PRICING-008 are still relevant but belong inside PRICING-004's controller, not a separate task. `GET /pricing/currencies` does not exist in `api-design/pricing.md`'s Endpoint Index (only `GET /pricing/offers/:id/effective-price` and `GET /pricing/fx-rates` are documented) and is not a `backlog.md` task — dropped rather than built.
- **Schema column names corrected:** `currency_code` (not `currency`), `starts_at`/`ends_at` (not `sale_starts_at`/`sale_ends_at`), `is_seller_price_allowed` (not `is_active`), unique constraint includes `min_qty`.
