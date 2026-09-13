# Phase 1 — Master Backlog

**Project:** AliceUT Global Multi-Vendor Marketplace  
**Last groomed:** 2026-09-13  
**Solo developer:** quality over speed; no deadline  

---

## Backlog Health

- Top 2 sprints: detailed, estimated, sprint-ready (Sprints 1–2)  
- Next 3 sprints: roughly estimated with clear intent (Sprints 3–5)  
- Beyond Sprint 5: directional, task titles only  
- No zombie stories; all items traceable to BRD or user stories  

---

## Epic Index

| ID | Epic | Sprint(s) | Total Tasks | Status |
|----|------|-----------|------------|--------|
| INFRA | Infrastructure | 1 | 12 | Now |
| SHARED | Shared Backend Libraries | 1 | 9 | Now |
| PLATFORM | Outbox + Kafka Infrastructure | 1 | 8 | Now |
| AUTH | Authentication Module | 2 | 19 | Now |
| IDENTITY | User Profile + Addresses | 2 | 6 | Now |
| CATALOG | Catalog Module | 3 | 12 | Next |
| PRICING | Pricing Module | 3 | 9 | Next |
| INVENTORY | Inventory Module | 3–4 | 11 | Next |
| SELLER | Seller Module | 4 | 10 | Next |
| ADMIN | Admin Module | 4 | 14 | Next |
| CART | Cart Module | 4 | 10 | Next |
| SEARCH | Search Module | 5 | 14 | Later |
| ORDERS | Orders / Checkout Module | 6 | 22 | Later |
| NOTIFICATIONS | Notifications Module | 7 | 25 | Later |
| SEED | Seed Data | 7 | 11 | Later |
| FE-SHARED | Frontend Shared Libraries | 8 | 12 | Later |
| FE-AUTH | Frontend Auth Flows | 8 | 10 | Later |
| FE-BUYER | Frontend Buyer Portal | 9 | 13 | Later |
| FE-SELLER | Frontend Seller Portal | 9–10 | 11 | Later |
| FE-ADMIN | Frontend Admin Portal | 10 | 9 | Later |

---

## Epic: INFRA — Infrastructure

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| INFRA-001 | Bootstrap Nx backend monorepo (apps/api, apps/workers, libs/) | M | — | — | Now |
| INFRA-002 | Bootstrap Nx frontend monorepo (apps/buyer-app, apps/seller-app, apps/admin-app, libs/) | M | — | — | Now |
| INFRA-003 | Write docker-compose.yml (all 16 services per topology doc) | L | INFRA-001 | — | Now |
| INFRA-004 | PostgreSQL 16 setup + uuidv7 extension SQL function | M | INFRA-003 | — | Now |
| INFRA-005 | MongoDB 7 setup + connection config (NestJS) | S | INFRA-003 | — | Now |
| INFRA-006 | Redis 7 setup + connection config (ioredis) | S | INFRA-003 | — | Now |
| INFRA-007 | Elasticsearch 8 setup + index template placeholder | M | INFRA-003 | — | Now |
| INFRA-008 | Kafka (KRaft) + Confluent Schema Registry setup | L | INFRA-003 | — | Now |
| INFRA-009 | Kafka UI (provectus) setup + network config | S | INFRA-008 | — | Now |
| INFRA-010 | MinIO setup + minio-init container (3 buckets) | M | INFRA-003 | — | Now |
| INFRA-011 | .env.example + Joi schema validation (fail-fast on missing vars) | M | INFRA-001 | US-P-08 | Now |
| INFRA-012 | Health check endpoints (GET /health on api:3000 and workers:3001) | S | INFRA-001 | — | Now |

---

## Epic: SHARED — Shared Backend Libraries

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| SHARED-001 | JSON structured logger (pino/winston + correlation ID field) | M | INFRA-001 | US-P-10 | Now |
| SHARED-002 | Global HTTP exception filter (maps NestJS exceptions to RFC 7807) | M | INFRA-001 | US-P-09 | Now |
| SHARED-003 | Global validation pipe (class-validator, whitelist:true, forbidNonWhitelisted:true) | S | INFRA-001 | US-P-09 | Now |
| SHARED-004 | Money utility lib (decimal.js wrapper: add, subtract, multiply, format, parse) | M | INFRA-001 | US-P-04 | Now |
| SHARED-005 | Correlation ID middleware (generate X-Correlation-ID on each request) | S | INFRA-001 | NFR-12 | Now |
| SHARED-006 | UUIDv7 generator utility (wraps @uuid/v7 or similar; used everywhere for IDs) | S | INFRA-001 | — | Now |
| SHARED-007 | Swagger / OpenAPI 3 setup (SwaggerModule, auto-generated from decorators) | M | INFRA-001 | — | Now |
| SHARED-008 | JWT auth guard + roles guard (JwtAuthGuard, @Roles decorator, RolesGuard) | M | SHARED-001 | US-A-00b | Now |
| SHARED-009 | Paginated response wrapper type + PaginationQueryDto | S | INFRA-001 | — | Now |

---

## Epic: PLATFORM — Outbox + Kafka Infrastructure

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| PLATFORM-001 | platform schema raw-SQL migrations (outbox_event, processed_event + all enum types) | L | INFRA-004 | US-P-10 | Now |
| PLATFORM-002 | OutboxEvent entity + TypeORM repository + OutboxRepository interface | M | PLATFORM-001 | US-P-10 | Now |
| PLATFORM-003 | ProcessedEvent entity + TypeORM repository + IdempotencyHelper service | M | PLATFORM-001 | US-P-13 | Now |
| PLATFORM-004 | Avro serializer service (Schema Registry client + schema caching) | L | INFRA-008 | US-P-13 | Now |
| PLATFORM-005 | Kafka producer service (KafkaJS + Avro serialization + per-topic schema) | M | PLATFORM-004 | US-P-10 | Now |
| PLATFORM-006 | Outbox relay worker (poll PENDING events → serialize Avro → publish → mark PUBLISHED) | L | PLATFORM-005 | US-P-10 | Now |
| PLATFORM-007 | Consumer idempotency decorator/helper (check processed_event before side-effect, insert after) | M | PLATFORM-003 | US-P-13 | Now |
| PLATFORM-008 | DLQ routing (per consumer group dead-letter topic; route on max retry exceeded) | M | PLATFORM-005 | US-P-14 | Now |

---

## Epic: AUTH — Authentication Module

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| AUTH-001 | identity schema raw-SQL migrations (user, oauth_identity, refresh_session, address, email_verification_token, password_reset_token) | L | PLATFORM-001 | — | Now |
| AUTH-002 | User entity + TypeORM repository + UserRepository interface | M | AUTH-001 | — | Now |
| AUTH-003 | Argon2id password hashing service | S | SHARED-001 | NFR-05 | Now |
| AUTH-004 | Local auth strategy (Passport.js local; validate email+password) | M | AUTH-002 | US-B-00 | Now |
| AUTH-005 | JWT access token service (sign, verify; short TTL from env; sub+roles+email_verified payload) | M | AUTH-002 | NFR-06 | Now |
| AUTH-006 | RefreshSession entity + repository + rotation service (issue, rotate, revoke, revoke-all) | L | AUTH-001 | NFR-06 | Now |
| AUTH-007 | POST /auth/register (buyer) — create user, send email_verification_requested event | M | AUTH-002 | US-B-01 | Now |
| AUTH-008 | POST /auth/login (buyer) — local strategy, return access+refresh tokens | M | AUTH-004 | US-B-00 | Now |
| AUTH-009 | POST /auth/logout — invalidate current refresh token | S | AUTH-006 | US-B-00 | Now |
| AUTH-010 | POST /auth/logout/all — revoke all sessions for account | S | AUTH-006 | US-B-00 | Now |
| AUTH-011 | POST /auth/refresh — rotate refresh token, return new access+refresh | M | AUTH-006 | US-B-00 | Now |
| AUTH-012 | Google OAuth strategy (Passport.js; verify or create account; link if email exists) | L | AUTH-002 | US-B-01 | Now |
| AUTH-013 | Facebook OAuth strategy (Passport.js; same linking logic as Google) | M | AUTH-012 | US-B-01 | Now |
| AUTH-014 | OAuth callback handlers (GET /auth/google/callback, /auth/facebook/callback) | M | AUTH-012 | US-B-01 | Now |
| AUTH-015 | EmailVerificationToken entity + verify endpoint + resend (rate-limit 3/hr) | L | AUTH-001 | US-B-01 | Now |
| AUTH-016 | POST /auth/forgot-password (enumeration-safe; publish password_reset_requested) | M | AUTH-002 | US-B-13 | Now |
| AUTH-017 | POST /auth/reset-password (validate token, update hash, revoke all sessions) | M | AUTH-016 | US-B-13 | Now |
| AUTH-018 | Seller portal auth routes (/seller/login, /seller/forgot-password, /seller/reset-password) | M | AUTH-004 | US-S-12 | Now |
| AUTH-019 | Admin portal auth route (/admin/login; email/password only, no OAuth) | M | AUTH-004 | US-A-00b | Now |

---

## Epic: IDENTITY — User Profile + Addresses

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| IDENTITY-001 | ProfileController: GET /profile, PUT /profile (name, preferred_currency) | M | AUTH-002 | US-B-15 | Now |
| IDENTITY-002 | Address entity + CRUD (POST/GET/PUT/DELETE /profile/addresses) | M | AUTH-001 | US-B-14 | Now |
| IDENTITY-003 | Address limit enforcement (max 10 per user) | S | IDENTITY-002 | US-B-14 | Now |
| IDENTITY-004 | Default address logic (set default, prompt on delete-default) | S | IDENTITY-002 | US-B-14 | Now |
| IDENTITY-005 | B2B business fields: PUT /profile/business (business_name, logo upload) | M | IDENTITY-001 | US-B-15 | Now |
| IDENTITY-006 | Business logo MinIO upload (user-assets bucket; JPEG/PNG/WebP ≤2MB, resize) | M | IDENTITY-005 | US-B-15 | Now |

---

## Epic: CATALOG — Catalog Module

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| CATALOG-001 | catalog schema raw-SQL migrations (category, product, product_variant, product_image, offer) | L | PLATFORM-001 | — | Next |
| CATALOG-002 | Category entity + repository + GET /categories (tree structure) | M | CATALOG-001 | US-B-02 | Next |
| CATALOG-003 | Category taxonomy seed (6+ top-level: electronics, books, home, apparel, kitchen, sports; is_prohibited flags) | M | CATALOG-001 | US-P-06 | Next |
| CATALOG-004 | Product entity + repository interface | M | CATALOG-001 | US-S-03 | Next |
| CATALOG-005 | ProductVariant entity + repository | S | CATALOG-001 | US-S-03 | Next |
| CATALOG-006 | ProductImage entity + MinIO upload handler (product-images bucket; JPEG/PNG/WebP ≤5MB) | L | CATALOG-001 | US-S-03 | Next |
| CATALOG-007 | ProductsController: GET /products, GET /products/:id (buyer read) | M | CATALOG-004 | US-B-05 | Next |
| CATALOG-008 | Offer entity + repository interface | M | CATALOG-001 | US-P-01 | Next |
| CATALOG-009 | Seller product writes: POST/PATCH/DELETE /seller/products (create/edit/soft-delete listing; served by SellerModule per backend-module-architecture.md) | L | CATALOG-008 | US-S-03 | Next |
| CATALOG-010 | Keyword blocklist service + prohibited category guard (block on save, flag offer) | L | CATALOG-008 | US-P-06c | Next |
| CATALOG-011 | Offer status state machine (DRAFT→ACTIVE, ACTIVE→FLAGGED, FLAGGED→ACTIVE/REMOVED; status_changed_reason) | M | CATALOG-008 | US-S-04 | Next |
| CATALOG-012 | Outbox events: product.changed, offer.changed, listing.soft_deleted (Avro schemas registered) | M | PLATFORM-004 | US-P-10 | Next |

---

## Epic: PRICING — Pricing Module

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| PRICING-001 | pricing schema raw-SQL migrations (currency, offer_price, fx_rate) | M | PLATFORM-001 | — | Next |
| PRICING-002 | Currency seed (USD, THB, JPY, SGD; minor_unit_scale; is_seller_price_allowed) | S | PRICING-001 | US-P-06a | Next |
| PRICING-003 | OfferPrice entity + repository interface | M | PRICING-001 | US-P-01 | Next |
| PRICING-004 | PUT /seller/offers/:id/prices/:type (upsert price for currency + type) | L | PRICING-003 | US-S-04b | Next |
| PRICING-005 | Effective price resolution service (B2B_TIER → SALE → LIST priority; time + qty + account_type) | L | PRICING-003 | US-P-01 | Next |
| PRICING-006 | FxRate entity + repository | M | PRICING-001 | US-P-02 | Next |
| PRICING-007 | FX display conversion helper (cheapest-offer + FX → estimated price with ≈ label) | M | PRICING-006 | US-P-02 | Next |
| PRICING-008 | FX rate refresh scheduler (hourly cron; exchangerate.host; publish fx_rate.updated outbox) | M | PRICING-006 | US-P-19 | Next |
| PRICING-009 | Outbox event: fx_rate.updated (Avro schema; base+quote currency pair + rate + as_of) | S | PLATFORM-004 | US-P-19 | Next |

---

## Epic: INVENTORY — Inventory Module

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| INVENTORY-001 | inventory schema raw-SQL migrations (stock, stock_reservation) | M | PLATFORM-001 | — | Next |
| INVENTORY-002 | Stock entity + repository interface (optimistic lock via version column) | M | INVENTORY-001 | US-S-08 | Next |
| INVENTORY-003 | StockReservation entity + repository interface | M | INVENTORY-001 | US-B-09 | Next |
| INVENTORY-004 | InventoryController seller: GET/PUT /seller/inventory (table view + inline edit) | M | INVENTORY-002 | US-S-08 | Next |
| INVENTORY-005 | Low-stock edge-trigger detection (edge: ≥threshold → <threshold; publish inventory.low_stock outbox) | M | INVENTORY-002 | US-S-08 | Next |
| INVENTORY-006 | CSV bulk import: POST /seller/inventory/bulk-import (parse → preview diff → confirm) | L | INVENTORY-002 | US-S-09 | Next |
| INVENTORY-007 | Reservation service: createReservation (atomic: lock stock row, decrement reserved_qty) | M | INVENTORY-003 | US-B-09 | Next |
| INVENTORY-008 | Reservation expiry scheduler (poll ACTIVE reservations past TTL; release + publish inventory.reservation_expired) | M | INVENTORY-003 | US-P-17 | Next |
| INVENTORY-009 | Zero-stock deactivation logic (available_qty=0 → publish inventory.changed; search consumer hides from index) | M | INVENTORY-002 | US-S-03 | Next |
| INVENTORY-010 | Outbox events: inventory.changed, inventory.low_stock, inventory.reservation_expired | M | PLATFORM-004 | US-P-10 | Next |
| INVENTORY-011 | Kafka consumer: fulfillment.placed (consume reservation → CONSUMED; decrement on_hand_qty) | M | PLATFORM-007 | US-B-09 | Next |

---

## Epic: SELLER — Seller Module

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| SELLER-001 | seller schema raw-SQL migrations (seller_profile, kyc_application) | M | PLATFORM-001 | — | Next |
| SELLER-002 | SellerProfile entity + repository interface | M | SELLER-001 | US-S-01 | Next |
| SELLER-003 | KycApplication entity + repository interface | M | SELLER-001 | US-S-01 | Next |
| SELLER-004 | POST /seller/register (step 1: account; link SELLER role to existing account or create new) | L | AUTH-002 | US-S-01 | Next |
| SELLER-005 | POST /seller/kyc (KYC form + doc upload to MinIO kyc-documents bucket; presigned GET for download) | L | SELLER-003 | US-S-01 | Next |
| SELLER-006 | GET /seller/kyc/status (returns current application status + rejection reason if applicable) | S | SELLER-003 | US-S-02 | Next |
| SELLER-007 | POST /seller/kyc/resubmit (update docs + resubmit; links to prior rejection) | M | SELLER-003 | US-S-02 | Next |
| SELLER-008 | SellerKycGuard (block listing endpoints until kyc_status=APPROVED and suspension_status=ACTIVE) | M | SELLER-002 | US-S-02 | Next |
| SELLER-009 | GET /seller/dashboard (counts: pending orders, low-stock SKUs, active listings, flagged listings) | M | SELLER-002 | US-S-00 | Next |
| SELLER-010 | Outbox event: seller.kyc.submitted (Avro schema; seller_id, kyc_application_id, is_resubmission) | S | PLATFORM-004 | US-P-10 | Next |

---

## Epic: ADMIN — Admin Module

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| ADMIN-001 | admin schema raw-SQL migrations (moderation_case) | M | PLATFORM-001 | — | Next |
| ADMIN-002 | ModerationCase entity + repository interface | M | ADMIN-001 | US-A-03 | Next |
| ADMIN-003 | GET /admin/kyc (pending queue; paginated; filterable by country; sortable by submitted_at; SLA badge data) | M | SELLER-003 | US-A-01 | Next |
| ADMIN-004 | POST /admin/kyc/:id/approve (activate seller; publish seller.kyc.decided outbox) | M | SELLER-002 | US-A-02 | Next |
| ADMIN-005 | POST /admin/kyc/:id/reject (set rejection reason; publish seller.kyc.decided outbox) | M | SELLER-002 | US-A-02 | Next |
| ADMIN-006 | GET /admin/moderation (flagged listings queue; sorted by flagged_at DESC) | M | ADMIN-002 | US-A-03 | Next |
| ADMIN-007 | POST /admin/moderation/:caseId/decide (decision: REMOVE\|DISMISS; REMOVE = remove listing + mandatory reason, publish moderation.listing.removed; DISMISS = listing stays live, publish offer.changed) | L | ADMIN-002 | US-A-04, US-A-04b | Next |
| ADMIN-008 | POST /admin/sellers/:id/suspend (reason + duration; deactivate listings; publish seller.suspended) | L | SELLER-002 | US-A-05 | Next |
| ADMIN-009 | POST /admin/sellers/:id/reinstate (early lift; reactivate SUSPENSION listings only; publish seller.reinstated) | M | SELLER-002 | US-A-05b | Next |
| ADMIN-010 | GET /admin/sellers (search by name/email/tax_id; paginated) | M | SELLER-002 | US-A-06 | Next |
| ADMIN-011 | GET /admin/sellers/:id (full profile: KYC status, listings, moderation history) | M | SELLER-002 | US-A-06 | Next |
| ADMIN-012 | GET /admin/dashboard (live counts: pending KYC, flagged listings, suspended sellers, SLA breaches) | M | SELLER-002 | US-A-00 | Next |
| ADMIN-013 | Suspension expiry scheduler (poll SUSPENDED sellers where suspended_until <= now(); reinstate + publish seller.suspension_expired) | M | SELLER-002 | US-P-18 | Next |
| ADMIN-014 | Outbox events: seller.kyc.decided, seller.suspended, seller.reinstated, seller.suspension_expired, moderation.listing.removed, offer.changed | M | PLATFORM-004 | US-P-10 | Next |

---

## Epic: CART — Cart Module

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| CART-001 | cart schema raw-SQL migrations (cart, cart_item) | S | PLATFORM-001 | — | Next |
| CART-002 | Cart entity + repository interface | M | CART-001 | US-B-06 | Next |
| CART-003 | CartItem entity + repository interface | M | CART-001 | US-B-06 | Next |
| CART-004 | GET /cart (fetch server cart; re-resolve current effective prices; flag stale items) | L | CART-003 | US-B-06 | Next |
| CART-005 | POST /cart/items (add item; check availability; cap at available qty; 50-item limit) | M | CART-002 | US-B-06 | Next |
| CART-006 | PUT /cart/items/:id (update quantity; revalidate inventory) | M | CART-003 | US-B-06 | Next |
| CART-007 | DELETE /cart/items/:id (remove item) | S | CART-003 | US-B-06 | Next |
| CART-008 | Guest cart merge on login (sum quantities per offer; cap at live inventory; toast counts) | L | CART-002 | US-B-07 | Next |
| CART-009 | Stale item detection (check offer.status != ACTIVE; label "Unavailable"; block checkout) | M | CART-003 | US-B-06 | Next |
| CART-010 | Cart limit enforcement (50 distinct offer+variant combinations) | S | CART-002 | US-B-06 | Next |

---

## Epic: SEARCH — Search Module

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| SEARCH-001 | Elasticsearch product index mapping (productId, lowestOffer + offer fields, display_prices map, inStock, category path) | L | INFRA-007 | US-B-02 | Later |
| SEARCH-002 | SearchController: GET /search/products (q, categoryId, priceMin, priceMax, currency, inStock, sortBy, limit, cursor) | L | SEARCH-001 | US-B-02 | Later |
| SEARCH-003 | ES query builder (multi-match fuzzy on title+brand+description; bool filter for category/price/stock) | L | SEARCH-001 | US-B-03 | Later |
| SEARCH-004 | Faceted aggregations (category counts, price range) | M | SEARCH-003 | US-B-03 | Later |
| SEARCH-005 | Kafka consumer: product.changed (upsert product doc in ES) | M | PLATFORM-007 | US-P-11 | Later |
| SEARCH-006 | Kafka consumer: offer.changed (update offer fields; recalculate display_prices) | M | PLATFORM-007 | US-P-11 | Later |
| SEARCH-007 | Kafka consumer: inventory.changed (update available_qty field; handle zero-stock visibility) | M | PLATFORM-007 | US-P-11 | Later |
| SEARCH-008 | Kafka consumer: seller.suspended (bulk mark seller's offers as inactive in ES) | M | PLATFORM-007 | US-A-05 | Later |
| SEARCH-009 | Kafka consumer: seller.reinstated / seller.suspension_expired (bulk restore SUSPENSION-deactivated offers) | M | PLATFORM-007 | US-A-05b | Later |
| SEARCH-010 | Kafka consumer: moderation.listing.removed (delete offer doc from ES) | M | PLATFORM-007 | US-A-04 | Later |
| SEARCH-011 | Kafka consumer: listing.soft_deleted (delete offer doc from ES; idempotent if not exists) | M | PLATFORM-007 | US-P-11 | Later |
| SEARCH-012 | Kafka consumer: fx_rate.updated (refresh display_prices map for all offers with affected currency) | L | PLATFORM-007 | US-P-02 | Later |
| SEARCH-013 | Kafka consumer: inventory.reservation_expired (update available_qty in ES) | M | PLATFORM-007 | US-P-17 | Later |
| SEARCH-014 | ES unavailable fallback (503 structured response; featured-products fallback from Postgres on empty query) | M | SEARCH-002 | US-B-02 | Later |

---

## Epic: ORDERS — Orders / Checkout Module

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| ORDERS-001 | orders schema raw-SQL migrations (order, fulfillment, fulfillment_item, payment_attempt, idempotency_key) | L | PLATFORM-001 | — | Later |
| ORDERS-002 | Order entity + repository interface | M | ORDERS-001 | US-B-09 | Later |
| ORDERS-003 | Fulfillment entity + repository interface + status state machine | M | ORDERS-001 | US-B-09 | Later |
| ORDERS-004 | FulfillmentItem entity + repository (immutable; no updated_at) | M | ORDERS-001 | US-P-03 | Later |
| ORDERS-005 | PaymentAttempt entity + repository (mock payment; append-only) | M | ORDERS-001 | US-B-09 | Later |
| ORDERS-006 | IdempotencyKey entity + repository + CheckoutIdempotencyService | M | ORDERS-001 | US-B-09 | Later |
| ORDERS-007 | CheckoutService: cart validation (re-resolve prices; price-revalidation diff; stale item exclusion) | L | CART-003 | US-B-09 | Later |
| ORDERS-008 | CheckoutService: seller/currency grouping algorithm | M | ORDERS-007 | US-B-09 | Later |
| ORDERS-009 | CheckoutService: atomic reservation + snapshot transaction (per-group: reserve inventory → snapshot item prices → create fulfillment + items → clear cart items → write outbox; all in one PG transaction) | XL | ORDERS-008 | US-P-03 | Later |
| ORDERS-010 | CheckoutService: mock payment simulation (deterministic SIMULATED_SUCCESS; create payment_attempt row) | M | ORDERS-009 | US-B-09 | Later |
| ORDERS-011 | Order display_id + fulfillment display_id generation (ORD-<uuid8hex>, FUL-<uuid8hex>) | S | ORDERS-002 | US-B-09 | Later |
| ORDERS-012 | POST /orders/checkout (submit checkout; return order with placement_outcome + fulfillments + skipped/failed) | L | ORDERS-009 | US-B-09 | Later |
| ORDERS-013 | Order aggregate status derivation (from fulfillment states; all rules from US-B-09) | M | ORDERS-003 | US-B-09 | Later |
| ORDERS-014 | GET /orders (buyer order history; paginated; newest first; placement_outcome warning) | M | ORDERS-002 | US-B-11 | Later |
| ORDERS-015 | GET /orders/:id (order detail; immutable snapshot pricing; fulfillment breakdown) | M | ORDERS-002 | US-B-11 | Later |
| ORDERS-016 | GET /seller/fulfillments (seller dashboard list; tabs; paginated; filterable) | M | ORDERS-003 | US-S-05 | Later |
| ORDERS-017 | GET /seller/fulfillments/:id (order detail with buyer address; access-logged for NFR-09) | M | ORDERS-003 | US-S-05b | Later |
| ORDERS-018 | POST /seller/fulfillments/:id/ship (PENDING→SHIPPED; idempotent on repeat; publish fulfillment.shipped outbox) | M | ORDERS-003 | US-S-06 | Later |
| ORDERS-019 | POST /seller/fulfillments/:id/refund (PENDING/SHIPPED→REFUNDED; restore stock if PENDING; publish fulfillment.refunded outbox) | L | ORDERS-003 | US-S-07 | Later |
| ORDERS-020 | POST /seller/fulfillments/:id/cancel (PENDING→CANCELLED; restore stock; fake refund; publish fulfillment.cancelled outbox) | L | ORDERS-003 | US-S-11 | Later |
| ORDERS-021 | Mock delivery scheduler (poll SHIPPED where eta<=now; SHIPPED→DELIVERED; publish fulfillment.delivered; if all delivered → publish order.completed) | M | ORDERS-003 | US-P-15 | Later |
| ORDERS-022 | Auto-refund monitor scheduler (poll PENDING where seller SUSPENDED and placed_at+window<now; PENDING→REFUNDED; restore stock; publish fulfillment.refund_suspended_seller) | M | ORDERS-003 | US-P-16 | Later |

---

## Epic: NOTIFICATIONS — Notifications Module

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| NOTIFICATIONS-001 | notifications schema raw-SQL migrations (in_app_notification, email_template, pending_listing_removal_digest) | M | PLATFORM-001 | — | Later |
| NOTIFICATIONS-002 | InAppNotification entity + repository | M | NOTIFICATIONS-001 | US-P-12 | Later |
| NOTIFICATIONS-003 | NotificationsController: GET /notifications (unread list; paginated), POST /notifications/:id/read | M | NOTIFICATIONS-002 | US-P-12 | Later |
| NOTIFICATIONS-004 | SMTP adapter (nodemailer; async queue; failure-isolated; retry on transient) | L | INFRA-001 | US-P-12 | Later |
| NOTIFICATIONS-005 | EmailTemplate seed (all 21 ET-* templates: Handlebars subjects + html + text bodies) | L | NOTIFICATIONS-001 | US-B-12 | Later |
| NOTIFICATIONS-006 | Kafka consumer: order.finalized → ET-01 (buyer order summary; snapshot pricing) | M | PLATFORM-007 | US-B-12 | Later |
| NOTIFICATIONS-007 | Kafka consumer: fulfillment.shipped → ET-02 (buyer: tracking + ETA) | M | PLATFORM-007 | US-B-12 | Later |
| NOTIFICATIONS-008 | Kafka consumer: fulfillment.delivered → ET-03 + ET-05 (buyer delivered; order completed if ≥2 fulfillments all delivered) | M | PLATFORM-007 | US-B-12 | Later |
| NOTIFICATIONS-009 | Kafka consumer: fulfillment.refunded → ET-04 (buyer refund confirmation) | M | PLATFORM-007 | US-B-12 | Later |
| NOTIFICATIONS-010 | Kafka consumer: fulfillment.cancelled → ET-16 (buyer cancellation notice) | M | PLATFORM-007 | US-S-11 | Later |
| NOTIFICATIONS-011 | Kafka consumer: fulfillment.placed (seller-alert) → ET-17 (seller new order notification) | M | PLATFORM-007 | US-S-05 | Later |
| NOTIFICATIONS-012 | Kafka consumer: seller.kyc.decided (APPROVED) → ET-06 (seller approved) | M | PLATFORM-007 | US-A-02 | Later |
| NOTIFICATIONS-013 | Kafka consumer: seller.kyc.decided (REJECTED) → ET-07 (seller rejected + reason) | M | PLATFORM-007 | US-A-02 | Later |
| NOTIFICATIONS-014 | Kafka consumer: seller.kyc.submitted → ET-14 (seller confirmation) + ET-21 (admin alert) | M | PLATFORM-007 | US-S-01 | Later |
| NOTIFICATIONS-015 | Kafka consumer: listing.flagged → ET-08 (seller flagged + admin CC) | M | PLATFORM-007 | US-S-10 | Later |
| NOTIFICATIONS-016 | Kafka consumer: moderation.listing.removed → staging table (pending_listing_removal_digest) | M | PLATFORM-007 | US-A-04 | Later |
| NOTIFICATIONS-017 | Daily digest scheduler (23:00 UTC; aggregate staging table per seller → ET-09; delete rows) | M | NOTIFICATIONS-001 | US-S-10 | Later |
| NOTIFICATIONS-018 | Kafka consumer: seller.suspended → ET-10 (seller suspension notice) + in-app | M | PLATFORM-007 | US-A-05 | Later |
| NOTIFICATIONS-019 | Kafka consumer: seller.suspension_expired → ET-11 (auto-lift notice) + in-app | M | PLATFORM-007 | US-P-18 | Later |
| NOTIFICATIONS-020 | Kafka consumer: seller.reinstated → ET-12 (admin-lifted notice) | M | PLATFORM-007 | US-A-05b | Later |
| NOTIFICATIONS-021 | Kafka consumer: fulfillment.refund_suspended_seller → ET-13 (buyer) + ET-13b (seller) | M | PLATFORM-007 | US-P-16 | Later |
| NOTIFICATIONS-022 | Kafka consumer: inventory.low_stock → ET-15 (seller low-stock alert) + in-app | M | PLATFORM-007 | US-S-08 | Later |
| NOTIFICATIONS-023 | Kafka consumer: auth.email_verification_requested → ET-18 | M | PLATFORM-007 | US-B-01 | Later |
| NOTIFICATIONS-024 | Kafka consumer: auth.password_reset_requested → ET-19 | M | PLATFORM-007 | US-B-13 | Later |
| NOTIFICATIONS-025 | Kafka consumer: auth.password_changed → ET-20 | M | PLATFORM-007 | US-B-13 | Later |

---

## Epic: SEED — Seed Data

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| SEED-001 | UUIDv7 PostgreSQL extension function (SQL migration; applied before all other migrations) | S | INFRA-004 | — | Later |
| SEED-002 | Idempotent seed runner (NestJS CLI command; check-before-insert; re-runnable) | M | PLATFORM-001 | US-P-06 | Later |
| SEED-003 | Currency seed rows (USD, THB, JPY, SGD; minor_unit_scale; is_seller_price_allowed=true) | S | PRICING-001 | US-P-06a | Later |
| SEED-004 | Demo account seed (4 accounts: consumer, business buyer, seller, admin; argon2id hashed passwords) | M | AUTH-001 | US-P-06 | Later |
| SEED-005 | Category taxonomy seed (6+ top-level; is_prohibited on weapons/drugs/adult; full hierarchy slugs) | M | CATALOG-001 | US-P-06 | Later |
| SEED-006 | Kaggle Amazon product data import pipeline (parse CSV; clean missing fields; map to Product+Variant schema; 100 products) | XL | CATALOG-001 | US-P-06 | Later |
| SEED-007 | Product images import (download from URLs or use placeholder images; upload to MinIO product-images bucket) | L | SEED-006 | US-P-06 | Later |
| SEED-008 | Seeded seller profiles (3 pre-approved sellers; kyc_status=APPROVED; suspension_status=ACTIVE) | M | SELLER-001 | US-P-06 | Later |
| SEED-009 | Offer + price seed (100 offers; mix USD/THB/JPY/SGD; 10% SALE, 5% B2B_TIER; publish product.changed events) | L | SEED-008 | US-P-06 | Later |
| SEED-010 | Inventory seed (reasonable on_hand per offer; low_stock_threshold=5; no initial reservations) | M | INVENTORY-001 | US-P-06 | Later |
| SEED-011 | Email template seed (seed notifications.email_template rows for all 21 ET-* templates) | M | NOTIFICATIONS-001 | US-P-06 | Later |

---

## Epic: FE-SHARED — Frontend Shared Libraries

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| FE-SHARED-001 | Nx frontend workspace setup (Angular 22+; apps: buyer-app, seller-app, admin-app; libs: shared, api-client) | L | INFRA-002 | — | Later |
| FE-SHARED-002 | Angular Material theme setup (design tokens, typography, color palette per conventions/design-system.md) | M | FE-SHARED-001 | — | Later |
| FE-SHARED-003 | HTTP client config (environments; API base URL; withCredentials for refresh cookie) | S | FE-SHARED-001 | — | Later |
| FE-SHARED-004 | Auth interceptor (attach JWT; retry with refresh on 401; redirect to login on refresh failure) | L | FE-SHARED-001 | US-B-00 | Later |
| FE-SHARED-005 | Error interceptor (map API errors to user-friendly messages; structured error display) | M | FE-SHARED-001 | US-P-09 | Later |
| FE-SHARED-006 | Correlation ID header interceptor (add X-Correlation-ID to all requests) | S | FE-SHARED-001 | NFR-12 | Later |
| FE-SHARED-007 | Decimal display pipe (Intl.NumberFormat + decimal.js; currency-aware; no float rounding) | M | FE-SHARED-001 | US-P-04 | Later |
| FE-SHARED-008 | Auth state service (Signals/BehaviorSubject; currentUser, isAuthenticated, roles) | M | FE-SHARED-001 | US-B-00 | Later |
| FE-SHARED-009 | Route guards (AuthGuard, RoleGuard: buyer/seller/admin; redirect to appropriate login) | M | FE-SHARED-008 | US-A-00b | Later |
| FE-SHARED-010 | Shared UI components lib (page header, footer, loading spinner, error state, empty state, paginator) | L | FE-SHARED-002 | — | Later |
| FE-SHARED-011 | nginx Dockerfile for Angular apps (multi-stage build; proxy /api/* to api:3000) | M | INFRA-003 | — | Later |
| FE-SHARED-012 | OpenAPI client generation (openapi-generator-cli typescript-angular; npm script; do-not-edit banner) | M | SHARED-007 | — | Later |

---

## Epic: FE-AUTH — Frontend Auth Flows

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| FE-AUTH-001 | Buyer register page (/register; email/password form + B2B checkbox; client-side validation) | M | FE-SHARED-003 | US-B-01 | Later |
| FE-AUTH-002 | Buyer login page (/login; email/password; redirect on success) | M | FE-SHARED-004 | US-B-00 | Later |
| FE-AUTH-003 | Google OAuth button + redirect flow (/auth/google; callback page) | M | FE-AUTH-002 | US-B-01 | Later |
| FE-AUTH-004 | Facebook OAuth button + redirect flow | M | FE-AUTH-002 | US-B-01 | Later |
| FE-AUTH-005 | Email verification page (/verify-email; token in URL; resend button; rate-limit message) | M | FE-AUTH-001 | US-B-01 | Later |
| FE-AUTH-006 | Forgot password page (/forgot-password; enumeration-safe confirmation) | M | FE-AUTH-002 | US-B-13 | Later |
| FE-AUTH-007 | Reset password page (/reset-password; token from URL; new password form) | M | FE-AUTH-006 | US-B-13 | Later |
| FE-AUTH-008 | Seller login page (/seller/login; email/password only; no OAuth; link to seller register) | M | FE-SHARED-004 | US-S-12 | Later |
| FE-AUTH-009 | Admin login page (/admin/login; email/password only; no OAuth, no register link) | M | FE-SHARED-004 | US-A-00b | Later |
| FE-AUTH-010 | Seller register page (/seller/register; 2-step: account + KYC form; doc upload) | L | FE-AUTH-008 | US-S-01 | Later |

---

## Epic: FE-BUYER — Frontend Buyer Portal

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| FE-BUYER-001 | Home page (search hero + category navigation chips + featured products grid) | M | FE-SHARED-010 | US-B-02 | Later |
| FE-BUYER-002 | Search results page (/search; keyword from query string; results grid; sort dropdown) | L | FE-SHARED-012 | US-B-02 | Later |
| FE-BUYER-003 | Filter sidebar component (category checkbox tree; price range slider; min rating; in-stock toggle; chips in header) | L | FE-BUYER-002 | US-B-03 | Later |
| FE-BUYER-004 | Product detail page (/products/:id; gallery; variant selector; effective price; add-to-cart; B2B tier price) | XL | FE-SHARED-012 | US-B-05 | Later |
| FE-BUYER-005 | "Other sellers" section on PDP (multi-offer list; sorted by cheapest in buyer currency) | M | FE-BUYER-004 | US-P-05 | Later |
| FE-BUYER-006 | Cart page (/cart; line items; qty controls; line total; subtotal/shipping/tax/total; checkout CTA; stale items) | L | FE-SHARED-012 | US-B-06 | Later |
| FE-BUYER-007 | Checkout page (/checkout; 3 stages: address + shipping method + payment; price revalidation modal) | XL | FE-BUYER-006 | US-B-09 | Later |
| FE-BUYER-008 | Order confirmation page (/orders/:id/confirmation; placed/skipped/failed sections; mock tracking) | M | FE-BUYER-007 | US-B-10 | Later |
| FE-BUYER-009 | Order history page (/orders; paginated; status badge; placement warning) | M | FE-SHARED-012 | US-B-11 | Later |
| FE-BUYER-010 | Order detail page (/orders/:id; immutable snapshot; per-fulfillment status + tracking) | M | FE-BUYER-009 | US-B-11 | Later |
| FE-BUYER-011 | Profile page (/profile; name, preferred currency, account type, member since; read-only email) | M | FE-SHARED-012 | US-B-15 | Later |
| FE-BUYER-012 | Address book management (/profile/addresses; add/edit/delete/set-default; 10 address limit) | M | FE-BUYER-011 | US-B-14 | Later |
| FE-BUYER-013 | In-app notification bell + dropdown (unread count badge; list with mark-read; link to relevant page) | M | FE-SHARED-010 | US-P-12 | Later |

---

## Epic: FE-SELLER — Frontend Seller Portal

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| FE-SELLER-001 | Seller dashboard (/seller/dashboard; 4 count cards; pending approval / suspension banners) | M | FE-SHARED-010 | US-S-00 | Later |
| FE-SELLER-002 | KYC status page (/seller/kyc; pending/approved/rejected states; resubmit CTA) | M | FE-AUTH-010 | US-S-02 | Later |
| FE-SELLER-003 | Product create/edit form (/seller/products/new + /seller/products/:id/edit; title/desc/category/variants) | XL | FE-SHARED-012 | US-S-03 | Later |
| FE-SELLER-004 | Image upload + drag-to-reorder component (multi-file; per-image error states; thumbnail preview) | L | FE-SELLER-003 | US-S-03 | Later |
| FE-SELLER-005 | Pricing sub-form (LIST/SALE/B2B_TIER rows; date pickers for SALE; min_qty for B2B_TIER; currency selector) | L | FE-SELLER-003 | US-S-04b | Later |
| FE-SELLER-006 | Listings management page (/seller/products; ACTIVE/FLAGGED/REMOVED badges; edit/delete actions) | M | FE-SHARED-012 | US-S-04 | Later |
| FE-SELLER-007 | Inventory management page (/seller/inventory; table; inline on_hand edit; threshold config) | M | FE-SHARED-012 | US-S-08 | Later |
| FE-SELLER-008 | CSV bulk import page (/seller/inventory/import; upload; preview diff; confirm) | M | FE-SELLER-007 | US-S-09 | Later |
| FE-SELLER-009 | Fulfillment dashboard (/seller/fulfillments; 5 tabs; list with ship/refund/cancel actions) | L | FE-SHARED-012 | US-S-05 | Later |
| FE-SELLER-010 | Order detail view (/seller/fulfillments/:id; buyer address; snapshot items; action buttons) | M | FE-SELLER-009 | US-S-05b | Later |
| FE-SELLER-011 | Suspended seller restricted view (limited to pending orders tab; all other sections show suspension message) | M | FE-SELLER-001 | US-A-05 | Later |

---

## Epic: FE-ADMIN — Frontend Admin Portal

| Task ID | Title | Estimate | Depends On | US Ref | Status |
|---------|-------|----------|------------|--------|--------|
| FE-ADMIN-001 | Admin dashboard (/admin/dashboard; 4 count cards with links to queues; SLA breach count) | M | FE-SHARED-010 | US-A-00 | Later |
| FE-ADMIN-002 | KYC applications queue (/admin/kyc; paginated list; country filter; SLA badge; resubmit badge) | M | FE-SHARED-012 | US-A-01 | Later |
| FE-ADMIN-003 | KYC review page (/admin/kyc/:id; PDF/image doc viewer; approve/reject with mandatory reason) | L | FE-ADMIN-002 | US-A-02 | Later |
| FE-ADMIN-004 | Flagged listings queue (/admin/moderation; sorted by flagged_at; product+seller+reason) | M | FE-SHARED-012 | US-A-03 | Later |
| FE-ADMIN-005 | Listing moderation actions (remove with reason dropdown+text / clear flag; multi-select support) | L | FE-ADMIN-004 | US-A-04 | Later |
| FE-ADMIN-006 | Seller search page (/admin/sellers; search by name/email/tax_id; paginated results) | M | FE-SHARED-012 | US-A-06 | Later |
| FE-ADMIN-007 | Seller profile view (/admin/sellers/:id; full history; KYC status; moderation history; links to actions) | L | FE-ADMIN-006 | US-A-06 | Later |
| FE-ADMIN-008 | Suspend seller modal (reason + duration selector; permanent confirmation dialog) | M | FE-ADMIN-007 | US-A-05 | Later |
| FE-ADMIN-009 | Reinstate seller modal (mandatory reason; confirm) | M | FE-ADMIN-007 | US-A-05b | Later |

---

## Icebox (Explicitly Out of Scope — V1)

- Real payment gateway (Stripe/PayPal)
- Real shipping integration (EasyPost/carrier APIs)
- Reviews and ratings system
- Wishlist and personalized recommendations
- Seller analytics dashboard
- Dispute / refund mediation workflow
- Commission and payout configuration
- Multi-language i18n
- Native mobile apps
- Kubernetes / Istio deployment
- Guest checkout (requires authenticated account in V1)
- Buyer email address change
- Draft/publish workflow for seller listings (all listings go live on save)
- Post-delivery returns (DELIVERED→REFUNDED out of scope)
- Partial refunds
- Buyer-initiated order cancellation

All icebox items require a BRD amendment before implementation.

---

## Definition of Ready

A task is sprint-ready when:
- Acceptance criteria are defined (traceable to user story)
- Dependencies are resolved (task IDs listed and completed or in-sprint)
- Estimated
- No unresolved design questions
- Migration or schema changes drafted

## Definition of Done

A task is done when:
- Code written + unit tests ≥ 70% line coverage (backend)
- Happy path + at least one error path tested
- Swagger docs updated (if new/changed endpoint)
- PR merged to main
- No lint errors
- Dependent tasks unblocked
