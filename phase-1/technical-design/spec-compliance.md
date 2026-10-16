# Spec compliance — known code/spec divergences

**Status:** Living document
**Updated:** 2026-10-16

The technical design in this directory is canonical. This file is the register
of places where the code is known **not** to match it yet, so that no mismatch
is silent. See [`decisions/README.md`](../../decisions/README.md) for the rule
and for how to resolve an entry.

Each entry resolves one of three ways: fix the code (the default), write an ADR
and change spec plus code together, or — if it is a whole feature — move it into
sprint scope. Delete an entry when it is resolved; do not keep a tick-list of
history here.

---

## Resolved 2026-10-08/16

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
| `POST /seller/register` created no seller profile, returned only `{userId}`, did not verify the password when linking, emitted the uncatalogued `platform.seller.registered`, and the design's profile insert broke migration 0008_seller_schema's NOT NULL columns (0007 before 2026-10-16) | [ADR-0007](../../decisions/0007-seller-register-collects-business-details.md): register collects `businessName`, `taxId` and `businessAddress`; account, profile and session are created in one transaction and the response carries `accessToken` and `sellerProfileId` plus the refresh cookie; `401` / `403` / `409 PASSWORD_REQUIRED_FOR_LINK`; no event (backend#45, frontend#20). `POST /seller/kyc` answers `404` without a profile |
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
| Events were camelCase JSON envelopes and the Schema Registry ran unused; `product.changed` `CREATED` and `UPDATED` each omitted §2.10 fields, and `offer.changed`, `inventory.changed`, `listing.flagged` and the auth and fulfillment payloads differed from their schemas | Code fixed to kafka-events.md (backend#56, infra#4): the 29 catalog schemas are `libs/contracts/avro/*.avsc` with generated types; the relay publishes the §1 snake_case envelope in Confluent wire format and consumers decode through the registry; `OutboxService.writeEvent` is typed per topic and every producer spec encodes its payloads against the `.avsc`. [ADR-0012](../../decisions/0012-avro-subjects-registered-by-ci-and-schema-init.md): one script registers the subjects, from CI against an ephemeral registry and from a compose `schema-init` one-shot before `workers` |
| A seller soft delete and an admin `REMOVE` emitted no `offer.changed` `REMOVED`; admin and seller producers minted a fresh `correlation_id`; `createProduct` dropped `brand`; `fulfillment.delivered`, `order.completed`, `inventory.reservation_expired` and `keyword_blocklist.changed` had no producer; `inventory.low_stock` sent `''` for an offer without a variant | Code fixed (backend#57–#63, frontend#29, #30). Every api-side producer carries the request's `X-Correlation-ID`. `workers` runs the mock delivery scheduler (SHIPPED with `estimated_delivery_at <= now()`, every `DELIVERY_MOCK_INTERVAL_MS`), the `orders.delivery-tracker` consumer, whose completion check locks the order row, and `expire-stock-reservations`, which releases `reserved_qty` only and skips a row checkout touched. Blocklist writes emit `keyword_blocklist.changed` with the acting admin; an update maps to `ADDED`, or `REMOVED` on deactivation, since the enum has no `UPDATED`. [ADR-0013](../../decisions/0013-offer-requires-variant.md): every offer references a variant; an offer created without one gets the product's `DEFAULT` variant, existing offers were backfilled and `variant_id` is NOT NULL. `offer.changed` keeps `variant_id` nullable for messages already on the topic. Avro built-as rules from backend#56: DLQ records are JSON with `envelope_encoding` `json`, or `base64` for undecodable bytes; a payload that fails its schema marks the outbox row `FAILED` at once; a new offer's `inventory.changed` uses `MANUAL_UPDATE` with the opening `on_hand_qty` as `delta`; `seller.suspension_amended` sends `''` for a null reason |
| The notification, audit and inventory consumers were not built: no email or in-app notification was sent, `pii.accessed` and `inventory.changed` reached no MongoDB document, and seller refund, cancel and the suspended-seller auto-refund released reservations inline | Built (backend#64–#66, infra#5). The four `inventory.*` groups move stock through `InventoryApplicationService`, every reservation write scoped to the fulfillment's `ACTIVE` rows, quantities taken from the reservation rows; the inline releases are gone, and a release that would drive `reserved_qty` negative fails its CHECK and dead-letters rather than clamping. `platform.audit` routes every catalogued topic except `fx_rate.updated` and `seller.profile_changed` into `audit_logs` / `activity_events` / `pii_access_logs`, masked, idempotent on `event_id`; only `workers` holds a MongoDB client, and `MONGODB_URI` must name a database. The 21 `notification.*` groups send through nodemailer and write in-app rows idempotent on `(recipient_user_id, source_event_id)`; email is at-least-once (no send marker in the ERD), retried 1+3 times and then written to `email.outbound.dlq` with ET-18/ET-19 bodies redacted; the 23:00 UTC digest sends ET-09 under the advisory lock; migration 0018 adds `seller_email` / `seller_name` to `pending_listing_removal_digest`; templates are code, not `notifications.email_template` rows |
| Migrations did not run on an empty database: 0001–0005 and 0003b carried later TypeORM timestamps than 0006–0018, 0003b and 0008 both created `identity."user"`, and seller (0007) referenced the user table before identity (0008) created it | [ADR-0014](../../decisions/0014-migration-name-suffix-is-the-sequence.md) (backend#67): every `name` ends in `179000000{seq}`; 0003b deleted; identity is `0007_identity_schema`, seller `0008_seller_schema`; every `CREATE TABLE` is `IF NOT EXISTS`; CI's `migrations` job applies, reverts and re-applies the sequence on an empty Postgres. Existing databases are rebuilt, not carried over |
| The refresh cookie was `refresh_token` with `SameSite=Lax`; nothing was rate limited; seller register created an unverified account and sent no verification email; the seller app had no profile page | Code fixed (backend#68, frontend#31): the cookie is `refreshToken`, `SameSite=Strict`, cleared with the same attributes; `@nestjs/throttler` applies auth-jwt-design §5 and seller.md's register limit through a Redis store shared by every `api` replica, with `429 TOO_MANY_REQUESTS`, `X-RateLimit-*` and `Retry-After`; health is unthrottled. [ADR-0015](../../decisions/0015-seller-register-sends-verification-email.md): a new seller account gets ET-18's seller variant, `auth.email_verification_requested` carries `portal` (default `BUYER`), and the seller app serves `/verify-email`, an unverified banner with resend, and `/profile` (read-only while suspended, as seller.md requires). Sellers holding `SELLER` without a profile were not migrated: every database was rebuilt under ADR-0014, so none remain |

---

## Open — API surface

### 1. Money gaps left after CurrencyScaleCache

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

### 2. Decisions the design leaves open

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

### 3. Seller handlers write other modules' schemas directly

The seller routes write `catalog`, `pricing`, `inventory` and `orders` rows
themselves rather than through each owner's application service, which the
[sole-writer rule](api-design/seller.md#db-mapping) requires. The soft-delete's
pending check still joins `orders` tables to `catalog.offer` in one statement.
The search indexer rebuilds each document by reading `catalog`, `seller`,
`pricing` and `inventory` directly, rather than merging per-event payload
fields as search.md § Document composition specifies. The `product.changed`
and `offer.changed` payload builders (backend#56) read `seller.seller_profile`
and `pricing.offer_price` / `fx_rate` with SQL inside the producing
transaction, not through the owners' application services, which conventions
§4.2 requires; those services read outside the transaction. The same holds
for the wave-5 producers: the mock delivery scheduler and the order-completion
check read `identity."user"` for `buyer_email` / `buyer_name` (as the
suspended-seller auto-refund already did), because `orders.order` keeps no buyer
snapshot, and `expire-stock-reservations` joins `catalog.offer` for
`product_id`, which no `inventory` table carries. The wave-6 inventory consumers do the same: `inventory.changed` requires
`product_id`, so `InventoryApplicationService` reads `catalog.offer` (marked
`SPEC GAP` in code). The fix for both is to carry `product_id` on the
`fulfillment.*` items, and `offer_id` too on `fulfillment.refunded` items,
which lack it — so consumer-field-matrix §6's refunded row cannot be filled
from the payload as written.

### 4. Most retention jobs are not built

[cleanup-jobs.md](cleanup-jobs.md) lists more jobs than the five `workers` now
runs (outbox retention, suspension expiry, suspended-seller auto-refund, FX
refresh, the orphaned-image sweep and `expire-stock-reservations`). The
remaining six have no implementation.

### 5. Tooling the conventions assume is missing

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

### 6. Design documents out of step with the built consumers

- data-model-erd.md's `pending_listing_removal_digest` lacks `seller_email` and
  `seller_name`, which kafka-events.md §2.14 and the matrix require (migration
  0018 adds them).
- data-model-erd.md loads templates from `notifications.email_template` with
  Handlebars; the code renders them in code and the table is unused. Needs an
  ADR or a seed.
- `seller.kyc.submitted` has no `review_due_at`, so ET-21 omits its review-by
  line; the matrix says to read it "from the owning row", against its own §1.
- `fulfillment.refund_suspended_seller` has no `display_id`; ET-13 / ET-13b
  show the order UUID.
- Retry count: conventions say "retry 3x", kafka-events §4 "after 3 attempts";
  built as 4 attempts in all.
- The UI-design tables list seller in-app `ORDER_PLACED` and `KYC_SUBMITTED`;
  the matrix has no seller row for either. Built per the matrix.
- Templates and auth.md link to `${SELLER_APP_URL}/seller/...` and
  `${ADMIN_APP_URL}/admin/...`; the seller and admin apps serve those routes at
  root. The seller app redirects `/seller/verify-email` and
  `/seller/reset-password` (frontend#31); other seller links and every admin
  link still miss.
- Matrix §5 gives `inventory.changed` `UNKNOWN` the seller as actor;
  data-model-mongodb.md says `SYSTEM`. Built as `SYSTEM`.
- `audit_logs.actor_id` is "the acting user", but the matrix maps it to
  `payload.seller_id` (a seller profile id) for `seller.kyc.submitted` and seller
  stock edits. Built per the matrix; `seller_user_id` is on `kyc.submitted`.
- The docs say KYC payloads carry `tax_id`; neither KYC schema has it.
- A non-`ADMIN_MANUAL` `listing.flagged` is audited with role `SYSTEM`, which the
  matrix does not state.
- No `inventory.low_stock` is emitted when a checkout reservation takes
  available stock below the threshold, though the ERD's edge-triggered rule
  covers any stock write.
