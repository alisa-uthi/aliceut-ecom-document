# ADR-0002: `variantLabel` is persisted inside `product_variant.attributes`

**Status:** Accepted
**Date:** 2026-10-09
**Affects:** `phase-1/technical-design/api-design/seller.md`, `phase-1/technical-design/data-model-erd.md`
**Implemented by:** aliceut-ecom-backend#24, aliceut-ecom-frontend#17

## Context

`POST /seller/products` takes `variants: [{ sku, variantLabel, attributes }]`,
and `variantLabel` is read back by the cart, catalog, orders and seller
responses — it is the string a buyer sees next to a line item ("Black / M").

`catalog.product_variant` has no column for it. The table is
`(id, product_id, sku, attributes JSONB, created_at, updated_at)`, and the
create-product sequence in `seller.md` inserts exactly
`(product_id, sku, attributes)`. So the API accepted a field with nowhere to
land, while four other documents promised to return it. The conflict surfaced
when the endpoint was implemented, because implementing the body as written
required a column that does not exist.

`orders.fulfillment_item.variant_label_snapshot` is unaffected: order lines
snapshot the label at checkout and already have their own column.

## Decision

`variantLabel` is stored as `attributes.variantLabel` in the existing JSONB
column. The request body keeps the field — clients send it as the API design
says — and the service folds it into `attributes` on insert. No migration, and
the create-product sequence in `seller.md` stays literally true.

## Consequences

Every read path that returns `variantLabel` must read it out of JSONB rather
than selecting a column, which is more verbose in each query and gives the
field no database-level type or length guarantee beyond what the DTO validates
(max 200 characters). A label cannot be indexed or constrained without a
migration later, and nothing stops a client writing a conflicting
`attributes.variantLabel` directly — the service overwrites the key rather than
merging, so the dedicated field wins.

Against that: no schema change to a table that already holds seeded data, and
no second source of truth for the same string. If a label ever needs sorting,
uniqueness or a `NOT NULL`, promoting it to a column is a contained migration
plus a read-path change, and this ADR should then be superseded.

## Alternatives considered

**Add a `variant_label TEXT` column.** The cleanest model, and what the API
design implies by naming the field at all. Rejected for now because it changes
the ERD and a seeded table to buy nothing the JSONB key does not already
provide at this stage — no query filters, sorts or joins on the label.

**Drop `variantLabel` from the request body** and update `seller.md`. Rejected:
cart, catalog, orders and seller responses all return it, so dropping the only
write path would leave four documented fields permanently null.
