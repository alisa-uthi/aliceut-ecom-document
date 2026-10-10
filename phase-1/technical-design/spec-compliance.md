# Spec compliance — known code/spec divergences

**Status:** Living document
**Updated:** 2026-10-10

The technical design in this directory is canonical. This file is the register
of places where the code is known **not** to match it yet, so that no mismatch
is silent. See [`decisions/README.md`](../../decisions/README.md) for the rule
and for how to resolve an entry.

Each entry resolves one of three ways: fix the code (the default), write an ADR
and change spec plus code together, or — if it is a whole feature — move it into
sprint scope. Delete an entry when it is resolved; do not keep a tick-list of
history here.

---

## Resolved 2026-10-08/10

Recorded for context; these are closed.

| Divergence | Resolution |
|---|---|
| Session responses were data-wrapped in the spec, bare in code | [ADR-0001](../../decisions/0001-auth-session-responses-are-not-data-wrapped.md) — spec corrected to the bare shape |
| Six auth routes returned 204 where the spec specifies a message body | Code fixed to the spec (backend#23) |
| `POST /auth/login`, `/auth/forgot-password`, `/auth/reset-password` ignored `portal` | Code fixed to the spec (backend#23) — admin and seller portal login had been returning 400 |
| Six seller request DTOs had no validation and lived inside service files | Code fixed: moved to `http/dto` with validators matching the spec's stated constraints |
| `POST /seller/products` accepted no `images` or `variants`, and created the offer, price and stock in the same call | Code fixed to the spec: product-only create plus a new `POST /seller/offers` |
| Create-product emitted `product.created`, a topic `kafka-init.sh` never creates and the indexer does not subscribe to — so new products never reached the search index | Code fixed: emits `product.changed`, which the indexer already handled |
| Uploaded product images that were never referenced accumulated with nothing to reap them | [ADR-0004](../../decisions/0004-orphaned-product-image-sweep.md) — `cleanup-orphaned-product-images` added to `cleanup-jobs.md` and built in `workers` |
| 30 Seller and Admin operations declared no response body, and the seller lists were offset-paginated | Code fixed across backend#26–#30: every 2xx on all 69 paths now declares a typed body (169 schemas, none empty). `GET /seller/offers` serves the listings *and* the inventory table; the undesigned `GET /seller/products` and `GET /seller/inventory` are gone; `PATCH /seller/offers/:offerId` and the CSV bulk-inventory upload are built; admin requests are validated. frontend#18 follows |
| `DELETE /seller/products/:productId` set every seller's offers on the product to `REMOVED`, always removed the product row, answered `422` for a `PENDING` fulfillment and emitted the uncatalogued `platform.product.removed` | Code fixed to the spec (backend#31): only the caller's `ACTIVE` offers go `INACTIVE`; the product row goes `REMOVED` only when no other seller holds a non-`REMOVED` offer; `409`; one `listing.soft_deleted` per offer, plus `product.changed` on the removal branch |
| The search indexer deleted the whole product document on `listing.soft_deleted` and `moderation.listing.removed`, erasing every co-seller's listing from search, and its `processed_event` insert omitted the NOT NULL `outcome`, so every indexed event retried forever | Code fixed (backend#33): removal events rebuild the document from the remaining offers, update-only; only `product.changed` `REMOVED` deletes a document |
| No DLQ per consumer group | Code fixed (backend#33): reusable consumer host in `workers` with bounded retry and `<group>.dlq`; the indexer runs the twelve `search.*` groups of kafka-events.md §4 |
| `order.placed`, `notification.checkout.summary`, `order.events` and `seller.events` went to topics the broker does not create | Code fixed (backend#34): `fulfillment.placed`, `order.finalized`, `fulfillment.refund_suspended_seller` and `seller.suspension_expired`, with catalogue payloads |
| Schedulers ran in every `api` replica with no advisory lock | Code fixed (backend#37): all four jobs run in `workers`, each under `pg_advisory_lock`; `ScheduleModule` is gone from `api`; outbox retention follows cleanup-jobs.md |
| `api` health probes reported `up` without checking anything | Code fixed (backend#32): real probes with per-check and total timeouts, shared with `workers` |
| `UPDATE`/`DELETE ... RETURNING` results were destructured as one row, but TypeORM returns `[rows, rowCount]` — refund and cancel never released reservations, every price withdrawal answered 500, suspend and reinstate events carried null offer ids | Code fixed (backend#35, #37): `returningRows` / `returningRow` / `affectedCount` in `shared`; test mocks return the real shape |
| `GET`/`PATCH /seller/profile`, `POST /seller/kyc/resubmit` and `POST /profile/me/logo` were missing | Built to the spec (backend#36) |
| `GET /catalog/products`, `GET /catalog/categories/:categoryId` and `GET /pricing/fx-rates` were missing | Built to the spec (backend#41) |
| The global `ValidationPipe` answered request validation with `422`, and the exception filter emitted `{code, message, details}` | Code fixed (backend#39): `400` with the api-conventions error shape `{statusCode, error, message, errors[]}`; the business-rule `422`s the spec keeps are unchanged |
| `POST /seller/kyc` took JSON and published to the uncreated `platform.seller.kyc.submitted`, keyed on the application | Code fixed (backend#40): multipart upload, `seller.kyc.submitted` keyed on the seller profile. It also creates the profile when none exists, which is **interim** (entry 5) |
| `admin.service.ts` read the nonexistent `u.first_name` / `u.last_name` in seven queries | Code fixed (backend#40): `u.full_name` |
| `fulfillment.refunded`, `.cancelled` and `.shipped` were keyed on `fulfillment_id` | Code fixed (backend#40): keyed on `order_id`; refunded and cancelled payloads follow §2.7 / §2.16 |
| Checkout reservations expired after two days; `order.finalized` carried `buyer_business_logo_url: null`; a null `preferred_currency` checked out in USD | Code fixed (backend#38): 15-minute TTL; logo key presigned; currency resolved from `Accept-Language` |
| Search's `category` filter was a slug where the design said a `categoryId` UUID, and `category_path` held only the leaf | [ADR-0005](../../decisions/0005-search-category-filter-is-a-slug.md): the filter is a slug, and `category_path` is ancestor-to-leaf slugs in the index and in every `product.changed` (backend#42). `reindexAllProducts` must run once after deploy |
| The `PATCH /seller/profile` design wrote `seller_profile.submitted_data`, a column that does not exist | [ADR-0006](../../decisions/0006-seller-profile-patch-writes-address-columns.md): the request is `{businessName?, businessAddress?}` on the address columns (backend#42) |

---

## Open — API surface

### 1. Response models far from the design

- `Cart` is specified to BE the checkout preview — `productTitle`,
  `sellerName`, `effectivePrice`, `lineTotal`, `groups[]`, the four totals and
  the FX display fields — and currently returns offer ids and quantities only.
- Search results return `description`, `status`, `lowestListPrice` /
  `lowestSalePrice`, `imageStorageKey` and `offers[]`; the design has `brand`,
  `categoryId`, `images[]`, `lowestOffer`, `inStock`, `score` and `facets`.
- Checkout still takes `items[{offerId, quantity}]` rather than the designed
  `cartItems[]` plus the `confirmedPrices[]` / `PRICE_CHANGED` handshake.
- `GET /pricing/offers/:offerId/effective-price` returns `nativeAmount` /
  `nativeCurrency` without `priceType`, `compareAtAmount` or `saleEndsAt`;
  defaults `currency` to USD where pricing.md makes it required; answers a
  missing FX row with the native currency and `fxStale: true` instead of
  `displayAmount: null`; and has no `404` for an inactive offer and no `422`
  for a missing `LIST` price. Pricing does not apply the Auto-currency rule
  that checkout now uses.
- `GET /catalog/products/:productId` omits `offers[]`;
  `GET /catalog/products/:productId/offers` has a non-spec shape and no
  seller-eligibility filter; the category list exposes `isProhibited`.
- `GET /seller/kyc` returns `{kycStatus, applicationStatus, decisionReason}`
  where seller.md specifies the application record and a `404` when there is
  none, and its join drops decided applications.
- `GET /seller/profile` returns no address fields, so a seller cannot read
  back the address `PATCH` writes. The design omits them too, so this is a
  spec gap.
- `fulfillment.shipped` lacks the §2.5 `buyer_*` and `seller_name` fields.

### 2. API amounts are emitted at storage scale

Every monetary field is returned as the driver hands it back — `"99.9900"`,
four fractional digits, whatever the currency. The design renders amounts at
the currency's `minor_unit_scale` and specifies a startup-loaded
`CurrencyScaleCache` in `pricing` as the single source of that scale
([backend-coding-standards.md §3.2](../../conventions/backend-coding-standards.md)).
No such cache exists, so nothing formats: a JPY price reads `"1000.0000"`.
The effective-price conversion also rounds with `toFixed(4)`. The supported
currency list `USD, THB, JPY, SGD` is redefined in five or more libs; the
cache is the natural single source for that too.

### 3. Undesigned `GET /catalog/categories/:categoryId/products`

`GET /catalog/products?categoryId=` (backend#41) now covers it. The legacy
route 404s on an unknown category, returns the detail shape with `variants`
always `[]` because the query never loads them, uses a raw product id as its
cursor and clamps `limit` to 50. Delete it, or design it.

### 4. `product.changed` payloads differ per producer

`CREATED` omits `brand` and shapes `variants[]` and `images[]` differently
from §2.10; `UPDATED` omits `created_at`, `variants[]` and `images[]`.
`category_path` now agrees everywhere (ADR-0005). A Schema Registry (entry 8)
would have caught this.

### 5. `POST /seller/register` does not follow its design

It creates no `seller_profile`, returns only `{userId}` with no access token,
`sellerProfileId` or refresh cookie, does not verify the password when linking
an existing account (no `401` / `PASSWORD_REQUIRED_FOR_LINK`), and emits the
uncatalogued `platform.seller.registered`. The design's profile insert also
cannot run as written: it leaves `business_name` and `tax_id` NULL, and
migration 0007 makes those and the address columns NOT NULL. That
**spec/schema gap** has to be settled first. Until register is fixed,
`POST /seller/kyc` creates the profile when none exists (backend#40); that
branch must be removed in the same change.

### 6. Decisions the design leaves open

- **Locale to currency.** The design says "the currency matching the locale"
  with no table. backend#38 resolves only the highest-q locale, maps a bare
  language to its likely region (`th` to THB, `ja` to JPY, `en` to USD), and
  falls back to USD.
- **Event logo URL lifetime.** `order.finalized` carries a presigned logo URL
  valid for one hour, so an email built or opened later shows a dead image.
  Either event URLs get a longer TTL or the consumer presigns from a key in
  the payload.
- **Refund reason.** A refund requires a `reason` so the buyer is told why,
  but the §2.7 `fulfillment.refunded` schema has no field for it, so it is
  stored nowhere.
- **`POST /seller/kyc` with a `REJECTED` application.** backend#40 answers
  `409` pointing to `/seller/kyc/resubmit`; the sequence lists only
  `PENDING`, `UNDER_REVIEW` and `APPROVED` for the `409`.
- **Duplicate SKU within one product** is a `422`; seller.md does not list it,
  and it reads as request validation (`400`).
- **Response details not spelled out:** the `GET
  /catalog/categories/:categoryId` body (built as the list shape with direct
  children), an unknown `categoryId` on `GET /catalog/products` (built as an
  empty page), and the `GET /pricing/fx-rates` error table.
- search.md says Catalog resolves `category_path` because walking the tree
  would read another module's schema. The indexer already reads `catalog.*`,
  so that rationale is stale.

---

## Open — platform conventions

### 7. Only one consumer exists

`apps/workers` runs the outbox relay, the schedulers and the search indexer.
The notification, audit and inventory consumers the design relies on are not
built, so:

- `pii.accessed` rows accumulate in the outbox with nothing writing
  `pii_access_logs`, and `inventory.changed`'s `adjustment_reason` reaches no
  `audit_logs` document.
- No email or in-app notification is ever sent, `inventory.low_stock` included.
- The stock movements the `inventory.*` consumer owns have no writer. Seller
  refund and cancel, and the suspended-seller auto-refund, therefore release
  reservations **inline**, which is the only reason a cancelled order's units
  become sellable again. When the consumer lands, those inline releases must go
  in the same change or the movement gains two writers and a redelivered event
  double-counts.

This is sprint scope rather than a defect, but it is the reason several
handlers do work the design assigns to a consumer.

### 8. Events are JSON, not Avro

[kafka-events.md](../../conventions/kafka-events.md) specifies Avro with the
Confluent Schema Registry under BACKWARD compatibility. The outbox relay and
the consumers use `JSON.stringify` / `JSON.parse`. Coherent end to end, but not
the designed wire format, and the Schema Registry is running unused. A registry
would have caught the mixed `product.changed` payloads in entry 4.

### 9. Seller handlers write other modules' schemas directly

The seller routes write `catalog`, `pricing`, `inventory` and `orders` rows
themselves rather than through each owner's application service, which the
[sole-writer rule](api-design/seller.md#db-mapping) requires. The soft-delete's
pending check still joins `orders` tables to `catalog.offer` in one statement.

### 10. Most retention jobs are not built

[cleanup-jobs.md](cleanup-jobs.md) lists more jobs than the five `workers` now
runs (outbox retention, suspension expiry, suspended-seller auto-refund, FX
refresh and the orphaned-image sweep). The remaining seven have no
implementation.

### 11. Tooling the conventions assume is missing

- No project has a `lint` target, so CI's `nx run-many -t lint` runs nothing
  and the money-field lint rule the conventions require is not enforced.
- The pre-merge checklist requires a Supertest test per endpoint; the backend
  has none.
- About 50 nullable string DTO fields are emitted as `type: object` in the
  OpenAPI document (NestJS union reflection), mostly in seller and admin.
- Many endpoints with a request DTO do not declare the `400` they can answer.
- `CheckoutService` sits in `application/` but runs raw SQL through TypeORM's
  `DataSource`, against the Tier 1 layer rule.
