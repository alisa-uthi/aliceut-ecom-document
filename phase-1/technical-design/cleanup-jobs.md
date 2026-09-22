# Phase 1 — Scheduled Cleanup Jobs

**Status:** Complete  
**Source of truth:** [BRD v1.2](../requirements/BRD.md)

Phase 1 implementation of the data lifecycle convention. Every job runs in the `workers` NestJS process using `@nestjs/schedule`. There is **no in-database scheduler**: PostgreSQL is the stock `postgres:16-alpine` image with no `pg_cron` and no scheduling extension, and nothing in this document may require one.

**Convention:** [conventions/data-lifecycle.md](../../conventions/data-lifecycle.md)  
**Related:** [data-model-erd.md](./data-model-erd.md), [data-model-mongodb.md](./data-model-mongodb.md), [backend-module-architecture.md §scheduled tasks](./backend-module-architecture.md#scheduled-tasks), [conventions/auth-jwt-design.md](../../conventions/auth-jwt-design.md), [conventions/observability.md](../../conventions/observability.md)

---

## Summary

| Job name | Table | Default schedule | Schedule env var | Guard |
|---|---|---|---|---|
| [`cleanup-refresh-sessions`](#cleanup-refresh-sessions) | `identity.refresh_session` | `0 3 * * *` | `CLEANUP_REFRESH_SESSIONS_CRON` | `pg_advisory_lock` |
| [`cleanup-email-verification-tokens`](#cleanup-email-verification-tokens) | `identity.email_verification_token` | `5 3 * * *` | `CLEANUP_EMAIL_VERIFICATION_TOKENS_CRON` | `pg_advisory_lock` |
| [`cleanup-password-reset-tokens`](#cleanup-password-reset-tokens) | `identity.password_reset_token` | `10 3 * * *` | `CLEANUP_PASSWORD_RESET_TOKENS_CRON` | `pg_advisory_lock` |
| [`expire-stock-reservations`](#stock-reservation) | `inventory.stock_reservation` | `@Interval` 300000 ms | `RESERVATION_EXPIRY_INTERVAL_MS` | `pg_advisory_lock` |
| [`cleanup-old-stock-reservations`](#stock-reservation) | `inventory.stock_reservation` | `15 3 * * *` | `CLEANUP_STOCK_RESERVATIONS_CRON` | `pg_advisory_lock` |
| [`cleanup-idempotency-keys`](#cleanup-idempotency-keys) | `orders.idempotency_key` | `20 3 * * *` | `CLEANUP_IDEMPOTENCY_KEYS_CRON` | `pg_advisory_lock` |
| [`cleanup-outbox-events`](#cleanup-outbox-events) | `platform.outbox_event` | `25 3 * * *` | `CLEANUP_OUTBOX_EVENTS_CRON` | `pg_advisory_lock` |
| [`cleanup-processed-events`](#cleanup-processed-events) | `platform.processed_event` | `30 3 * * *` | `CLEANUP_PROCESSED_EVENTS_CRON` | `pg_advisory_lock` |
| [`cleanup-read-notifications`](#cleanup-read-notifications) | `notifications.in_app_notification` | `35 3 * * *` | `CLEANUP_IN_APP_NOTIFICATIONS_CRON` | `pg_advisory_lock` |
| [`lift-expired-suspensions`](#lift-expired-suspensions) | `seller.seller_profile` | `0 * * * *` | `SUSPENSION_EXPIRY_CRON` | `pg_advisory_lock` |

- [Job conventions](#job-conventions)
- [Stores with no job here](#no-job)

---

<a id="job-conventions"></a>
## Job conventions

These rules hold for every job below; each section states only what differs.

**Where the code lives.** Schedulers are plain `@Injectable()` providers in `apps/workers/src/schedulers/`, registered in `WorkersModule` ([backend-module-architecture.md §scheduled tasks](./backend-module-architecture.md#scheduled-tasks)). The eight retention deletes are methods on `cleanup.scheduler.ts`; the reservation sweep and the suspension lift have their own schedulers because they change domain state and publish events. Each scheduler injects the exported application service of the module that owns the table and never reaches another module's schema directly.

**No schedule, TTL or batch size is a literal.** Every value comes from the environment, with the documented default as the fallback:

```typescript
@Cron(process.env.CLEANUP_REFRESH_SESSIONS_CRON ?? '0 3 * * *', {
  name: 'cleanup-refresh-sessions',
  timeZone: 'UTC',
})
async cleanupRefreshSessions(): Promise<void> { /* … */ }
```

All cron expressions are UTC. Changing a schedule is an `.env` edit plus a `workers` restart — acceptable in the V1 docker-compose deployment, and the same operational model the logging convention uses for `LOG_SENSITIVE_KEYS`.

**Concurrency guard — `pg_advisory_lock` per job.** No job depends on the `workers` service running at replica count 1. Each run first takes a session-level advisory lock keyed on the job name, and releases it in a `finally` block:

```sql
SELECT pg_try_advisory_lock(hashtext(:jobName)) AS acquired;
-- … work …
SELECT pg_advisory_unlock(hashtext(:jobName));
```

The lock is session-level rather than transaction-level so that it spans a multi-batch run. A run that does not acquire the lock logs at `warn` with `skipped: 'lock_held'` and returns immediately — it does not wait, because the next tick is cheaper than a queued worker holding a connection.

**Deletes are batched.** Every retention delete removes at most `CLEANUP_BATCH_SIZE` rows (default 1000) per statement and loops until a statement affects fewer rows than the batch size:

```sql
DELETE FROM <table>
WHERE id IN (
  SELECT id FROM <table>
  WHERE <retention predicate>
  LIMIT :batchSize
);
```

Batching keeps each statement's lock footprint and WAL volume bounded, so a first run against a table that accumulated rows for months cannot block application traffic. Because every predicate is evaluated against the current clock and no cursor is persisted, an interrupted run simply resumes on the next tick.

**Observability.** Each run generates a UUIDv7 correlation id at start and places it in `AsyncLocalStorage`, so every log line and every outbox row the run writes carries it ([conventions/observability.md §4](../../conventions/observability.md#correlation-id)). Structured JSON only:

| Outcome | Level | Fields |
|---|---|---|
| Completed | `info` | `job`, `correlationId`, `deleted` (or `released`), `batches`, `durationMs` |
| Lock held by another replica | `warn` | `job`, `correlationId`, `skipped: 'lock_held'` |
| Failed | `error` | `job`, `correlationId`, `deleted` (rows committed before the failure), `batches`, `durationMs`, the exception message and stack |

A failure aborts the run and leaves the remaining rows for the next tick; no job retries in-run, and no job swallows an exception. Batches already committed stay committed — every predicate is idempotent, so re-running is safe.

**Outbox rows.** The two jobs that publish events insert `platform.outbox_event` in the same transaction as the state change they record, and populate all eleven required columns — `aggregate_type`, `aggregate_id`, `topic`, `key`, `event_type`, `event_version`, `payload`, `correlation_id`, `occurred_at`, `created_at`, `updated_at`. `key` is the aggregate id rendered as text, so per-aggregate ordering holds. `correlation_id` is the run's UUIDv7, generated by the worker: `gen_random_uuid()` is a UUIDv4 and is not used anywhere in this model.

The **outbox relay itself is not a scheduled job.** It polls continuously (`OUTBOX_POLL_INTERVAL_MS`), and its lag alert — relay lag > 30 s — is owned by [docker-compose-topology.md](./docker-compose-topology.md), together with the non-empty-DLQ alert. The job below only deletes rows the relay has already published.

**No job mints a human-facing identifier.** `ORD-`, `FUL-` and `TRK-` values come from the per-type PostgreSQL sequences declared in the `orders` migration and are assigned by column default inside the inserting transaction ([data-model-erd.md](./data-model-erd.md)). There is no id-generation or id-backfill job. Gaps in those sequences are expected — a rolled-back transaction consumes its value and does not return it — and no job renumbers or compacts them; a display id is a stable reference a buyer has already been shown by email.

---

## Jobs

<a id="cleanup-refresh-sessions"></a>
### `identity.refresh_session`

Session rows are soft-revoked and retained: rotation and logout set `revoked_at` and `replaced_by_id` rather than deleting ([conventions/auth-jwt-design.md](../../conventions/auth-jwt-design.md)). A retained revoked row is the evidence for reuse detection — presenting a refresh token whose session has `revoked_at IS NOT NULL` is how token theft is detected. Delete that row too early and the stolen token stops looking stolen: the lookup finds nothing, the response is an ordinary `401`, and the family is never revoked. This job is therefore the one place where deleting too eagerly is a security regression, and its two predicates are deliberately separate.

| Property | Value |
|---|---|
| Scheduler | `cleanup.scheduler.ts` → `cleanupRefreshSessions()` |
| Default schedule | `0 3 * * *` (03:00 UTC) |
| Schedule env var | `CLEANUP_REFRESH_SESSIONS_CRON` |
| Retention env vars | `JWT_REFRESH_TTL_SECONDS` (existing, default 604800), `REFRESH_SESSION_CLEANUP_BUFFER_DAYS` (default 7) |
| Guard | `pg_advisory_lock` on `cleanup-refresh-sessions` |

```sql
DELETE FROM identity.refresh_session
WHERE id IN (
  SELECT id FROM identity.refresh_session
  WHERE (revoked_at IS NOT NULL
         AND revoked_at < now() - :refreshTtl - :buffer)
     OR (revoked_at IS NULL
         AND expires_at < now() - :buffer)
  LIMIT :batchSize
);
```

**Revoked rows** (`revoked_at IS NOT NULL`) are collectable once `revoked_at` is older than the refresh TTL plus the buffer. The bound is `revoked_at`, not `expires_at`: a token can only be *presented* usefully until the refresh TTL after its session was issued, and rotation revokes a session at most that late, so `revoked_at + refresh TTL` is the last instant at which a theft attempt could still arrive. The buffer keeps the row available for investigation after that.

**Never-revoked rows** (`revoked_at IS NULL`) are sessions that simply lapsed — the user neither logged out nor refreshed. They are collectable once `expires_at` is older than the buffer. There is no reuse signal to preserve: an expired token is rejected on `expires_at` whether or not the row survives.

Deleting an old revoked ancestor cannot weaken family revocation, which is `UPDATE … WHERE user_id = :userId AND revoked_at IS NULL` rather than a walk of the `replaced_by_id` chain. The chain is for investigation, and the retention window above is what bounds investigation.

---

<a id="cleanup-email-verification-tokens"></a>
### `identity.email_verification_token`

24-hour TTL single-use tokens, one active row per user. Rows accumulate whenever a user never clicks the link. The row is kept until `expires_at` passes so that a late click produces "this link has expired" from the token row rather than "invalid link" from its absence.

| Property | Value |
|---|---|
| Scheduler | `cleanup.scheduler.ts` → `cleanupEmailVerificationTokens()` |
| Default schedule | `5 3 * * *` (03:05 UTC) |
| Schedule env var | `CLEANUP_EMAIL_VERIFICATION_TOKENS_CRON` |
| Retention | driven by the row's own `expires_at`; the 24 h TTL is set by the issuing path, not by this job |
| Guard | `pg_advisory_lock` on `cleanup-email-verification-tokens` |

```sql
DELETE FROM identity.email_verification_token
WHERE id IN (
  SELECT id FROM identity.email_verification_token
  WHERE expires_at < now()
  LIMIT :batchSize
);
```

---

<a id="cleanup-password-reset-tokens"></a>
### `identity.password_reset_token`

60-minute TTL single-use tokens. Both expired-unused and already-used rows are collectable: a used row is rejected on `used_at` while it lives, and its expiry is at most an hour away regardless.

| Property | Value |
|---|---|
| Scheduler | `cleanup.scheduler.ts` → `cleanupPasswordResetTokens()` |
| Default schedule | `10 3 * * *` (03:10 UTC) |
| Schedule env var | `CLEANUP_PASSWORD_RESET_TOKENS_CRON` |
| Retention | driven by the row's own `expires_at`; the 60 min TTL is set by the issuing path |
| Guard | `pg_advisory_lock` on `cleanup-password-reset-tokens` |

```sql
DELETE FROM identity.password_reset_token
WHERE id IN (
  SELECT id FROM identity.password_reset_token
  WHERE expires_at < now()
  LIMIT :batchSize
);
```

---

<a id="stock-reservation"></a>
### `inventory.stock_reservation`

Two jobs act on this table: a sweep that reclaims abandoned checkouts, and a retention delete for terminal rows.

#### `expire-stock-reservations` — abandoned-checkout sweep

An `ACTIVE` reservation whose `expires_at` has passed **and which never acquired a `fulfillment_id`** belongs to a checkout the buyer abandoned. The sweep releases its held stock, marks it `EXPIRED`, and emits `inventory.reservation_expired` — all in one transaction per reservation.

**The `fulfillment_id IS NULL` predicate is the boundary, not an optimisation.** A reservation carrying a `fulfillment_id` belongs to a placed order, and its transitions out of `ACTIVE` are written by the Inventory module's Kafka consumer groups alone — `CONSUMED` by `inventory.fulfillment-shipped` when the fulfillment ships, `RELEASED` on seller cancel or on refund of a `PENDING` fulfillment, the suspension-refund path included, since prior status decides there too and a `SHIPPED` fulfillment restores nothing. If this sweep also released those rows, a reservation whose fulfillment was cancelled would have its quantity subtracted from `reserved_qty` twice: once by the consumer handling `fulfillment.cancelled`, once here. Restoring stock for an order state change is never this job's work.

Delivery is absent from that list deliberately: `fulfillment.delivered` moves no stock and touches no reservation. The reservation was already `CONSUMED` and `on_hand_qty` already decremented at shipment, so delivery is a status transition on the fulfillment alone. A future consumer group on that topic must not adjust `inventory.stock` or a reservation row — there is nothing left to adjust, and doing so would double-count the shipment.

| Property | Value |
|---|---|
| Scheduler | `reservation-expiry.scheduler.ts` (module `inventory`) |
| Default schedule | `@Interval` 300000 ms (5 min) |
| Schedule env var | `RESERVATION_EXPIRY_INTERVAL_MS` |
| TTL env var | `INVENTORY_RESERVATION_TTL_MINUTES` (existing, default 15) — sets `expires_at` at reservation time; this job only reads the column |
| Batch env var | `CLEANUP_BATCH_SIZE` — rows claimed per pass |
| Guard | `pg_advisory_lock` on `expire-stock-reservations` |

Claim the due rows:

```sql
SELECT id, offer_id, order_id, quantity
FROM inventory.stock_reservation
WHERE status = 'ACTIVE'
  AND expires_at < now()
  AND fulfillment_id IS NULL
LIMIT :batchSize;
```

Then resolve the product id of every claimed offer in one call — `CatalogApplicationService.getProductIdsForOffers(offerIds)`. It is not a join: `catalog.offer` is Catalog's table, and the event needs `product_id` because the search consumer's write is addressed by document id and that consumer may read nothing.

Then, per row, in one transaction — release the stock under the optimistic lock, mark the reservation, write the outbox row:

```sql
UPDATE inventory.stock
SET reserved_qty = reserved_qty - :quantity,
    version      = version + 1,
    updated_at   = now()
WHERE offer_id = :offerId
  AND version  = :version
RETURNING on_hand_qty - reserved_qty AS available_qty;

UPDATE inventory.stock_reservation
SET status = 'EXPIRED', updated_at = now()
WHERE id = :reservationId
  AND status = 'ACTIVE';

INSERT INTO platform.outbox_event (
  aggregate_type, aggregate_id, topic, key,
  event_type, event_version, payload, correlation_id,
  occurred_at, created_at, updated_at
) VALUES (
  'inventory.stock', :offerId, 'inventory.reservation_expired', :offerId::text,
  'inventory.reservation_expired', 1,
  jsonb_build_object(
    'reservation_id', :reservationId,
    'offer_id',       :offerId,
    'product_id',     :productId,
    'order_id',       :orderId,
    'available_qty',  :availableQty,
    'released_at',    :releasedAt
  ),
  :correlationId, now(), now(), now()
);
```

The stock `UPDATE` carries the `version` read with the row and is the required optimistic lock: a checkout that reserved against the same offer between the `SELECT` and the `UPDATE` bumps `version`, the statement affects zero rows, and the row is skipped and retried on the next pass rather than decrementing `reserved_qty` from a stale figure. The reservation `UPDATE` re-checks `status = 'ACTIVE'` for the same reason — a checkout that completed in that window has already set `fulfillment_id`, and its reservation must not be expired underneath it. The payload carries every field `InventoryReservationExpiredPayload` declares ([kafka-events.md § 2.19](kafka-events.md#219-inventoryreservation_expired)); `order_id` is why `stock_reservation.order_id` stays `NOT NULL`. Three details of it are load-bearing:

- **`available_qty`, the absolute figure, not the quantity released.** It comes from the `RETURNING` clause of the release itself, so it is the post-release value read inside the same transaction. The search consumer sets `offers[].available_qty` to it. A delta would not be idempotent: the topic is at-least-once, and a redelivered release applied as an increment raises availability a second time.
- **`product_id`.** The Elasticsearch index holds product documents, so the consumer's write is a `POST /products/_update/:productId`, and the consumer may not read `catalog.offer` to find the id. The scheduler resolves it through `CatalogApplicationService`, once per batch, rather than joining `catalog.offer` into the claim query above.
- **The partition key is `offer_id`.** The topic keys on the offer, and the outbox contract makes `key` = `aggregate_id`, so the aggregate is the stock row and not the reservation. Keyed on `reservationId` every expiry for one offer would land on a different partition, and two expiries racing on one offer could be applied to the index out of order — the later absolute figure overwritten by the earlier one.

#### `cleanup-old-stock-reservations` — terminal-row retention

`EXPIRED`, `CONSUMED` and `RELEASED` rows are kept for a window after their last transition so that a stock discrepancy can be reconstructed, then deleted. All three values occur: `EXPIRED` from the sweep above, `CONSUMED` and `RELEASED` from the inventory consumer.

| Property | Value |
|---|---|
| Scheduler | `cleanup.scheduler.ts` → `cleanupOldStockReservations()` |
| Default schedule | `15 3 * * *` (03:15 UTC) |
| Schedule env var | `CLEANUP_STOCK_RESERVATIONS_CRON` |
| Retention env var | `STOCK_RESERVATION_RETENTION_DAYS` (default 30) |
| Guard | `pg_advisory_lock` on `cleanup-old-stock-reservations` |

```sql
DELETE FROM inventory.stock_reservation
WHERE id IN (
  SELECT id FROM inventory.stock_reservation
  WHERE status IN ('EXPIRED', 'CONSUMED', 'RELEASED')
    AND updated_at < now() - :retention
  LIMIT :batchSize
);
```

---

<a id="cleanup-idempotency-keys"></a>
### `orders.idempotency_key`

Checkout idempotency keys carry `expires_at`. The window is **`IDEMPOTENCY_KEY_TTL_HOURS` (default 24)**, applied by the checkout path when it inserts the row; this job only honours the column. The window has to outlast every client retry of one checkout — a key deleted while a retry is still in flight turns a replay into a second order — and there is no reason to keep it beyond that, since a key reused a day later would be a different checkout anyway.

| Property | Value |
|---|---|
| Scheduler | `cleanup.scheduler.ts` → `cleanupIdempotencyKeys()` |
| Default schedule | `20 3 * * *` (03:20 UTC) |
| Schedule env var | `CLEANUP_IDEMPOTENCY_KEYS_CRON` |
| Retention env var | `IDEMPOTENCY_KEY_TTL_HOURS` (default 24) — set on insert, read here |
| Guard | `pg_advisory_lock` on `cleanup-idempotency-keys` |

```sql
DELETE FROM orders.idempotency_key
WHERE id IN (
  SELECT id FROM orders.idempotency_key
  WHERE expires_at < now()
  LIMIT :batchSize
);
```

---

<a id="cleanup-outbox-events"></a>
### `platform.outbox_event`

Published rows are kept only for relay debugging. Rows in a non-published state are kept far longer: a `FAILED` row is a message that never reached Kafka, so deleting it on the same schedule as a successful one destroys the only local record that the event existed.

| Property | Value |
|---|---|
| Scheduler | `cleanup.scheduler.ts` → `cleanupOutboxEvents()` |
| Default schedule | `25 3 * * *` (03:25 UTC) |
| Schedule env var | `CLEANUP_OUTBOX_EVENTS_CRON` |
| Retention env vars | `OUTBOX_PUBLISHED_RETENTION_DAYS` (default 7), `OUTBOX_FAILED_RETENTION_DAYS` (default 30) |
| Guard | `pg_advisory_lock` on `cleanup-outbox-events` |

```sql
DELETE FROM platform.outbox_event
WHERE id IN (
  SELECT id FROM platform.outbox_event
  WHERE (publication_status = 'PUBLISHED'
         AND published_at < now() - :publishedRetention)
     OR (publication_status = 'FAILED'
         AND updated_at < now() - :failedRetention)
  LIMIT :batchSize
);
```

`PENDING` rows are never deleted by this job at any age. A `PENDING` row older than the relay's poll interval is a stuck relay, which the lag alert in [docker-compose-topology.md](./docker-compose-topology.md) reports; deleting it would silence the alert by discarding the event. `FAILED` rows are retained for a month so that a DLQ investigation can still find the producer-side row, and the run logs the `FAILED` count it deleted so that a growing figure is visible in Loki.

---

<a id="cleanup-processed-events"></a>
### `platform.processed_event`

The consumer idempotency dedupe window. A dedupe row exists to make a *redelivery* idempotent, and redelivery has two sources of very different reach: a rebalance or an uncommitted offset, which replays within minutes, and a deliberate offset reset or DLQ replay, which can replay anything still in the Kafka log. The second is what sizes this window, so what governs it is an ordering rule rather than a number — **dedupe retention must be strictly greater than Kafka log retention.** Equal values race: a replay of a message at the very edge of the log can find its dedupe row already deleted and apply the side effect a second time. The `kafka` service pins `KAFKA_LOG_RETENTION_HOURS=168` (7 days), so this window is 14 days. Changing either figure means checking the other; the rule and both numbers are stated in [kafka-events.md](./kafka-events.md), which owns per-topic retention.

| Property | Value |
|---|---|
| Scheduler | `cleanup.scheduler.ts` → `cleanupProcessedEvents()` |
| Default schedule | `30 3 * * *` (03:30 UTC) |
| Schedule env var | `CLEANUP_PROCESSED_EVENTS_CRON` |
| Retention env var | `PROCESSED_EVENT_RETENTION_DAYS` (default 14) — must be **strictly greater** than Kafka log retention (`KAFKA_LOG_RETENTION_HOURS`, 168 h) |
| Guard | `pg_advisory_lock` on `cleanup-processed-events` |

```sql
DELETE FROM platform.processed_event
WHERE (consumer_group, event_id) IN (
  SELECT consumer_group, event_id FROM platform.processed_event
  WHERE processed_at < now() - :retention
  LIMIT :batchSize
);
```

The subquery selects the composite primary key because this table has no surrogate `id`.

---

<a id="cleanup-read-notifications"></a>
### `notifications.in_app_notification`

The in-app notification read model. Rows the recipient has read are collectable after a retention window; **unread rows are never deleted at any age** — an unread notification is still the user's only in-app record of a KYC decision or a suspension, and expiring it would silently remove information the user has not yet seen.

| Property | Value |
|---|---|
| Scheduler | `cleanup.scheduler.ts` → `cleanupReadNotifications()` |
| Default schedule | `35 3 * * *` (03:35 UTC) |
| Schedule env var | `CLEANUP_IN_APP_NOTIFICATIONS_CRON` |
| Retention env var | `IN_APP_NOTIFICATION_READ_RETENTION_DAYS` (default 90) |
| Guard | `pg_advisory_lock` on `cleanup-read-notifications` |

```sql
DELETE FROM notifications.in_app_notification
WHERE id IN (
  SELECT id FROM notifications.in_app_notification
  WHERE read_at IS NOT NULL
    AND read_at < now() - :retention
  LIMIT :batchSize
);
```

Deleting a read row also releases its `(recipient_user_id, source_event_id)` unique pair. That is safe: the dedupe it provides only matters while the event can still be redelivered, and `PROCESSED_EVENT_RETENTION_DAYS` is far shorter than this window.

---

<a id="lift-expired-suspensions"></a>
### `seller.seller_profile` — timed suspension expiry

`suspended_until` is a non-null timestamp when a suspension is temporary (`NULL` means permanent). This job lifts suspensions whose timestamp has passed and publishes `seller.suspension_expired` through the outbox. Profile update and outbox insert are one transaction per profile.

| Property | Value |
|---|---|
| Scheduler | `suspension-expiry.scheduler.ts` (module `seller`) |
| Default schedule | `0 * * * *` (hourly, UTC) |
| Schedule env var | `SUSPENSION_EXPIRY_CRON` |
| Batch env var | `CLEANUP_BATCH_SIZE` — profiles claimed per run |
| Guard | `pg_advisory_lock` on `lift-expired-suspensions` |

Claim the due profiles from the job's own schema:

```sql
SELECT p.id, p.user_id, p.business_name, p.suspended_until
FROM seller.seller_profile p
WHERE p.suspension_status = 'SUSPENDED'
  AND p.suspended_until IS NOT NULL
  AND p.suspended_until < now()
LIMIT :batchSize;
```

**No join to `identity.user`.** The recipient identity the payload carries comes from `IdentityApplicationService.getUsersByIds(userIds): UserView[]`, called once per batch with the claimed `user_id` set, not from SQL across a schema this module does not own ([backend-module-architecture § Ownership boundaries](./backend-module-architecture.md#ownership-boundaries), D-03). The view supplies `id`, `email` and `full_name` — the three the payload needs, `id` included, because `seller.suspension_expired.seller_user_id` is the `identity.user` id the in-app notification is addressed by and the profile row does not hold it under that name. The call is outside the per-profile transaction: it is a read, it does not have to be atomic with the update, and a batch of one round trip is cheaper than a join that the Phase 2 extraction would have to unpick.

Then, per profile, in one transaction:

```sql
UPDATE seller.seller_profile
SET suspension_status = 'ACTIVE',
    suspended_until   = NULL,
    suspension_reason = NULL,
    updated_at        = now()
WHERE id = :sellerProfileId
  AND suspension_status = 'SUSPENDED';
```

Then, in the same transaction, reactivate the offers the suspension deactivated — through Catalog, which owns the table:

```
offerIds = CatalogApplicationService.reactivateSuspendedOffers(sellerProfileId, tx)
```

```sql
INSERT INTO platform.outbox_event (
  aggregate_type, aggregate_id, topic, key,
  event_type, event_version, payload, correlation_id,
  occurred_at, created_at, updated_at
) VALUES (
  'seller_profile', :sellerProfileId, 'seller.suspension_expired', :sellerProfileId::text,
  'seller.suspension_expired', 1,
  jsonb_build_object(
    'seller_id',       :sellerProfileId,
    'seller_user_id',  :userId,
    'seller_email',    :email,
    'seller_name',     :fullName,
    'business_name',   :businessName,
    'suspended_until', :suspendedUntil,
    'expired_at',      :expiredAt,
    'offer_ids',       :offerIds
  ),
  :correlationId, now(), now(), now()
);
```

`suspension_reason` is cleared with `suspended_until`. Leaving it set on an `ACTIVE` profile makes every reader of the row — admin seller view, seller portal banner — see a suspension reason on an unsuspended seller; the historical reason survives in MongoDB `audit_logs` against the `SELLER_SUSPENDED` action, which is where suspension history is queried from anyway.

The payload carries the recipient identity ET-11 renders (`seller_name`, `business_name`) and the `seller_user_id` the in-app row is addressed by, rather than only the profile id, so the notification consumer does not have to read `identity.user` from another module's schema. Every field the schema declares ([kafka-events § 2.18](./kafka-events.md#218-sellersuspension_expired)) is populated here: the payload and the producer are one list, and a required field this job omits does not degrade at the consumer, it fails Avro serialization in the relay.

**Offers are reactivated in this transaction, through Catalog.** Offers the suspension deactivated carry `catalog.offer.status = 'INACTIVE'` with `status_changed_reason = 'SUSPENSION'`, and `catalog` is the only writer of that table, so the job calls `CatalogApplicationService.reactivateSuspendedOffers(sellerProfileId, tx): string[]` rather than issuing the `UPDATE` itself. The service sets exactly those rows back to `ACTIVE` with `status_changed_reason = NULL`, leaves `REMOVED` and `FLAGGED` offers untouched — an expiry lifts a suspension, not a content decision — and returns the ids it changed, which become the payload's `offer_ids`. The method takes the caller's transaction handle, so the profile update and the offer reactivation commit together or not at all.

**Why not defer reactivation to a consumer.** Leaving it to `seller.suspension_expired`'s subscribers would have required a new Catalog consumer group on the topic, and would have left `offer_ids` unsuppliable: the payload field the search consumer matches on is "the offers the expiry reactivated", and a producer that reactivates nothing has no set to name. It would also have split one state transition across a synchronous profile write and an asynchronous offer write, so a seller whose suspension expired would be `ACTIVE` with `INACTIVE` offers for as long as the consumer lagged. This is the shape manual reinstatement already uses ([api-design/admin.md](./api-design/admin.md#reinstate-seller)): reactivate in the transaction, publish the ids, let search re-enable the indexed entries from the payload.

---

<a id="no-job"></a>
## Stores with no job here

Every time-bounded store in the model appears in the summary table above or in this one. A store listed here must not also get a cleanup job — a second mechanism for the same retention rule is two rules that will drift.

| Store | Why no job here |
|---|---|
| MongoDB `audit_logs`, `activity_events`, `pii_access_logs` | Expired by their own MongoDB TTL indexes ([data-model-mongodb.md](./data-model-mongodb.md)). The TTL index is the single retention mechanism for MongoDB; a job doing the same deletes would race the TTL monitor. |
| `pricing.fx_rate` | Nothing to prune. The table is one row per currency pair, primary key `(base_currency_code, quote_currency_code)`, refreshed by upsert in place — a fixed-size table whose row count is the number of supported pairs. Staleness is a **read-time** concern: when `now() - as_of` exceeds `FX_STALE_AFTER_HOURS` (default 24) the API returns the rate marked stale and the UI shows an indicative-rate note. The field is `as_of`; there is no `fetched_at` and no rate history. The hourly upsert that refreshes the rows is `fx-rate.scheduler.ts` (`FX_RATE_REFRESH_CRON`, default `0 * * * *`) — a refresh, not a retention delete, which is why it is not in the summary table above. |
| `admin.keyword_blocklist` | Deactivation is `is_active = false`, never a delete — the audit history of which term was active when a listing was flagged has to survive. The in-process cache of active terms is refreshed on an in-process TTL (`KEYWORD_BLOCKLIST_CACHE_TTL`, default 60 s), which is a cache expiry, not a scheduled job. Mutations to the table publish `keyword_blocklist.changed` for the audit trail ([data-model-mongodb.md](./data-model-mongodb.md)), and **no consumer of that topic rescans the catalogue**: a newly added term applies at the next listing-time scan and never retroactively flags a live listing. There is no rescan job in V1 and none is to be added on the strength of that topic. |
| `notifications.pending_listing_removal_digest` | Drained and deleted by the ET-09 digest scheduler (`NOTIFICATION_DIGEST_CRON`, default `0 23 * * *`), which aggregates rows per `seller_profile_id`, sends one digest per selling profile, and deletes exactly the rows it sent — under the same `pg_advisory_lock` guard as every job above, so two `workers` replicas cannot send one seller two digests ([backend-module-architecture.md §scheduled tasks](./backend-module-architecture.md#scheduled-tasks), [data-model-erd.md](./data-model-erd.md)). A retention delete on top of it would race the send. |
| `orders.order`, `orders.fulfillment`, `orders.fulfillment_item`, `orders.payment_attempt` | Immutable financial records. Never deleted, at any age. |
| `notifications.email_template`, `pricing.currency`, `catalog.category` | Reference data, not time-bounded. |
| `identity.user`, `identity.address`, `identity.oauth_identity`, `cart.cart`, `cart.cart_item`, `catalog.*`, `pricing.offer_price`, `inventory.stock`, `seller.*`, `admin.moderation_case` | Lifecycle is driven by the user or by an admin decision, not by a clock. Removal is status-driven or soft-deleted where history must remain visible. |
