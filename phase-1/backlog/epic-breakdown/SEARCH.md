# EPIC: SEARCH — Search Module

**Sprint:** 4  
**Total Tasks:** 8  

Elasticsearch-backed full-text product search with real-time index maintenance via Kafka consumers. All index writes are event-driven (async from domain events); no sync writes from API. Admin provides a full re-index utility.

---

## SEARCH-001 — Elasticsearch Products Index Mapping

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** INFRA-007
- **Spec References:** `phase-1/technical-design/api-design/search.md`, `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- File: `libs/search/src/infrastructure/elasticsearch/index-bootstrap.service.ts`
- On workers startup (`OnModuleInit`): create index if not exists with full mapping:
  ```json
  {
    "mappings": {
      "properties": {
        "offer_id":       { "type": "keyword" },
        "product_id":     { "type": "keyword" },
        "seller_id":      { "type": "keyword" },
        "title":          { "type": "text", "analyzer": "english" },
        "description":    { "type": "text", "analyzer": "english" },
        "brand":          { "type": "keyword" },
        "category_id":    { "type": "keyword" },
        "category_path":  { "type": "keyword" },
        "status":         { "type": "keyword" },
        "seller_status":  { "type": "keyword" },
        "price_usd":      { "type": "scaled_float", "scaling_factor": 10000 },
        "prices":         {
          "type": "nested",
          "properties": {
            "currency": { "type": "keyword" },
            "amount":   { "type": "scaled_float", "scaling_factor": 10000 }
          }
        },
        "available_qty":  { "type": "integer" },
        "rating":         { "type": "half_float" },
        "image_url":      { "type": "keyword", "index": false },
        "created_at":     { "type": "date" }
      }
    },
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0
    }
  }
  ```
- Idempotent: skip if index exists already (HTTP 400 `resource_already_exists_exception` from ES → catch and ignore)
- `price_usd`: USD LIST price for sorting/filtering (normalized at index time)

**Done Criteria**

- Workers start: `products` index exists in Elasticsearch
- `GET /products/_mapping` returns all expected fields
- Restarting workers does not fail (idempotent create)

---

## SEARCH-002 — Kafka Consumer: product.changed → ES index upsert

- **US Ref:** FR-P-10
- **Estimate:** L
- **Dependencies:** SEARCH-001, PLATFORM-003, PRICING-004
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/api-design/search.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- Consumer group: `search.product-changed`
- Topic: `product.changed`
- `handle(event)`:
  1. Load full product + all active offers + prices from DB (fresh query — not from event payload which may be partial)
  2. For each active offer: index one document (offer is the search unit)
  3. If `event.payload.status = 'REMOVED'`: delete all ES documents with `product_id = event.payload.product_id`
- ES upsert: `client.update({ id: offerId, body: { doc: {...}, doc_as_upsert: true } })`
- `price_usd`: call `EffectivePriceService.resolve(offerId, { accountType: 'BUYER', qty: 1, preferredCurrency: 'USD' })`
- Extends `BaseKafkaConsumer` for idempotency

**Done Criteria**

- Create product → offer document appears in ES within 2s
- Product status = REMOVED → all offer documents for that product deleted from ES
- Duplicate `product.changed` event: idempotent (same ES state)

---

## SEARCH-003 — Kafka Consumer: inventory.changed → ES available_qty update

- **US Ref:** FR-P-10
- **Estimate:** M
- **Dependencies:** SEARCH-001, PLATFORM-003
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/api-design/search.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- Consumer group: `search.inventory-changed`
- Topic: `inventory.changed`
- `handle(event)`:
  - Partial update: `client.update({ id: event.payload.offer_id, body: { doc: { available_qty: event.payload.effective_available } } })`
  - If effective_available = 0: also set `status: 'OUT_OF_STOCK'` in ES doc (for filter)
  - If effective_available > 0 and offer was `OUT_OF_STOCK`: restore `status: 'ACTIVE'`
- Skip update if offer not found in ES (may not be indexed yet — return without error)

**Done Criteria**

- Seller reduces stock to 0 → ES document `available_qty = 0`, `status = 'OUT_OF_STOCK'`
- Search filter `inStock: true` excludes zero-stock items

---

## SEARCH-004 — Kafka Consumer: seller.suspended / seller.reinstated → ES seller_status update

- **US Ref:** FR-P-10
- **Estimate:** M
- **Dependencies:** SEARCH-001, PLATFORM-003
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/api-design/search.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- Consumer groups: `search.seller-suspended`, `search.seller-reinstated`
- Topics: `seller.suspended`, `seller.reinstated`
- On `seller.suspended`:
  - Update by query: all ES docs with `seller_id = event.payload.seller_id` → set `seller_status: 'SUSPENDED'`
  - Update by query ES API: `client.updateByQuery({ query: { term: { seller_id } }, script: "ctx._source.seller_status = 'SUSPENDED'" })`
- On `seller.reinstated`:
  - Set `seller_status: 'ACTIVE'` for all seller's documents
- Search query filters out `seller_status: 'SUSPENDED'` documents by default

**Done Criteria**

- Seller suspended → all their products hidden from search within 2s
- Seller reinstated → products return to search results

---

## SEARCH-005 — Kafka Consumer: moderation.listing.removed → ES delete

- **US Ref:** FR-P-10
- **Estimate:** S
- **Dependencies:** SEARCH-001, PLATFORM-003
- **Spec References:** `phase-1/technical-design/kafka-events.md`, `phase-1/technical-design/api-design/search.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- Consumer group: `search.moderation-removed`
- Topic: `moderation.listing.removed`
- `handle(event)`: delete ES document by `event.payload.offer_id`
- Hard delete from ES index (listing permanently removed by admin)
- Idempotent: delete of non-existent doc returns 404 → catch and treat as success

**Done Criteria**

- Admin removes listing → ES document deleted; no longer appears in search
- Deleting already-deleted doc: no error

---

## SEARCH-006 — GET /search (full-text + filter + sort + pagination)

- **US Ref:** US-B-03, US-B-04
- **Estimate:** L
- **Dependencies:** SEARCH-001
- **Spec References:** `phase-1/technical-design/api-design/search.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- `GET /search?q=&category=&minPrice=&maxPrice=&currency=USD&inStock=&sortBy=relevance|price_asc|price_desc|newest&limit=20&cursor=` — `@Public()`
- ES query:
  ```json
  {
    "query": {
      "bool": {
        "must": [
          { "multi_match": { "query": "{{q}}", "fields": ["title^3", "description", "brand^2"] } }
        ],
        "filter": [
          { "term": { "status": "ACTIVE" } },
          { "term": { "seller_status": "ACTIVE" } },
          { "range": { "available_qty": { "gt": 0 } } },
          // optional filters:
          { "term": { "category_id": "{{category}}" } },
          { "range": { "price_usd": { "gte": minPriceUSD, "lte": maxPriceUSD } } }
        ]
      }
    },
    "sort": [{ "_score": "desc" } | { "price_usd": "asc/desc" } | { "created_at": "desc" }],
    "from": cursorOffset,
    "size": limit + 1
  }
  ```
- Cursor pagination: offset-based for search (ES doesn't support keyset natively in V1; `search_after` acceptable if implemented)
- Price filter always converted to USD internally before querying `price_usd`
- Response: `PaginatedResponseDto<SearchResultDto>` with `{ offerId, productId, title, brand, imageUrl, priceUsd, prices, sellerName, availableQty, rating }`

**Done Criteria**

- `GET /search?q=laptop` returns relevant results
- `GET /search?q=laptop&inStock=true` excludes zero-stock items
- `GET /search?q=laptop&sortBy=price_asc` returns ascending price order
- Suspended seller's products absent from results
- Empty query `q=` returns all active products (browse mode)

---

## SEARCH-007 — Product Suggestions (autocomplete) GET /search/suggest

- **US Ref:** US-B-03
- **Estimate:** M
- **Dependencies:** SEARCH-001
- **Spec References:** `phase-1/technical-design/api-design/search.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- `GET /search/suggest?q=lap&limit=5` — `@Public()`; debounced from frontend (300ms)
- ES completion suggester or prefix match on `title` field:
  ```json
  { "query": { "match_phrase_prefix": { "title": { "query": "{{q}}", "max_expansions": 10 } } }, "size": 5 }
  ```
- Response: `{ suggestions: [{ offerId, title, imageUrl, priceUsd }] }`
- Cache in Redis 60s per query string to reduce ES load
- Min query length: 2 characters (below this → return empty immediately without ES call)

**Done Criteria**

- `GET /search/suggest?q=la` returns up to 5 suggestions
- `GET /search/suggest?q=x` (1 char) → empty array, no ES call
- Second call for same `q` hits Redis cache (verify via ES request count)

---

## SEARCH-008 — Admin Re-index All Utility (POST /admin/search/reindex)

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** SEARCH-001, PRICING-004
- **Spec References:** `phase-1/technical-design/api-design/search.md`, `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- `POST /admin/search/reindex` — `@Roles('ADMIN')`; runs full product re-index
- Implementation:
  1. Delete existing `products` index
  2. Recreate with full mapping (SEARCH-001)
  3. Query all active offers from DB (cursor-paginated, 100 per batch)
  4. For each offer: build ES document (same as SEARCH-002 logic); bulk index
  5. Return `{ indexed: N, errors: M, durationMs }` after completion
- Synchronous for V1 (no background job queue); timeout set to 300s
- Used for: after migration, after data correction, initial data load

**Done Criteria**

- `POST /admin/search/reindex` re-populates index from DB
- All active offers appear in ES after re-index
- Protected: non-admin call → 403
