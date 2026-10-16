# ADR-0016: Every seller-currency FX pair is derived from one USD-based quote

**Status:** Accepted
**Date:** 2026-10-16
**Affects:** `phase-1/technical-design/data-model-erd.md` (`pricing.fx_rate`), `phase-1/technical-design/kafka-events.md` (§ 2.20 `fx_rate.updated`)
**Implemented by:** aliceut-ecom-backend#69

## Context

`pricing.fx_rate` is keyed `(base_currency_code, quote_currency_code)`, and
the ERD defines the base as the **seller's native pricing currency** (one of
USD, THB, JPY, SGD) and the quote as the buyer's display currency. Every
reader follows that: effective-price, catalog offers, cart and checkout read
the row `base = offer currency, quote = display currency`, and the search
indexer reprices offers whose native currency is the event's base.

The FX-refresh scheduler asked the provider for `base=USD` only and stored
the three USD-based rows. Nothing derived the others. An offer priced in THB,
JPY or SGD therefore had no display price in any other currency
(`displayAmount: null`), no display-currency price filter in search could
match it, and checkout of such an offer for a buyer in another currency
failed with `422`. The design never said where the nine non-USD pairs come
from. `spec-compliance.md` entry 1 recorded the gap.

FR-P-04 already anticipates inverse rates: rates are `NUMERIC(19,8)` because
an inverse against a zero-decimal currency (JPY to USD, about `0.00636`)
loses 0.6% at four digits.

## Decision

The scheduler makes **one** provider call with base `USD` and fills every
ordered pair `(B, Q)` of seller-price currencies with `B ≠ Q` — twelve rows
for V1:

- `USD → Q` is the provider's rate.
- `B → USD` is `1 / (USD → B)`.
- `B → Q` is `(USD → Q) / (USD → B)`.

Each derived rate is computed in `decimal.js` from the provider's unrounded
strings and rounded **once** to 8 fractional digits, half-up (ADR-0008). Every
row written in a refresh carries the provider response's `as_of` and
`provider`. A currency the provider omits is skipped together with every pair
that involves it, so its stored rows keep their old values and go stale
normally. The refresh emits **one `fx_rate.updated` per base currency**, in
the same transaction as the upserts, each carrying that base's refreshed
quotes — which is what the `search.fx-rate-updated` side effect in § 2.20
already expects. The ERD `pricing.fx_rate` section and kafka-events.md
§ 2.20 now state this.

## Consequences

**Every offer has a display price in every V1 currency** once a refresh has
run. Search price filters, effective-price, catalog, cart and checkout work
for non-USD sellers without any reader changing.

**Cross rates are synthetic.** A THB → JPY rate is two USD quotes divided, not
a market quote, so it can differ slightly from a direct THB/JPY quote. This is
acceptable for a display-only cache; order amounts are snapshotted at
capture (FR-P-03), and `fx_rate_used_at_capture` records whichever rate was
used.

**Inverse and cross rates are mutually consistent.** All twelve come from the
same three numbers at one `as_of`, so `A → B × B → A` equals 1 within 8-dp
rounding, which fetching per base would not guarantee.

**Four events per refresh instead of one.** The search consumer reprices one
base currency's offers per event, so the total work is the same as one event
covering all bases; the event count grows with the number of seller
currencies.

**Provider dependency stays at one call per hour.**

## Alternatives considered

**Fetch per base currency.** Four provider calls per refresh, no arithmetic.
Rejected: four times the calls against a free public API, and the pairs come
from four quotes taken at slightly different moments, so `A → B` and `B → A`
need not be inverses.

**Derive at read time.** Keep only USD rows and have each reader compute the
pair. Rejected: every reader (pricing, catalog, cart, checkout, search,
`offer.changed` producers) would need the same derivation, and the ERD's
"exactly one row per pair" read path would no longer hold.

**Do nothing.** Rejected: non-USD sellers' offers are invisible to price
filters and unpurchasable across currencies.
