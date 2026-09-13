# EPIC: SEED — Development Seed Data

**Sprint:** 5  
**Total Tasks:** 5  

Kaggle "Amazon Product Data" — curated to 100 products across major categories. Seed script is idempotent (safe to re-run). Provides realistic dev/demo data for all modules.

---

## SEED-001 — Seed Data Preparation (Kaggle Dataset Curation)

- **US Ref:** —
- **Estimate:** L
- **Dependencies:** INFRA-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/data-model-mongodb.md`

**Implementation Notes**

- Source: Kaggle "Amazon Product Data" (public dataset)
- Curation target: 100 products across these categories (≥5 products each):
  - Electronics
  - Books
  - Home & Kitchen
  - Sports & Outdoors
  - Clothing & Accessories
  - Beauty & Personal Care
  - Toys & Games
  - Office Products
- File: `apps/workers/src/seed/data/products.json` — curated subset with fields:
  ```json
  {
    "id": "...",
    "title": "...",
    "description": "...",
    "brand": "...",
    "category": "Electronics > Headphones",
    "imageUrl": "https://...",
    "originalPrice": "39.99",
    "currency": "USD",
    "sku": "AMZN-001"
  }
  ```
- Images: use Kaggle-provided URLs (external CDN). Do NOT download to MinIO for seed (dev convenience only)
- Keep original ASIN or row ID as `sku` for traceability

**Done Criteria**

- 100 product records in `products.json`
- At least 8 categories represented
- No duplicate products

---

## SEED-002 — Seed Users, Sellers, Categories

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** AUTH-001, SELLER-003, CATALOG-002
- **Spec References:** `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `apps/workers/src/seed/seed-users.ts`
- Create via service layer (not raw SQL) to trigger proper side effects:
  - 2 ADMIN users: `admin1@aliceut.dev`, `admin2@aliceut.dev` (password: `Admin1234!`)
  - 3 SELLER users, all KYC APPROVED, status ACTIVE: `seller1@aliceut.dev`, `seller2@aliceut.dev`, `seller3@aliceut.dev`
  - 5 BUYER users: `buyer1@aliceut.dev` through `buyer5@aliceut.dev` (password: `Buyer1234!`)
- All accounts: `isEmailVerified = true` (set directly in DB; skip token flow)
- Seller profiles: `displayName = "Demo Seller N"`, `businessName = "Demo Business N"`
- Seed categories (catalog.category):
  - Electronics (+ 3 subcategories)
  - Books, Home & Kitchen, Sports & Outdoors, Clothing & Accessories, Beauty & Personal Care, Toys & Games, Office Products (flat; no subcategories for simplicity)
- Idempotent: check by email/slug before insert

**Done Criteria**

- All users created; can log in with seeded passwords
- All seller profiles KYC APPROVED; sellers can create listings
- 8+ categories exist in `catalog.category`

---

## SEED-003 — Seed Products, Offers, Prices

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** SEED-001, SEED-002, CATALOG-008, PRICING-006
- **Spec References:** `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `apps/workers/src/seed/seed-products.ts`
- For each of the 100 products from `products.json`:
  1. Create `catalog.product` row (use curated data)
  2. Assign to one seller (round-robin across 3 seed sellers: product index % 3)
  3. Create `catalog.offer` (status = `ACTIVE`)
  4. Create `pricing.offer_price` (type = `LIST`, currency = `USD`, price from curated data)
  5. Create `catalog.stock` (qty = random 5–100)
- Distribute products across seed categories (by curated `category` field mapping)
- `offer.status = ACTIVE` for all seed offers
- No image upload to MinIO (use external URLs from curated data)

**Done Criteria**

- 100 products in DB; all indexed in ES via async `product.changed` event
- Each product: 1 offer, 1 USD price, 1 stock record
- `GET /search?q=headphones` returns matching products within 5s of seeding

---

## SEED-004 — Seed Orders (sample order history)

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** SEED-003, ORDERS-005
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `phase-1/technical-design/data-model-mongodb.md`

**Implementation Notes**

- File: `apps/workers/src/seed/seed-orders.ts`
- Create 20 sample orders (bypass checkout validation for seed; use `dataSource.transaction` directly):
  - 5 orders status = `PROCESSING` (for buyers 1–3)
  - 5 orders status = `SHIPPED` (buyers 4–5; set `shipped_at = now() - 1 day`)
  - 5 orders status = `DELIVERED` (various buyers; set `delivered_at = now() - 3 days`)
  - 5 orders status = `CANCELLED` (various buyers; reservations already released)
- Each order: 1–3 fulfillment items from existing products; mock `payment_attempt` with `SUCCEEDED`
- `display_id` format: `ORD-YYYYMMDD-XXXX` (use actual date of seeding)
- Seed audit log entries in MongoDB for status transitions

**Done Criteria**

- 20 orders seeded across 4 statuses
- GET /orders returns buyer's orders (buyer1 sees only their orders)
- GET /seller/fulfillments: seller1 sees their fulfillments

---

## SEED-005 — Master Seed Runner + Idempotency Guard

- **US Ref:** —
- **Estimate:** M
- **Dependencies:** SEED-002, SEED-003, SEED-004
- **Spec References:** `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `apps/workers/src/seed/seed.runner.ts`
- Single entry point: `npm run seed` (or `ts-node seed.runner.ts`)
- Execution order:
  1. `seedCategories()` — categories first (products depend on them)
  2. `seedUsers()` — users and seller profiles
  3. `seedProducts()` — products, offers, prices, stock
  4. `seedOrders()` — orders and fulfillments
- Each step: `SeedRunner.isSeeded(stepName): boolean` — checks a `seed_log` table or config flag
  - `seed_log` table: `(step_name TEXT PRIMARY KEY, seeded_at TIMESTAMP)`
  - If already seeded: skip + log `[SKIP] Step already seeded`
  - If not seeded: run + insert `seed_log` row on success
- `--force` flag: drop all seed data and re-run (dev convenience; never in prod)
- `--step=users` flag: run single step only
- Exit 0 on success; exit 1 on any step failure; partial success logged clearly

**Done Criteria**

- `npm run seed` completes idempotently (no error on second run)
- `npm run seed --force` re-seeds from scratch
- `npm run seed --step=users` runs only user seed
- Final console output: summary table `[step] [status] [count]`
