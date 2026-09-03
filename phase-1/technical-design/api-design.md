# API Design — Phase 1

**Status:** Draft  
**Base URL:** `/api/v1`  
**Auth scheme:** JWT Bearer (`Authorization: Bearer <access_token>`)  
**Source of truth:** [BRD v1.1](../requirements/BRD.md), [ERD](data-model-erd.md), [implementation-specs](implementation-specs.md)

---

## Summary

- [1. Conventions](#conventions)
- [2. Module Index](#module-index)

<a id="conventions"></a>
## 1. Conventions

Cross-cutting API conventions (naming, money, pagination, error shape, auth guard legend, idempotency, OpenAPI tags) live in [conventions/api-conventions.md](../../conventions/api-conventions.md).

### 1.1 Guard application matrix

Maps Phase 1 endpoint groups to NestJS guard classes. `—` = guard not applied.

| Endpoint group | JwtAuth | Roles | EmailVerified | SellerApproved | SellerNotSuspended |
|----------------|---------|-------|--------------|----------------|--------------------|
| `GET /auth/google`, `/auth/facebook`, `/auth/google/callback`, `/auth/facebook/callback` | — | — | — | — | — |
| `POST /auth/login`, `/auth/refresh`, `/auth/forgot-password`, `/auth/reset-password`, `/auth/verify-email` | — | — | — | — | — |
| `POST /auth/resend-verification` | YES | — | — | — | — |
| `POST /auth/logout`, `/auth/change-password`, `/auth/set-password` | YES | — | — | — | — |
| `GET /profile/me`, `PATCH /profile/me` | YES | — | — | — | — |
| `*/profile/addresses` | YES | BUYER | — | — | — |
| `GET /catalog/*`, `GET /pricing/*`, `GET /search/*` | — | — | — | — | — |
| `GET /cart`, `POST /cart/items`, cart mutations, `POST /cart/merge` | YES | BUYER | — | — | — |
| `POST /orders` | YES | BUYER | YES | — | — |
| `GET /orders`, `GET /orders/:id` | YES | BUYER | — | — | — |
| `POST /seller/register` | YES | BUYER | YES | — | — |
| `GET /seller/profile`, `GET /seller/kyc` | YES | SELLER | — | — | — |
| `GET /seller/offers`, `GET /seller/offers/:id` | YES | SELLER | — | YES | — |
| `POST /seller/offers`, `PATCH /seller/offers/:id`, pricing, inventory | YES | SELLER | — | YES | YES |
| `GET /seller/orders`, `GET /seller/orders/:id`, `POST /seller/orders/:id/ship` | YES | SELLER | — | — | — |
| `POST /seller/orders/:id/refund` | YES | SELLER | — | YES | YES |
| `GET /admin/*`, `POST /admin/*` | YES | ADMIN | — | — | — |
| `GET /notifications`, `PATCH /notifications/*` | YES | — | — | — | — |

**Suspended sellers:** `SellerNotSuspendedGuard` allows only the three SELLER endpoints above; all other SELLER routes return 403 `{ "message": "Your account is suspended." }`.

**Admin routes:** Return HTTP 403 for both unauthenticated (missing/invalid token) AND unauthorized (valid token, role ≠ ADMIN) — 401 would leak admin route existence.

---

<a id="module-index"></a>
## 2. Module Index

| Module | File | Endpoints | Primary DB(s) |
|--------|------|-----------|---------------|
| Identity & Auth | [api-design/auth.md](api-design/auth.md) | Registration, login, OAuth, token rotation, password flows | Postgres |
| Profile | [api-design/profile.md](api-design/profile.md) | Profile read/update, address book CRUD | Postgres |
| Catalog | [api-design/catalog.md](api-design/catalog.md) | Category tree, product list/detail, offer listing (public read) | Postgres |
| Pricing | [api-design/pricing.md](api-design/pricing.md) | Effective price resolution, FX rate cache | Postgres |
| Search | [api-design/search.md](api-design/search.md) | Full-text product search with facets | Elasticsearch |
| Cart | [api-design/cart.md](api-design/cart.md) | Cart CRUD, guest cart merge | Postgres |
| Orders | [api-design/orders.md](api-design/orders.md) | Checkout (transactional), order list/detail | Postgres |
| Seller | [api-design/seller.md](api-design/seller.md) | KYC, offer/inventory/product management, seller order ops | Postgres + Kafka outbox |
| Admin | [api-design/admin.md](api-design/admin.md) | KYC decisions, seller suspension, moderation queue | Postgres + MongoDB audit |
| Notifications | [api-design/notifications.md](api-design/notifications.md) | In-app notification list, mark read | Postgres |
| Health | [api-design/health.md](api-design/health.md) | Liveness/readiness probe | Postgres, MongoDB, ES, Kafka |
