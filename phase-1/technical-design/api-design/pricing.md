# Pricing API

**Module:** `Pricing`  
**Parent:** [API Design Index](../api-design.md)  
**Source of truth:** [BRD v1.1](../../requirements/BRD.md), [ERD](../data-model-erd.md)

---

## Endpoint Index

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | [`/pricing/offers/:id/effective-price`](#get-effective-price) | PUBLIC | Resolve effective price (LIST / SALE / B2B_TIER) with optional FX display |
| `GET` | [`/pricing/fx-rates`](#list-fx-rates) | PUBLIC | Display-only FX rate cache |

---

## DB Mapping

| Endpoint | Primary DB | Tables |
|----------|-----------|--------|
| `GET /pricing/offers/:id/effective-price` | Postgres | `pricing.offer_price` (resolve by account type + time + qty), `pricing.fx_rate` (display conversion), `pricing.currency` |
| `GET /pricing/fx-rates` | Postgres | `pricing.fx_rate`, `pricing.currency` (read-only cache) |

**Note:** FX rates are display-only. They are never used to reprice orders. `fulfillment_item.fx_rate_used_at_capture` is a separate snapshot taken at checkout time.

---

## Endpoints

### Get effective price

```
GET /pricing/offers/:offerId/effective-price
Tag: Pricing
Auth: PUBLIC (buyer account type from JWT if authenticated)
```
**Query params**
- `currency`: `USD | THB | JPY | SGD` (required) — **buyer's requested display currency**
- `qty`: integer ≥ 1 (default 1)
- `accountType`: `B2C | B2B` (default B2C; overridden by JWT if authenticated)

**Response 200**
```json
{
  "data": {
    "offerId": "uuid",
    "amount": "99.99",
    "currency": "USD",
    "priceType": "LIST | SALE | B2B_TIER",
    "saleEndsAt": "ISO8601 | null",
    "minQty": 1,
    "displayCurrency": "THB",
    "displayAmount": "3440.00",
    "fxRate": "34.40000000",
    "fxRateStaleAt": "ISO8601 | null"
  }
}
```
**Field semantics:**
- `amount` / `currency` — seller's native pricing currency (the price row stored in `pricing.offer_price`)
- `displayCurrency` / `displayAmount` / `fxRate` / `fxRateStaleAt` — buyer's requested display currency (FX-converted, display-only). Omitted when `currency` param matches the offer's native currency (no conversion needed). `fxRateStaleAt` is set (and `displayAmount` omitted) when the FX rate is missing or stale.
**Errors:** 404 offer not found, 422 currency not supported

#### Sequence

```mermaid
sequenceDiagram
    participant Client
    participant API as API (NestJS)
    participant PricingService
    participant Postgres

    Client->>API: GET /pricing/offers/:offerId/effective-price?currency=THB&qty=2&accountType=B2B
    Note over API: PUBLIC — no auth guard. If valid JWT present, accountType is overridden from token claims (B2C or B2B)
    API->>PricingService: getEffectivePrice({ offerId, currency, qty, accountType })

    PricingService->>Postgres: SELECT id, status FROM catalog.offer WHERE id = :offerId
    Postgres-->>PricingService: offer row

    alt offer not found or status != ACTIVE
        PricingService-->>API: not found
        API-->>Client: 404 offer not found
    else offer is active
        PricingService->>Postgres: SELECT code, minor_unit_scale FROM pricing.currency<br/>WHERE code = :currency AND is_seller_price_allowed = true
        Postgres-->>PricingService: currency row

        alt currency not supported (not in USD, THB, JPY, SGD)
            PricingService-->>API: unsupported currency
            API-->>Client: 422 currency not supported
        else currency valid
            PricingService->>Postgres: SELECT price_type, amount, currency_code, min_qty, starts_at, ends_at<br/>FROM pricing.offer_price WHERE offer_id = :offerId AND currency_code = :currency
            Postgres-->>PricingService: price rows (LIST#59; optionally SALE and B2B_TIER)

            alt no LIST row exists for requested currency
                PricingService-->>API: no price in this currency
                API-->>Client: 404 offer not found
            else price rows present
                Note over PricingService: Price resolution (decimal.js arithmetic): Step 1 — B2B_TIER: accountType = B2B AND B2B_TIER row exists AND qty >= B2B_TIER.min_qty — selectedPrice = B2B_TIER row. Step 2 — SALE: SALE row exists AND NOW() BETWEEN starts_at AND ends_at — selectedPrice = SALE row — saleEndsAt = ends_at. Step 3 — Fallback: selectedPrice = LIST row

                alt requestedCurrency is offer native currency (no FX conversion)
                    PricingService-->>API: effective price result (no display conversion)
                else requestedCurrency differs from offer native currency
                    PricingService->>Postgres: SELECT rate, as_of, updated_at FROM pricing.fx_rate<br/>WHERE base_currency_code = :offerCurrency AND quote_currency_code = :displayCurrency
                    Postgres-->>PricingService: FX rate row (or empty)
                    Note over PricingService: FX is display-only — never used to reprice orders. If stale or missing: fxRateStaleAt set — displayAmount omitted. If fresh: displayAmount = amount x rate (decimal.js)
                    PricingService-->>API: effective price with optional FX display conversion
                end

                API-->>Client: 200 { data: { offerId, amount, currency, priceType, saleEndsAt,<br/>minQty, displayCurrency, displayAmount, fxRate, fxRateStaleAt } }
            end
        end
    end
```

---

### List FX rates

```
GET /pricing/fx-rates
Tag: Pricing
Auth: PUBLIC
```
**Query params:** `base` (default USD)  
**Response 200**
```json
{
  "data": {
    "baseCurrency": "USD",
    "rates": [
      { "quoteCurrency": "THB", "rate": "34.40000000", "asOf": "ISO8601" }
    ]
  }
}
```

#### Sequence

```mermaid
sequenceDiagram
    participant Client
    participant API as API (NestJS)
    participant PricingService
    participant Postgres

    Client->>API: GET /pricing/fx-rates?base=USD
    Note over API: PUBLIC — no auth guard
    API->>PricingService: getFxRates(base)
    PricingService->>Postgres: SELECT fx.quote_currency_code, fx.rate, fx.as_of<br/>FROM pricing.fx_rate fx<br/>JOIN pricing.currency c ON c.code = fx.quote_currency_code<br/>WHERE fx.base_currency_code = :base AND c.is_seller_price_allowed = true
    Postgres-->>PricingService: FX rate rows for seller-allowed currencies (USD, THB, JPY, SGD)
    Note over PricingService: FX rates are a display-only cache. Never used to reprice orders (order repricing uses fulfillment_item.fx_rate_used_at_capture snapshot)
    PricingService-->>API: rates array
    API-->>Client: 200 { data: { baseCurrency: "USD", rates: [{ quoteCurrency, rate, asOf }] } }
```
