# Phase 1 — Module Inventory

**Status:** Draft  
**Source of truth:** [conventions/module-architecture.md](../../conventions/module-architecture.md)

Module structure conventions (hexagonal layers, CQRS pattern, outbox integration, OpenAPI generation, shared library): see [conventions/module-architecture.md](../../conventions/module-architecture.md).

---

## Summary

- [Module summary table](#module-summary-table)
- [Scheduled tasks (workers)](#scheduled-tasks)

<a id="module-summary-table"></a>
## Module summary table

Tier column references [conventions/module-architecture.md §2](../../conventions/module-architecture.md): **T1** = full hexagonal, **T2** = simplified service, **T3** = thin/infrastructure.

| Module lib | Tier | NestJS module | HTTP controllers | Kafka producers | Kafka consumers |
|------------|------|--------------|-----------------|----------------|----------------|
| `catalog` | T1 | `CatalogModule` | `CategoriesController`, `ProductsController` | `product.changed`, `offer.changed` | — |
| `pricing` | T1 | `PricingModule` | `PricingController` | — | — |
| `inventory` | T1 | `InventoryModule` | (via Seller module) | `inventory.changed`, `inventory.low_stock` | `fulfillment.placed` (consumer group: `inventory.fulfillment-placed`) |
| `cart` | T1 | `CartModule` | `CartController` | — | — |
| `orders` | T1 | `OrdersModule` | `OrdersController` | `fulfillment.placed`, `fulfillment.shipped`, `fulfillment.refunded`, `order.finalized` | — |
| `identity` | T2 | `IdentityModule` | `AuthController`, `ProfileController` | (via outbox) | — |
| `seller` | T2 | `SellerModule` | `SellerController` | `seller.kyc.submitted` | — |
| `admin` | T2 | `AdminModule` | `AdminController` | `seller.kyc.decided`, `seller.suspended`, `seller.reinstated`, `moderation.listing.removed` | — |
| `search` | T3 | `SearchModule` | `SearchController` | — | `product.changed`, `offer.changed`, `inventory.changed`, `seller.suspended`, `seller.reinstated`, `moderation.listing.removed` |
| `notifications` | T3 | `NotificationsModule` | `NotificationsController` | — | `order.finalized`, `fulfillment.*`, `order.completed`, `seller.kyc.decided`, `inventory.low_stock`, `moderation.listing.removed`, `seller.suspended`, `seller.reinstated` |
| `platform` | T3 | `PlatformModule` | `HealthController` | (outbox relay publishes all topics) | — |
| `workers` | T3 | `WorkersModule` | `HealthController (port 3001)` | `fulfillment.delivered` (mock scheduler), `order.completed` (delivery-tracker) | `fulfillment.delivered` |

---

<a id="scheduled-tasks"></a>
## Scheduled tasks (workers)

All schedulers live in `apps/workers/src/schedulers/`. Pattern: see [conventions/module-architecture.md §10](../../conventions/module-architecture.md).

| Scheduler file | Cron | Purpose |
|---|---|---|
| `digest.scheduler.ts` | `0 23 * * *` (23:00 UTC) | ET-09 listing-removed daily digest per seller |
| `fx-rate.scheduler.ts` | `0 * * * *` (hourly) | FX rate refresh from exchangerate.host |
| `suspension-expiry.scheduler.ts` | `*/5 * * * *` (every 5 min) | Emit `seller.suspension_expired` for due rows |
| `reservation-expiry.scheduler.ts` | `*/5 * * * *` (every 5 min) | Emit `inventory.reservation_expired` for expired holds |
| `delivery-mock.scheduler.ts` | `*/5 * * * *` (every 5 min) | Poll SHIPPED fulfillments where `eta <= now()`; emit `fulfillment.delivered` (V1 mock — no real carrier) |
| `auto-refund.scheduler.ts` | `*/5 * * * *` (every 5 min) | US-P-16: poll PENDING fulfillments where seller is SUSPENDED and `placed_at + fulfillment_window_days < now()`; emit `fulfillment.refund_suspended_seller` |
