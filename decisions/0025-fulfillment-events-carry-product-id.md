# ADR-0025: `fulfillment.*` items carry `product_id`, and `fulfillment.refunded` items carry `offer_id`

**Status:** Accepted
**Date:** 2026-10-22
**Affects:** `phase-1/technical-design/kafka-events.md` (§ 2.4, 2.5, 2.7, 2.16, 2.17), `phase-1/technical-design/data-model-erd.md` (`orders.fulfillment_item`), `phase-1/technical-design/consumer-field-matrix.md` (§ 6)
**Implemented by:** aliceut-ecom-backend (PR linked in `spec-compliance.md`)

## Context

`inventory.changed` requires `product_id` (the search consumer's write is
addressed by it). The inventory consumers build that event from
`fulfillment.*` payloads, none of whose items carried `product_id`, so
`InventoryApplicationService` read `catalog.offer` (marked `SPEC GAP`). That
breaks the consumer rule in consumer-field-matrix § 1: where a consumer needs
a field its event lacks, the fix is to fatten the event. `fulfillment.refunded`
items also lacked `offer_id`, so consumer-field-matrix § 6's refunded row could
not be filled from the payload as written.

## Decision

1. **Storage.** `orders.fulfillment_item` gains `product_id UUID`, the
   `catalog.offer.product_id` snapshotted by checkout in the same transaction
   as the item (checkout already joins `catalog.offer` for the price). A
   migration adds it nullable, then a separate migration backfills existing
   rows and sets `NOT NULL`.
2. **Events.** Every item record of `fulfillment.placed`, `.shipped`,
   `.cancelled`, `.refunded` and `.refund_suspended_seller` gains
   `product_id`, `["null","string"]` with `default: null`; `RefundedItem` also
   gains `offer_id` with the same type and default. Optional-with-default
   fields are `BACKWARD`-compatible, so `event_version` stays 1. Producers
   always set both; the nullable type exists only for compatibility with
   events already in the topic. The subject must be registered before the new
   producer runs (ADR-0012).
3. **Consumers.** No consumer changes its inputs to read more; the
   inventory consumers still take `offer_id` from the payload. Where the
   inventory service needs `product_id` for `inventory.changed`, it reads
   `inventory.stock.product_id` (ADR-0026), not the event, so a pre-change
   event in flight is still handled.
4. **`fulfillment.delivered`** is unchanged: its only consumers use
   `order_id`.

## Consequences

- Events published before this change decode `product_id` as null; nothing in
  V1 reads it from the event, so there is no behaviour difference.
- `fulfillment_item` rows grow by 16 bytes.

## Alternatives considered

**Read `catalog.offer` in the consumer.** The status quo; violates the
consumer contract. Rejected.

**Resolve `product_id` through `CatalogApplicationService` at consume time.**
An enrichment call the matrix forbids. Rejected.
