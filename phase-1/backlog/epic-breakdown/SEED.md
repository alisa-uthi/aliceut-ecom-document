# EPIC: SEED — Seed Data

**Sprint:** 9  
**Total Tasks:** 5  
**Status:** Planned  

Load the 100 curated products from the Kaggle Amazon dataset into the platform. Creates categories, seller profiles, products, offers, inventory records, and triggers search indexing. Architecture must support 10k+ products (NFR-03) even though seed is only 100.

---

## SEED-001 — Kaggle Dataset Acquisition & Curation

| Field | Value |
|-------|-------|
| **US Ref** | US-P-19 |
| **Estimate** | M (1d) |
| **Dependencies** | none |

**Implementation Notes**

- Dataset: "Amazon Product Data" from Kaggle (or similar public e-commerce dataset)
- Download manually; place raw CSV in `tools/seed/data/raw/amazon_products.csv`
- Curation script: `tools/seed/scripts/curate-products.ts`
  - Select 100 diverse products across 6–8 major categories: Electronics, Books, Clothing & Apparel, Home & Kitchen, Sports & Outdoors, Beauty & Personal Care, Toys & Games
  - Exclude: weapons/drugs/adult content categories (prohibited categories per BRD)
  - Normalize fields: title, description (truncate to 2000 chars), price (normalize to USD decimal), category, brand, image URL
  - Output: `tools/seed/data/curated/products.json` — 100 products in internal format
- Product internal format:
  ```json
  {
    "title": "...",
    "description": "...",
    "brand": "...",
    "category": "Electronics > Laptops",
    "images": ["https://images.example.com/..."],
    "priceUsd": "299.99",
    "attributes": { "color": "Silver", "weight": "1.5kg" }
  }
  ```
- Commit curated JSON to repo; raw CSV in `.gitignore`

**Done Criteria**

- `tools/seed/data/curated/products.json` exists with exactly 100 products
- All products have: title, description, priceUsd (valid decimal string), at least 1 image URL, category path
- No prohibited categories present
- File committed to git; raw CSV excluded

---

## SEED-002 — Category Tree Seed

| Field | Value |
|-------|-------|
| **US Ref** | US-P-19 |
| **Estimate** | S (½d) |
| **Dependencies** | SEED-001, CATALOG epic |

**Implementation Notes**

- Script: `tools/seed/scripts/seed-categories.ts`
- Create category tree from product category paths in curated JSON
- Category tree (max 2 levels in V1):
  ```
  Electronics
    └── Laptops
    └── Smartphones
    └── Headphones
  Books
    └── Fiction
    └── Non-Fiction
  Clothing & Apparel
    └── Men's Clothing
    └── Women's Clothing
  Home & Kitchen
  Sports & Outdoors
  Beauty & Personal Care
  Toys & Games
  ```
- Use `CatalogService.createCategory()` or direct TypeORM insert
- Idempotent: `INSERT ... ON CONFLICT (slug) DO NOTHING`
- Store category `slug` as URL-safe lowercase kebab (e.g. `electronics`, `home-kitchen`)
- Returns map: `{ "Electronics > Laptops": categoryId }` used by product seed script

**Done Criteria**

- All categories from curated products exist in DB after seed run
- Running seed twice: no duplicate categories (idempotent)
- Parent-child relationships correct (Electronics → Laptops)
- Category slugs are URL-safe

---

## SEED-003 — Seller Profile Seed

| Field | Value |
|-------|-------|
| **US Ref** | US-P-19 |
| **Estimate** | S (½d) |
| **Dependencies** | SEED-001, SELLER-001, AUTH-001 |

**Implementation Notes**

- Script: `tools/seed/scripts/seed-sellers.ts`
- Create 3–5 demo seller accounts (different product categories each)
- For each seller:
  1. Create `user_account` with `role = 'seller'`, `account_status = 'ACTIVE'`, `is_email_verified = true`
  2. Create `seller_profile` with `kyc_status = 'APPROVED'`, `seller_status = 'ACTIVE'`
  3. Password: argon2id hash of `SEED_SELLER_PASSWORD` env var (default `Seller@12345`)
- Demo sellers:
  - `tech-seller@aliceut.local` — Electronics category products
  - `book-seller@aliceut.local` — Books category products
  - `lifestyle-seller@aliceut.local` — Clothing/Home/Sports products
- Output: map of seller `{ email: sellerId }` for product seed script

**Done Criteria**

- 3 seller accounts created; each can log in with seed password
- `seller_status = 'ACTIVE'`, `kyc_status = 'APPROVED'` (bypasses KYC for demo data)
- Running twice: no duplicate sellers (check email before insert)
- Seller passwords not committed to git (use env var)

---

## SEED-004 — Product & Offer Seed

| Field | Value |
|-------|-------|
| **US Ref** | US-P-19 |
| **Estimate** | L (2d) |
| **Dependencies** | SEED-002, SEED-003, CATALOG epic, PRICING epic, INVENTORY epic |

**Implementation Notes**

- Script: `tools/seed/scripts/seed-products.ts`
- For each product in curated JSON:
  1. Assign to seller based on category (electronics → tech-seller, books → book-seller, etc.)
  2. Create `catalog.product` row via `CatalogService` (triggers `product.changed` event via outbox)
  3. Create `catalog.offer` row for the assigned seller
  4. Create `pricing.price` rows:
     - `LIST` price in USD: from product JSON
     - `LIST` price in THB: `priceUsd * current_fx_rate` (rounded to 2 decimal places)
     - For ~20% of products: add a `SALE` price (80% of LIST price; active for 30 days from seed date)
  5. Create `inventory.inventory` row: `quantity_available = random(10, 100)`, `low_stock_threshold = 5`
  6. Upload product images to MinIO `product-images` bucket: download from URL in JSON, re-upload
- All operations via service layer (not direct SQL inserts) so events fire correctly
- Products seeded → `product.changed` outbox events → relay → Kafka → Search module → ES indexed
- Run sequence: categories → sellers → products (dependency order)
- Total products: exactly 100

**Done Criteria**

- 100 products in `catalog.product`; 100 offers in `catalog.offer`
- Each product has LIST price in USD and THB
- ~20 products have active SALE prices
- All 100 products searchable via `GET /search?q=` within 30s of seed completion
- Inventory records exist for all 100 offers
- Product images uploaded to MinIO (or at minimum: URL references stored without upload on first pass)

---

## SEED-005 — Seed Runner CLI

| Field | Value |
|-------|-------|
| **US Ref** | US-P-19 |
| **Estimate** | S (½d) |
| **Dependencies** | SEED-002, SEED-003, SEED-004 |

**Implementation Notes**

- File: `tools/seed/scripts/run-seed.ts`
- npm script: `"seed": "ts-node tools/seed/scripts/run-seed.ts"`
- Seed order enforced: categories → sellers → products
- `--dry-run` flag: validates curated JSON + DB connectivity without inserting
- `--reset` flag: truncates all seed data tables in reverse dependency order (DANGEROUS: only for dev reset)
- Idempotent by default: each script checks for existing data before insert
- Output: progress bar + summary table:
  ```
  ✓ Categories: 8 root, 22 leaf (30 total)
  ✓ Sellers: 3 created
  ✓ Products: 100 created
  ✓ Offers: 100 created
  ✓ Prices: 220 created (100 USD + 100 THB + 20 SALE)
  ✓ Inventory: 100 records
  ✓ Search: 100 products indexed
  Seed completed in 45.2s
  ```
- `--reset` flag requires `NODE_ENV=development` (refuses to run in production)

**Done Criteria**

- `npm run seed` completes without error on fresh DB
- Running `npm run seed` twice: no duplicates, no errors (idempotent)
- `npm run seed -- --dry-run`: validates data, exits without DB writes
- After seed: `GET /search?q=laptop` returns results
- After seed: seller can log in and see their products
