# Spec compliance — known code/spec divergences

**Status:** Living document
**Updated:** 2026-10-15

The technical design in this directory is canonical. This file is the register
of places where the code is known **not** to match it yet, so that no mismatch
is silent. See [`decisions/README.md`](../../decisions/README.md) for the rule
and for how to resolve an entry.

Each entry resolves one of three ways: fix the code (the default), write an ADR
and change spec plus code together, or — if it is a whole feature — move it into
sprint scope. Delete an entry when it is resolved; do not keep a tick-list of
history here.

---

## Resolved 2026-10-08/15

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
| `POST /seller/kyc` took JSON and published to the uncreated `platform.seller.kyc.submitted`, keyed on the application | Code fixed (backend#40): multipart upload, `seller.kyc.submitted` keyed on the seller profile. Its interim create-profile fallback is gone (backend#45) |
| `admin.service.ts` read the nonexistent `u.first_name` / `u.last_name` in seven queries | Code fixed (backend#40): `u.full_name` |
| `fulfillment.refunded`, `.cancelled` and `.shipped` were keyed on `fulfillment_id` | Code fixed (backend#40): keyed on `order_id`; refunded and cancelled payloads follow §2.7 / §2.16 |
| Checkout reservations expired after two days; `order.finalized` carried `buyer_business_logo_url: null`; a null `preferred_currency` checked out in USD | Code fixed (backend#38): 15-minute TTL; logo key presigned; currency resolved from `Accept-Language` |
| Search's `category` filter was a slug where the design said a `categoryId` UUID, and `category_path` held only the leaf | [ADR-0005](../../decisions/0005-search-category-filter-is-a-slug.md): the filter is a slug, and `category_path` is ancestor-to-leaf slugs in the index and in every `product.changed` (backend#42). `reindexAllProducts` must run once after deploy |
| The `PATCH /seller/profile` design wrote `seller_profile.submitted_data`, a column that does not exist | [ADR-0006](../../decisions/0006-seller-profile-patch-writes-address-columns.md): the request is `{businessName?, businessAddress?}` on the address columns (backend#42) |
| API amounts were emitted at storage scale (`"1000.0000"` for JPY), effective-price rounded with `toFixed(4)`, and the supported-currency list was redefined in six places | Code fixed (backend#46): startup-loaded `CurrencyScaleCache` in `pricing` per backend-coding-standards §3.2; every API amount renders at its currency's `minor_unit_scale`, rounded half-up; FX rates keep 8 dp and event payloads 4 dp as kafka-events.md specifies; one `SELLER_PRICE_CURRENCIES` list |
| The undesigned `GET /catalog/categories/:categoryId/products` duplicated `GET /catalog/products?categoryId=` | Deleted (backend#44); the buyer app moved to `GET /catalog/products` (frontend#19) |
| `POST /seller/register` created no seller profile, returned only `{userId}`, did not verify the password when linking, emitted the uncatalogued `platform.seller.registered`, and the design's profile insert broke migration 0007's NOT NULL columns | [ADR-0007](../../decisions/0007-seller-register-collects-business-details.md): register collects `businessName`, `taxId` and `businessAddress`; account, profile and session are created in one transaction and the response carries `accessToken` and `sellerProfileId` plus the refresh cookie; `401` / `403` / `409 PASSWORD_REQUIRED_FOR_LINK`; no event (backend#45, frontend#20). `POST /seller/kyc` answers `404` without a profile |
| The frontend called the backend through hand-written `HttpClient` wrappers; the generated client was gitignored, so the client-sync workflow could never open a PR | Code fixed (frontend#21): `@aliceut/api-client` re-exports the committed `openapi-generator-cli` output, the wrappers are deleted, and frontend CI fails when the committed client differs from the backend spec. Moving onto the spec's shapes fixed buyer register (sent `accountType`), multipart KYC submit, the category tree, search and order field names, and admin enums |
| `POST /auth/register` rejected `accountType` with `400` and hardcoded `B2C`, so no buyer could become B2B | Code fixed to auth.md (backend#47, frontend#23): required `accountType` `B2C \| B2B`, stored and carried in the token; the buyer register toggle sends it |
| The rounding mode for API amounts was unspecified | [ADR-0008](../../decisions/0008-api-amounts-round-half-up.md): half-up, stated in backend-coding-standards §3.1/§3.2 (implemented by backend#46) |
| `GET /pricing/offers/:offerId/effective-price` returned `nativeAmount` / `nativeCurrency`, defaulted `currency` to USD, answered a missing FX row with `fxStale: true`, and had no `404` / `422` | Code fixed to pricing.md (backend#50): `amount`, `currency`, `priceType`, `compareAtAmount`, `saleEndsAt` and the five display keys; `currency` required; `displayAmount: null` without an FX row; `404` for an inactive offer, `422` without a `LIST` price. Cart, checkout and catalog resolve prices through the same pricing functions |
| `Cart` returned offer ids and quantities; checkout took `items[{offerId, quantity}]`, always captured `LIST`, converted a missing FX pair at 1:1, stored `'****'` and the payment method as `shipping_method`, and hashed the idempotency key instead of the body | Code fixed (backend#53, frontend#25): the cart is the checkout preview (lines, `groups[]`, four totals, FX fields); checkout takes `cartItems[]` plus `confirmedPrices[]` with `409 PRICE_CHANGED`, `skippedItems` and `failedGroups`; the request body is hashed |
| Search results had `description`, `status`, storage-scale `lowestListPrice` / `lowestSalePrice`, `imageStorageKey` and `offers[]`, and the index mapping differed from search.md | Code fixed (backend#51, frontend#25): the search.md result shape with `lowestOffer`, `inStock`, `score` and `facets`; the mapping matches § Index Mapping, and `workers` rebuilds the index from Postgres when `_meta.mapping_version` changes; `workers` no longer mounts `/search` or `/pricing`. Infra's init container and stale template are gone (infra#3) |
| Search broke sort ties on `_id`, which Elasticsearch 8 rejects | [ADR-0010](../../decisions/0010-search-sort-tiebreak-is-product-id.md): tie-break on `product_id` (backend#52) |
| `GET /catalog/products/:productId` omitted `offers[]`, `GET .../offers` had a non-spec shape and no seller-eligibility filter, and the category list exposed `isProhibited` | Code fixed to catalog.md (backend#49, frontend#25) |
| A null `preferred_currency` meant USD in catalog and cart but the Accept-Language rule in checkout | [ADR-0011](../../decisions/0011-null-preferred-currency-resolves-from-accept-language.md): pricing's Auto rule everywhere (backend#54) |
| `GET /seller/kyc` returned a status summary and dropped decided applications; `GET /seller/profile` had no address; `fulfillment.shipped` lacked the §2.5 buyer and seller fields | Code fixed (backend#48, frontend#25); [ADR-0009](../../decisions/0009-seller-profile-get-returns-business-address.md) adds `businessAddress` to the profile response, and the KYC form prefills from it |
| The buyer register page signed in twice, and a `401` from the refresh call left every app's interceptor waiting forever | Code fixed (frontend#25) |
| `GET /orders` and `GET /orders/:id` returned the old `OrderDto`, a status filter returned short pages while `hasMore` was true, `:orderId` took only a UUID, and the generated client could not type the `201` of `POST /orders` | Code fixed to orders.md (backend#55, frontend#28): `OrderSummaryDto` with cursor pagination, `OrderDetailDto` (shipping address, totals, lifecycle timestamps), UUID or `ORD-` id with ownership in the query; the `200` schema is a `oneOf` of the replay and placed envelopes, so the client types both. Two modules' `FulfillmentItemDto` shared one schema name, which blanked seller item titles; renamed |

---

## Open — API surface

### 1. `product.changed` payloads differ per producer

`CREATED` omits `brand` and shapes `variants[]` and `images[]` differently
from §2.10; `UPDATED` omits `created_at`, `variants[]` and `images[]`.
`category_path` now agrees everywhere (ADR-0005). A Schema Registry (entry 6)
would have caught this.

### 2. Session and account gaps found with seller register

- **Refresh cookie.** auth.md and seller.md name it `refreshToken` with
  `SameSite=Strict`; the code sets `refresh_token` with `SameSite=Lax`, on
  login and seller register alike (one shared `REFRESH_COOKIE`).
- **No rate limiting.** The spec requires 5 attempts per IP per 15 minutes on
  `POST /seller/register`; the backend has no throttler at all, so auth login
  and register are unlimited too.
- **No verification email for sellers.** Seller register creates the account
  with `emailVerified=false`, but nothing sends a verification email and the
  design emits no `auth.email_verification_requested` for it.
- **Sellers registered before backend#45** hold the `SELLER` role with no
  profile, so `POST /seller/kyc` answers `404`. Calling register again with the
  password creates the profile (ADR-0007); no data migration was written.
- **No seller profile page.** `PATCH /seller/profile` and its address have no
  screen in the seller app.

### 3. Money gaps left after CurrencyScaleCache

- The `pricing.currency` seed has no `BHD` row, which the §3.2 table lists
  (scale 3, not seller-allowed).
- Seller price input accepts 4 dp in any currency, backend and frontend, so a
  JPY `1000.5` displays as `1001`. Input is not validated against the scale.
- The §3.2 refresh snippet `setInterval(() => void this.refresh())` crashes
  Node on a failed reload; the code catches, logs and keeps the loaded scales.
  The doc should match.
- `Money.toJSON(scale)` is the §3.1 name but collides with the
  `JSON.stringify` `toJSON(key)` hook; stringifying a `Money` directly breaks.
- Only USD-based `fx_rate` rows exist and nothing derives cross or inverse
  rates, so an offer priced in THB has no USD, JPY or SGD display price: it
  shows `displayAmount: null` and no display-currency price filter matches it.
- Seller prices with 4 dp make a cart `lineTotal` differ from the rendered unit
  price times quantity, and `buyer_currency_total` (rounded once) can differ by
  one minor unit from the sum of per-line buyer amounts. Literal to orders.md.

### 4. Decisions the design leaves open

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
- **Price check on a first checkout.** `cart_item` stores no shown price, so a
  line submitted without a `confirmedPrices` entry is not revalidated. The
  buyer app always sends them; the design should either snapshot the shown
  price or make `confirmedPrices` mandatory.
- **`PARTIALLY_PLACED` with only skipped items.** kafka-events.md §2.8 says
  yes, orders.md says only when a group failed. The code follows §2.8.
- **Checkout edge cases the design does not cover**, built as: a missing FX
  row fails the whole request with `422`; a `cartItems` id not in the cart is
  `404`; groups and totals count `ACTIVE` lines only; a line without a live
  `LIST` row has null `effectivePrice` / `lineTotal` (cart.md shows non-null);
  the cart reads `seller.seller_profile` for `sellerName`, absent from cart.md's
  DB mapping. Skipped items and failed groups are not on `GET /orders/:id`, so
  the confirmation page loses them on reload.
- **Search facets.** `priceRange.min` / `max` are read as USD and
  `displayMin` / `displayMax` as the requested currency, as in the example.
- **Catalog offers**, built as: an offer with no live `LIST` row is omitted; an
  invalid Bearer token is anonymous rather than `401`; the sale window is
  `starts_at <= now() < ends_at`; offers are ordered by offer id. Prohibited
  categories still appear in the public tree because no filter is named.
- **Seller KYC read**, built as: `priorRejectionReason` is the previous
  application's reason when the latest one supersedes a rejection; a seller
  with no profile gets the same `404` as one with no application.
- **Order detail**, built as: `shippingAddress.phone` is always null because
  `identity.address` has no phone column; `itemCount` is the sum of line
  quantities. orders.md's `orderStatus` enum lists `DELIVERED`, which its
  derived-status table never produces (all delivered is `COMPLETED`).
- search.md says Catalog resolves `category_path` because walking the tree
  would read another module's schema. The indexer already reads `catalog.*`,
  so that rationale is stale.

---

## Open — platform conventions

### 5. Only one consumer exists

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

### 6. Events are JSON, not Avro

[kafka-events.md](../../conventions/kafka-events.md) specifies Avro with the
Confluent Schema Registry under BACKWARD compatibility. The outbox relay and
the consumers use `JSON.stringify` / `JSON.parse`. Coherent end to end, but not
the designed wire format, and the Schema Registry is running unused. A registry
would have caught the mixed `product.changed` payloads in entry 1.

### 7. Seller handlers write other modules' schemas directly

The seller routes write `catalog`, `pricing`, `inventory` and `orders` rows
themselves rather than through each owner's application service, which the
[sole-writer rule](api-design/seller.md#db-mapping) requires. The soft-delete's
pending check still joins `orders` tables to `catalog.offer` in one statement.
The search indexer rebuilds each document by reading `catalog`, `seller`,
`pricing` and `inventory` directly, rather than merging per-event payload
fields as search.md § Document composition specifies.

### 8. Most retention jobs are not built

[cleanup-jobs.md](cleanup-jobs.md) lists more jobs than the five `workers` now
runs (outbox retention, suspension expiry, suspended-seller auto-refund, FX
refresh and the orphaned-image sweep). The remaining seven have no
implementation.

### 9. Tooling the conventions assume is missing

- No project has a `lint` target, so CI's `nx run-many -t lint` runs nothing
  and the money-field lint rule the conventions require is not enforced.
- The pre-merge checklist requires a Supertest test per endpoint; the backend
  has none.
- About 50 nullable string and date DTO fields are emitted as `type: object` in
  the OpenAPI document (NestJS union reflection), mostly in seller and admin
  (`readAt`, `suspendedUntil`, `shippedAt`, `decidedAt`, `nextCursor`, ...), so
  the generated client types them `object | null` and the apps cast. The fix is
  an explicit `type: String` on each `@ApiProperty`.
- The frontend `typecheck` target fails on tsconfig settings
  (`declarationMap` / `rootDir`) and CI does not run it.
- `auth.service.seller-account.spec.ts` timed out once in a full parallel test
  run and passed alone; it may flake in CI.
- Many endpoints with a request DTO do not declare the `400` they can answer.
- `@nestjs/swagger` silently merges two DTO classes with the same name into one
  schema. One collision (`FulfillmentItemDto`) was found and renamed; nothing
  checks for others.
- `CheckoutService` sits in `application/` but runs raw SQL through TypeORM's
  `DataSource`, against the Tier 1 layer rule.
