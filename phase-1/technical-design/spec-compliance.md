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
| `DELETE /seller/products/:productId` set every seller's offers on the product to `REMOVED`, always removed the product row, answered `422` for a `PENDING` fulfillment and emitted the uncatalogued `platform.product.removed` | Code fixed to the spec (backend#31): only the caller's `ACTIVE` offers go `INACTIVE`; the product row goes `REMOVED` only when no other seller holds a non-`REMOVED` offer; `409`; one `listing.soft_deleted` per offer, plus `product.changed` on the removal branch |
| The search indexer deleted the whole product document on `listing.soft_deleted` and `moderation.listing.removed`, erasing every co-seller's listing from search, and its `processed_event` insert omitted the NOT NULL `outcome`, so every indexed event retried forever | Code fixed (backend#33): removal events rebuild the document from the remaining offers, update-only; only `product.changed` `REMOVED` deletes a document |
| No DLQ per consumer group | Code fixed (backend#33): reusable consumer host in `workers` with bounded retry and `<group>.dlq`; the indexer runs the twelve `search.*` groups of kafka-events.md §4 |
| `order.placed`, `notification.checkout.summary`, `order.events` and `seller.events` went to topics the broker does not create | Code fixed (backend#34): `fulfillment.placed`, `order.finalized`, `fulfillment.refund_suspended_seller` and `seller.suspension_expired`, with catalogue payloads |
| Schedulers ran in every `api` replica with no advisory lock | Code fixed (backend#37): all four jobs run in `workers`, each under `pg_advisory_lock`; `ScheduleModule` is gone from `api`; outbox retention follows cleanup-jobs.md |
| `api` health probes reported `up` without checking anything | Code fixed (backend#32): real probes with per-check and total timeouts, shared with `workers` |
| `UPDATE`/`DELETE ... RETURNING` results were destructured as one row, but TypeORM returns `[rows, rowCount]` — refund and cancel never released reservations, every price withdrawal answered 500, suspend and reinstate events carried null offer ids | Code fixed (backend#35, #37): `returningRows` / `returningRow` / `affectedCount` in `shared`; test mocks return the real shape |
| `GET`/`PATCH /seller/profile`, `POST /seller/kyc/resubmit` and `POST /profile/me/logo` were missing | Built to the spec (backend#36) |

---

## Open — API surface

<a id="missing-endpoints"></a>
### 1. Missing endpoints

From the design, not yet implemented: `GET /catalog/products`,
`GET /catalog/categories/:categoryId` and `GET /pricing/fx-rates`.

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

### 3. API amounts are emitted at storage scale

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

### 4. Validation failures answer `422`, not `400`

The global `ValidationPipe` uses `422`, where every endpoint's error table
specifies `400` for a validation failure. It is one setting, but it changes
every endpoint's contract, so it lands with a contract-test pass.

### 5. `POST /seller/kyc` does not follow its design

It takes a JSON body where the design specifies a multipart document upload,
and it publishes `seller.kyc.submitted` to `platform.seller.kyc.submitted` — a
topic `kafka-init.sh` does not create, so the event is never delivered — keyed
on the application id rather than the seller. `POST /seller/kyc/resubmit`
(backend#36) is built to the design and is the pattern to follow.

### 6. Smaller handler divergences

- `admin.service.ts` `reinstateSeller` selects `u.first_name` / `u.last_name`;
  `identity.user` has only `full_name`.
- `fulfillment.refunded` and `fulfillment.cancelled` are keyed on
  `fulfillment_id`; the catalogue keys them on `order_id`.
- Checkout reservations expire after two days; [orders.md](api-design/orders.md)
  specifies 15 minutes.
- `order.finalized` always carries `buyer_business_logo_url: null`; the stored
  logo key is not presigned on that path.
- `product.changed` carries a different payload per producer. `REMOVED`
  (backend#31) follows the §2.10 schema; `CREATED` omits `brand` and shapes
  `variants[]` and `images[]` differently, and `UPDATED` omits
  `category_path`, `created_at`, `variants[]` and `images[]`. `category_path`
  is a leaf slug everywhere, where §2.10 specifies ancestor-to-leaf names —
  tied to the search filter in entry 7.

### 7. Deviations kept on purpose, pending an ADR

- Search's `category` filter is a **slug**, not the designed `categoryId` UUID.
  The products index carries only a `category_path` of slugs, so the designed
  filter would always match nothing. Serving it needs the indexer to emit
  category ids plus ancestors, an ES mapping change and a reindex.
- Checkout resolves a null `preferred_currency` to USD; the design resolves it
  from `Accept-Language`.

Both need an ADR or an implementation, not silence.

### 8. The design writes a column that does not exist

The `PATCH /seller/profile` sequence writes `seller_profile.submitted_data`,
which neither the ERD nor migration 0007 has. backend#36 maps `submittedData`
onto the address columns the table does carry and rejects the phone and
contact keys, which have no column. This is a **spec** gap: an ADR either adds
the column or rewrites the request to the address fields.

---

## Open — platform conventions

### 9. Only one consumer exists

`apps/workers` runs the outbox relay, the schedulers and the search indexer.
The notification, audit and inventory consumers the design relies on are not
built, so:

- `pii.accessed` rows accumulate in the outbox with nothing writing
  `pii_access_logs`, and `inventory.changed`'s `adjustment_reason` reaches no
  `audit_logs` document.
- No email or in-app notification is ever sent, `inventory.low_stock` included.
- The stock movements the `inventory.*` consumer owns have no writer. Seller
  refund and cancel, and the suspended-seller auto-refund, therefore release
  reservations **inline**, which is the only reason a cancelled order's units
  become sellable again. When the consumer lands, those inline releases must go
  in the same change or the movement gains two writers and a redelivered event
  double-counts.

This is sprint scope rather than a defect, but it is the reason several
handlers do work the design assigns to a consumer.

### 10. Events are JSON, not Avro

[kafka-events.md](../../conventions/kafka-events.md) specifies Avro with the
Confluent Schema Registry under BACKWARD compatibility. The outbox relay and
the consumers use `JSON.stringify` / `JSON.parse`. Coherent end to end, but not
the designed wire format, and the Schema Registry is running unused. A registry
would have caught the mixed `product.changed` payloads in entry 6.

### 11. Seller handlers write other modules' schemas directly

The seller routes write `catalog`, `pricing`, `inventory` and `orders` rows
themselves rather than through each owner's application service, which the
[sole-writer rule](api-design/seller.md#db-mapping) requires. The soft-delete's
pending check still joins `orders` tables to `catalog.offer` in one statement.

### 12. Most retention jobs are not built

[cleanup-jobs.md](cleanup-jobs.md) lists more jobs than the five `workers` now
runs (outbox retention, suspension expiry, suspended-seller auto-refund, FX
refresh and the orphaned-image sweep). The remaining seven have no
implementation.
