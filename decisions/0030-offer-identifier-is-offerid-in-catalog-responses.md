# ADR-0030: The offer identifier is `offerId` in every catalog response

**Status:** Accepted
**Date:** 2026-10-23
**Affects:** `phase-1/technical-design/api-design/catalog.md` (`GET /catalog/products/:productId/offers` response and sequence), `phase-1/ui-design/buyer-portal.md` (PDP offer selector)
**Implemented by:** aliceut-ecom-backend and aliceut-ecom-frontend, not yet written: the offers-list response DTO, `libs/contracts/openapi/aliceut-v1.json`, the regenerated `libs/api-client/`

## Context

Every response that carries an offer identifier names it `offerId`:
`GET /catalog/products/:id` (`data.offers[]`), search (`lowestOffer.offerId`),
pricing, cart, checkout (`confirmedPrices[]`, `updatedPrices[]`) and the seller
portal. One response is the outlier: `GET /catalog/products/:productId/offers`
returns the same object under `id`.

The two catalog responses describe the same thing, the offers of a product.
The PDP wireframe reads `offer.id` while the PDP endpoint it loads from returns
`offerId`, so the wireframe and the contract disagree with each other. A client
that holds an offer from either response cannot pass it to `POST /cart/items
{ offerId }` without remembering which endpoint produced it.

## Decision

1. `GET /catalog/products/:productId/offers` returns `offerId`, not `id`, on
   each element of `data[]`. No other field changes.
2. The PDP offer selector in `buyer-portal.md` compares `offer.offerId` with
   `selectedOffer.offerId`.
3. `offerId` is the only name for an offer's identifier in a response body.
   `id` is reserved for a response's own primary resource (a product, a
   variant, an address), never for a referenced offer.

## Consequences

- Breaking for the generated Angular client: the offers-list element type
  loses `id` and gains `offerId`. The backend DTO changes, the OpenAPI spec
  diff in CI fails until `npm run generate:api-client` is run in the frontend
  repo and the result is committed with the backend change.
- Nothing is shipped yet, so there is no deployed consumer to migrate.
- No migration and no event change.

## Alternatives considered

**Rename the other responses to `id`.** Rejected: six documents and the
checkout contract already use `offerId`, and a bare `id` inside a cart line or a
price row is ambiguous with the line's own id.

**Return both `id` and `offerId`.** Rejected: two names for one value in a
contract that has no deployed consumer to protect.

**Keep the divergence.** Rejected: it is a standing special case in the client
for no benefit.
