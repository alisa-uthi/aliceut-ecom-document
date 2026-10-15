# ADR-0010: Search sort tie-break is product_id, not _id

**Status:** Accepted
**Date:** 2026-10-15
**Affects:** `phase-1/technical-design/api-design/search.md` (§ Product search, sequence diagram)
**Implemented by:** aliceut-ecom-backend (fix/search-sort-tiebreak-product-id)

## Context

`search.md § Product search` said every sort is "tie-broken on `_id`", so the
sort key is unique and `search_after` cannot skip or repeat a document. The
backend followed that and appended `{ _id: { order: 'asc' } }` to every sort.

Elasticsearch 8 does not allow that by default. The 8.0 migration guide says:

> Aggregating and sorting on `_id` is disallowed by default. Previously, it was
> possible to aggregate and sort on the built-in `_id` field by loading an
> expensive data structure called fielddata. This was deprecated in 7.6 and is
> now disallowed by default in 8.0.

The `_id` field reference repeats it: "The `_id` field is restricted from use in
aggregations, sorting, and scripting", and recommends duplicating `_id` into a
field with `doc_values` when a sort needs it. aliceut-ecom-infra runs
`docker.elastic.co/elasticsearch/elasticsearch:8.14.0`, so every search request
as specified would be rejected. The default can be lifted with
`indices.id_field_data.enabled`, but only by turning back on the fielddata the
deprecation was meant to remove.

The `products` mapping already holds that duplicate. `product_id` is a
`keyword` field, which has `doc_values` by default, and the indexer writes it on
every document with the same value as the document `_id`.

## Decision

Every product search sort is tie-broken on `product_id` ascending:
`(score | display_prices[currency] | created_at, product_id)`. `product_id` is
unique per document, because it is the document id, so the sort key stays
unique and `search_after` stays exact. `search.md`'s sequence diagram now names
`product_id` where it said `_id`. The mapping does not change.

## Consequences

- No mapping change and no reindex. `product_id` is already a mapped `keyword`,
  and its value equals `_id`, so the tie-break order is the same one `_id` would
  have given.
- A `nextCursor` issued before the change still decodes to a valid
  `search_after` tuple, because its last value is the product id either way.
- The tie-break now depends on the indexer writing `product_id` on every
  document. It always has, because the field is the document's identity in the
  index, but a document missing it would sort last rather than fail.

## Alternatives considered

- **Keep `_id` and set `indices.id_field_data.enabled: true`.** Lost: it
  re-enables the heap-resident fielddata that Elasticsearch deprecated and
  disabled, and it adds a cluster setting that infra must carry for one sort.
- **Tie-break on `_shard_doc` (point-in-time only).** Lost: it requires a
  point-in-time search context per cursor. The endpoint is stateless and its
  cursor is a bare `search_after` tuple.
- **Do nothing.** Lost: every search request fails against Elasticsearch 8.
