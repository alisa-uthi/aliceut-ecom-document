# API Conventions

Cross-phase REST API conventions for all AliceUT services.  
**Source of truth:** [BRD v1.1](../phase-1/requirements/BRD.md)

---

## Naming

- Paths: kebab-case, plural resources (`/orders`, `/cart-items`)
- Query params: camelCase (`priceMin`, `sortBy`)
- Body/response fields: camelCase
- `operationId`: `<Module>_<verb><Resource>` (e.g. `Identity_register`)

---

## Money

All monetary values in JSON requests and responses are **strings** (`"99.99"`), never numbers. The currency code is always sent alongside the amount.

See also: CLAUDE.md § Money handling for storage and arithmetic rules.

---

## Pagination

- **Cursor-based** (default for entity lists): `?limit=20&cursor=<opaque>` → `{ data, meta: { nextCursor, hasMore } }`
- **Offset-based** (simple admin queues): `?limit=20&offset=0` → `{ data, meta: { total, limit, offset } }`
- Default `limit`: 20. Max `limit`: 100.

---

## Standard Error Shape

```json
{
  "statusCode": 400,
  "error": "Bad Request",
  "message": "Validation failed",
  "errors": [{ "field": "email", "message": "must be an email" }]
}
```

Field `errors` is present only for 400 validation failures.

### HTTP error codes reference

| HTTP | Code | Meaning |
|------|------|---------|
| 400 | BAD_REQUEST | Validation failure; `errors[]` present |
| 401 | UNAUTHORIZED | Missing or expired token |
| 403 | FORBIDDEN | Authenticated but not authorized |
| 404 | NOT_FOUND | Resource not found |
| 409 | CONFLICT | Duplicate resource, state conflict, or price change |
| 422 | UNPROCESSABLE | Business rule violation (no items, unsupported currency) |
| 429 | TOO_MANY_REQUESTS | Rate limit exceeded |
| 500 | INTERNAL_ERROR | Unexpected server error |

---

## Auth Guard Legend

| Guard | Description |
|-------|-------------|
| `PUBLIC` | No token required |
| `JWT` | Valid access token, any role |
| `BUYER` | JWT + `roles` contains `BUYER` |
| `SELLER` | JWT + `roles` contains `SELLER` |
| `ADMIN` | JWT + `roles` contains `ADMIN` |
| `EMAIL_VERIFIED` | JWT + `email_verified: true` |
| `SELLER_APPROVED` | SELLER guard + `SellerProfile.kyc_status = APPROVED` |
| `SELLER_ACTIVE` | SELLER_APPROVED + `SellerProfile.suspension_status != SUSPENDED` |

Suspended sellers may only access: `GET /seller/orders`, `GET /seller/orders/:id`, `POST /seller/orders/:id/ship`.

For the per-endpoint guard matrix see [api-design.md § Guard application matrix](../phase-1/technical-design/api-design.md#15b-guard-application-matrix).

---

## Idempotency

Checkout endpoint requires `Idempotency-Key: <client-uuid>` header. Same key returns the cached response until the key expires.

---

## OpenAPI Tags

`Identity`, `Auth`, `Profile`, `Catalog`, `Pricing`, `Search`, `Cart`, `Orders`, `Seller`, `Admin`, `Notifications`
