# API Design — Phase 1

**Status:** Complete  
**Base URL:** `/api/v1`  
**Auth scheme:** JWT Bearer (`Authorization: Bearer <access_token>`)  
**Source of truth:** [BRD v1.3](../requirements/BRD.md), [ERD](data-model-erd.md)

---

## Summary

- [1. Conventions](#conventions)
- [2. Module Index](#module-index)

<a id="conventions"></a>
## 1. Conventions

Cross-cutting API conventions (naming, money, pagination, error shape, auth guard legend, idempotency, OpenAPI tags) live in [conventions/api-conventions.md](../../conventions/api-conventions.md).

Three of those conventions apply to every endpoint in every module document below and are not restated per endpoint:

- **Correlation ID.** Every endpoint accepts an `X-Correlation-ID` request header, generates a UUIDv7 when it is absent, echoes it on the response, and carries the same value into every log line and every `platform.outbox_event` / Kafka envelope written during the request — see [observability.md § Correlation ID Propagation](../../conventions/observability.md#correlation-id).
- **Errors.** Every non-2xx response uses the envelope and the HTTP error-code table in [api-conventions.md § Standard Error Shape](../../conventions/api-conventions.md#standard-error-shape). Endpoint sections list the statuses and codes they can return, not the envelope shape.
- **Rate limiting.** Throttled endpoints return `X-RateLimit-Limit`, `X-RateLimit-Remaining` and, on `429`, `Retry-After`. Per-endpoint limits are defined in [auth-jwt-design.md § Rate limiting](../../conventions/auth-jwt-design.md#rate-limiting).

Every operation carries an `operationId` of the form `<Module>_<verb><Resource>` (`Identity_register`, `Seller_shipFulfillment`) per [api-conventions.md § Naming](../../conventions/api-conventions.md#naming).

### 1.1 Guard application matrix

Maps Phase 1 endpoint groups to NestJS guard classes. `—` = guard not applied. Guards are pure checks on the decoded JWT claims plus the `JwtAuthGuard` Redis revocation read; none of them queries Postgres — see [auth-jwt-design.md § Auth guards](../../conventions/auth-jwt-design.md#auth-guards).

| Endpoint group | JwtAuth | Roles | EmailVerified | SellerApproved | SellerNotSuspended |
|----------------|---------|-------|--------------|----------------|--------------------|
| `GET /health` (`api` and `workers`) | — | — | — | — | — |
| `GET /auth/google`, `/auth/facebook`, `/auth/google/callback`, `/auth/facebook/callback`, `POST /auth/oauth/exchange` | — | — | — | — | — |
| `POST /auth/register` | — | — | — | — | — |
| `POST /auth/login`, `/auth/refresh`, `/auth/forgot-password`, `/auth/reset-password`, `/auth/verify-email` | — | — | — | — | — |
| `POST /auth/resend-verification` | YES | — | — | — | — |
| `POST /auth/logout`, `/auth/logout-all`, `/auth/set-password`, `PATCH /auth/change-password` | YES | — | — | — | — |
| `GET /profile/me`, `PATCH /profile/me`, `POST /profile/me/logo` | YES | — | — | — | — |
| `*/profile/addresses`, `*/profile/addresses/:addressId`, `PATCH /profile/addresses/:addressId/default` | YES | BUYER | — | — | — |
| `GET /catalog/*`, `GET /pricing/*`, `GET /search/*` | — | — | — | — | — |
| `GET /cart`, `POST /cart/items`, cart mutations, `POST /cart/merge` | YES | BUYER | — | — | — |
| `POST /orders` | YES | BUYER | YES | — | — |
| `GET /orders`, `GET /orders/:orderId` | YES | BUYER | — | — | — |
| `POST /seller/register` | — | — | — | — | — |
| `POST /seller/kyc`, `GET /seller/kyc`, `POST /seller/kyc/resubmit` | YES | SELLER | — | — | — |
| `GET /seller/profile` | YES | SELLER | — | — | — |
| `PATCH /seller/profile` | YES | SELLER | — | — | YES |
| `GET /seller/offers`, `GET /seller/offers/:offerId` | YES | SELLER | — | YES | YES |
| `POST /seller/offers`, `PATCH /seller/offers/:offerId`, `PUT`/`DELETE /seller/offers/:offerId/prices/*` | YES | SELLER | — | YES | YES |
| `PATCH /seller/inventory/:offerId`, `POST /seller/inventory/bulk` | YES | SELLER | — | YES | YES |
| `POST /seller/products`, `PATCH /seller/products/:productId`, `DELETE /seller/products/:productId` | YES | SELLER | — | YES | YES |
| `GET /seller/orders`, `GET /seller/orders/:fulfillmentId`, `POST /seller/orders/:fulfillmentId/ship` | YES | SELLER | — | — | — |
| `POST /seller/orders/:fulfillmentId/refund`, `POST /seller/orders/:fulfillmentId/cancel` | YES | SELLER | — | YES | YES |
| `GET /seller/dashboard/summary` | YES | SELLER | — | YES | YES |
| `GET`/`POST`/`PATCH`/`DELETE /admin/*` | YES | ADMIN | — | — | — |
| `GET /notifications`, `PATCH /notifications/*` | YES | — | — | — | — |

**Seller registration is public.** `POST /seller/register` takes no token: a prospective seller may hold no account at all, and one who already holds a buyer account authenticates with their password inside the request body rather than with a buyer JWT (US-S-01, [diagram 06](../diagrams/06-auth-portals.md)). `POST /seller/kyc` requires a SELLER token but neither KYC approval — which it is the means of obtaining — nor a verified email.

**`SellerApprovedGuard` scope:** listing, pricing, inventory, product and fulfillment-action routes only. The onboarding routes (`/seller/register`, `/seller/kyc`, `/seller/kyc/resubmit`, `GET`/`PATCH /seller/profile`) and the read-only order routes are reachable before approval.

**Suspended sellers:** `SellerNotSuspendedGuard` allows only `GET /seller/orders`, `GET /seller/orders/:fulfillmentId` and `POST /seller/orders/:fulfillmentId/ship`, plus the read-only `GET /seller/profile` and `GET /seller/kyc` needed to render the suspension reason and `suspended_until` on the locked dashboard (US-S-02). All other SELLER routes return 403 `{ "message": "Your account is suspended." }`.

**Admin routes:** Return HTTP 403 for both unauthenticated (missing/invalid token) AND unauthorized (valid token, role ≠ ADMIN) — 401 would leak admin route existence.

**Product mutation is creator-scoped, and the check is not a guard.** `PATCH` and `DELETE /seller/products/:productId` require an ADMIN caller or a `catalog.product.created_by_seller_id` equal to the calling seller's profile; any other seller gets `403`, and a `NULL` value means platform-owned — every one of the 100 seeded products — so those are ADMIN-only. The claims in the JWT cannot answer this, since it depends on a row, so it belongs in the service layer beside the mutation and not in the matrix above. Creating an **offer** against a product another seller created stays open to every approved seller: the shared catalogue is the design ([`seller.md`](./api-design/seller.md#product-authorization), [`data-model-erd.md`](./data-model-erd.md#table-catalog-product)).

---

<a id="module-index"></a>
## 2. Module Index

| Module | File | Endpoints | Primary DB(s) |
|--------|------|-----------|---------------|
| Identity & Auth | [api-design/auth.md](api-design/auth.md) | Registration, portal-scoped login, OAuth code exchange, token rotation, password flows | Postgres + Redis |
| Profile | [api-design/profile.md](api-design/profile.md) | Profile read/update, address book CRUD | Postgres |
| Catalog | [api-design/catalog.md](api-design/catalog.md) | Category tree, product list/detail, offer listing (public read) | Postgres |
| Pricing | [api-design/pricing.md](api-design/pricing.md) | Effective price resolution, FX rate cache | Postgres |
| Search | [api-design/search.md](api-design/search.md) | Full-text product search with facets | Elasticsearch |
| Cart | [api-design/cart.md](api-design/cart.md) | Cart CRUD, guest cart merge | Postgres |
| Orders | [api-design/orders.md](api-design/orders.md) | Checkout (transactional), order list/detail | Postgres |
| Seller | [api-design/seller.md](api-design/seller.md) | Registration, KYC, offer/inventory/product management, seller fulfillment ops | Postgres + Kafka outbox |
| Admin | [api-design/admin.md](api-design/admin.md) | KYC decisions, seller suspension, moderation queue, keyword blocklist | Postgres + Kafka outbox |
| Notifications | [api-design/notifications.md](api-design/notifications.md) | In-app notification list, mark read | Postgres |
| Health | [api-design/health.md](api-design/health.md) | Liveness + readiness probes for `api` and `workers` | Postgres, MongoDB, ES, Kafka, MinIO, Redis, Schema Registry, SMTP |
