# EPIC: SEED — Seed Data

**Sprint:** 5
**Total Tasks:** 11

Kaggle "Amazon Product Data" curated to 100 products; exactly 4 demo accounts (per US-P-06 / US-A-00b); idempotent, re-runnable seed pipeline. Architecture must still support 10k+ products (NFR-03) even though seed data is small.

---

## SEED-001 — UUIDv7 PostgreSQL Extension Function

- **US Ref:** —
- **Estimate:** S
- **Dependencies:** INFRA-004
- **Spec References:** `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `libs/platform/src/infrastructure/migrations/000_uuidv7_extension.sql`
- Raw-SQL function providing `uuidv7()` (PostgreSQL has no native UUIDv7 generator as of the locked version); must run **before every other migration** since all PK defaults reference it
- Numbered `000_` so migration runner applies it first regardless of module

**Done Criteria**

- `SELECT uuidv7();` returns a valid UUID on a fresh DB
- Every subsequent migration that defaults a PK to `uuidv7()` succeeds

---

## SEED-002 — Idempotent Seed Runner

- **US Ref:** US-P-06
- **Estimate:** M
- **Dependencies:** PLATFORM-001
- **Spec References:** `phase-1/technical-design/backend-module-architecture.md`

**Implementation Notes**

- File: `apps/workers/src/seed/seed.runner.ts` — NestJS CLI command (`nest-commander`), invoked via `npm run seed`
- Each step (currency, accounts, categories, products, images, sellers, offers, inventory, email templates) is check-before-insert (idempotent) and independently re-runnable
- `--step=<name>` runs a single step; default runs all in dependency order
- Exit 0 on success; exit 1 on any step failure; console summary table `[step] [status] [count]`

**Done Criteria**

- Running the seed command twice produces no duplicate rows and no error
- `--step=<name>` runs only that step

---

## SEED-003 — Currency Seed Rows

- **US Ref:** US-P-06a
- **Estimate:** S
- **Dependencies:** PRICING-001
- **Spec References:** `CLAUDE.md` (V1 currencies), `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `apps/workers/src/seed/steps/seed-currencies.ts`
- Seeds exactly the V1-locked currency set: USD, THB, JPY, SGD
- Each row: correct `minor_unit_scale` (JPY = 0, others = 2), `is_seller_price_allowed = true`

**Done Criteria**

- 4 currency rows exist, each with correct `minor_unit_scale`
- No currency outside the V1 set is seeded

---

## SEED-004 — Demo Account Seed

- **US Ref:** US-P-06
- **Estimate:** M
- **Dependencies:** AUTH-001
- **Spec References:** `phase-1/requirements/user-stories/` (US-P-06, US-A-00b)

**Implementation Notes**

- File: `apps/workers/src/seed/steps/seed-accounts.ts`
- Seeds exactly 4 demo accounts, one per role required by US-P-06 / US-A-00b: consumer buyer, business buyer, seller, admin — exact emails/roster per those user stories, not duplicated here
- Passwords hashed with argon2id (same hashing path as real signup — no shortcut)
- `isEmailVerified = true` set directly (skip token flow for seed convenience)
- Seller account: KYC APPROVED, suspension status ACTIVE (ready to list immediately)

**Done Criteria**

- Exactly 4 accounts exist after seeding — no extras
- Each account can log in with its seeded password
- Seller account can create listings without further KYC steps

---

## SEED-005 — Category Taxonomy Seed

- **US Ref:** US-P-06
- **Estimate:** M
- **Dependencies:** CATALOG-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md`, `CLAUDE.md` (prohibited categories)

**Implementation Notes**

- File: `apps/workers/src/seed/steps/seed-categories.ts`
- 6+ top-level categories with full hierarchy slugs (parent/child path)
- `is_prohibited = true` on weapons/drugs/adult-content branches, per the prohibited-categories rule — these exist in the taxonomy for moderation-flag testing but are never used by seeded products (SEED-006)

**Done Criteria**

- 6+ top-level categories exist with correct slug hierarchy
- Prohibited branches flagged `is_prohibited = true`

---

## SEED-006 — Kaggle Amazon Product Data Import Pipeline

- **US Ref:** US-P-06
- **Estimate:** XL
- **Dependencies:** CATALOG-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `apps/workers/src/seed/steps/import-kaggle-products.ts`
- Source: Kaggle "Amazon Product Data" (public dataset), curated to exactly 100 products across major categories (SEED-005), ≥5 per top-level category
- Parses CSV, cleans missing/malformed fields, maps to `catalog.product` (+ variant where the dataset provides size/color) schema
- Idempotent: skip products already imported (match on source SKU/ASIN)
- Publishes `product.changed` via outbox per imported product (async ES indexing, per event-driven-writes rule)

**Done Criteria**

- Exactly 100 products imported, spanning ≥5 categories from SEED-005
- No duplicate products on re-run
- Each import triggers a `product.changed` outbox event

---

## SEED-007 — Product Images Import

- **US Ref:** US-P-06
- **Estimate:** L
- **Dependencies:** SEED-006
- **Spec References:** `phase-1/technical-design/data-model-mongodb.md` (MinIO buckets)

**Implementation Notes**

- File: `apps/workers/src/seed/steps/import-product-images.ts`
- Downloads images from Kaggle-provided URLs where reachable; falls back to a placeholder image set otherwise (dataset image links rot over time)
- Uploads to MinIO `product-images` bucket; associates with the corresponding `catalog.product` row

**Done Criteria**

- Every seeded product has at least one image in the `product-images` MinIO bucket
- Placeholder fallback used with no pipeline failure when a source URL is unreachable

---

## SEED-008 — Seeded Seller Profiles

- **US Ref:** US-P-06
- **Estimate:** M
- **Dependencies:** SELLER-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `apps/workers/src/seed/steps/seed-seller-profiles.ts`
- 3 pre-approved seller profiles (`kyc_status = APPROVED`, `suspension_status = ACTIVE`) — distinct from the single seller demo-login account in SEED-004; these are the sellers products get assigned to in SEED-009
- Products distributed round-robin across the 3 profiles

**Done Criteria**

- 3 seller profiles exist, all KYC APPROVED and ACTIVE
- Each can be assigned offers without further approval steps

---

## SEED-009 — Offer + Price Seed

- **US Ref:** US-P-06
- **Estimate:** L
- **Dependencies:** SEED-008
- **Spec References:** `CLAUDE.md` (pricing model), `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `apps/workers/src/seed/steps/seed-offers.ts`
- One `catalog.offer` per seeded product (100 total), assigned to a seller profile from SEED-008
- Price currency mix across the 4 V1 currencies (SEED-003) — `pricing.offer_price` rows, never priced on `Product` directly
- 10% of offers get a `SALE` price (time-bounded) in addition to `LIST`; 5% get a `B2B_TIER` price (min-qty tier)
- Publishes `product.changed` (or `offer.changed`, per the event actually tied to offer/price mutation in `kafka-events.md`) via outbox for each created offer

**Done Criteria**

- 100 offers exist, each with a `LIST` price in one of the 4 V1 currencies
- ~10% of offers additionally have a `SALE` price, ~5% a `B2B_TIER` price
- No price row references `Product` directly

---

## SEED-010 — Inventory Seed

- **US Ref:** US-P-06
- **Estimate:** M
- **Dependencies:** INVENTORY-001
- **Spec References:** `phase-1/technical-design/data-model-erd.md`

**Implementation Notes**

- File: `apps/workers/src/seed/steps/seed-inventory.ts`
- One inventory row per offer from SEED-009: reasonable random `on_hand` quantity, `low_stock_threshold = 5`
- No initial reservations (clean slate for checkout/cart testing)

**Done Criteria**

- Every offer from SEED-009 has exactly one inventory row
- No reservation rows exist immediately after seeding

---

## SEED-011 — Email Template Seed

- **US Ref:** US-P-06
- **Estimate:** M
- **Dependencies:** NOTIFICATIONS-001
- **Spec References:** `phase-1/requirements/user-stories/email-templates.md` (ET-01..21, plus the ET-13b variant)

**Implementation Notes**

- File: `apps/workers/src/seed/steps/seed-email-templates.ts`
- Seeds `notifications.email_template` rows for the full canonical template set defined in `email-templates.md` — subjects/HTML/text bodies sourced from that doc, not duplicated here
- Idempotent: upsert by template code (`ET-01`, `ET-02`, ... `ET-13b`, ...)

**Done Criteria**

- Every template code in `email-templates.md` has a corresponding seeded row
- Re-running the step updates existing rows rather than duplicating them
