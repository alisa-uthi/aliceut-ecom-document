# EPIC: SEARCH — Elasticsearch Product Search

**Sprint:** 6  
**Total Tasks:** 8  
**Status:** Planned  

Full-text product search via Elasticsearch. Index populated and maintained exclusively from Kafka events (never from API write path). Provides buyer-facing search and filter API. Handles suspend/reinstate/removal events to keep index consistent with platform state.

---

## SEARCH-001 — Elasticsearch Index Mapping

| Field | Value |
|-------|-------|
| **US Ref** | US-B-03 |
| **Estimate** | M (1d) |
| **Dependencies** | INFRA-007 |

**Implementation Notes**

- File: `libs/search/src/infrastructure/elasticsearch/product-index.service.ts`
- Index: `products_v1` (alias: `products`); create on `SearchModule.onModuleInit` if not exists
- Full mapping:
  ```json
  {
    "settings": {
      "analysis": {
        "analyzer": {
          "product_analyzer": {
            "type": "standard",
            "stopwords": "_english_"
          }
        }
      },
      "number_of_shards": 1,
      "number_of_replicas": 0
    },
    "mappings": {
      "dynamic": "strict",
      "properties": {
        "product_id":        { "type": "keyword" },
        "offer_id":          { "type": "keyword" },
        "seller_id":         { "type": "keyword" },
        "title":             { "type": "text", "analyzer": "product_analyzer", "fields": { "keyword": { "type": "keyword" } } },
        "description":       { "type": "text", "analyzer": "product_analyzer" },
        "category_id":       { "type": "keyword" },
        "category_path":     { "type": "keyword" },
        "brand":             { "type": "keyword" },
        "attributes":        { "type": "object", "dynamic": true },
        "list_price_usd":    { "type": "scaled_float", "scaling_factor": 10000 },
        "sale_price_usd":    { "type": "scaled_float", "scaling_factor": 10000 },
        "currency":          { "type": "keyword" },
        "in_stock":          { "type": "boolean" },
        "quantity_available": { "type": "integer" },
        "image_url":         { "type": "keyword", "index": false },
        "listing_status":    { "type": "keyword" },
        "seller_name":       { "type": "keyword" },
        "seller_suspended":  { "type": "boolean" },
        "created_at":        { "type": "date" },
        "updated_at":        { "type": "date" }
      }
    }
  }
  ```
- Prices stored as `scaled_float` (integer * 10000 = NUMERIC(19,4) equivalent); convert from Decimal string to integer on index
- Index alias `products` → `products_v1`; enables zero-downtime re-indexing in Phase 2

**Done Criteria**

- `GET /products/_mapping` returns the defined mapping
- `dynamic: "strict"` prevents unknown fields from being indexed
- Index alias `products` resolves to `products_v1`
- Module creates index on startup if absent; no-ops if already present

---

## SEARCH-002 — Product Index Consumer (`product.changed`)

| Field | Value |
|-------|-------|
| **US Ref** | US-B-03 |
| **Estimate** | M (1d) |
| **Dependencies** | SEARCH-001, PLATFORM-003 |

**Implementation Notes**

- Consumer group: `search.product-changed`
- Topic: `product.changed`
- Handler: upsert full product document in `products` ES index
  - Build document from payload (no cross-service DB read — all needed data in event payload)
  - `listing_status = 'ACTIVE'` → include in index; `listing_status = 'INACTIVE'` or `'ARCHIVED'` → delete from index
  - Use `esClient.index({ index: 'products', id: offer_id, body: document })` (upsert by offer_id)
- Also consume `offer.changed` events (same consumer class; different topic handler)
  - `offer.changed` updates price fields (`list_price_usd`, `sale_price_usd`) on existing document
  - Use `esClient.update({ index: 'products', id: offer_id, body: { doc: { ... } } })`
- Idempotent via `BaseKafkaConsumer` → `ProcessedEvent`

**Done Criteria**

- `product.changed` event consumed: product appears in ES within 1s
- `offer.changed` (price update): ES document price fields updated; no full reindex
- `listing_status = 'INACTIVE'`: product removed from ES index
- Idempotent: processing same event twice does not create duplicate

---

## SEARCH-003 — Inventory Status Consumer (`inventory.changed`)

| Field | Value |
|-------|-------|
| **US Ref** | US-B-03 |
| **Estimate** | S (½d) |
| **Dependencies** | SEARCH-002, PLATFORM-003 |

**Implementation Notes**

- Consumer group: `search.inventory-changed`
- Topics: `inventory.changed`, `inventory.reservation_expired`
- `inventory.changed` handler: update `in_stock` and `quantity_available` in ES document
  ```ts
  await esClient.update({
    index: 'products',
    id: offer_id,
    body: { doc: { in_stock: quantity_available > 0, quantity_available } }
  });
  ```
- `inventory.reservation_expired` handler: same update (reservation expiry releases stock; update `in_stock` if was previously out-of-stock)
- Skip if document not found in ES (product not yet indexed; will be updated when `product.changed` fires)

**Done Criteria**

- Stock goes to 0: `in_stock = false` in ES; product excluded from in-stock filter
- Reservation expires: if no other stock issues, `in_stock = true` in ES
- Missing ES doc: no 404 error; silently skipped
- Idempotent processing

---

## SEARCH-004 — Seller Suspend/Reinstate Consumer

| Field | Value |
|-------|-------|
| **US Ref** | US-B-03 |
| **Estimate** | S (½d) |
| **Dependencies** | SEARCH-002, PLATFORM-003 |

**Implementation Notes**

- Consumer group: `search.seller-suspended`
- Topics: `seller.suspended`, `seller.reinstated`, `seller.suspension_expired`
- `seller.suspended` handler: bulk update all docs for `seller_id` in ES:
  ```ts
  await esClient.updateByQuery({
    index: 'products',
    body: {
      query: { term: { seller_id: sellerId } },
      script: { source: 'ctx._source.seller_suspended = true' }
    }
  });
  ```
- `seller.reinstated` / `seller.suspension_expired` handler: same bulk update with `seller_suspended = false`
- Search API always filters `seller_suspended: false` to exclude suspended sellers' products
- `updateByQuery` is async in ES — eventual consistency acceptable (within seconds)

**Done Criteria**

- `seller.suspended` consumed: all seller's products get `seller_suspended = true` in ES
- Products with `seller_suspended = true` absent from `GET /search` results
- `seller.reinstated` consumed: products become visible again
- Bulk update applies to all offers for seller, not just one

---

## SEARCH-005 — Moderation Removal Consumer

| Field | Value |
|-------|-------|
| **US Ref** | US-B-03 |
| **Estimate** | S (½d) |
| **Dependencies** | SEARCH-002, PLATFORM-003 |

**Implementation Notes**

- Consumer group: `search.listing-removed`
- Topics: `moderation.listing.removed`, `listing.soft_deleted`
- Handler: delete document from ES index:
  ```ts
  await esClient.delete({ index: 'products', id: offer_id });
  ```
- `listing.flagged` (with `action: 'FLAG'`): keep in index but update `listing_status = 'FLAGGED'` — moderately visible or excluded based on search API filter
- `listing.soft_deleted`: delete from index (seller deleted their own listing)
- Also consumes `fx_rate.updated` to trigger no-op (FX rates don't affect search documents directly in V1)

**Done Criteria**

- `moderation.listing.removed` consumed: product removed from ES; no longer appears in search
- `listing.soft_deleted` consumed: same behavior
- Delete on non-existent doc: no error (ES returns `not_found` but not an exception)
- Idempotent: deleting already-deleted doc is a no-op

---

## SEARCH-006 — Search API Endpoint

| Field | Value |
|-------|-------|
| **US Ref** | US-B-03 |
| **Estimate** | L (2d) |
| **Dependencies** | SEARCH-001 |

**Implementation Notes**

- `GET /search` (public — no auth required)
- Query params:
  ```
  q=string                  full-text search across title + description
  category=uuid             filter by category_id
  brand=string              filter by brand (keyword exact match)
  minPrice=decimal_string   min list_price_usd
  maxPrice=decimal_string   max list_price_usd
  inStockOnly=boolean       filter in_stock=true
  sortBy=relevance|price_asc|price_desc|newest
  limit=number (max 50, default 20)
  cursor=base64url          pagination cursor
  ```
- ES query construction:
  ```ts
  {
    query: {
      bool: {
        must: [{ multi_match: { query: q, fields: ['title^2', 'description'] } }],
        filter: [
          { term: { listing_status: 'ACTIVE' } },
          { term: { seller_suspended: false } },
          ...(category ? [{ term: { category_id: category } }] : []),
          ...(inStockOnly ? [{ term: { in_stock: true } }] : []),
          ...(minPrice || maxPrice ? [{ range: { list_price_usd: { gte: minPrice, lte: maxPrice } } }] : []),
        ]
      }
    },
    sort: sortBy === 'price_asc' ? [{ list_price_usd: 'asc' }] :
          sortBy === 'price_desc' ? [{ list_price_usd: 'desc' }] :
          sortBy === 'newest' ? [{ created_at: 'desc' }] :
          ['_score'],          // relevance (default)
    from: cursorOffset,
    size: limit + 1           // fetch +1 to detect hasMore
  }
  ```
- Response: same `PaginatedResponseDto<ProductSearchResultDto>` shape
- `ProductSearchResultDto`: `{ offerId, productId, title, description, brand, categoryId, listPriceUsd: string, salePriceUsd: string | null, inStock, imageUrl, sellerName, sellerId }`
- Prices returned as strings

**Done Criteria**

- `GET /search?q=laptop` returns relevant products
- `GET /search?inStockOnly=true` excludes out-of-stock products
- `GET /search?category=uuid` filters by category
- Suspended sellers' products absent from results
- `hasMore: true` + `nextCursor` when results exceed `limit`
- No auth required; public endpoint

---

## SEARCH-007 — Product Suggestions (Autocomplete)

| Field | Value |
|-------|-------|
| **US Ref** | US-B-03 |
| **Estimate** | M (1d) |
| **Dependencies** | SEARCH-006 |

**Implementation Notes**

- `GET /search/suggestions?q=str&limit=5` (public)
- Uses ES `completion` suggester or prefix query on `title.keyword`
- Simple prefix match on `title.keyword` (no custom completion suggester in V1):
  ```ts
  {
    query: {
      bool: {
        must: [{ prefix: { 'title.keyword': { value: q.toLowerCase(), case_insensitive: true } } }],
        filter: [{ term: { listing_status: 'ACTIVE' } }, { term: { seller_suspended: false } }]
      }
    },
    size: limit,
    _source: ['title', 'offer_id', 'image_url']
  }
  ```
- Returns: `{ suggestions: [{ title: string, offerId: string, imageUrl: string }] }`
- Max 5 suggestions; no pagination
- Debounce: handled client-side (Angular `debounceTime(300)`)
- Response time target: < 100ms (simple prefix query on keyword field)

**Done Criteria**

- `GET /search/suggestions?q=lap` returns up to 5 products starting with "lap"
- Suspended seller products not in suggestions
- Response time < 200ms on local dev stack
- No auth required

---

## SEARCH-008 — Re-index All (Admin Utility)

| Field | Value |
|-------|-------|
| **US Ref** | — |
| **Estimate** | M (1d) |
| **Dependencies** | SEARCH-001 |

**Implementation Notes**

- `POST /admin/search/reindex` (admin only)
- Full re-index from PostgreSQL (only for recovery/migration; not used in normal ops)
- Flow:
  1. Query all active products + offers from DB (with JOIN to get all fields)
  2. Bulk index to ES using `esClient.helpers.bulk()`
  3. Return `{ reindexed: count, errors: errorCount }`
- Runs synchronously (no async job in V1); timeout: 5 minutes
- Use this ONLY after data loss or mapping migration — normal updates flow through Kafka
- Document clearly in API description: "Emergency use only; all normal updates are event-driven"

**Done Criteria**

- `POST /admin/search/reindex`: all active, non-suspended products appear in ES after completion
- Suspended sellers' products NOT indexed
- Already-indexed products overwritten (not duplicated)
- Returns count of indexed documents and any errors
