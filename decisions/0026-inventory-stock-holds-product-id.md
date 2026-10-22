# ADR-0026: `inventory.stock` holds `product_id`

**Status:** Accepted
**Date:** 2026-10-22
**Affects:** `phase-1/technical-design/data-model-erd.md` (`inventory.stock`), `phase-1/technical-design/cleanup-jobs.md` (reservation expiry), `phase-1/technical-design/consumer-field-matrix.md` (§ 6), `phase-1/technical-design/api-design/seller.md` (create offer)
**Implemented by:** aliceut-ecom-backend (PR linked in `spec-compliance.md`)

## Context

`inventory.changed` and `inventory.reservation_expired` both need `product_id`.
`cleanup-jobs.md` said the expiry sweep resolves it through
`CatalogApplicationService.getProductIdsForOffers()`; that method was never
built and the code joined `catalog.offer` instead. The inventory consumers did
the same. Inventory holds an `offer_id` and nothing that maps it to a product.

## Decision

`inventory.stock` gains `product_id UUID NOT NULL`, a copy of
`catalog.offer.product_id`, written by the same statement that creates the
stock row (offer creation, which already knows the product). An offer never
changes product, so the copy cannot go stale. A migration adds it nullable, a
separate migration backfills from `catalog.offer` (a one-off migration read)
and sets `NOT NULL`.

Both `inventory.changed` (consumers) and `inventory.reservation_expired`
(expiry sweep) take `product_id` from `inventory.stock`, in the statement that
already reads or updates that row. No `catalog` table is read at runtime.

## Consequences

- Any new writer of `inventory.stock` (seed script, a future import) must set
  `product_id`; the `NOT NULL` makes forgetting loud.
- The unbuilt `CatalogApplicationService.getProductIdsForOffers()` is no longer
  part of the design.

## Alternatives considered

**Build `getProductIdsForOffers()` and call it.** Keeps inventory ignorant of
products but adds a module call on a hot consumer path and, for the expiry
sweep, a call outside the claim query. Rejected: a stored copy of an immutable
value is smaller and cheaper.

**Take `product_id` from the `fulfillment.*` item (ADR-0025).** Works for the
consumers but not for the expiry sweep, which has no fulfillment. Two sources
would also disagree during rollout. Rejected as the sole source.
