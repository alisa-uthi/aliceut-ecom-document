# ADR-0011: A null preferred currency resolves from Accept-Language everywhere

**Status:** Accepted
**Date:** 2026-10-15
**Affects:** `phase-1/technical-design/api-design/catalog.md` (§ Get product offers), `phase-1/technical-design/api-design/cart.md` (§ Display currency, § Get cart sequence), `phase-1/technical-design/api-design/orders.md` (§ Place order field semantics and sequence)
**Implemented by:** aliceut-ecom-backend#54

## Context

`identity.user.preferred_currency` is `NULL` for the "Auto" setting, which is
also the default. US-B-01, profile.md and the buyer-portal design all define
Auto the same way: the display currency is the currency of the browser's
`Accept-Language` locale, falling back to `USD` when that currency is not one
the platform prices in.

The API documents did not agree with that. cart.md and the orders.md
checkout sequence said a `NULL` preference "falls back to `USD`", and
catalog.md said `GET /catalog/products/:id/offers` defaults to the
preference "otherwise `USD`". The code had already split: checkout
(backend#38) and the cart preview (backend#53) resolved Auto from
`Accept-Language`, as US-P-03 requires for the captured currency, while the
catalog offers route followed catalog.md and used `USD`. So a buyer on the
Auto setting with a Thai browser saw a product's offers in USD, and then saw
the same offers in THB in their cart and order. The mismatch surfaced while
catalog response models were being fixed (backend#49).

## Decision

The user chose Accept-Language. Wherever a display currency defaults from the
buyer's preference, a `NULL` preference, and an anonymous caller where the
route is public, resolves by the Auto rule: the currency of the highest-ranked
`Accept-Language` locale, or `USD` when there is no header or that currency is
not one of `USD`, `THB`, `JPY`, `SGD`. `USD` survives only as the last step of
that rule, never as the direct fallback for a `NULL`. An explicit `?currency=`
still wins where a route takes one. catalog.md § Get product offers, cart.md
§ Display currency and its Get cart sequence, and the orders.md Place order
field semantics and sequence now state this. pricing.md needed no change: it
takes `currency` as a required parameter and has no preference default.

## Consequences

**One currency per buyer.** Browse, cart and checkout now show an Auto buyer
the same display currency, and it is the one checkout captures, so the cart
preview never promises a currency the order will not use.

**The result depends on a request header.** Two requests from the same buyer
with different `Accept-Language` values can render different display
currencies, and a response that defaults its currency is no longer a function
of the URL and the token alone. A cache in front of these routes would have
to vary on `Accept-Language`; none exists in V1. Clients must send the header,
which browsers do by default.

**Contract change.** `GET /catalog/products/{productId}/offers` declares an
optional `Accept-Language` header in `aliceut-v1.json`, so the generated
frontend client is regenerated. The response shape is unchanged.

**Search is not covered.** `GET /search/products?currency=` defaults to `USD`,
but that parameter names the currency of the price filters, not a display
preference, and the route reads no buyer preference. It is unchanged.

## Alternatives considered

**`USD` for a `NULL` preference everywhere.** Matches the old API documents and
needs no header, but it contradicts the Auto setting as US-B-01 and profile.md
define it, and it would have meant changing checkout, whose captured currency
US-P-03 ties to `Accept-Language`. Rejected by the user.

**Leave the routes divergent.** Rejected: a buyer seeing one currency on the
product page and another in the cart is the bug this ADR exists to remove.
