# Pricing Model and Price Resolution

**References:** US-P-01, US-P-02, US-S-03, US-S-04b, US-B-06  

## Key invariants

- Cart and FulfillmentItem reference **Offer**, never Product; price is never stored on Product (FR-P-01)
- Seller pricing currencies: USD, THB, JPY, SGD only (FR-P-06a); buyer display currency may differ — converted via FX, never stored
- Checkout captures offer-currency price + FX rate at capture time; display conversions are ephemeral and never stored (FR-P-03)
- Price priority: B2B_TIER (B2B buyer + qty >= min_qty) beats SALE (within time window) beats LIST
- SALE must have starts_at < ends_at; system auto-reverts to LIST after ends_at; overlapping SALE periods for same currency rejected
- At most one active LIST price per offer per currency; second LIST in same currency rejected with explicit error
- FX stale: show offer-currency price only, no estimate — prevents misleading display conversions

## Diagram

```mermaid
graph TD
    subgraph DM["DATA MODEL"]
        PRODUCT["Product\nno price stored here"]
        OFFER["Offer\nper seller"]
        PRICE["Price\nper currency / per price_type"]
        PT_LIST["LIST\ndefault / always required"]
        PT_SALE["SALE\ntime-bounded\nstarts_at / ends_at"]
        PT_B2B["B2B_TIER\nmin_qty >= 2"]
        CCY["Currencies\nUSD / THB / JPY / SGD"]
        CART["Cart / FulfillmentItem"]
        PRODUCT -->|"has many"| OFFER
        OFFER -->|"has many"| PRICE
        PRICE -->|"price_type"| PT_LIST
        PRICE -->|"price_type"| PT_SALE
        PRICE -->|"price_type"| PT_B2B
        PT_LIST -->|"scoped to"| CCY
        PT_SALE -->|"scoped to"| CCY
        PT_B2B -->|"scoped to"| CCY
        CART -->|"references"| OFFER
        CART -. "NEVER references" .-> PRODUCT
    end

    subgraph PR["PRICE RESOLUTION - Decision Tree"]
        BV["Buyer views Offer\nquantity = Q"]
        B2B_Q{"Buyer is B2B\nAND Q >= B2B_TIER.min_qty\nAND B2B_TIER price exists?"}
        SALE_T{"Current time within\nSALE starts_at / ends_at?"}
        EP_B2B["Use B2B_TIER price"]
        EP_SALE["Use SALE price"]
        EP_LIST["Use LIST price"]
        BV --> B2B_Q
        B2B_Q -->|"Yes"| EP_B2B
        B2B_Q -->|"No"| SALE_T
        SALE_T -->|"Yes"| EP_SALE
        SALE_T -->|"No"| EP_LIST
    end

    subgraph FX["FX DISPLAY FLOW"]
        EFF["Effective price resolved\nin offer currency"]
        CCY_Q{"Price exists in\nbuyer preferred currency?"}
        STALE_Q{"FX rate stale?\nabove staleness threshold?"}
        EXACT["Show exact price\nin buyer preferred currency"]
        APPROX["Convert via cached FX rate\nPrefix approx / Tooltip: Estimated in CCY"]
        OFFER_ONLY["Show offer-currency price only\nno estimate shown"]
        CHECKOUT["Checkout capture\noffer-currency price\n+ FX rate snapshot at capture\nImmutable - never re-derived"]
        EFF --> CCY_Q
        CCY_Q -->|"Yes"| EXACT
        CCY_Q -->|"No"| STALE_Q
        STALE_Q -->|"No - rate is fresh"| APPROX
        STALE_Q -->|"Yes - rate is stale"| OFFER_ONLY
        EXACT -->|"buyer confirms"| CHECKOUT
        APPROX -->|"display-only / buyer confirms"| CHECKOUT
        OFFER_ONLY -->|"buyer confirms"| CHECKOUT
    end

    EP_B2B --> EFF
    EP_SALE --> EFF
    EP_LIST --> EFF
```
