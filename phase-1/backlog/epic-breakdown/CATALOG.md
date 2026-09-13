# EPIC: CATALOG — Catalog Module

**Sprint:** 3
**Lib:** `libs/catalog/`
**Module:** `CatalogModule`
**Controllers:** `CategoriesController`, `ProductsController`, `SellerCatalogController`
**Kafka producers:** `product.changed`, `offer.changed`, `listing.soft_deleted`, `listing.flagged`

Overview: Manages the product taxonomy, seller listings, and listing lifecycle state. Products and offers are separate concepts — a product is the canonical item; an offer is a seller's listing of that product at a specific price. Listing moderation state (FLAGGED/REMOVED) is managed here but decided by the admin module.

---

### CATALOG-001 — catalog Schema Migrations
**US Ref:** —
**Estimate:** L
**Dependencies:** PLATFORM-001
**Implementation Notes:**
- File: `libs/catalog/src/infrastructure/migrations/0001_catalog_schema.sql`
- Create `catalog` schema; tables: `catalog.category`, `catalog.product`, `catalog.product_variant`, `catalog.product_image`, `catalog.offer`
- All columns/constraints per data-model-erd.md §5 catalog section
- `catalog.offer.status` uses `offer_status` enum (defined in PLATFORM-001)
- `catalog.offer.status_changed_reason TEXT NULLABLE` — values: `SUSPENSION`, `ADMIN_REMOVAL`, `SELLER_DEACTIVATED`, `SELLER_MANUAL`
- `catalog.offer.seller_id FK → seller.seller_profile(id)` — this cross-schema FK applied in a separate `0002_catalog_offer_seller_fk.sql` after seller migrations run
- Indexes: `product(category_id)`, `product(status)`, `offer(seller_id)`, `offer(product_id)`, `offer(status)`, `product_variant(product_id)`, `product_image(product_id, position)`

**Done Criteria:**
- All catalog tables created; `SELECT * FROM catalog.offer LIMIT 0` succeeds

---

### CATALOG-002 — Category Entity + GET /categories
**US Ref:** US-B-02, US-B-03
**Estimate:** M
**Dependencies:** CATALOG-001
**Implementation Notes:**
- TypeORM entity for `catalog.category` (self-referential parent_id)
- `GET /categories` — returns full tree (recursive CTE or app-layer tree builder); format: `[{ id, name, slug, isProhibited, children: [...] }]`
- `GET /categories/:id` — single category with children
- Recursive tree building: use PostgreSQL `WITH RECURSIVE` CTE for efficiency; max depth 5 levels
- `isProhibited` flag exposed in API for frontend to show warning when seller selects

**Done Criteria:**
- `GET /categories` returns nested tree structure with children arrays
- Root categories have `parentId: null`; leaf categories have `children: []`

---

### CATALOG-003 — Category Taxonomy Seed
**US Ref:** US-P-06
**Estimate:** M
**Dependencies:** CATALOG-001
**Implementation Notes:**
- Seeded in `npm run seed` (see SEED-005); taxonomy scaffold here
- Root categories: Electronics, Books, Home & Kitchen, Apparel & Clothing, Sports & Outdoors, Toys & Games
- Sub-categories per root (2–4 per root for 100 products; enough to demonstrate hierarchy)
- `is_prohibited = true` for any subcategory in: Weapons (under a "Tools" or separate root), Drugs, Adult Content — create stub prohibited categories for moderation testing
- Slugs: URL-safe, e.g. `electronics`, `books`, `home-kitchen`

**Done Criteria:**
- `GET /categories` returns at least 6 root categories with subcategories
- `is_prohibited = true` categories exist for testing moderation guard

---

### CATALOG-004 — Product Entity + Repository Interface
**US Ref:** US-S-03, US-B-05
**Estimate:** M
**Dependencies:** CATALOG-001
**Implementation Notes:**
- TypeORM entity for `catalog.product`
- `ProductRepository` interface: `findById(id)`, `findWithOffers(id)`, `save(product)`, `softDelete(id)`
- Domain class `Product`: `isActive()`, `isRemoved()`
- `attributes JSONB` field for V1: stores imported `{ "rating": 4.3 }` from seed; no mutation endpoint
- File: `libs/catalog/src/domain/product.ts`, `libs/catalog/src/infrastructure/repositories/product.repository.ts`

**Done Criteria:**
- Unit test: `Product.isActive()` returns false when status = REMOVED

---

### CATALOG-005 — ProductVariant Entity + Repository
**US Ref:** US-S-03
**Estimate:** S
**Dependencies:** CATALOG-001
**Implementation Notes:**
- TypeORM entity for `catalog.product_variant`
- `attributes JSONB`: normalized attributes like `{ "color": "Black", "size": "M" }`
- `sku` is unique per product
- `ProductVariantRepository`: `findByProductId(productId)`, `findBySku(productId, sku)`, `save(variant)`

**Done Criteria:**
- Duplicate SKU within same product returns unique constraint error

---

### CATALOG-006 — ProductImage Entity + MinIO Upload
**US Ref:** US-S-03
**Estimate:** L
**Dependencies:** CATALOG-001, INFRA-010
**Implementation Notes:**
- TypeORM entity for `catalog.product_image`; `position SMALLINT` unique per product for ordering
- `POST /seller/products/:id/images` — multipart upload, 1–10 images, JPEG/PNG/WebP ≤5MB each
- Upload to MinIO `product-images` bucket; key: `products/{productId}/{uuid}.{ext}`
- Public read policy (no presigned URL needed; direct URL from MinIO)
- `PUT /seller/products/:id/images/reorder` — accepts ordered array of image IDs; updates `position` values
- Error handling: per-image error, partial failure allowed (US-S-03)
- Use `multer` or NestJS `@UploadedFiles()` for multipart

**Done Criteria:**
- Upload 3 images → MinIO `product-images` bucket shows them; GET product returns image URLs
- Reorder endpoint changes position; GET returns new order

---

### CATALOG-007 — ProductsController (Buyer Read)
**US Ref:** US-B-05
**Estimate:** M
**Dependencies:** CATALOG-004
**Implementation Notes:**
- `GET /products/:id` — returns product with all its active offers, variants, images, category breadcrumb, effective prices (via PricingService), availability badge
- No authentication required (public endpoint); `@Public()`
- Effective price resolved per offer via `PricingService.resolveEffectivePrice(offerId, accountType, qty)` — must be injected from pricing module
- If buyer is authenticated, use their `preferred_currency` for FX display; otherwise default to USD
- Response includes `attributes.rating` for star display (V1 seed-only)
- `GET /products` — paginated product list (used by home page; no search — search goes through SEARCH module)

**Done Criteria:**
- GET /products/:id returns product with offers, images, variants, and effective price per currency
- REMOVED product returns 404

---

### CATALOG-008 — Offer Entity + Repository Interface
**US Ref:** US-P-01
**Estimate:** M
**Dependencies:** CATALOG-001
**Implementation Notes:**
- TypeORM entity for `catalog.offer`
- `OfferRepository` interface: `findById(id)`, `findBySellerAndProduct(sellerId, productId)`, `findByProduct(productId)`, `save(offer)`, `updateStatus(id, status, reason?)`
- `Offer.isAvailableForCart(): boolean` — status = ACTIVE and has at least one price
- `variant_id` validation: if present, must belong to `offer.product_id` (enforce in service layer + DB constraint)

**Done Criteria:**
- Unit test: `Offer.isAvailableForCart()` = false when status = FLAGGED

---

### CATALOG-009 — SellerCatalogController (Create/Edit/Delete)
**US Ref:** US-S-03, US-S-04
**Estimate:** L
**Dependencies:** CATALOG-008, SELLER-008
**Implementation Notes:**
- All endpoints guarded by `@JwtAuthGuard` + `@Roles('SELLER')` + `SellerKycGuard` (approved + active seller only)
- `POST /seller/products` — DTO: `CreateProductDto { title (10-200), description (Markdown ≤5000), categoryId, variants: [...], initialInventory: number }` — creates Product + Offer + Stock (initial) + publishes product.changed + offer.changed events in one transaction
- `PUT /seller/products/:id` — edit own product only; re-run keyword blocklist check on save
- `DELETE /seller/products/:id` — soft-delete: set `product.status = REMOVED`, all offers `status = REMOVED`; publish `listing.soft_deleted` event
- Ownership check: `offer.seller_id = authenticated seller's profile id`; 404 if not owned
- Cannot delete listing with PENDING orders on any variant (check before delete)
- No DRAFT state: listings go live immediately on create

**Done Criteria:**
- Create product → product in DB + offer in DB + outbox events published
- Cannot edit another seller's product → 404
- Soft-delete with PENDING orders blocked → 422

---

### CATALOG-010 — Keyword Blocklist + Prohibited Category Guard
**US Ref:** US-S-03, FR-P-06c
**Estimate:** L
**Dependencies:** CATALOG-008
**Implementation Notes:**
- `ModerationGuardService`:
  - `checkCategory(categoryId): boolean` — returns true if `category.is_prohibited = true` or any ancestor is prohibited
  - `checkKeywords(title, description): string[]` — returns matched keywords from blocklist
- Blocklist: seeded table or hardcoded constant; keywords: weapons (`gun`, `knife`, `explosive`, ...), drugs (`cocaine`, `heroin`, `cannabis`, ...), adult content (explicit terms)
- On listing create/edit: if category prohibited → block with 422 "Category contains prohibited items"; if keywords matched → set `offer.status = FLAGGED`; publish `listing.flagged` outbox event; seller notified (async via Kafka consumer in notifications module)
- Offer `FLAGGED` means `moderation.moderation_case` is created for admin review
- File: `libs/catalog/src/application/moderation-guard.service.ts`

**Done Criteria:**
- Title containing "cocaine" → offer flagged; `listing.flagged` event in outbox
- Prohibited category → 422 blocked immediately
- False-positive can be cleared by admin (via ADMIN-008)

---

### CATALOG-011 — Offer Status State Machine
**US Ref:** US-S-04, US-A-04, US-A-05
**Estimate:** M
**Dependencies:** CATALOG-008
**Implementation Notes:**
- Valid transitions (enforced in `OfferStatusService`):
  - `DRAFT → ACTIVE` (seller activates)
  - `ACTIVE → FLAGGED` (keyword blocklist hit or admin flag)
  - `FLAGGED → ACTIVE` (admin clears false positive via ADMIN-008)
  - `FLAGGED → REMOVED` (admin removes via ADMIN-007)
  - `ACTIVE → INACTIVE` (seller deactivates; reason = `SELLER_MANUAL`)
  - `ACTIVE/INACTIVE → INACTIVE` (seller suspended; reason = `SUSPENSION`)
  - `INACTIVE → ACTIVE` (seller reinstated; only if reason = `SUSPENSION`)
  - `ACTIVE/FLAGGED/INACTIVE → REMOVED` (admin action; reason = `ADMIN_REMOVAL`)
- `status_changed_reason` tracked so suspension reinstatement only restores SUSPENSION-deactivated offers

**Done Criteria:**
- Unit test: invalid transition (REMOVED → ACTIVE) throws InvalidTransitionError
- Suspension reinstatement only restores offers with `status_changed_reason = 'SUSPENSION'`

---

### CATALOG-012 — Outbox Events: product.changed, offer.changed, listing.soft_deleted, listing.flagged
**US Ref:** US-P-10, US-P-11
**Estimate:** M
**Dependencies:** PLATFORM-004, CATALOG-008
**Implementation Notes:**
- Register Avro schemas in Schema Registry for: `product.changed` (v1), `offer.changed` (v1), `listing.soft_deleted` (v1), `listing.flagged` (v1)
- `product.changed` payload: `{ product_id, status, category_id, title, description, brand, attributes, changed_at }`
- `offer.changed` payload: `{ offer_id, product_id, seller_id, status, status_changed_reason, variant_id, changed_at }`
- `listing.soft_deleted` payload: `{ offer_id, product_id, seller_id, soft_deleted_at }`
- `listing.flagged` payload: `{ offer_id, product_id, seller_id, flag_reason, source, flagged_at }`
- Events published inside the domain transaction (same PG TX as the state change) by writing to `platform.outbox_event`

**Done Criteria:**
- Create product → `product.changed` + `offer.changed` events appear in Kafka UI within 2s of TX commit
- Schema Registry shows all 4 schemas registered
