# Phase 1 — Module Inventory

**Status:** Draft  
**Source of truth:** [conventions/backend-module-architecture.md](../../conventions/backend-module-architecture.md)

Module structure conventions (hexagonal layers, CQRS pattern, outbox integration, OpenAPI generation, shared library): see [conventions/backend-module-architecture.md](../../conventions/backend-module-architecture.md).

---

## Summary

- [Module summary table](#module-summary-table)
- [Scheduled tasks (workers)](#scheduled-tasks)

<a id="module-summary-table"></a>
## Module summary table

Tier column references [conventions/backend-module-architecture.md §2](../../conventions/backend-module-architecture.md): **T1** = full hexagonal, **T2** = simplified service, **T3** = thin/infrastructure.

| Module lib | Tier | NestJS module | HTTP controllers | Kafka producers | Kafka consumers |
|------------|------|--------------|-----------------|----------------|----------------|
| `catalog` | T1 | `CatalogModule` | `CategoriesController`, `ProductsController` | `product.changed`, `offer.changed` | — |
| `pricing` | T1 | `PricingModule` | `PricingController` | — | — |
| `inventory` | T1 | `InventoryModule` | (via Seller module) | `inventory.changed`, `inventory.low_stock` | `fulfillment.placed` (consumer group: `inventory.fulfillment-placed`) |
| `cart` | T1 | `CartModule` | `CartController` | — | — |
| `orders` | T1 | `OrdersModule` | `OrdersController` | `fulfillment.placed`, `fulfillment.shipped`, `fulfillment.refunded`, `order.finalized` | — |
| `identity` | T2 | `IdentityModule` | `AuthController`, `ProfileController` | (via outbox) | — |
| `seller` | T2 | `SellerModule` | `SellerController` | `seller.kyc.submitted` | — |
| `admin` | T2 | `AdminModule` | `AdminController` | `seller.kyc.decided`, `seller.suspended`, `seller.reinstated`, `moderation.listing.removed`, `listing.flagged (from POST /admin/moderation — triggers ET-08 seller notification + ES deindex)` | — |
| `search` | T3 | `SearchModule` | `SearchController` | — | `product.changed`, `offer.changed`, `inventory.changed`, `inventory.reservation_expired`, `seller.suspended`, `seller.reinstated`, `seller.suspension_expired`, `moderation.listing.removed`, `listing.soft_deleted`, `fx_rate.updated` |
| `notifications` | T3 | `NotificationsModule` | `NotificationsController` | — | `order.finalized`, `fulfillment.*`, `fulfillment.cancelled` (ET-16 + FULFILLMENT_CANCELLED in-app), `fulfillment.refund_suspended_seller` (ET-13/ET-13b), `order.completed`, `seller.kyc.decided`, `seller.kyc.submitted` (ET-14 admin + ET-21 seller), `seller.suspension_expired` (ET-11 + SUSPENSION_EXPIRED in-app), `inventory.low_stock`, `moderation.listing.removed`, `seller.suspended`, `seller.reinstated`, `auth.email_verification_requested` (ET-18), `auth.password_reset_requested` (ET-19), `auth.password_changed` (ET-20) |
| `platform` | T3 | `PlatformModule` | `HealthController` | (outbox relay publishes all topics) | — |
| `workers` | T3 | `WorkersModule` | `HealthController (port 3001)` | `fulfillment.delivered` (mock scheduler), `order.completed` (delivery-tracker) | `fulfillment.delivered` |

---

<a id="scheduled-tasks"></a>
## Scheduled tasks (workers)

All schedulers live in `apps/workers/src/schedulers/`. Pattern: see [conventions/backend-module-architecture.md §10](../../conventions/backend-module-architecture.md).

| Scheduler file | Cron | Purpose |
|---|---|---|
| `digest.scheduler.ts` | `0 23 * * *` (23:00 UTC) | ET-09 listing-removed daily digest per seller |
| `fx-rate.scheduler.ts` | `0 * * * *` (hourly) | FX rate refresh from exchangerate.host |
| `delivery-mock.scheduler.ts` | `@Interval()` — default 60 s (configurable via `DELIVERY_MOCK_INTERVAL_MS`) | Poll SHIPPED fulfillments where `eta <= now()`; emit `fulfillment.delivered` (V1 mock — no real carrier) (US-P-15) |
| `auto-refund.scheduler.ts` | `@Interval()` — default 3600 s (configurable via `AUTO_REFUND_INTERVAL_MS`) | US-P-16: poll PENDING fulfillments where seller is SUSPENDED and `placed_at + fulfillment_window_days < now()`; emit `fulfillment.refund_suspended_seller` |
