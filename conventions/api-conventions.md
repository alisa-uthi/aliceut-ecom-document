# API Conventions

Cross-phase REST API conventions for all AliceUT services.

**Status:** Complete  
**Source of truth:** [BRD v1.2](../phase-1/requirements/BRD.md)

---

## Summary

- [Naming](#naming)
- [Money](#money)
- [Success Response Shape](#success-response-shape)
- [Pagination](#pagination)
- [Standard Error Shape](#standard-error-shape)
- [Auth Guard Legend](#auth-guard-legend)
- [Correlation ID](#correlation-id)
- [Datetime](#datetime)
- [Idempotency](#idempotency)
- [OpenAPI Tags](#openapi-tags)

<a id="naming"></a>
## Naming

- Paths: kebab-case, plural resources (`/orders`, `/cart-items`)
- Query params: camelCase (`priceMin`, `sortBy`)
- Body/response fields: camelCase
- `operationId`: `<Module>_<verb><Resource>` (e.g. `Identity_register`)

---

<a id="money"></a>
## Money

All monetary values in JSON requests and responses are **strings** (`"99.99"`), never numbers. The currency code is always sent alongside the amount.

See also: CLAUDE.md § Money handling for storage and arithmetic rules.

---

<a id="success-response-shape"></a>
## Success Response Shape

All successful responses wrap payload in a `data` field. `meta` is optional on single-resource responses.

**Single resource** (GET one, POST create, PATCH, PUT):
```json
{
  "data": {
    "id": "uuid",
    "email": "user@example.com"
  }
}
```

**Collection** (GET list):
```json
{
  "data": [...],
  "meta": {
    "nextCursor": "opaque",
    "hasMore": true
  }
}
```

**Empty success** (DELETE, POST action with no body):
- HTTP `204 No Content` — no body.

---

<a id="pagination"></a>
## Pagination

**Cursor-based only.** Every list endpoint in every module uses the single envelope below — entity lists, search results, notification feeds, and admin queues alike. `page`, `offset` and `meta.total` do not exist in V1: **no endpoint may return a total count**, because a cursor-paginated query cannot produce one without a second full scan.

### Request parameters

| Param | Type | Default | Max | Notes |
|-------|------|---------|-----|-------|
| `limit` | integer | 20 | 100 | Items to return. A value above the max is a `400`. |
| `cursor` | string | — | — | Opaque continuation token. Omitted on the first request; on every later request it is the previous response's `meta.nextCursor`, passed back verbatim. |

Sort and filter params (`sortBy`, `sortDir`, and per-endpoint filters) may accompany `limit` and `cursor`, but a cursor is only valid for the sort and filter set it was issued under. A cursor presented alongside a different sort or filter is a `400`.

### Response envelope

```json
{
  "data": [ ... ],
  "meta": {
    "nextCursor": "eyJwbGFjZWRBdCI6IjIwMjYtMDktMDJUMTQ6MzA6MDAuMDAwWiIsImlkIjoiMDE5MzBhYmMtLi4uIn0",
    "hasMore": true
  }
}
```

| Field | Type | Meaning |
|-------|------|---------|
| `data` | array | The page of items. An empty array is a valid page. |
| `meta.hasMore` | boolean | `true` when a further page exists. |
| `meta.nextCursor` | string \| null | Token for the next page; `null` when `hasMore` is `false`. |

No other `meta` key is permitted on a list response.

### Sort key and cursor contents

The sort key is always the tuple `(<sort column>, id)` — the requested sort column plus the row's primary key as tiebreaker — so it is unique and stable even when the sort column holds duplicate values. When no sort is requested, the default sort column is the endpoint's documented one (typically `created_at`).

The cursor is the **base64url encoding of a JSON object carrying that tuple**:

```
{"placedAt":"2026-09-02T14:30:00.000Z","id":"01930abc-..."}
  → eyJwbGFjZWRBdCI6IjIwMjYtMDktMDJUMTQ6MzA6MDAuMDAwWiIsImlkIjoiMDE5MzBhYmMtLi4uIn0
```

The cursor is **opaque**: clients never parse, construct, or modify it, and its internal shape may change without an API version bump. A malformed or undecodable cursor is a `400` — never silently treated as "first page".

Keyset predicate, descending sort:

```sql
WHERE (sort_column, id) < (:cursorSortValue, :cursorId)
ORDER BY sort_column DESC, id DESC
LIMIT :limit + 1     -- the extra row only decides hasMore; it is not returned
```

Every list endpoint's sort column must be covered by an index on `(<sort column>, id)`.

### Client consequences

Without a total, a client cannot render page numbers, "N of M", or a last-page jump. List UIs use Previous/Next navigation only, and must state their empty and end-of-list conditions explicitly — see [frontend-coding-standards.md § 8](frontend-coding-standards.md#8-angular-material-usage-rules).

---

<a id="standard-error-shape"></a>
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

<a id="auth-guard-legend"></a>
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

For the per-endpoint guard matrix see [api-design.md § Guard application matrix](../phase-1/technical-design/api-design.md#11-guard-application-matrix).

---

<a id="correlation-id"></a>
## Correlation ID

Every endpoint accepts an `X-Correlation-ID` request header, generates one (UUIDv7) when it is absent, echoes it on the response as `X-Correlation-ID`, and carries the same value into every log line and every Kafka event envelope it produces (`correlation_id`).

The full contract — middleware, `AsyncLocalStorage` propagation, outbound-HTTP forwarding, log envelope fields, and sensitive-key masking — is defined in [observability.md](observability.md#correlation-id) and governs Phase 1.

---

<a id="datetime"></a>
## Datetime

All datetime fields in JSON requests and responses use **ISO 8601 UTC** strings with millisecond precision: `"2026-09-02T14:30:00.000Z"`.

- Suffix `Z` (UTC) required. No offsets (`+07:00`) in API payloads.
- Field naming: `*At` suffix for timestamps (`createdAt`, `updatedAt`, `expiresAt`), `*Date` suffix for calendar-only dates (`birthDate`, `scheduledDate`).
- Calendar-only dates (no time component): `"YYYY-MM-DD"` format, no time/timezone attached.
- Storage: Postgres `TIMESTAMPTZ` (store UTC, DB handles offset awareness). MongoDB: native BSON Date.
- Client displays: frontend converts UTC to local timezone for rendering — server never sends localized times.
- Duration/intervals: ISO 8601 duration strings where applicable (`"PT24H"`, `"P7D"`).

---

<a id="idempotency"></a>
## Idempotency

Checkout requires an `Idempotency-Key: <client-uuid>` header; seller and admin mutations accept one optionally.

A replay of the same key with the same body returns the **current state of the resource that key created or transitioned**, re-read at replay time. No response body is stored — the handler re-reads the resource and re-serialises it, which is why a replay may legitimately return a *later* state than the original call did: a fulfillment shipped between the first call and the replay comes back shipped. The same key with a **different** body is `409`, decided on the stored `request_hash`. Replay protection lasts until the key row expires; after that the key is a new key.

---

<a id="openapi-tags"></a>
## OpenAPI Tags

`Identity`, `Auth`, `Profile`, `Catalog`, `Pricing`, `Search`, `Cart`, `Orders`, `Seller`, `Admin`, `Notifications`, `Platform`
