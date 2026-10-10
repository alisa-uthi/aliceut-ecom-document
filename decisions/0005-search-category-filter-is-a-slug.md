# ADR-0005: The search category filter is a category slug

**Status:** Accepted
**Date:** 2026-10-10
**Affects:** `phase-1/technical-design/api-design/search.md`, `phase-1/technical-design/kafka-events.md` (§2.10 `product.changed`), `phase-1/ui-design/buyer-portal.md`, `phase-1/ui-design/navigation-routing.md`
**Implemented by:** aliceut-ecom-document (this PR); backend follow-up for the ancestor path, see Consequences

## Context

`search.md § Product search` specified `GET /search/products?categoryId=<uuid>`,
"includes subcategories". The backend serves `?category=<string>` instead, and
applies it as `term: { category_path: <value> }` against the `products` index.
The divergence was recorded as item #7a in `spec-compliance.md`.

The index decides what the filter can be. `category_path` is a `keyword` field
in both the designed mapping and the deployed index template
(`aliceut-ecom-infra/config/elasticsearch/products-index-template.json`), and
what the indexer writes into it is category **slugs**:
`ProductIndexerService.buildProductDoc` reads
`ARRAY(SELECT c.slug FROM catalog.category c WHERE c.id = p.category_id)`, and
`SellerProductService.create` puts `[slug]` into the `product.changed` payload.
The documents the indexer builds carry no `category_id` at all. Serving a UUID
filter would therefore mean a new indexed field, a mapping change to the
template, and a full reindex of every product document.

Two further facts the code exposes:

1. **The path holds only the leaf.** Both writers emit a one-element array, the
   product's own category. A `term` match on it is an exact-category match, so
   `category=electronics` does not find a product filed under
   `electronics/cameras` — the "includes subcategories" behaviour the design
   promises is missing, whichever identifier the filter uses.
2. **The path holds slugs where §2.10 said names.** `kafka-events.md` §2.10
   documented `category_path` as "ancestor-to-leaf category names, e.g.
   `['Electronics','Cameras']`" and the search response example showed names.
   A slug filter matched against names can never hit, so the two descriptions
   could not both be right.

## Decision

`GET /search/products` takes **`category`, a category slug**, in place of
`categoryId`. It is a `term` filter on `category_path`.

`category_path` — in the index and in the `product.changed` payload — is the
product's category **slugs, ancestor-to-leaf** (`["electronics", "cameras"]`).
Subcategories are included because every ancestor's slug is in each
descendant's path, so a parent slug matches by plain `term` with no tree walk
at query time. The result's `categoryPath` is that same slug array; display
names come from `GET /catalog/categories`, which already returns `name` beside
`slug`. `facets.categories` entries gain a `slug` so a facet can be turned
into a filter.

Spec sections changed: `search.md` query-param table, response example, notes
and sequence; `kafka-events.md` §2.10 `category_path` doc; the buyer-portal
category tiles, search route, breadcrumbs and data-source notes; the
navigation-routing query-param row. `category_id` stays in the mapping and the
result, and `GET /catalog/products?categoryId=` (a Postgres read in
`catalog.md`) is untouched.

## Consequences

**The §2.10 change follows from the filter, not alongside it.** Names in the
path would make every slug filter miss, so the event schema's doc string now
says slugs. No field is added, removed or retyped, so no Avro compatibility
question arises.

**The backend owes one change to meet this ADR.** Both writers emit only the
leaf slug. To include subcategories, `ProductIndexerService.buildProductDoc`
must resolve the full ancestor chain (a recursive CTE up `parent_id`, ordered
root-first), and `SellerProductService` should put the same array into the
`product.changed` payload on `CREATED` and `UPDATED` (the `UPDATED` payload
currently omits `category_path` entirely). Until then a filter on a leaf
category works and a filter on a parent returns only products filed directly
under it. Because the indexer rebuilds documents from Postgres, existing
documents pick up the full path on their next reindex; there is no mapping
change and no index rebuild, only a one-off `reindexAllProducts` run after
deploy for products already in nested categories.

**Slugs are not globally unique.** `catalog.category` enforces uniqueness on
`(parent_id, slug)`, so `cameras` may exist under two parents, and
`category=cameras` matches products under both. Phase 1's taxonomy is small and
admin-curated, so this is accepted rather than designed around; if it starts to
matter, the fix is a globally unique slug constraint (or a slug-path filter),
not a return to UUIDs.

**Breadcrumbs need a lookup.** A result's `categoryPath` is no longer
renderable text. The buyer portal already loads the category tree for the
search sidebar, so the lookup is a client-side map rather than another request.

**What it buys:** shareable, readable search URLs
(`/search?category=cameras`), and a filter that works against the index as it
is deployed today.

## Alternatives considered

**Keep `categoryId` as designed.** Rejected by the user: it needs a new
indexed field on the explicit `strict` mapping, a template change in infra, and
a full reindex, for a filter whose readable form the buyer portal would have
to map back to anyway.

**Index both `category_ids` and slugs and accept either.** Two parameters for
one filter, and the same mapping change and reindex as the UUID option.

**Leave the path as the leaf only and drop "includes subcategories".** It would
make the current code conformant with no backend change, but a parent-category
tile that shows nothing filed under its children is a visible regression from
the design, and the user decision covered the identifier, not the semantics.
