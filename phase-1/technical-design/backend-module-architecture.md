# Phase 1 — Module Inventory

**Status:** Complete  
**Source of truth:** [conventions/backend-module-architecture.md](../../conventions/backend-module-architecture.md)

Module structure conventions (hexagonal layers, CQRS pattern, outbox integration, OpenAPI generation, shared library): see [conventions/backend-module-architecture.md](../../conventions/backend-module-architecture.md).

Topic partition keys, Avro schemas and per-consumer-group side effects: see [kafka-events.md](./kafka-events.md). Tables per Postgres schema: see [data-model-erd.md](./data-model-erd.md#postgresql-schema-map).

---

## Summary

- [Processes](#processes)
- [Module summary table](#module-summary-table)
- [Ownership boundaries](#ownership-boundaries)
- [Scheduled tasks (workers)](#scheduled-tasks)
- [Outbox relay and consumer wiring](#outbox-and-consumers)

<a id="processes"></a>
## Processes

Two deployable processes, both built from the `aliceut-ecom-backend` monorepo ([conventions §1](../../conventions/backend-module-architecture.md#1-repository-structure)). Neither is a module — each is a composition root that wires the eleven module libs below.

| Process | Nx app | Composition root | Responsibility |
|---------|--------|-----------------|----------------|
| `api` | `apps/api` | `AppModule` | HTTP only. Every controller listed below is registered here. Writes outbox rows; consumes no Kafka topic and runs no scheduled job. |
| `workers` | `apps/workers` | `WorkersModule` | The outbox relay, every Kafka consumer group listed below, and every scheduled job. No public HTTP surface: a single `WorkersHealthController` on `PORT_WORKERS` (default 3001) serves the compose probe. |

A module lib does not choose its process. `libs/<module>` exports controllers (wired by `api`), consumer handlers and schedulable application services (wired by `workers`); the composition root decides what runs where. The Kafka consumer column below therefore names the module that **owns** the handler — the process executing it is always `workers`.

Deployment topology for both processes: [docker-compose-topology.md](./docker-compose-topology.md#service-inventory).

---

<a id="module-summary-table"></a>
## Module summary table

Tier column references [conventions/backend-module-architecture.md §2](../../conventions/backend-module-architecture.md#2-module-tiers): **T1** = full hexagonal, **T2** = simplified service, **T3** = thin/infrastructure.

The Postgres schema column is the module's **sole-writer** claim: no other module writes those tables, and no module reads another module's tables (see [Ownership boundaries](#ownership-boundaries)).

| Module lib | Tier | NestJS module | Postgres schema | HTTP controllers | Kafka producers | Kafka consumer groups |
|------------|------|--------------|----------------|-----------------|----------------|----------------------|
| `catalog` | T1 | `CatalogModule` | `catalog` | `CategoriesController`, `ProductsController` | `product.changed`, `offer.changed` (**sole producer** — a seller listing edit reaches it through `CatalogApplicationService`), `listing.soft_deleted` | — |
| `pricing` | T1 | `PricingModule` | `pricing` | `PricingController` | `fx_rate.updated` (written by `PricingApplicationService.refreshRates()`, invoked by the workers FX scheduler) | — |
| `inventory` | T1 | `InventoryModule` | `inventory` | — (seller-facing inventory routes live on `SellerController`, which calls `InventoryApplicationService`) | `inventory.changed`, `inventory.low_stock`, `inventory.reservation_expired` (via the workers reservation-expiry scheduler) | `inventory.fulfillment-placed` (`fulfillment.placed`), `inventory.fulfillment-shipped` (`fulfillment.shipped`), `inventory.fulfillment-cancelled` (`fulfillment.cancelled`), `inventory.fulfillment-refunded` (`fulfillment.refunded` **and** `fulfillment.refund_suspended_seller`) |
| `cart` | T1 | `CartModule` | `cart` | `CartController` | — | — |
| `orders` | T1 | `OrdersModule` | `orders` | `OrdersController` | `fulfillment.placed`, `fulfillment.shipped`, `fulfillment.refunded`, `fulfillment.cancelled`, `order.finalized`, `order.completed`, `fulfillment.delivered` (via the workers delivery-mock scheduler), `fulfillment.refund_suspended_seller` (via the workers auto-refund scheduler) | `orders.delivery-tracker` (`fulfillment.delivered` → completion check → `order.completed`) |
| `identity` | T2 | `IdentityModule` | `identity` | `AuthController`, `ProfileController` | `auth.email_verification_requested`, `auth.password_reset_requested`, `auth.password_changed` | — |
| `seller` | T2 | `SellerModule` | `seller` | `SellerController` (`POST /seller/register` is PUBLIC — see [Ownership boundaries](#ownership-boundaries)) | `seller.kyc.submitted`, `seller.profile_changed`, `seller.suspension_expired` (via the workers suspension-expiry scheduler) | — |
| `admin` | T2 | `AdminModule` | `admin` | `AdminController`, `KeywordBlocklistController` | `seller.kyc.decided`, `seller.suspended`, `seller.suspension_amended`, `seller.reinstated`, `listing.flagged`, `moderation.listing.removed` | — |
| `search` | T3 | `SearchModule` | — (owns the Elasticsearch `products` index, no Postgres tables) | `SearchController` | — | `search.product-changed`, `search.offer-changed`, `search.inventory-changed`, `search.reservation-expired`, `search.seller-suspended`, `search.seller-reinstated`, `search.suspension-expired`, `search.listing-flagged`, `search.listing-removed`, `search.listing-soft-deleted`, `search.seller-profile-changed`, `search.fx-rate-updated` |
| `notifications` | T3 | `NotificationsModule` | `notifications` | `NotificationsController` | — | `notification.kyc-submitted` (ET-14 seller + ET-21 admin), `notification.kyc-decided`, `notification.seller-suspended`, `notification.seller-reinstated`, `notification.suspension-expired` (ET-11 + `SUSPENSION_EXPIRED` in-app), `notification.fulfillment-placed`, `notification.fulfillment-seller-alert`, `notification.fulfillment-shipped`, `notification.fulfillment-delivered`, `notification.fulfillment-refunded`, `notification.fulfillment-cancelled` (ET-16 + `FULFILLMENT_CANCELLED` in-app), `notification.refund-suspended-seller-buyer` (ET-13), `notification.refund-suspended-seller-seller` (ET-13b), `notification.order-summary`, `notification.order-completed`, `notification.low-stock`, `notification.listing-flagged` (ET-08), `notification.listing-removed`, `notification.email-verification` (ET-18), `notification.password-reset` (ET-19), `notification.password-changed` (ET-20) |
| `platform` | T3 | `PlatformModule` | `platform` | `HealthController` | — (the outbox relay it owns publishes every topic on behalf of the producing module) | `platform.audit` — the single audit projection group; subscribes to every topic in [kafka-events.md §1](./kafka-events.md#topic-summary) except the two that are deliberately not persisted, and writes MongoDB `audit_logs` / `activity_events` / `pii_access_logs` |

**Eleven module libs, two apps.** `libs/contracts` (OpenAPI DTOs, Avro schemas) and `libs/shared` (money, errors, logger, guards) are support libraries, not modules, and own no domain state.

**Thirty-nine consumer groups** are named in the last column, all of them running in `workers`: four on `inventory`, one on `orders`, twelve on `search`, twenty-one on `notifications` and one on `platform`. That total is the number of dead-letter topics to expect, since a DLQ is per group ([Outbox relay and consumer wiring](#outbox-and-consumers)) — it is not the event-topic count, because two groups subscribe to more than one topic: `platform.audit` to nearly every topic, and `inventory.fulfillment-refunded` to both refund topics.

**The audit group is named `platform.audit`, once, everywhere.** `consumer_group` is half the primary key of `platform.processed_event` ([data-model-erd.md](./data-model-erd.md#table-platform-processed-event)) and it names the DLQ topic, so two spellings are not two names for one group but two groups: each would keep its own dedupe rows and its own offsets, so every event would be projected into MongoDB twice, and the dead-letter topic one of them wrote to would be a topic nothing consumed and no operator was watching. The short form `audit` is not an alias.

The `HealthController` in `platform` (the public `GET /api/v1/health` contract, [api-design/health.md](./api-design/health.md)) and the `WorkersHealthController` in `apps/workers` are deliberately distinct classes serving distinct contracts; they are not two registrations of one controller.

---

<a id="ownership-boundaries"></a>
## Ownership boundaries

Cross-module rules come from [conventions §7](../../conventions/backend-module-architecture.md#7-module-dependency-rules): a module may call another module's exported `ApplicationService`, and may react to another module's Kafka topic, but never touches another module's tables. Six boundaries carry enough weight to state explicitly.

**The seller module owns `seller` and writes nothing else.** Every seller-facing listing, pricing and stock route lives on `SellerController` and every one of them addresses a table another module owns, so each is a call to that module's application service rather than SQL. The services and the signatures the seller routes use:

| Owning module | Application service | Methods the seller routes call |
|---|---|---|
| `catalog` | `CatalogApplicationService` | `createOffer(dto, sellerProfileId, tx): OfferView`, `setOfferStatus(offerId, status, sellerProfileId, tx): OfferView`, `createProduct(dto, sellerProfileId, tx): ProductView`, `updateProduct(productId, dto, sellerProfileId, tx): ProductView`, `withdrawSellerListings(productId, sellerProfileId, tx): WithdrawalResult`, `getProductForListing(productId): ProductListingView`, `getOfferForSeller(selector, sellerProfileId): OfferView \| null`, `listOffersForSeller(filter, sellerProfileId): Page<OfferView>` |
| `pricing` | `PricingApplicationService` | `upsertOfferPrice(offerId, priceType, dto, tx): PriceView`, `deactivateOfferPrice(offerId, priceId, tx): PriceView`, `deactivateOfferPrices(offerIds, tx): void`, `listLivePrices(offerId): PriceView[]`, `assertSellerPriceableCurrency(code): void`, `toDisplayPrices(amount, nativeCurrencyCode): Record<string, string>` |
| `orders` | `OrdersApplicationService` | `hasPendingFulfillmentsForProduct(productId, sellerProfileId): boolean` — the read that replaces the `orders.fulfillment_item` → `catalog.offer` join in the seller's product-withdrawal guard. The same service owns the order-completion check the `orders.delivery-tracker` consumer calls. |
| `inventory` | `InventoryApplicationService` | `openStock(offerId, onHandQty, lowStockThreshold, tx): StockView`, `adjustStock(offerId, dto, sellerProfileId, tx): StockView`, `adjustStockBulk(rows, sellerProfileId, tx): BulkResult`, `getStock(offerId): StockView` |
| `catalog` (SKU resolution, suspension reactivation) | `CatalogApplicationService` | `resolveSkuForSeller(sku, sellerProfileId): SkuOfferView \| null`, `republishOffer(offerId, tx): void` — the second is how a price or seller-profile change reaches `offer.changed` without a second producer — and `reactivateSuspendedOffers(sellerProfileId, tx): string[]`, called by the suspension-expiry scheduler |
| `admin` | `ModerationApplicationService` | `screenListingContent(content): ScreeningResult`, `getOpenCaseForOffer(offerId): ModerationCaseView \| null`, `flagListing(offerId, source, matchedTerms, tx): ModerationCaseView` |

`ScreeningResult` is `{ outcome: 'CLEAN' \| 'FLAG' \| 'BLOCK', matchedTerms: string[], prohibitedCategory: boolean }`. `outcome` is the strictest tier among everything that matched — one `BLOCK` term outranks any number of `FLAG` ones, and a prohibited taxonomy node is always `BLOCK` — so the caller branches on a single value and never has to rank the matches itself. The tiers are the two of D-05, defined on [`admin.keyword_blocklist.enforcement`](./data-model-erd.md#table-admin-keyword-blocklist); `matchedTerms` is what the `moderation_case` stores in `matched_terms` and what the dismissed-term suppression rule queries, so it is returned on a `FLAG` and on a `BLOCK` alike even though only the `FLAG` path persists it.

Each method takes the caller's transaction handle and writes its own module's rows **and its own outbox row** inside it, which is what keeps the producer of every topic the schema owner: `catalog.offer` and `offer.changed` move together, `inventory.stock` and `inventory.changed` move together. The seller module writes `seller.seller_profile`, `seller.kyc_application` and the `seller.kyc.submitted`, `seller.profile_changed` and `seller.suspension_expired` outbox rows, and nothing further.

**The rule binds the module's schedulers, not only its routes.** The suspension-expiry sweep ([cleanup-jobs.md](./cleanup-jobs.md#lift-expired-suspensions)) runs in the `workers` service inside the seller module and touches two schemas it does not own, so it takes the same two seams: `CatalogApplicationService.reactivateSuspendedOffers(sellerProfileId, tx): string[]` sets the suspension-deactivated offers back to `ACTIVE` and returns their ids, which the sweep publishes as `seller.suspension_expired.offer_ids`; `IdentityApplicationService.getUsersByIds(userIds): UserView[]` supplies the `id`, `email` and `full_name` the payload carries, replacing the `seller.seller_profile` → `identity.user` join D-03 removes. A scheduler that wrote `catalog.offer` directly would be the same violation as a controller that did, and it is the harder one to notice, because no request ever fails.

**The admin module reaches the same service for its one product cascade.** A moderation `REMOVE` that takes the last non-`REMOVED` offer off a product calls `CatalogApplicationService.removeProductIfNoOffersRemain(productId, tx): boolean`, which counts the survivors, sets `catalog.product.status = REMOVED` when there are none, writes the `product.changed` (`change_type: REMOVED`) outbox row in the caller's transaction, and returns whether it fired. The cascade cannot sit in the admin handler: the payload carries `category_path`, `title`, `variants[]` and `images[]`, which only catalog can assemble, and the event is what deletes the product's Elasticsearch document — the removal event deletes no document by design ([api-design/admin.md](api-design/admin.md#decide-moderation-case)).

The three-foreign-schema write at listing creation — `catalog.offer`, `pricing.offer_price`, `inventory.stock` — becomes an orchestration rather than a joint transaction: `SellerService.createOffer()` opens one transaction, calls `CatalogApplicationService.createOffer()`, then `PricingApplicationService.upsertOfferPrice()` per price row, then `InventoryApplicationService.openStock()`, and commits. The transaction boundary is the caller's; the writes inside it are each their owner's. That is the shape Phase 2 extracts: the same call sequence over process boundaries becomes three service calls and a saga, and the atomicity V1 gets from one database is the property the extraction has to replace — which it can only do if the seam is already where the extraction would cut it.

**Inventory is the only writer of `inventory.*`.** Four fulfillment transitions move stock — shipment, ordinary refund, suspension refund and seller cancel — and in every one of them the Orders module updates `orders.fulfillment` and writes the outbox event, then stops: it does not touch `inventory.stock` or `inventory.stock_reservation`. Three consumer groups owned by Inventory are the single writers of those changes:

| Transition | Topic | Consuming group |
|---|---|---|
| Shipment | `fulfillment.shipped` | `inventory.fulfillment-shipped` |
| Refund | `fulfillment.refunded` | `inventory.fulfillment-refunded` |
| Refund of a suspended seller's order | `fulfillment.refund_suspended_seller` | `inventory.fulfillment-refunded` (same group, second topic) |
| Seller cancel | `fulfillment.cancelled` | `inventory.fulfillment-cancelled` |
| **Delivery** | `fulfillment.delivered` | **none — delivery moves no stock** |

The two refund topics share one group deliberately. The suspension refund restores stock by exactly the rule the ordinary refund uses, so a second group would duplicate the branch, the `processed_event` row and the dead-letter topic without changing behaviour. Delivery is the opposite case and is listed to make the absence explicit rather than look like an omission: the `on_hand_qty` decrement happens at **shipment**, so by the time a fulfillment is delivered the stock has already left and there is nothing left to write. No group consumes `fulfillment.delivered` on Inventory's behalf, and none should be added.

Every inventory write is therefore eventually consistent, bounded by consumer lag; available-stock reads may lag a fulfillment status change briefly. All three groups dedupe on `event_id`, so a redelivered `fulfillment.cancelled` cannot restore stock twice and a redelivered `fulfillment.shipped` cannot decrement twice. Checkout is the one synchronous exception the convention grants: it calls `InventoryApplicationService.reserveStock()` inside the checkout transaction.

**Shipment is where stock actually leaves.** `inventory.fulfillment-shipped` closes the ownership gap that moving the `on_hand_qty` decrement to ship time created: without it nothing subscribed to `fulfillment.shipped`, reservations of shipped fulfillments would stay `ACTIVE` for the life of the offer, and availability would stay understated forever. The handler does four things in one transaction: sets that fulfillment's `ACTIVE` reservations to `CONSUMED` (scoped `WHERE fulfillment_id = :fulfillment_id`), decrements `on_hand_qty` by the shipped quantity, decrements `reserved_qty` by the same quantity, and writes an `inventory.changed` outbox row whose payload carries `change_reason = 'SHIPMENT'`. `change_reason` is a payload field only: `inventory.stock` has no reason column and no PostgreSQL enum type defines the value, so `SHIPMENT` is added to the `inventory.changed` Avro schema in [kafka-events.md](./kafka-events.md#topic-summary) and nowhere in the migration set. The two decrements move together, so `available = on_hand - reserved` does not change and buyer-facing availability does not move at shipment. The event still fires even though availability is unchanged: the stock trail lives in the MongoDB audit stream, which is fed by events, so omitting it would leave the on-hand decrement with no audit record anywhere — and the seller portal's on-hand display reads it.

**The keyword blocklist belongs to `admin`.** `admin.keyword_blocklist` is an admin-editable Postgres table with CRUD endpoints on `KeywordBlocklistController` (ADMIN role only, every mutation audited) — not a constant in code. The listing-time guard that Catalog and Seller run on create and edit reads an in-process cache of the active terms, refreshed on a TTL (`KEYWORD_BLOCKLIST_CACHE_TTL`, default 60 s); it must not query per save. Prohibited **categories** are a separate mechanism — `catalog.category.is_prohibited`, owned by Catalog.

**Seller registration is public.** `POST /seller/register` carries no `JwtAuthGuard`: it is the account-creation entry point and cannot require an account. It is two-step — registration, then `POST /seller/kyc`, which requires JWT + SELLER role but neither KYC approval (circular) nor email verification. `SellerApprovedGuard` applies to listing, inventory, pricing and fulfillment routes only.

**The outbox relay is `platform`'s, the events are not.** `platform` owns `outbox_event`, `processed_event` and the relay process, and publishes every topic. The event's *meaning* and its payload contract belong to the producing module in the table above; the relay is transport and never interprets a payload.

---

<a id="scheduled-tasks"></a>
## Scheduled tasks (workers)

Every scheduled job in Phase 1 runs in the `workers` process using `@nestjs/schedule`. There is **no in-database scheduler**: Postgres is the stock `postgres:16-alpine` image with no `pg_cron` and no scheduling extension. Schedulers live in `apps/workers/src/schedulers/` and are plain `@Injectable()` providers registered in `WorkersModule`; each one injects the exported application service of the module that owns the data and never reaches a table directly ([conventions §10](../../conventions/backend-module-architecture.md#10-workers-composition-root)).

Every interval, TTL and batch size is env-configurable, and the env var name is in the table below beside the default it overrides — no schedule literal is hardcoded anywhere in the set. Each job acquires a `pg_advisory_lock` keyed on the job name before doing work and releases it at the end, so a second `workers` replica is safe by construction rather than by deployment convention.

| Scheduler file | Owning module | Cron / interval | Purpose |
|---|---|---|---|
| `digest.scheduler.ts` | `notifications` | `0 23 * * *` (23:00 UTC) — `NOTIFICATION_DIGEST_CRON` | ET-09 listing-removed daily digest: aggregate `notifications.pending_listing_removal_digest` per seller profile, send, delete the processed rows |
| `fx-rate.scheduler.ts` | `pricing` | `0 * * * *` (hourly, UTC) — `FX_RATE_REFRESH_CRON` | FX rate refresh from exchangerate.host; upsert `pricing.fx_rate` in place and emit `fx_rate.updated` |
| `delivery-mock.scheduler.ts` | `orders` | `@Interval()` — default 60 s (`DELIVERY_MOCK_INTERVAL_MS`) | Poll SHIPPED fulfillments where `eta <= now()`; emit `fulfillment.delivered` (V1 mock — no real carrier) (US-P-15) |
| `auto-refund.scheduler.ts` | `orders` | `@Interval()` — default 3600 s (`AUTO_REFUND_INTERVAL_MS`) | US-P-16: poll PENDING fulfillments where the seller is SUSPENDED and `placed_at + fulfillment_window_days < now()`; emit `fulfillment.refund_suspended_seller` |
| `reservation-expiry.scheduler.ts` | `inventory` | `@Interval()` — default 5 min (`RESERVATION_EXPIRY_INTERVAL_MS`) | Release `ACTIVE` reservations past `expires_at` that never reached a fulfillment (`fulfillment_id IS NULL`); mark them EXPIRED and emit `inventory.reservation_expired`, all in one transaction |
| `suspension-expiry.scheduler.ts` | `seller` | `0 * * * *` (hourly, UTC) — `SUSPENSION_EXPIRY_CRON` | Lift suspensions whose `suspended_until` has passed; emit `seller.suspension_expired` |
| `cleanup.scheduler.ts` | `identity`, `inventory`, `orders`, `platform`, `notifications` | per job — see [cleanup-jobs.md](./cleanup-jobs.md) | Retention deletes for expired refresh sessions, credential tokens, terminal stock reservations, idempotency keys, published outbox rows, processed-event rows and read in-app notifications |

All cron expressions are UTC. The per-job schedule, retention window, env var name and advisory-lock key are recorded with each job in [cleanup-jobs.md](./cleanup-jobs.md); this table is the ownership view.

---

<a id="outbox-and-consumers"></a>
## Outbox relay and consumer wiring

Envelope, partition-key, DLQ and BACKWARD-compatibility rules: [conventions/kafka-events.md](../../conventions/kafka-events.md). The Phase 1 wiring commitments are:

**Producing side.** Every domain state change writes its `platform.outbox_event` row in the *same* Postgres transaction as the change — there is no publish-after-commit path. Each insert populates `aggregate_type`, `aggregate_id`, `topic`, `key`, `event_type`, `event_version`, `payload`, `correlation_id`, `occurred_at`, `created_at` and `updated_at`; all eleven are `NOT NULL`, so an insert naming only a topic and a payload fails at the database rather than at the relay. `key` **is** the aggregate id rendered as text, which is what keeps every event about one aggregate on one partition and preserves per-aggregate ordering. `correlation_id` is the value from the inbound `X-Correlation-ID` header, or one the API generated when the header was absent; a scheduled job with no inbound request generates its own.

**Relay.** The relay in `apps/workers` polls `WHERE publication_status = 'PENDING'` every `OUTBOX_POLL_INTERVAL_MS` (default 500 ms), serializes to Avro through the Schema Registry client, publishes, and sets `publication_status = 'PUBLISHED'`. It never republishes a row already marked PUBLISHED. Relay lag — the age of the oldest PENDING row — is reported on the workers health endpoint and alerts above 30 s ([docker-compose-topology.md §12](./docker-compose-topology.md#operations-and-alerting)).

**Consuming side.** Every consumer group in the table above:

- dedupes on `platform.processed_event (consumer_group, event_id)` before executing its side effect;
- commits its Kafka offset **after** the side effect and the `processed_event` insert, never before — at-least-once delivery with idempotent handlers, not at-most-once;
- has its own dead-letter topic, `<consumer_group>.dlq`, carrying the original envelope plus `error_type`, `error_message`, `failed_at` and `attempt_count`. Any non-empty DLQ is an alert condition.

No consumer reads another module's tables to enrich an event. If a handler needs a field, the field belongs in the payload — and which handler needs which field is recorded, field by field, in [consumer-field-matrix.md](./consumer-field-matrix.md). That matrix is the enforcement artifact for this rule: a consumer with a field no event supplies has nowhere legitimate to get it, so the gap has to be visible before the code is written rather than discovered when the handler is.
