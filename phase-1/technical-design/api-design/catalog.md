# Catalog API — Public Browse

**Module:** `Catalog`  
**Parent:** [API Design Index](../api-design.md)  
**Source of truth:** [BRD v1.1](../../requirements/BRD.md), [ERD](../data-model-erd.md)

---

## Summary

- [Endpoint Index](#endpoint-index)
- [DB Mapping](#db-mapping)
- [Endpoints](#endpoints)

<a id="endpoint-index"></a>
## Endpoint Index

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | [`/catalog/categories`](#list-categories) | PUBLIC | Full category tree |
| `GET` | [`/catalog/categories/:id`](#get-category) | PUBLIC | Single category with children |
| `GET` | [`/catalog/products`](#list-products-public-browse) | PUBLIC | Paginated product list |
| `GET` | [`/catalog/products/:id`](#get-product-detail) | PUBLIC | Product detail with active offers |
| `GET` | [`/catalog/products/:id/offers`](#get-product-offers) | PUBLIC | All active offers for a product |

---

<a id="db-mapping"></a>
## DB Mapping

| Endpoint | Primary DB | Tables |
|----------|-----------|--------|
| `GET /catalog/categories` | Postgres | `catalog.category` (full tree read) |
| `GET /catalog/categories/:id` | Postgres | `catalog.category` (single + children) |
| `GET /catalog/products` | Postgres | `catalog.product`, `catalog.product_variant`, `catalog.product_image` |
| `GET /catalog/products/:id` | Postgres | `catalog.product`, `catalog.product_variant`, `catalog.product_image`, `catalog.offer`, `pricing.offer_price`, `inventory.stock` |
| `GET /catalog/products/:id/offers` | Postgres | `catalog.offer`, `pricing.offer_price`, `pricing.fx_rate`, `inventory.stock`, `seller.seller_profile` |

**Note:** Catalog endpoints are read-only public routes. All writes go through the Seller API (`/seller/products`, `/seller/offers`). Elasticsearch is the search read model — see [search.md](search.md) for `/search/products`.

---

<a id="endpoints"></a>
## Endpoints

### List categories

```
GET /catalog/categories
Tag: Catalog
Auth: PUBLIC
```
**Response 200**
```json
{
  "data": [{
    "id": "uuid",
    "parentId": "uuid | null",
    "name": "Electronics",
    "slug": "electronics",
    "children": [...]
  }]
}
```
Returns the full category tree (nested or flat with `parentId`). No pagination — category count bounded by taxonomy.

#### Sequence

```mermaid
sequenceDiagram
    participant Client
    participant API as API (NestJS)
    participant CatalogService
    participant Postgres

    Client->>API: GET /catalog/categories
    Note over API: PUBLIC — no auth guard
    API->>CatalogService: getCategories()
    CatalogService->>Postgres: SELECT id, parent_id, name, slug<br/>FROM catalog.category ORDER BY parent_id NULLS FIRST, name
    Postgres-->>CatalogService: category rows (flat list)
    Note over CatalogService: Assemble nested tree in memory (root nodes first#59; attach children by parent_id)
    CatalogService-->>API: nested category tree
    API-->>Client: 200 { data: [{ id, parentId, name, slug, children }] }
```

---

### Get category

```
GET /catalog/categories/:categoryId
Tag: Catalog
Auth: PUBLIC
```
**Response 200** — single category with children

#### Sequence

```mermaid
sequenceDiagram
    participant Client
    participant API as API (NestJS)
    participant CatalogService
    participant Postgres

    Client->>API: GET /catalog/categories/:categoryId
    Note over API: PUBLIC — no auth guard
    API->>CatalogService: getCategoryById(categoryId)
    CatalogService->>Postgres: SELECT id, parent_id, name, slug FROM catalog.category<br/>WHERE id = :categoryId
    Postgres-->>CatalogService: category row
    alt category not found
        CatalogService-->>API: null
        API-->>Client: 404 Not Found
    else found
        CatalogService->>Postgres: SELECT id, parent_id, name, slug FROM catalog.category<br/>WHERE parent_id = :categoryId
        Postgres-->>CatalogService: direct children rows
        CatalogService-->>API: category with children array
        API-->>Client: 200 { data: { id, parentId, name, slug, children: [...] } }
    end
```

---

### List products (public browse)

```
GET /catalog/products
Tag: Catalog
Auth: PUBLIC
Pagination: cursor
```
**Query params**
- `categoryId`: UUID
- `status`: `ACTIVE` (default, only value exposed publicly)
- `limit`, `cursor`

**Response 200**
```json
{
  "data": [{
    "id": "uuid",
    "title": "string",
    "brand": "string",
    "categoryId": "uuid",
    "status": "ACTIVE",
    "images": [{ "storageKey": "string", "position": 0 }],
    "variants": [{ "id": "uuid", "sku": "string", "attributes": {} }]
  }],
  "meta": { "nextCursor": "string | null", "hasMore": false }
}
```

#### Sequence

```mermaid
sequenceDiagram
    participant Client
    participant API as API (NestJS)
    participant CatalogService
    participant Postgres

    Client->>API: GET /catalog/products?categoryId&limit=20&cursor
    Note over API: PUBLIC — no auth guard. status always ACTIVE (only value exposed publicly)
    API->>CatalogService: listProducts({ categoryId, limit, cursor })
    Note over CatalogService: Decode opaque cursor to UUIDv7 lower bound
    CatalogService->>Postgres: SELECT p.*, v.id, v.sku, v.attributes, i.storage_key, i.position<br/>FROM catalog.product p<br/>LEFT JOIN catalog.product_variant v ON v.product_id = p.id<br/>LEFT JOIN catalog.product_image i ON i.product_id = p.id<br/>WHERE p.status = 'ACTIVE'<br/>AND (categoryId IS NULL OR p.category_id = :categoryId)<br/>AND p.id > :cursor ORDER BY p.id LIMIT :limit + 1
    Postgres-->>CatalogService: product + variant + image rows
    Note over CatalogService: Aggregate rows into product objects. If count = limit+1: hasMore=true, trim last row, encode nextCursor from last included product id
    CatalogService-->>API: products[], nextCursor, hasMore
    API-->>Client: 200 { data: [...], meta: { nextCursor, hasMore } }
```

---

### Get product detail

```
GET /catalog/products/:productId
Tag: Catalog
Auth: PUBLIC
```
**Response 200**
```json
{
  "data": {
    "id": "uuid",
    "title": "string",
    "brand": "string",
    "description": "string",
    "categoryId": "uuid",
    "status": "ACTIVE",
    "attributes": {},
    "variants": [{ "id": "uuid", "sku": "string", "attributes": {} }],
    "images": [{ "storageKey": "string", "altText": "string | null", "position": 0 }],
    "offers": [
      {
        "offerId": "uuid",
        "sellerId": "uuid",
        "variantId": "uuid | null",
        "variantLabel": "string | null",
        "effectivePrice": {
          "amount": "99.99",
          "currency": "USD",
          "priceType": "LIST | SALE",
          "saleEndsAt": "ISO8601 | null"
        },
        "availableQty": 42,
        "status": "ACTIVE"
      }
    ]
  }
}
```
**Note:** `effectivePrice.amount` is a string (money-as-string convention). No FX display conversion on this endpoint — use `GET /catalog/products/:id/offers?currency=` for buyer display currency.

**Errors:** 404

**Note:** No `currency` query param — `effectivePrice.amount` / `effectivePrice.currency` reflect the seller's native pricing currency only. No FX display conversion. For buyer display currency, use `GET /catalog/products/:id/offers?currency=` or `GET /pricing/offers/:id/effective-price?currency=`.

#### Sequence

```mermaid
sequenceDiagram
    participant Client
    participant API as API (NestJS)
    participant CatalogService
    participant Postgres

    Client->>API: GET /catalog/products/:productId
    Note over API: PUBLIC — no auth guard
    API->>CatalogService: getProductDetail(productId)
    CatalogService->>Postgres: SELECT id, title, brand, description, category_id, status, attributes<br/>FROM catalog.product WHERE id = :productId AND status = 'ACTIVE'
    Postgres-->>CatalogService: product row
    alt product not found or status != ACTIVE
        CatalogService-->>API: null
        API-->>Client: 404 Not Found
    else found
        CatalogService->>Postgres: SELECT id, sku, attributes FROM catalog.product_variant<br/>WHERE product_id = :productId
        Postgres-->>CatalogService: variant rows
        CatalogService->>Postgres: SELECT storage_key, alt_text, position FROM catalog.product_image<br/>WHERE product_id = :productId ORDER BY position
        Postgres-->>CatalogService: image rows
        CatalogService->>Postgres: SELECT o.id, o.seller_id, o.variant_id,<br/>op.amount, op.currency_code, op.price_type, op.min_qty, op.starts_at, op.ends_at,<br/>(s.on_hand_qty - s.reserved_qty) AS available_qty<br/>FROM catalog.offer o<br/>JOIN pricing.offer_price op ON op.offer_id = o.id<br/>JOIN inventory.stock s ON s.offer_id = o.id<br/>WHERE o.product_id = :productId AND o.status = 'ACTIVE'
        Postgres-->>CatalogService: active offers with all price rows and stock
        Note over CatalogService: Resolve effectivePrice per offer (B2C default, qty = 1): 1. SALE row present AND NOW() BETWEEN starts_at AND ends_at use SALE. 2. Otherwise use LIST
        CatalogService-->>API: product + variants + images + offers with effectivePrice
        API-->>Client: 200 { data: { id, title, brand, description, variants, images, offers } }
    end
```

---

### Get product offers

```
GET /catalog/products/:productId/offers
Tag: Catalog
Auth: PUBLIC
```
**Query params:** `currency` (ISO 4217, optional — **buyer's display preference currency**, defaults to USD)  
**Response 200**
```json
{
  "data": [{
    "id": "uuid",
    "sellerId": "uuid",
    "sellerName": "string",
    "variantId": "uuid | null",
    "status": "ACTIVE",
    "effectivePrice": {
      "amount": "99.99",
      "currency": "USD",
      "priceType": "LIST | SALE",
      "saleEndsAt": "ISO8601 | null",
      "displayAmount": "3440.00",
      "displayCurrency": "THB",
      "fxRate": "34.40000000"
    },
    "availableQty": 10
  }]
}
```
**Field semantics:**
- `effectivePrice.amount` / `effectivePrice.currency` — seller's native pricing currency (resolved from `pricing.offer_price`)
- `effectivePrice.displayAmount` / `effectivePrice.displayCurrency` / `effectivePrice.fxRate` — buyer's requested display currency (FX-converted from seller's native price using `pricing.fx_rate`). Omitted when `?currency` matches the offer's native currency.

#### Sequence

```mermaid
sequenceDiagram
    participant Client
    participant API as API (NestJS)
    participant CatalogService
    participant Postgres

    Client->>API: GET /catalog/products/:productId/offers?currency=USD
    Note over API: PUBLIC — no auth guard. currency defaults to USD
    API->>CatalogService: getProductOffers(productId, currency)
    CatalogService->>Postgres: SELECT o.id, o.seller_id, o.variant_id, sp.business_name AS seller_name<br/>FROM catalog.offer o<br/>JOIN seller.seller_profile sp ON sp.id = o.seller_id<br/>WHERE o.product_id = :productId AND o.status = 'ACTIVE'<br/>AND sp.kyc_status = 'APPROVED' AND sp.suspension_status = 'ACTIVE'
    Postgres-->>CatalogService: offers from KYC-approved non-suspended sellers only
    CatalogService->>Postgres: SELECT offer_id, amount, currency_code, price_type, min_qty, starts_at, ends_at<br/>FROM pricing.offer_price<br/>WHERE offer_id IN (:offerIds)
    Postgres-->>CatalogService: all price rows for all offers (seller's native currencies)
    CatalogService->>Postgres: SELECT offer_id, (on_hand_qty - reserved_qty) AS available_qty<br/>FROM inventory.stock WHERE offer_id IN (:offerIds)
    Postgres-->>CatalogService: available stock per offer
    Note over CatalogService: Resolve effectivePrice per offer (B2C default, qty = 1) in seller's native currency: 1. SALE row present AND NOW() BETWEEN starts_at AND ends_at use SALE. 2. Otherwise use LIST
    alt display currency != seller's native currency for any offer
        CatalogService->>Postgres: SELECT base_currency_code, quote_currency_code, rate<br/>FROM pricing.fx_rate<br/>WHERE (base_currency_code, quote_currency_code) IN (:pairs)
        Postgres-->>CatalogService: FX rate rows
        Note over CatalogService: Compute displayAmount = amount x rate (decimal.js). Populate displayCurrency, fxRate. Omit display fields when seller's native == requested display currency.
    end
    CatalogService-->>API: offers with effectivePrice (native + optional display fields) + availableQty
    API-->>Client: 200 { data: [{ id, sellerId, sellerName, variantId, effectivePrice, availableQty }] }
```
