# Search API

**Module:** `Search`  
**Parent:** [API Design Index](../api-design.md)  
**Source of truth:** [BRD v1.1](../../requirements/BRD.md), [ERD](../data-model-erd.md)

---

## Summary

- [Endpoint Index](#endpoint-index)
- [DB Mapping](#db-mapping)
- [Endpoints](#endpoints)
- [ES Index Maintenance](#es-index-maintenance)

<a id="endpoint-index"></a>
## Endpoint Index

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | [`/search/products`](#product-search) | PUBLIC | Full-text product search with facets (Elasticsearch `search_after`) |

See [ES Index Maintenance](#es-index-maintenance) for the async Kafka consumer write paths that keep the index current.

---

<a id="db-mapping"></a>
## DB Mapping

| Endpoint | Primary DB | Index / Notes |
|----------|-----------|---------------|
| `GET /search/products` | Elasticsearch | `products` index (read-only, cursor via `search_after`) |

**Write path (async):** The search index is never written by the API. Kafka consumers update it from `catalog`, `offer`, `inventory`, and `seller` events. Offers from non-approved or suspended sellers are excluded at index time — not filtered at query time.

---

<a id="endpoints"></a>
## Endpoints

### Product search

```
GET /search/products
Tag: Search
Auth: PUBLIC
Pagination: cursor (Elasticsearch search_after)
```
**Query params**

| Param | Type | Description |
|-------|------|-------------|
| `q` | string | Full-text query |
| `categoryId` | UUID | Filter by category (includes subcategories) |
| `priceMin` | string (decimal) | Min price in `currency` |
| `priceMax` | string (decimal) | Max price |
| `currency` | ISO 4217 | Currency for price filters (default USD) |
| `inStock` | boolean | Only in-stock offers |
| `sortBy` | `relevance \| priceAsc \| priceDesc \| newest` | Default `relevance` |
| `limit` | int | Default 20, max 100 |
| `cursor` | string | Opaque search_after cursor |

**Response 200**
```json
{
  "data": [{
    "productId": "uuid",
    "title": "string",
    "brand": "string",
    "categoryId": "uuid",
    "categoryPath": ["Electronics", "Cameras"],
    "images": [{ "storageKey": "string" }],
    "lowestOffer": {
      "offerId": "uuid",
      "amount": "99.99",
      "currency": "USD",
      "priceType": "LIST | SALE",
      "displayAmount": "3440.00",
      "displayCurrency": "THB",
      "fxRate": "34.40000000"
    },
    "inStock": true,
    "score": 1.234
  }],
  "facets": {
    "categories": [{ "id": "uuid", "name": "string", "count": 12 }],
    "priceRange": { "min": "9.99", "max": "999.00", "currency": "USD", "displayMin": "344.00", "displayMax": "34400.00", "displayCurrency": "THB" }
  },
  "meta": { "nextCursor": "string | null", "hasMore": true, "total": 250 }
}
```

**Notes:**
- `lowestOffer.amount` / `lowestOffer.currency` = seller's native price. `displayAmount` / `displayCurrency` / `fxRate` = buyer's requested currency, sourced from the pre-computed `display_prices[currency]` map in ES (kept fresh by `fx_rate.updated` consumer). Omitted when `currency` == offer's native currency (no conversion).
- `facets.priceRange` `displayMin` / `displayMax` / `displayCurrency` follow the same rule — omitted when no conversion applies.
- Display prices are for presentation only. Order capture uses `fulfillment_item.fx_rate_used_at_capture` snapshotted at checkout.
- Offers from sellers with `suspension_status = SUSPENDED` or `kyc_status != APPROVED` are excluded from search results. Only offers from KYC-approved, non-suspended sellers appear.

#### Sequence

```mermaid
sequenceDiagram
    participant Client
    participant API as API (NestJS)
    participant SearchService
    participant ES as Elasticsearch

    Client->>API: GET /search/products?q=camera&categoryId&priceMin&priceMax&currency=USD&inStock=true&sortBy=relevance&limit=20&cursor
    Note over API: PUBLIC — no auth guard
    API->>SearchService: searchProducts({ q, categoryId, priceMin, priceMax, currency, inStock, sortBy, limit, cursor })
    Note over SearchService: Build ES bool query: must=multi_match(title,brand,description when q present)#59; filter=status ACTIVE, seller_active=true, category_id/path, display_prices[currency] range, available_qty>0 (inStock)#59; sort=score|display_prices[currency].asc|.desc|created_at.desc#59; search_after=decoded cursor#59; size=limit+1#59; aggs=category terms+display_prices[currency] stats
    SearchService->>ES: POST /products/_search { query, sort, search_after, size, aggs }
    ES-->>SearchService: hits[], aggregations, total.value
    Note over SearchService: If hits.length = limit+1: hasMore=true, trim last hit. Encode nextCursor from sort values of last included hit
    SearchService-->>API: result set, facets, pagination meta
    API-->>Client: 200 { data: [...], facets: { categories, priceRange }, meta: { nextCursor, hasMore, total } }
```

---

<a id="es-index-maintenance"></a>
## ES Index Maintenance

The `products` Elasticsearch index is a **read model only**. No API handler writes to it directly. All writes are driven by Kafka consumers reacting to domain-change events. Every domain state change commits its domain rows and a `platform.outbox_event` row in a single Postgres transaction; the Outbox Relay polls for unpublished events and produces them to Kafka; SearchConsumer groups consume from Kafka, update Elasticsearch, record a `platform.processed_event` row for idempotency, then commit the Kafka offset (at-least-once delivery, idempotent on `event_id`).

Offers from sellers with `kyc_status != APPROVED` or `suspension_status = SUSPENDED` are excluded **at index time** — the suspension/reinstatement events trigger bulk updates to the `seller_active` field on indexed offer documents; there is no query-time filter.

---

### product.changed — product document upsert and delete

Producers: Catalog module (product create, update, status change to REMOVED).

```mermaid
sequenceDiagram
    participant Catalog as Catalog Module
    participant Postgres
    participant Relay as Outbox Relay
    participant Kafka
    participant Consumer as SearchConsumer
    participant ES as Elasticsearch

    Note over Catalog,Postgres: Domain change: product created, updated, or status = REMOVED
    Catalog->>Postgres: BEGIN TX<br/>INSERT or UPDATE catalog.product<br/>INSERT platform.outbox_event (topic=product.changed, change_type, payload)
    Postgres-->>Catalog: COMMIT

    loop Outbox relay poll
        Relay->>Postgres: SELECT FROM platform.outbox_event<br/>WHERE publication_status = 'PENDING' LIMIT 100
        Postgres-->>Relay: pending outbox rows
        Relay->>Kafka: Produce to product.changed (partition key: product_id)
        Relay->>Postgres: UPDATE platform.outbox_event SET publication_status = 'PUBLISHED'
    end

    Kafka-->>Consumer: Consume product.changed (group: search.product-changed)
    Note over Consumer: Check platform.processed_event (consumer_group, event_id) for idempotency
    alt event already processed
        Note over Consumer: Skip — idempotent
    else new event
        alt change_type = REMOVED
            Consumer->>ES: DELETE /products/_doc/:productId
        else change_type = CREATED or UPDATED
            Consumer->>ES: PUT /products/_doc/:productId<br/>{ title, brand, category_id, category_path, images, status, variants }
        end
        ES-->>Consumer: acknowledged
        Consumer->>Postgres: INSERT platform.processed_event (consumer_group, event_id, outcome)
        Note over Consumer: Commit Kafka offset
    end
```

---

### offer.changed — offer fields update in product document

Producers: Catalog module / Seller module (offer created, activated, updated, deactivated, or removed).

```mermaid
sequenceDiagram
    participant SellerAPI as Seller API
    participant Postgres
    participant Relay as Outbox Relay
    participant Kafka
    participant Consumer as SearchConsumer
    participant ES as Elasticsearch

    Note over SellerAPI,Postgres: Seller creates, updates, or deactivates an offer
    SellerAPI->>Postgres: BEGIN TX<br/>UPDATE catalog.offer SET status = ACTIVE (or INACTIVE or REMOVED)<br/>UPSERT pricing.offer_price rows<br/>INSERT platform.outbox_event (topic=offer.changed, change_type, payload)
    Postgres-->>SellerAPI: COMMIT

    Relay->>Kafka: Produce to offer.changed (partition key: offer_id)

    Kafka-->>Consumer: Consume offer.changed (group: search.offer-changed)
    Note over Consumer: Idempotency check on platform.processed_event

    alt change_type = DEACTIVATED or REMOVED
        Consumer->>ES: Update /products/_doc/:productId<br/>Remove offer from nested offers array<br/>If no active offers remain: set inStock = false
    else change_type = CREATED or UPDATED
        Note over Consumer: Only indexed when seller.kyc_status = APPROVED AND suspension_status = ACTIVE<br/>(verified against seller state captured in event payload)
        Consumer->>ES: Update /products/_doc/:productId<br/>Upsert offer in nested offers array<br/>Update lowestOffer if this offer has the lowest price<br/>Set inStock = true when available_qty > 0
    end
    ES-->>Consumer: acknowledged
    Consumer->>Postgres: INSERT platform.processed_event
    Note over Consumer: Commit Kafka offset
```

---

### inventory.changed and inventory.reservation_expired — stock availability update

Producers: Inventory module (manual/bulk update, reservation, refund restore); Workers module (reservation expiry scheduler, US-P-17).

```mermaid
sequenceDiagram
    participant Inventory as Inventory Module / Workers
    participant Postgres
    participant Relay as Outbox Relay
    participant Kafka
    participant Consumer as SearchConsumer
    participant ES as Elasticsearch

    alt inventory.changed (stock updated)
        Inventory->>Postgres: BEGIN TX<br/>UPDATE inventory.stock (on_hand_qty or reserved_qty)<br/>INSERT platform.outbox_event (topic=inventory.changed, available_qty, change_reason)
    else inventory.reservation_expired (reservation released by scheduler)
        Inventory->>Postgres: BEGIN TX<br/>UPDATE inventory.stock_reservation SET status = EXPIRED<br/>UPDATE inventory.stock SET reserved_qty = reserved_qty - :quantity<br/>INSERT platform.outbox_event (topic=inventory.reservation_expired, released_qty)
    end
    Postgres-->>Inventory: COMMIT

    Relay->>Kafka: Produce to inventory.changed or inventory.reservation_expired (partition key: offer_id)

    Kafka-->>Consumer: Consume event (group: search.inventory-changed or search.reservation-expired)
    Note over Consumer: Idempotency check on platform.processed_event
    Consumer->>ES: Update /products/_doc/:productId<br/>Set offers[offer_id].available_qty = :available_qty<br/>Set inStock = (available_qty > 0)
    ES-->>Consumer: acknowledged
    Consumer->>Postgres: INSERT platform.processed_event
    Note over Consumer: Commit Kafka offset
```

---

### seller.suspended and seller.reinstated / seller.suspension_expired — seller active flag

Producers: Admin module (suspend/reinstate); Workers module (timed suspension expiry scheduler, US-P-18).

```mermaid
sequenceDiagram
    participant Admin as Admin Module / Workers
    participant Postgres
    participant Relay as Outbox Relay
    participant Kafka
    participant Consumer as SearchConsumer
    participant ES as Elasticsearch

    alt Admin suspends seller (seller.suspended)
        Admin->>Postgres: BEGIN TX<br/>UPDATE seller.seller_profile SET suspension_status = SUSPENDED<br/>UPDATE catalog.offer SET status = INACTIVE, status_changed_reason = SUSPENSION<br/>  WHERE seller_id = :sellerId AND status = ACTIVE<br/>INSERT platform.outbox_event (topic=seller.suspended, payload includes offer_ids)
        Postgres-->>Admin: COMMIT
        Relay->>Kafka: Produce to seller.suspended (partition key: seller_id)
        Kafka-->>Consumer: Consume seller.suspended (group: search.seller-suspended)
        Note over Consumer: Idempotency check on platform.processed_event
        Consumer->>ES: Bulk update: set seller_active = false for all offer_ids in payload<br/>Recalculate inStock per product (false if no other active offers remain)
    else Admin manually reinstates seller (seller.reinstated)
        Admin->>Postgres: BEGIN TX<br/>UPDATE seller.seller_profile SET suspension_status = ACTIVE, suspended_until = NULL<br/>UPDATE catalog.offer SET status = ACTIVE, status_changed_reason = NULL<br/>  WHERE seller_id = :sellerId AND status_changed_reason = SUSPENSION<br/>INSERT platform.outbox_event (topic=seller.reinstated, payload includes offer_ids)
        Postgres-->>Admin: COMMIT
        Relay->>Kafka: Produce to seller.reinstated (partition key: seller_id)
        Kafka-->>Consumer: Consume seller.reinstated (group: search.seller-reinstated)
        Note over Consumer: Idempotency check on platform.processed_event
        Consumer->>ES: Bulk update: set seller_active = true for all offer_ids in payload
    else Timed suspension expires (seller.suspension_expired, Workers scheduler)
        Admin->>Postgres: BEGIN TX — Workers polls WHERE suspended_until <= NOW()<br/>UPDATE seller.seller_profile SET suspension_status = ACTIVE, suspended_until = NULL<br/>UPDATE catalog.offer SET status = ACTIVE, status_changed_reason = NULL<br/>  WHERE seller_id = :sellerId AND status_changed_reason = SUSPENSION<br/>INSERT platform.outbox_event (topic=seller.suspension_expired)
        Postgres-->>Admin: COMMIT
        Relay->>Kafka: Produce to seller.suspension_expired (partition key: seller_id)
        Kafka-->>Consumer: Consume seller.suspension_expired (group: search.suspension-expired)
        Note over Consumer: Idempotency check on platform.processed_event
        Consumer->>ES: Bulk update: re-enable SUSPENSION-deactivated offers (set seller_active = true)
    end
    ES-->>Consumer: acknowledged
    Consumer->>Postgres: INSERT platform.processed_event
    Note over Consumer: Commit Kafka offset
```

---

### moderation.listing.removed and listing.soft_deleted — offer and product removal

Producers: Admin module (moderation removal); Catalog module (seller soft-delete, US-P-11).

```mermaid
sequenceDiagram
    participant Source as Admin API / Seller API
    participant Postgres
    participant Relay as Outbox Relay
    participant Kafka
    participant Consumer as SearchConsumer
    participant ES as Elasticsearch

    alt Admin removes listing via moderation (moderation.listing.removed)
        Source->>Postgres: BEGIN TX<br/>UPDATE admin.moderation_case SET status = RESOLVED, decision = REMOVED<br/>UPDATE catalog.offer SET status = REMOVED<br/>INSERT platform.outbox_event (topic=moderation.listing.removed)
        Postgres-->>Source: COMMIT
        Relay->>Kafka: Produce to moderation.listing.removed (partition key: offer_id)
        Kafka-->>Consumer: Consume moderation.listing.removed (group: search.listing-removed)
        Note over Consumer: Idempotency check on platform.processed_event
        Consumer->>ES: Remove offer from /products/_doc/:productId nested offers array<br/>If no active offers remain: remove product doc or mark inStock = false
    else Seller soft-deletes own listing (listing.soft_deleted)
        Source->>Postgres: BEGIN TX<br/>UPDATE catalog.offer SET status = REMOVED<br/>INSERT platform.outbox_event (topic=listing.soft_deleted)
        Postgres-->>Source: COMMIT
        Relay->>Kafka: Produce to listing.soft_deleted (partition key: offer_id)
        Kafka-->>Consumer: Consume listing.soft_deleted (group: search.listing-soft-deleted)
        Note over Consumer: Idempotency check on platform.processed_event
        Consumer->>ES: Remove offer from /products/_doc/:productId nested offers array<br/>If no active offers remain: remove product doc or mark inStock = false
    end
    ES-->>Consumer: acknowledged
    Consumer->>Postgres: INSERT platform.processed_event
    Note over Consumer: Commit Kafka offset
```

---

### fx_rate.updated — display price refresh across all offer documents

Producer: Workers module (FX rate refresh cron, US-P-19).

```mermaid
sequenceDiagram
    participant FXWorker as FX Rate Worker (Workers)
    participant Postgres
    participant Relay as Outbox Relay
    participant Kafka
    participant Consumer as SearchConsumer
    participant ES as Elasticsearch

    Note over FXWorker: Cron job fetches fresh FX rates from external provider
    FXWorker->>Postgres: BEGIN TX<br/>UPSERT pricing.fx_rate SET rate = :rate, as_of = :asOf, updated_at = NOW()<br/>INSERT platform.outbox_event (topic=fx_rate.updated, payload includes base_currency and rates array)
    Postgres-->>FXWorker: COMMIT

    Relay->>Kafka: Produce to fx_rate.updated (partition key: base_currency)

    Kafka-->>Consumer: Consume fx_rate.updated (group: search.fx-rate-updated)
    Note over Consumer: Idempotency check on platform.processed_event
    Note over Consumer: FX rates are display-only — no order repricing
    Consumer->>ES: Bulk update all offer documents priced in base_currency:<br/>Refresh display_prices[currency] = offer_price x new_rate (decimal.js)<br/>for each affected currency pair
    ES-->>Consumer: acknowledged
    Consumer->>Postgres: INSERT platform.processed_event
    Note over Consumer: Commit Kafka offset
```
