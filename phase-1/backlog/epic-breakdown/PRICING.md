# EPIC: PRICING — Pricing Module

**Sprint:** 3  
**Lib:** `libs/pricing/`  
**Module:** `PricingModule`  
**Controllers:** `PricingController`  
**Kafka producers:** `fx_rate.updated`  

Overview: Manages multi-currency offer prices, effective price resolution (LIST vs SALE vs B2B_TIER), FX display conversion, and FX rate refresh scheduling. Cart and checkout both call `EffectivePriceService` directly.

---

### PRICING-001 — pricing Schema Migrations

- **US Ref:** —
- **Estimate:** S
- **Dependencies:** PLATFORM-001
- **Spec References:** `phase-1/technical-design/api-design/pricing.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- File: `libs/pricing/src/infrastructure/migrations/0001_pricing_schema.sql`
- Tables:
  - `pricing.offer_price`: id, offer_id FK, currency (CHAR 3), price_type (enum: `LIST`|`SALE`|`B2B_TIER`), amount NUMERIC(19,4), sale_starts_at nullable, sale_ends_at nullable, min_qty INT nullable (B2B only), created_at, updated_at
  - `pricing.currency`: code CHAR(3) PK, name, minor_unit_scale SMALLINT (USD=2, JPY=0, BHD=3), is_active bool
- Unique constraint on `offer_price(offer_id, currency, price_type)` for LIST type; for SALE allow multiple (by time range); B2B allow multiple (by min_qty tiers)
- Index: `offer_price(offer_id)`, `offer_price(offer_id, currency, price_type)`

**Done Criteria:**
- Tables created; unique constraint on `offer_id + currency + LIST` enforced

---

### PRICING-002 — Currency Seed

- **US Ref:** —
- **Estimate:** S
- **Dependencies:** PRICING-001
- **Spec References:** `phase-1/technical-design/api-design/pricing.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- Seed `pricing.currency` with V1 supported currencies:
  ```sql
  INSERT INTO pricing.currency (code, name, minor_unit_scale, is_active) VALUES
    ('USD', 'US Dollar', 2, true),
    ('THB', 'Thai Baht', 2, true),
    ('JPY', 'Japanese Yen', 0, true),
    ('SGD', 'Singapore Dollar', 2, true);
  ```
- `is_active = false` currencies are blocked at pricing input validation

**Done Criteria:**
- `GET /pricing/currencies` returns 4 active currencies

---

### PRICING-003 — OfferPrice Entity + PricingController (seller CRUD)

- **US Ref:** US-S-05
- **Estimate:** L
- **Dependencies:** PRICING-001, CATALOG-008
- **Spec References:** `phase-1/technical-design/api-design/pricing.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- TypeORM entity for `pricing.offer_price`
- `PricingController` (prefix `/seller/offers/:offerId/prices`); all endpoints guarded by `@JwtAuthGuard` + `@Roles('SELLER')` + `SellerKycGuard`; ownership check: offer must belong to authenticated seller
- `GET /seller/offers/:offerId/prices` — list all prices for offer
- `POST /seller/offers/:offerId/prices { currency, priceType, amount, saleStartsAt?, saleEndsAt?, minQty? }`:
  - Validate currency in `pricing.currency WHERE is_active = true`
  - Validate amount > 0; type is decimal string (e.g. `"29.99"`)
  - SALE type: require `saleStartsAt < saleEndsAt`; check no overlapping SALE for same currency
  - B2B_TIER: require `minQty >= 2`
  - Upsert LIST price (one per currency per offer); insert SALE/B2B_TIER
- `PUT /seller/offers/:offerId/prices/:priceId` — update single price
- `DELETE /seller/offers/:offerId/prices/:priceId` — delete SALE/B2B_TIER only (LIST cannot be deleted alone; soft-delete offer instead)

**Done Criteria:**
- Create LIST price for offer → price row created
- Create SALE without dates → 400
- Overlapping SALE for same currency → 409
- Access another seller's offer prices → 404

---

### PRICING-004 — EffectivePriceService (price resolution)

- **US Ref:** US-B-05, US-B-06, US-S-05
- **Estimate:** L
- **Dependencies:** PRICING-001, SHARED-001
- **Spec References:** `phase-1/technical-design/api-design/pricing.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- File: `libs/pricing/src/application/effective-price.service.ts`
- `EffectivePriceService.resolve(offerId: string, context: PriceResolutionContext): Promise<MoneyVO>`:
  - `PriceResolutionContext { accountType: 'BUYER'|'B2B'|'SELLER', qty: number, preferredCurrency: string, now?: Date }`
  - Resolution order:
    1. If `accountType = 'B2B'`: find highest `min_qty` B2B_TIER price where `min_qty <= qty` for preferred currency
    2. If active SALE exists (now between `sale_starts_at` and `sale_ends_at`): use SALE price
    3. Otherwise: use LIST price
  - If no price for `preferredCurrency`: fall back to `USD` LIST price
  - Return `MoneyVO` with amount and currency
  - All arithmetic via `decimal.js`; no JS `number` operations on money
- Used by: CartService (GET /cart), CheckoutService (ORDERS-004), ProductsController (CATALOG-007)

**Done Criteria:**
- Active SALE price exists → returns SALE price (not LIST)
- Expired SALE → returns LIST
- B2B account with qty=5, tier at min_qty=5 → returns B2B_TIER price
- No price for currency → falls back to USD LIST
- Returns MoneyVO (decimal precision test: no floating point)

---

### PRICING-005 — FxRate Entity + FX Display Conversion Helper

- **US Ref:** US-B-05
- **Estimate:** M
- **Dependencies:** PLATFORM-005, SHARED-001
- **Spec References:** `phase-1/technical-design/api-design/pricing.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- TypeORM entity for `platform.fx_rate` (already in PLATFORM-001; entity defined here for use in pricing module)
- `FxDisplayService.convert(amount: MoneyVO, toCurrency: string): Promise<MoneyVO>`:
  - Reads from `platform.fx_rate`; uses PLATFORM-005 service
  - Convert via: `amount * rate(base=amount.currency, quote=toCurrency)`
  - If `toCurrency = amount.currency`: return unchanged
  - Rounds to `minor_unit_scale` digits for display (e.g. JPY rounds to 0 decimal places)
  - Used only for *display* — never stored; checkout always uses seller's native price currency
- `GET /pricing/fx-rates` (public) — returns current rates table; cached 5min in Redis

**Done Criteria:**
- `convert(new MoneyVO("100", "USD"), "THB")` returns MoneyVO with THB amount matching current rate
- JPY result rounds to whole number
- Rates endpoint responds 200 with current rates

---

### PRICING-006 — FX Rate Refresh Scheduler (Workers)

- **US Ref:** US-P-17
- **Estimate:** M
- **Dependencies:** PLATFORM-005
- **Spec References:** `phase-1/technical-design/api-design/pricing.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- Delegates to `FxRateService.refresh()` from PLATFORM-005
- Worker cron: `0 * * * *` (hourly); first run immediately on startup
- On refresh: compare new rates to stored rates; if any rate changed by > 0.01%: publish `fx_rate.updated` outbox event
- `fx_rate.updated` payload: `{ rates: [{ base, quote, rate, fetchedAt }], changedAt }`
- SEARCH module consumer (SEARCH-007) re-indexes USD prices on this event

**Done Criteria:**
- Hourly job runs; rate table updated
- Changed rate → `fx_rate.updated` outbox event written
- Unchanged rates → no outbox event (avoid noise)

---

### PRICING-007 — Outbox Event: fx_rate.updated

- **US Ref:** FR-P-09
- **Estimate:** S
- **Dependencies:** SHARED-005, PLATFORM-005
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/data-model-erd.md`

**Implementation Notes:**
- `fx_rate.updated` Avro schema registered with Schema Registry:
  ```json
  {
    "type": "record",
    "name": "FxRateUpdated",
    "namespace": "com.aliceut.events",
    "fields": [
      { "name": "event_id", "type": "string" },
      { "name": "occurred_at", "type": "long", "logicalType": "timestamp-millis" },
      {
        "name": "rates",
        "type": { "type": "array", "items": {
          "type": "record", "name": "FxRatePair",
          "fields": [
            { "name": "base_currency", "type": "string" },
            { "name": "quote_currency", "type": "string" },
            { "name": "rate", "type": "string" }
          ]
        }}
      }
    ]
  }
  ```
- Written by FxRateService via `OutboxEventWriter.write()` in same transaction as `platform.fx_rate` update

**Done Criteria:**
- Schema registered in Schema Registry under `fx_rate.updated-value`
- Kafka UI shows `fx_rate.updated` message after hourly refresh runs

---

### PRICING-008 — Seller Pricing Sub-form Validation (Backend)

- **US Ref:** US-S-05
- **Estimate:** S
- **Dependencies:** PRICING-003
- **Spec References:** `phase-1/technical-design/api-design/pricing.md`

**Implementation Notes:**
- Validation rules enforced in `PricingController`:
  - Amount: decimal string, > 0, max 9 digits before decimal, max 4 after
  - Currency: must be in active currencies (USD/THB/JPY/SGD)
  - SALE period: `saleStartsAt` must be future; `saleEndsAt > saleStartsAt`; period max 90 days
  - B2B min_qty: integer ≥ 2; multiple tiers must have distinct min_qty values
  - Cannot set LIST price to 0 (use offer deactivation instead)
- All validation errors return structured `{ field, message }` array in 400 response

**Done Criteria:**
- Amount "0.00" → 400
- Sale end before start → 400
- B2B min_qty = 1 → 400
- Two B2B tiers with same min_qty → 409

---

### PRICING-009 — GET /pricing/currencies (public)

- **US Ref:** —
- **Estimate:** S
- **Dependencies:** PRICING-002
- **Spec References:** `phase-1/technical-design/api-design/pricing.md`

**Implementation Notes:**
- `GET /pricing/currencies` — public (`@Public()`); returns active currencies
- Response: `[{ code, name, minorUnitScale }]` — only `is_active = true` rows
- Cached in Redis 1h (rarely changes)
- Used by frontend currency selector in pricing sub-form and price display

**Done Criteria:**
- Returns 4 active currencies
- Response cached in Redis (second call hits cache, not DB)
