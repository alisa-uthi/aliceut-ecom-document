# ADR-0013: Every offer must reference a variant; omitting variantId creates a default variant

**Status:** Accepted
**Date:** 2026-10-15
**Affects:** `phase-1/technical-design/data-model-erd.md` (§5 `catalog.offer.variant_id` column), `phase-1/technical-design/api-design/seller.md` (`POST /seller/offers` request/response), `phase-1/technical-design/kafka-events.md` (open item in §5 of spec-compliance)
**Implemented by:** aliceut-ecom-backend#58

## Context

`inventory.low_stock` (kafka-events.md §2.13) declares `sku_label` and `sku_id` as
non-null `string` fields in the Avro schema. The producing code in
`libs/seller/src/services/seller-inventory.service.ts` worked around an offer
with a null `variant_id` by emitting `''` for both fields (`?? ''`). That empty
string satisfies the Avro type at the wire level but contradicts the semantic
guarantee the schema makes: a `sku_id` of `''` is not a valid identifier of
anything.

The spec-compliance tracker recorded this as an open item:

> `inventory.low_stock` `sku_label` / `sku_id` are non-null in §2.13 and sent as
> `''` for an offer without a variant. Either they become nullable or every offer
> must have a variant.

The ERD shows `catalog.offer.variant_id` as a nullable FK, remarking "when a
product has variants". The product schema, however, already requires at least one
variant: `POST /seller/products` enforces `variants: [...]` with a minimum of
one element. Seeded (platform-owned) products are the only ones that currently
reach the database without a variant row. Consequently, the only legitimate reason
for a null `variant_id` on an offer is a seeded product, which is a gap rather
than an intended design.

Making `sku_label` and `sku_id` nullable would widen the Avro contract and every
consumer that branches on their presence. The narrower fix — making every offer
reference a variant and removing the `'' ` fallback — closes the gap without
loosening any schema.

## Decision

`catalog.offer.variant_id` is NOT NULL. Every offer references exactly one
`catalog.product_variant`. The data constraint is enforced at the database level by
a migration, and at the application level by the offer-creation path.

**When a seller creates an offer (`POST /seller/offers`) without supplying a
`variantId`:** Catalog finds or creates a *default variant* for the product in the
same transaction. The default variant uses SKU `'DEFAULT'` and empty attributes
(`{}`). A product-level unique constraint on `(product_id, sku)` prevents
duplicates; a concurrent insert uses `ON CONFLICT (product_id, sku) DO NOTHING`
followed by a SELECT so that both writers end up pointing at the same row. The
`variantId` returned in the 201 response is always non-null, whether the caller
supplied it or the server resolved it.

**When a `variantId` is supplied:** the existing validation that it belongs to the
named product is retained unchanged.

**Backfill of existing offers:** Migration `0016_offer_variant_backfill` inserts a
default variant (SKU `'DEFAULT'`, attributes `{}`) for each product that currently
has at least one offer with a null `variant_id`, then updates all those offers to
point at the new row. A single default variant is created per product regardless of
how many sellers hold null-variant offers for it. If a product already has a variant
with SKU `'DEFAULT'` from a previous seller action, that row is reused; the
`ON CONFLICT DO NOTHING` + SELECT pattern guarantees idempotency.

**Removal of the `'' ` fallback:** The `LEFT JOIN` to `catalog.product_variant` in
the `maybeWriteLowStock` query becomes an `INNER JOIN`. The two fields are typed as
`string` (not `string | null`) and the `?? ''` coercions are removed. An
`InventoryLowStockPayload` built after this change always carries the variant's
actual SKU and UUID.

**Avro schema for `offer.changed`:** The `variant_id` field in
`offer.changed.avsc` (kafka-events.md §2.11) currently uses the union
`["null","string"]` with a `null` default. Changing it to a plain `"string"` would
break BACKWARD compatibility with messages written before this migration, so the
type union is kept. In practice, every newly produced `offer.changed` message will
carry a non-null string; consumers must continue to handle a null for events
replayed from before the migration.

## Consequences

- `catalog.offer.variant_id` is NOT NULL in all environments after migration
  `0017_offer_variant_not_null` is applied.
- The `POST /seller/offers` response always carries a non-null `variantId`.
- `inventory.low_stock` events emitted after this migration always carry the
  variant's actual `sku_label` (variant label from `attributes.variantLabel`) and
  `sku_id` (variant UUID) rather than empty strings.
- Any code path that treats `offer.variant_id` as nullable must be updated;
  downstream services relying on a null variant_id to detect "variant-less offer"
  need to handle the default variant pattern instead.
- The seed script must create a variant for each product and set `variant_id` on
  the seeded offer; the current `ON CONFLICT DO NOTHING` pattern makes re-runs
  safe.
- The frontend client is regenerated from the updated OpenAPI spec, where
  `variantId` changes from `string | null` to `string` in offer response shapes.
- Two migrations are required (separate per the database-migrations convention:
  data backfill in `0016`, schema constraint in `0017`).

## Alternatives considered

- **Make `sku_label` / `sku_id` nullable in the Avro schema.** Rejected: this
  widens the contract for every current and future consumer of
  `inventory.low_stock`. The notification consumer and audit consumer already
  branch on `sku_label` to render the variant badge in ET-15 and in the activity
  log; a nullable value there is a presentation gap (blank variant on the alert),
  not just a schema question.
- **Keep the `'' ` fallback and document it.** Rejected: the empty string is not a
  valid variant identifier. An audit consumer that treats it as such would
  accumulate bogus entries, and a notification that displays it would show a blank
  badge.
- **Make `variantId` required in the API request.** Considered. This would be
  explicit and non-magical, but is a breaking change for any client that currently
  omits the field. The default-variant creation approach preserves backward
  compatibility while meeting the same invariant.
- **Allow a single offer per product, choosing the only variant automatically.**
  Rejected: a product may have multiple variants (e.g. a shirt in S, M, and L),
  and each variant is a separate offer. Auto-picking "the only variant" is safe
  only when the product has exactly one, which is not a stable assumption once a
  seller adds a second.
