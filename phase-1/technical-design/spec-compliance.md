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
| 30 Seller and Admin operations declared no response body, and the seller lists were offset-paginated | Code fixed across backend#26–#30: every 2xx on all 69 paths now declares a typed body (169 schemas, none empty). `GET /seller/offers` serves the listings *and* the inventory table; the undesigned `GET /seller/products` and `GET /seller/inventory` are gone; `PATCH /seller/offers/:offerId` and the CSV bulk-inventory upload are built; admin requests are validated. frontend#18 follows |

---

## Open — API surface

<a id="missing-endpoints"></a>
### 1. Missing endpoints

From the design, not yet implemented: `POST /profile/me/logo`,
`GET`/`PATCH /seller/profile`, `POST /seller/kyc/resubmit`,
`GET /catalog/products`, `GET /catalog/categories/:categoryId` and
`GET /pricing/fx-rates`.

The backend additionally serves `GET /catalog/categories/:categoryId/products`,
which is **not** in the design. Reconciling it is a design question, not a
rename.

### 2. Response models far from the design

`Cart` is specified to BE the checkout preview — `productTitle`, `sellerName`,
`effectivePrice`, `lineTotal`, `groups[]`, the four totals and the FX display
fields — and currently returns offer ids and quantities only. Search results
lack `brand`, `images[]`, `lowestOffer`, `score` and the `facets` block.
Checkout still takes `items[{offerId, quantity}]` rather than the designed
`cartItems[]` plus the `confirmedPrices[]` / `PRICE_CHANGED` handshake.

### 3. Soft-deleting a product withdraws every seller's listing

[`DELETE /seller/products/:productId`](api-design/seller.md#delete-product-soft)
branches on whether another seller still holds a non-`REMOVED` offer: with one,
only the caller's offers and prices are withdrawn and the product row stays
`ACTIVE`; without, the product row moves to `REMOVED` as well. The handler does
neither — it sets **every** offer on the product to `REMOVED` regardless of
owner and always removes the product row, so deleting a shared product
withdraws a co-seller's live listing. It also answers `422` where the design
specifies `409` for a `PENDING` fulfillment, and emits `platform.product.removed`
in place of one `listing.soft_deleted` per offer plus `product.changed`.

### 4. API amounts are emitted at storage scale

Every monetary field is returned as the driver hands it back — `"99.9900"`,
four fractional digits, whatever the currency. The design renders amounts at
the currency's `minor_unit_scale` and specifies a startup-loaded
`CurrencyScaleCache` in `pricing` as the single source of that scale
([backend-coding-standards.md §3.2](../../conventions/backend-coding-standards.md)).
No such cache exists, so nothing formats: a JPY price reads `"1000.0000"` where
the scale is zero. Amounts are strings end to end and no arithmetic is done in
JS `number`, so this is a presentation divergence rather than a money-handling
one — but it is one the whole API shares, and the fix belongs in one pass over
every money-returning endpoint.

### 5. Deviations kept on purpose, pending an ADR

- Search's `category` filter is a **slug**, not the designed `categoryId` UUID.
  The products index carries only a `category_path` of slugs, so the designed
  filter would always match nothing. Serving it needs the indexer to emit
  category ids plus ancestors, an ES mapping change and a reindex.
- Checkout resolves a null `preferred_currency` to USD; the design resolves it
  from `Accept-Language`.

Both need an ADR or an implementation, not silence.

---

## Open — platform conventions

### 6. Only one consumer exists

`apps/workers` runs the outbox relay, the FX scheduler, the image-cleanup job
and `ProductIndexerConsumer`. The notification, audit and inventory consumers
the design relies on are not built, so:

- `pii.accessed` rows accumulate in the outbox with nothing writing
  `pii_access_logs`, and `inventory.changed`'s `adjustment_reason` reaches no
  `audit_logs` document.
- No email or in-app notification is ever sent, `inventory.low_stock` included.
- The stock movements the `inventory.*` consumer owns have no writer. Seller
  refund and cancel therefore release the fulfillment's reservations **inline**,
  which is the only reason a cancelled order's units become sellable again.
  When the consumer lands, that inline release must go in the same change or
  the movement gains two writers and a redelivered event double-counts.

This is sprint scope rather than a defect, but it is the reason several
handlers do work the design assigns to a consumer.

### 7. Four events still go to topics the broker does not create

`kafka-init.sh` creates the catalogue's topics and broker auto-creation is off,
so an event published elsewhere cannot be delivered at all. `order.placed` and
`notification.checkout.summary` (checkout) and `order.events` and
`seller.events` (the seller scheduler) are not in the catalogue. The seller
handlers' `platform.fulfillment.*` and `platform.inventory.low-stock` were
fixed in backend#28 and #27.

### 8. Events are JSON, not Avro

[kafka-events.md](../../conventions/kafka-events.md) specifies Avro with the
Confluent Schema Registry under BACKWARD compatibility. The outbox relay and
`ProductIndexerConsumer` both use `JSON.stringify` / `JSON.parse`. Coherent end
to end, but not the designed wire format, and the Schema Registry is running
unused. The payload field names also vary by producer — `seller_profile_id`
against the catalogue's `seller_id`, for instance — which a registry would have
caught.

### 9. No DLQ per consumer group

Required by `kafka-events.md` and by the backend `CLAUDE.md`.
`ProductIndexerConsumer` rethrows and relies on kafkajs retry alone, so a
poison message blocks its partition indefinitely.

### 10. Schedulers run in `api`, not `workers`, without advisory locks

[cleanup-jobs.md](cleanup-jobs.md) places the scheduled jobs in the `workers`
service, each under a `pg_advisory_lock`. `PlatformModule` and `SellerModule`
register them in `api` via `ScheduleModule.forRoot()`, so every API replica runs
every job concurrently. The outbox relay and `cleanup-orphaned-product-images`
are the only two that take a lock today — the latter is in `workers` and is the
pattern the rest should move to. `fx-rate.scheduler.ts` is in `workers` but has
a hardcoded cron and no lock.

### 11. Health checks are stubs

`api`'s `postgres`, `redis`, `mongodb`, `elasticsearch`, `kafka`,
`schemaRegistry` and `minio` probes all log a warning and report `up` without
checking anything, so the probe cannot fail for a real outage. Only the
`workers` probe does real checks. MongoDB has no driver in the workspace at all.
