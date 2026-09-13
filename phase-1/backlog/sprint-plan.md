# Phase 1 — Sprint Plan

**Project:** AliceUT Global Multi-Vendor Marketplace  
**Team:** Solo developer  
**Sprint length:** 2 weeks  
**Capacity:** ~40h / sprint (8h/day × 5 days × 2 weeks; 20% buffer for review/bugs)  
**Total sprints:** 11  
**Last updated:** 2026-09-13  

---

## Estimation Legend

| Size | Hours | Description |
|------|-------|-------------|
| S | 2h | Simple CRUD, config, migration |
| M | 4h | Standard service/entity/endpoint |
| L | 8h | Complex logic, multi-layer, auth flows |
| XL | 12h+ | Critical path, atomic transaction, full feature |

---

## Sprint 1 — Foundation
**Goal:** Dev environment up; NestJS and Angular monorepos init; Docker services running; outbox/Kafka infrastructure ready; shared libs complete.  
**Capacity:** 40h  

| Task ID | Title | Size | Hours |
|---------|-------|------|-------|
| INFRA-001 | Bootstrap Nx backend monorepo | M | 4 |
| INFRA-002 | Bootstrap Nx frontend monorepo | M | 4 |
| INFRA-003 | docker-compose.yml — all 16 services | L | 8 |
| INFRA-004 | PostgreSQL 16 + uuidv7 SQL function | M | 4 |
| INFRA-005 | MongoDB 7 + NestJS connection | S | 2 |
| INFRA-006 | Redis 7 + ioredis config | S | 2 |
| INFRA-008 | Kafka (KRaft) + Schema Registry | L | 8 |
| INFRA-010 | MinIO + minio-init (3 buckets) | M | 4 |
| INFRA-011 | .env.example + Joi validation | M | 4 |
| **Total** | | | **40h** |

**Sprint 1 Done Criteria:**
- `docker-compose up` brings all 16 services without manual setup
- PostgreSQL `uuidv7()` function callable
- Kafka UI accessible at localhost:8080
- MinIO console accessible; all 3 buckets created
- `.env.example` covers every required variable; server crashes with clear message on missing var

---

## Sprint 2 — Shared Libs + Outbox + Auth Core
**Goal:** All shared NestJS infrastructure done; outbox pattern working end-to-end; JWT auth flow with refresh rotation complete.  
**Capacity:** 40h  

| Task ID | Title | Size | Hours |
|---------|-------|------|-------|
| INFRA-007 | Elasticsearch 8 + index template | M | 4 |
| INFRA-009 | Kafka UI network config | S | 2 |
| INFRA-012 | Health check endpoints | S | 2 |
| SHARED-001 | Structured logger (pino + correlation ID) | M | 4 |
| SHARED-002 | Global HTTP exception filter (RFC 7807) | M | 4 |
| SHARED-003 | Global validation pipe | S | 2 |
| SHARED-004 | Money utility lib (decimal.js wrapper) | M | 4 |
| SHARED-005 | Correlation ID middleware | S | 2 |
| SHARED-006 | UUIDv7 generator utility | S | 2 |
| SHARED-007 | Swagger / OpenAPI 3 setup | M | 4 |
| SHARED-008 | JWT auth guard + roles guard | M | 4 |
| SHARED-009 | Paginated response wrapper + DTO | S | 2 |
| PLATFORM-001 | platform schema migrations (outbox, processed_event, enums) | L | 8 |
| **Total** | | | **44h → trim or carry PLATFORM-002 to S3** |

> Trim: carry PLATFORM-002 to Sprint 3 if over capacity.

**Sprint 2 Done Criteria:**
- `POST /health` returns 200 on both api and workers
- Swagger UI renders at `/api/docs`
- Money util: `add("0.1", "0.2")` returns `"0.30"` (not `0.30000000000000004`)
- outbox_event table created; all custom enum types registered in PostgreSQL

---

## Sprint 3 — Outbox Relay + Auth Module
**Goal:** Outbox relay publishing Avro events to Kafka; full auth flows (local + OAuth + email verify + password reset) done.  
**Capacity:** 40h  

| Task ID | Title | Size | Hours |
|---------|-------|------|-------|
| PLATFORM-002 | OutboxEvent entity + repository | M | 4 |
| PLATFORM-003 | ProcessedEvent entity + IdempotencyHelper | M | 4 |
| PLATFORM-004 | Avro serializer service (Schema Registry client) | L | 8 |
| PLATFORM-005 | Kafka producer service | M | 4 |
| PLATFORM-006 | Outbox relay worker | L | 8 |
| PLATFORM-007 | Consumer idempotency helper/decorator | M | 4 |
| PLATFORM-008 | DLQ routing | M | 4 |
| AUTH-001 | identity schema migrations | L | 8 |
| **Total** | | | **44h → carry AUTH-002+ to S4** |

> Trim: AUTH-001 is blocking but large — start it, carry AUTH-002 to Sprint 4.

**Sprint 3 Done Criteria:**
- Outbox relay: write a test outbox_event row → verify message appears in Kafka topic via Kafka UI
- Avro serializer: schema registered in Schema Registry; encoded message decodable
- DLQ: consumer exceeding max retries routes to `.DLQ` topic

---

## Sprint 4 — Auth Complete + Identity
**Goal:** All 19 AUTH tasks done; Identity (profile + addresses) done; SEED accounts ready.  
**Capacity:** 40h  

| Task ID | Title | Size | Hours |
|---------|-------|------|-------|
| AUTH-002 | User entity + repository | M | 4 |
| AUTH-003 | Argon2id password hashing service | S | 2 |
| AUTH-004 | Local auth strategy | M | 4 |
| AUTH-005 | JWT access token service | M | 4 |
| AUTH-006 | RefreshSession entity + rotation service | L | 8 |
| AUTH-007 | POST /auth/register | M | 4 |
| AUTH-008 | POST /auth/login | M | 4 |
| AUTH-009 | POST /auth/logout | S | 2 |
| AUTH-010 | POST /auth/logout/all | S | 2 |
| AUTH-011 | POST /auth/refresh | M | 4 |
| AUTH-012 | Google OAuth strategy | L | 8 |
| AUTH-013 | Facebook OAuth strategy | M | 4 |
| AUTH-014 | OAuth callback handlers | M | 4 |
| **Total** | | | **54h — split; carry AUTH-015..019 to S5** |

> Sprint 4 = core JWT + OAuth; Sprint 5 = email verify + password reset + Identity.

**Sprint 4 Done Criteria:**
- `POST /auth/login` returns access + refresh tokens
- Refresh rotation: use a token twice → second use returns 401
- Google OAuth: callback creates or links user
- Argon2id hash present in DB; plaintext never stored

---

## Sprint 5 — Auth Finish + Identity + Catalog
**Goal:** Email verify, password reset, seller/admin auth; Identity CRUD; Catalog module (products, offers, blocklist).  
**Capacity:** 40h  

| Task ID | Title | Size | Hours |
|---------|-------|------|-------|
| AUTH-015 | EmailVerificationToken + verify + resend | L | 8 |
| AUTH-016 | POST /auth/forgot-password | M | 4 |
| AUTH-017 | POST /auth/reset-password | M | 4 |
| AUTH-018 | Seller portal auth routes | M | 4 |
| AUTH-019 | Admin portal auth route | M | 4 |
| IDENTITY-001 | ProfileController GET/PUT | M | 4 |
| IDENTITY-002 | Address CRUD | M | 4 |
| IDENTITY-003 | Address limit (max 10) | S | 2 |
| IDENTITY-004 | Default address logic | S | 2 |
| IDENTITY-005 | B2B business fields | M | 4 |
| IDENTITY-006 | Business logo MinIO upload | M | 4 |
| **Total** | | | **44h → trim IDENTITY-005/006 to S6 if needed** |

**Sprint 5 Done Criteria:**
- Email verification: register → link in "email" → verify endpoint → `email_verified=true`
- Password reset: request → token in email → reset → old sessions revoked
- Address limit: adding 11th returns 422 with clear message
- Enumeration-safe: forgot-password returns identical response for known/unknown email

---

## Sprint 6 — Catalog + Pricing + Inventory
**Goal:** Catalog (categories, products, offers, images) + Pricing (price types, FX seed) + Inventory (stock, reservations, bulk import) all done.  
**Capacity:** 40h  

| Task ID | Title | Size | Hours |
|---------|-------|------|-------|
| CATALOG-001 | catalog schema migrations | L | 8 |
| CATALOG-002 | Category entity + GET /categories (tree) | M | 4 |
| CATALOG-003 | Category taxonomy seed | M | 4 |
| CATALOG-004 | Product entity + repository | M | 4 |
| CATALOG-005 | ProductVariant entity + repository | S | 2 |
| CATALOG-006 | ProductImage entity + MinIO upload | L | 8 |
| CATALOG-007 | GET /products, GET /products/:id | M | 4 |
| CATALOG-008 | Offer entity + repository | M | 4 |
| CATALOG-009 | SellerCatalogController CRUD | L | 8 |
| CATALOG-010 | Keyword blocklist + prohibited category guard | L | 8 |
| **Total** | | | **54h → carry CATALOG-011/012 + all PRICING to S7** |

**Sprint 6 Done Criteria:**
- Category tree returns hierarchical JSON; prohibited categories have `is_prohibited=true`
- Create offer with prohibited keyword → 422 with flag reason
- Product image uploaded to `product-images` bucket; presigned URL returned

---

## Sprint 7 — Catalog Wrap + Pricing + Inventory + Seller + Admin
**Goal:** Pricing resolution service; FX scheduler; Inventory reservations; Seller onboarding; Admin KYC queue and moderation.  
**Capacity:** 40h  

| Task ID | Title | Size | Hours |
|---------|-------|------|-------|
| CATALOG-011 | Offer status state machine | M | 4 |
| CATALOG-012 | Outbox: product.changed, offer.changed | M | 4 |
| PRICING-001 | pricing schema migrations | M | 4 |
| PRICING-002 | Currency seed (USD/THB/JPY/SGD) | S | 2 |
| PRICING-003 | OfferPrice entity + repository | M | 4 |
| PRICING-004 | Seller pricing CRUD | L | 8 |
| PRICING-005 | Effective price resolution service | L | 8 |
| PRICING-006 | FxRate entity + repository | M | 4 |
| PRICING-007 | FX display conversion helper | M | 4 |
| PRICING-008 | FX rate refresh scheduler | M | 4 |
| PRICING-009 | Outbox: fx_rate.updated | S | 2 |
| **Total** | | | **48h → trim PRICING-008/009 or carry SELLER to S8** |

**Sprint 7 Done Criteria:**
- Price resolution: B2B_TIER price returned for B2B account with qualifying qty
- SALE price: active only within valid_from..valid_until window
- FX scheduler: hourly cron fires; fx_rate row updated; outbox event written

---

## Sprint 8 — Inventory + Seller + Admin + Cart
**Goal:** All inventory flows; seller KYC onboarding; admin approval queue; cart fully operational.  
**Capacity:** 40h  

| Task ID | Title | Size | Hours |
|---------|-------|------|-------|
| INVENTORY-001 | inventory schema migrations | M | 4 |
| INVENTORY-002 | Stock entity + repository (optimistic lock) | M | 4 |
| INVENTORY-003 | StockReservation entity + repository | M | 4 |
| INVENTORY-004 | InventoryController seller | M | 4 |
| INVENTORY-005 | Low-stock edge-trigger detection | M | 4 |
| INVENTORY-006 | CSV bulk import | L | 8 |
| INVENTORY-007 | Reservation service (atomic decrement) | M | 4 |
| INVENTORY-008 | Reservation expiry scheduler | M | 4 |
| INVENTORY-009 | Zero-stock deactivation | M | 4 |
| INVENTORY-010 | Outbox: inventory.changed, low_stock | M | 4 |
| INVENTORY-011 | Kafka consumer: fulfillment.placed → decrement | M | 4 |
| **Total** | | | **48h → carry SELLER to S9** |

**Sprint 8 Done Criteria:**
- Atomic reservation: concurrent requests for last unit — exactly one succeeds
- CSV import: 200-row file imported; incorrect rows in error report
- Reservation expiry: expired reservation restores `reserved_qty` and publishes event

---

## Sprint 9 — Seller + Admin + Cart
**Goal:** Complete seller onboarding; admin KYC + moderation + suspension; cart all operations.  
**Capacity:** 40h  

| Task ID | Title | Size | Hours |
|---------|-------|------|-------|
| SELLER-001 | seller schema migrations | M | 4 |
| SELLER-002 | SellerProfile entity + repository | M | 4 |
| SELLER-003 | KycApplication entity + repository | M | 4 |
| SELLER-004 | POST /seller/register | L | 8 |
| SELLER-005 | POST /seller/kyc (upload docs) | L | 8 |
| SELLER-006 | GET /seller/kyc/status | S | 2 |
| SELLER-007 | POST /seller/kyc/resubmit | M | 4 |
| SELLER-008 | SellerKycGuard | M | 4 |
| SELLER-009 | GET /seller/dashboard | M | 4 |
| SELLER-010 | Outbox: seller.kyc.submitted | S | 2 |
| ADMIN-001 | admin schema migrations | M | 4 |
| ADMIN-002 | ModerationCase entity + repository | M | 4 |
| **Total** | | | **52h → carry ADMIN-003..015 + CART to S10** |

**Sprint 9 Done Criteria:**
- Seller with PENDING KYC status blocked from listing endpoints (403)
- KYC docs uploaded to `kyc-documents` MinIO bucket; admin can download via presigned URL
- seller.kyc.submitted outbox event written in same transaction as KYC application insert

---

## Sprint 10 — Admin Complete + Cart + Search
**Goal:** Admin KYC review, moderation, suspension; cart CRUD + guest merge; search index + consumers.  
**Capacity:** 40h  

| Task ID | Title | Size | Hours |
|---------|-------|------|-------|
| ADMIN-003 | GET /admin/kyc queue | M | 4 |
| ADMIN-004 | POST /admin/kyc/:id/approve | M | 4 |
| ADMIN-005 | POST /admin/kyc/:id/reject | M | 4 |
| ADMIN-006 | GET /admin/moderation | M | 4 |
| ADMIN-007 | POST /admin/moderation/:id/remove | L | 8 |
| ADMIN-008 | POST /admin/moderation/:id/clear | M | 4 |
| ADMIN-009 | POST /admin/sellers/:id/suspend | L | 8 |
| ADMIN-010 | POST /admin/sellers/:id/reinstate | M | 4 |
| ADMIN-011 | GET /admin/sellers (search) | M | 4 |
| ADMIN-012 | GET /admin/sellers/:id | M | 4 |
| ADMIN-013 | GET /admin/dashboard | M | 4 |
| ADMIN-014 | Suspension expiry scheduler | M | 4 |
| ADMIN-015 | Outbox: all admin events | M | 4 |
| **Total** | | | **60h — split; carry CART + SEARCH to S11** |

> Sprint 10 covers admin only. CART and SEARCH move to Sprint 11.

**Sprint 10 Done Criteria:**
- Approve KYC → seller.kyc.decided outbox event written; seller can now list
- Suspend seller → all ACTIVE listings deactivated in same transaction; outbox event written
- Admin suspension expiry scheduler: `suspended_until <= now()` triggers reinstatement

---

## Sprint 11 — Cart + Search + Orders + Notifications Kickoff
**Goal:** Cart complete; ES search working via Kafka consumers; checkout atomic transaction; order history; notifications consumers and SMTP wired.  
**Capacity:** 40h  

| Task ID | Title | Size | Hours |
|---------|-------|------|-------|
| CART-001 | cart schema migrations | S | 2 |
| CART-002 | Cart entity + repository | M | 4 |
| CART-003 | CartItem entity + repository | M | 4 |
| CART-004 | GET /cart (resolve prices + stale items) | L | 8 |
| CART-005 | POST /cart/items | M | 4 |
| CART-006 | PUT /cart/items/:id | M | 4 |
| CART-007 | DELETE /cart/items/:id | S | 2 |
| CART-008 | Guest cart merge on login | L | 8 |
| CART-009 | Stale item detection | M | 4 |
| CART-010 | Cart limit enforcement (50 items) | S | 2 |
| **Total** | | | **42h — SEARCH, ORDERS, NOTIFICATIONS continue beyond S11** |

> Sprints 12+ (directional, not formally planned): SEARCH consumers, ORDERS checkout, NOTIFICATIONS, SEED, frontend epics. Groom and plan each 2-sprint window before execution.

**Sprint 11 Done Criteria:**
- Add 3 items → GET /cart returns line items with live effective prices
- Add item with `offer.status=REMOVED` → flagged as unavailable; blocked from checkout
- Guest cart + login → merged cart with quantities capped at inventory

---

## Sprints 12–18 (Directional)

| Sprint | Primary Focus | Key Deliverables |
|--------|--------------|-----------------|
| 12 | Search module | ES index mapping; all Kafka search consumers; GET /search with facets |
| 13 | Orders core | Checkout service; atomic reservation+snapshot transaction; mock payment |
| 14 | Orders finish + Workers | Fulfillment endpoints; seller ship/refund/cancel; mock delivery + auto-refund schedulers |
| 15 | Notifications + Seed | SMTP adapter; all 25 Kafka notification consumers; 21 email templates; seed runner |
| 16 | Frontend shared + Auth | Nx Angular setup; Angular Material theme; auth interceptor; buyer login/register/OAuth; seller/admin login |
| 17 | Frontend buyer core | Search, PDP, cart, checkout |
| 18 | Frontend buyer + seller + admin | Order history; seller portal; admin KYC queue; admin moderation |

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| ORDERS-009 (atomic tx) takes 2x estimate | High | High | Time-box 3 days; spike first; fallback: two-phase with compensation |
| Kafka + Schema Registry integration complexity in Sprint 3 | Medium | High | Spike Avro serializer before committing to full outbox relay |
| FX rate API (exchangerate.host) unavailable | Low | Medium | Cache last known rate; surface staleness age in API response; stale-serve |
| MinIO KYC doc download latency | Low | Medium | Presigned URLs cached 1h; background download not blocking |
| Elasticsearch Avro schema fan-out (fx_rate.updated) too slow | Medium | Medium | Batch ES bulk updates; accept eventual consistency per NFR-13 (≤5s p95) |
| Solo dev context switch overhead (backend → frontend) | High | Medium | Finish entire backend first before touching Angular; no mixed-mode sprints |
| argon2id compile issues on dev machine | Low | Low | Pin @phc-format/argon2 version; test in Docker from Sprint 1 |

---

## Definition of Sprint Done

Sprint is done when:
1. All committed tasks merged to main
2. `docker-compose up` starts cleanly (no new env var added without `.env.example` update)
3. Swagger docs reflect all new/changed endpoints
4. No new `number` type violations on money fields (ESLint rule enforced)
5. PROGRESS.md updated with sprint summary
