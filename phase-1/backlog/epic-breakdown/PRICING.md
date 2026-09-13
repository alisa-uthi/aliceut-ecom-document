# EPIC: PRICING — Pricing Module

**Sprint:** 3
**Lib:** `libs/pricing/`
**Module:** `PricingModule`
**Controllers:** `PricingController` (seller)
**Kafka producers:** `fx_rate.updated` (via workers scheduler)

Overview: Manages multi-currency offer prices (LIST/SALE/B2B_TIER), FX rate cache, and effective price resolution. Price is NEVER stored on Product. The effective price resolution (B2B_TIER → SALE → LIST) is a core service used by the Cart and Checkout modules. All monetary values use NUMERIC(19,4) and decimal.js.

---

### PRICING-001 — pricing Schema Migrations
**US Ref:** —
**Estimate:** M
**Dependencies:** PLATFORM-001
**Implementation Notes:**
- File: `libs/pricing/src/infrastructure/migrations/0001_pricing_schema.sql`
- Tables: `pricing.currency`, `pricing.offer_price`, `pricing.fx_rate`
- All columns/constraints per data-model-erd.md pricing section
- Unique constraint on `offer_price`: `(offer_id, currency_code, price_type, min_qty)` — prevents duplicate price rows
- `price_type` uses `price_type` enum (defined in PLATFORM-001)
- FK: `offer_price.offer_id → catalog.offer(id)` — cross-schema FK; applied after catalog schema exists
- `fx_rate` PK: `(base_currency_code, quote_currency_code)` — one row per pair; upsert on refresh

**Done Criteria:**
- Pricing tables created; `INSERT INTO pricing.currency VALUES ('USD', 2, true)` succeeds

---

### PRICING-002 — Currency Seed
**US Ref:** US-P-06a
**Estimate:** S
**Dependencies:** PRICING-001
**Implementation Notes:**
- Seeded in `npm run seed` (see SEED-003); content defined here
- Rows: `(USD, 2, true)`, `(THB, 2, true)`, `(JPY, 0, true)`, `(SGD, 2, true)`
- Additional display-only currencies: `(EUR, 2, false)`, `(GBP, 2, false)`, `(AUD, 2, false)` — so FX table can store rates for buyer display (V1 restriction: only USD/THB/JPY/SGD for seller pricing; all currencies allowed for display)
- `is_seller_price_allowed = false` for non-V1 currencies

**Done Criteria:**
- `SELECT * FROM pricing.currency` shows USD, THB, JPY, SGD with correct `minor_unit_scale` values

---

### PRICING-003 — OfferPrice Entity + Repository Interface
**US Ref:** US-P-01
**Estimate:** M
**Dependencies:** PRICING-001
**Implementation Notes:**
- TypeORM entity for `pricing.offer_price`
- `amount NUMERIC(19,4)` mapped as `string` by TypeORM (use `transformer` to keep as string; never convert to JS number)
- `OfferPriceRepository` interface: `findByOffer(offerId)`, `findEffectivePrice(offerId, priceType, currencyCode, qty, now)`, `save(price)`, `delete(id)`
- Validation on `SALE` price: `starts_at < ends_at` enforced at domain level
- Validation on `B2B_TIER`: `min_qty >= 2` enforced
- At most one active `LIST` price per offer per currency (unique constraint in DB handles this; application returns clear 409)

**Done Criteria:**
- Unit test: creating duplicate LIST price for same offer+currency returns 409
- `amount` field is always a string, never a JS number, in TypeScript code

---

### PRICING-004 — Pricing CRUD Endpoints (Seller)
**US Ref:** US-S-04b
**Estimate:** L
**Dependencies:** PRICING-003, SELLER-008
**Implementation Notes:**
- Endpoints under `/seller/offers/:offerId/prices`
- `GET /seller/offers/:offerId/prices` — list all price rows for the offer
- `POST /seller/offers/:offerId/prices` — create new price row; DTO: `CreatePriceDto { currencyCode, amount (string), priceType, minQty?, startsAt?, endsAt? }`
- `PUT /seller/offers/:offerId/prices/:priceId` — edit existing price; same validation
- `DELETE /seller/offers/:offerId/prices/:priceId` — delete; cannot delete last LIST price
- Ownership check: authenticated seller must own the offer; 404 if not
- On any price change: publish `offer.changed` event via outbox (price changes affect ES display_prices)
- Warning to seller: price change does not affect PENDING order snapshots (FR-P-03)

**Done Criteria:**
- Cannot delete last LIST price → 422 "At least one LIST price is required"
- SALE with `starts_at >= ends_at` → 400
- `offer.changed` event published after price create/update/delete

---

### PRICING-005 — Effective Price Resolution Service
**US Ref:** US-P-01, US-B-05
**Estimate:** L
**Dependencies:** PRICING-003
**Implementation Notes:**
- `EffectivePriceService.resolve(offerId, context: { accountType, qty, now, preferredCurrency }): ResolvedPrice`
- Priority order:
  1. `B2B_TIER` — if `accountType = B2B` AND `qty >= price.min_qty` AND currency = preferredCurrency (or any)
  2. `SALE` — if `now >= starts_at AND now <= ends_at` AND currency match
  3. `LIST` — always the fallback
- If no price exists in `preferredCurrency`: apply FX conversion to cheapest available price; return with `isConverted: true, estimatedSymbol: '≈'`
- Returns `{ amount: string, currencyCode: string, priceType, isConverted, originalAmount?, originalCurrencyCode?, fxRate? }`
- Used by: PDP (US-B-05), Cart (US-B-06 re-resolve on load), Checkout (US-B-09 revalidation)

**Done Criteria:**
- Unit test: B2B buyer with qty=15 gets B2B_TIER price over active SALE price
- Unit test: buyer with no price in preferred currency gets converted estimate with `isConverted: true`

---

### PRICING-006 — FxRate Entity + Repository
**US Ref:** US-P-02
**Estimate:** M
**Dependencies:** PRICING-001
**Implementation Notes:**
- TypeORM entity for `pricing.fx_rate`; composite PK `(base_currency_code, quote_currency_code)`
- `rate NUMERIC(19,8)` mapped as string; do NOT use JS float
- `FxRateRepository`: `upsert(baseCurrency, quoteCurrency, rate, asOf)`, `findRate(base, quote)`, `findAllRates()`, `getLatestAsOf(base, quote)`
- On upsert: `INSERT ... ON CONFLICT (base, quote) DO UPDATE SET rate = $3, as_of = $4, updated_at = now()`
- Staleness check: `now() - as_of < STALENESS_THRESHOLD` (configurable; default 4h)

**Done Criteria:**
- Upsert rate: second upsert updates `as_of` and `rate`; only one row per currency pair
- `rate` is always a string in TypeScript (decimal.js for arithmetic)

---

### PRICING-007 — FX Display Conversion Helper
**US Ref:** US-P-02
**Estimate:** M
**Dependencies:** PRICING-006
**Implementation Notes:**
- `FxConversionService.convert(amount: string, fromCurrency: string, toCurrency: string): ConversionResult`
- Returns `{ convertedAmount: string, rate: string, isStale: boolean, isConverted: true }`
- If `fromCurrency === toCurrency`: return `{ convertedAmount: amount, rate: '1', isConverted: false }`
- If no rate found or stale: return `{ convertedAmount: null, isConverted: false }` (hide conversion)
- All arithmetic with `decimal.js`: `new Decimal(amount).mul(new Decimal(rate)).toFixed(targetScale)`
- `targetScale` = `Currency.minor_unit_scale` for target currency (JPY=0, USD/THB/SGD=2)

**Done Criteria:**
- Unit test: convert `"100.00" USD → THB` with rate `"34.5000"` returns `"3450.00"` (not float 3449.9999...)
- JPY: result is rounded to 0 decimal places

---

### PRICING-008 — FX Rate Refresh Scheduler
**US Ref:** US-P-19
**Estimate:** M
**Dependencies:** PRICING-006, PLATFORM-005
**Implementation Notes:**
- File: `apps/workers/src/schedulers/fx-rate.scheduler.ts`
- `@Cron('0 * * * *')` — hourly; configurable via `FX_REFRESH_CRON` env var
- Fetch from `exchangerate.host/latest?base=USD&symbols=THB,JPY,SGD` (and similar for other base currencies); or use a single base and compute cross-rates
- On success: upsert all 4 base-currency × N quote-currency rate pairs via `FxRateRepository.upsert()`; publish `fx_rate.updated` outbox event
- On API failure: log error + alert; retain last known rates (do NOT zero out on failure)
- Env vars: `FX_API_URL` (default `https://api.exchangerate.host/latest`), `FX_API_KEY` (optional; free tier may not need key), `FX_STALENESS_THRESHOLD_HOURS` (default 4)

**Done Criteria:**
- Scheduler runs on startup (or after first interval); rates populated in DB; `fx_rate.updated` event in outbox
- API failure does not clear existing rates

---

### PRICING-009 — Outbox Event: fx_rate.updated
**US Ref:** US-P-19, US-P-11
**Estimate:** S
**Dependencies:** PLATFORM-004
**Implementation Notes:**
- Avro schema `fx_rate.updated` (v1): `{ base_currency, rates: [{ quote_currency, rate, as_of }], refreshed_at }`
- Published by FX scheduler (PRICING-008) when rates are fetched
- Consumer in Search module (SEARCH-012) uses this to refresh `display_prices` map in ES
- Schema registered in Schema Registry on app startup

**Done Criteria:**
- `fx_rate.updated` event appears in Kafka UI after scheduler runs
- Schema Registry shows the schema registered
