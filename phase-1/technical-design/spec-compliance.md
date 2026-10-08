# Spec compliance — known code/spec divergences

**Status:** Living document
**Updated:** 2026-10-09

The technical design in this directory is canonical. This file is the register
of places where the code is known **not** to match it yet, so that no mismatch
is silent. See [`decisions/README.md`](../../decisions/README.md) for the rule
and for how to resolve an entry.

Each entry resolves one of three ways: fix the code (the default), write an ADR
and change spec plus code together, or — if it is a whole feature — move it into
sprint scope. Delete an entry when it is resolved; do not keep a tick-list of
history here.

---

## Resolved 2026-10-08/09

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

---

## Open — API surface

### 1. Seller and Admin responses are unmodelled

30 operations (16 Seller, 14 Admin) declare no response body in the OpenAPI
spec: `admin.controller.ts` has no return type on any handler, and the seller
list services return `unknown` built from raw SQL. The generated client is
untyped for both portals.

`seller/products` and `seller/inventory` are also still offset-paginated
(`page`/`limit` with a total), where
[api-conventions.md](../../conventions/api-conventions.md) requires cursor
pagination with `{data, meta:{nextCursor, hasMore}}` and no total.

### 2. Missing endpoints

From the design, not yet implemented: `POST /profile/me/logo`,
`GET`/`PATCH /seller/profile`, `POST /seller/kyc/resubmit`,
`POST`/`GET`/`PATCH /seller/offers` (only the price sub-routes exist),
`GET /catalog/products`, `GET /catalog/categories/:categoryId` and
`GET /pricing/fx-rates`.

The backend additionally serves `GET /catalog/categories/:categoryId/products`,
which is **not** in the design. Reconciling it is a design question, not a
rename.

### 3. Response models far from the design

`Cart` is specified to BE the checkout preview — `productTitle`, `sellerName`,
`effectivePrice`, `lineTotal`, `groups[]`, the four totals and the FX display
fields — and currently returns offer ids and quantities only. Search results
lack `brand`, `images[]`, `lowestOffer`, `score` and the `facets` block.
Checkout still takes `items[{offerId, quantity}]` rather than the designed
`cartItems[]` plus the `confirmedPrices[]` / `PRICE_CHANGED` handshake.

### 4. Deviations kept on purpose, pending an ADR

- Search's `category` filter is a **slug**, not the designed `categoryId` UUID.
  The products index carries only a `category_path` of slugs, so the designed
  filter would always match nothing. Serving it needs the indexer to emit
  category ids plus ancestors, an ES mapping change and a reindex.
- Checkout resolves a null `preferred_currency` to USD; the design resolves it
  from `Accept-Language`.

Both need an ADR or an implementation, not silence.

---

## Open — platform conventions

### 5. Events are JSON, not Avro

[kafka-events.md](../../conventions/kafka-events.md) specifies Avro with the
Confluent Schema Registry under BACKWARD compatibility. The outbox relay and
`ProductIndexerConsumer` both use `JSON.stringify` / `JSON.parse`. Coherent end
to end, but not the designed wire format, and the Schema Registry is running
unused.

### 6. No DLQ per consumer group

Required by `kafka-events.md` and by the backend `CLAUDE.md`.
`ProductIndexerConsumer` rethrows and relies on kafkajs retry alone, so a
poison message blocks its partition indefinitely.

### 7. Schedulers run in `api`, not `workers`, without advisory locks

[cleanup-jobs.md](cleanup-jobs.md) places the scheduled jobs in the `workers`
service, each under a `pg_advisory_lock`. `PlatformModule` and `SellerModule`
register them in `api` via `ScheduleModule.forRoot()`, so every API replica runs
every job concurrently. The outbox relay and `cleanup-orphaned-product-images`
are the only two that take a lock today — the latter is in `workers` and is the
pattern the rest should move to. `fx-rate.scheduler.ts` is in `workers` but has
a hardcoded cron and no lock.

### 8. Health checks are stubs

`api`'s `postgres`, `redis`, `mongodb`, `elasticsearch`, `kafka`,
`schemaRegistry` and `minio` probes all log a warning and report `up` without
checking anything, so the probe cannot fail for a real outage. Only the
`workers` probe does real checks. MongoDB has no driver in the workspace at all.
