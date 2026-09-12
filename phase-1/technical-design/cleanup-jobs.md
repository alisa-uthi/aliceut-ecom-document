# Phase 1 — pg_cron Cleanup Jobs

Phase 1 implementation of the data lifecycle convention. All jobs run inside PostgreSQL via `pg_cron`.

**Convention:** [conventions/data-lifecycle.md](../../conventions/data-lifecycle.md)
**Related:** [data-model-erd.md](./data-model-erd.md), [conventions/auth-jwt-design.md](../../conventions/auth-jwt-design.md)

---

## Summary

| Job name | Table | Schedule | Type |
|---|---|---|---|
| [`cleanup-refresh-sessions`](#cleanup-refresh-sessions) | `identity.refresh_session` | Daily 03:00 | Simple DELETE |
| [`cleanup-email-verification-tokens`](#cleanup-email-verification-tokens) | `identity.email_verification_token` | Daily 03:05 | Simple DELETE |
| [`cleanup-password-reset-tokens`](#cleanup-password-reset-tokens) | `identity.password_reset_token` | Daily 03:10 | Simple DELETE |
| [`expire-stock-reservations`](#stock-reservation) | `inventory.stock_reservation` | Every 5 min | Function (atomic stock return) |
| [`cleanup-old-stock-reservations`](#stock-reservation) | `inventory.stock_reservation` | Daily 03:15 | Simple DELETE (terminal states > 30 days) |
| [`cleanup-idempotency-keys`](#cleanup-idempotency-keys) | `orders.idempotency_key` | Daily 03:20 | Simple DELETE |
| [`cleanup-outbox-events`](#cleanup-outbox-events) | `platform.outbox_event` | Daily 03:25 | Simple DELETE (published > 7 days) |
| [`cleanup-processed-events`](#cleanup-processed-events) | `platform.processed_event` | Daily 03:30 | Simple DELETE (> 7 days) |
| [`cleanup-fx-rates`](#cleanup-fx-rates) | `pricing.fx_rate` | Weekly Sun 04:00 | Simple DELETE (> 90 days) |
| [`lift-expired-suspensions`](#lift-expired-suspensions) | `seller.seller_profile` | Hourly | Function (update + outbox insert) |

---

## Jobs

<a id="cleanup-refresh-sessions"></a>
### `identity.refresh_session`

Revoked rows must remain until `expires_at` to support reuse detection (see [auth-jwt-design §2](../../conventions/auth-jwt-design.md#2-refresh-token-rotation-flow)). After expiry they serve no purpose.

```sql
-- daily at 03:00 UTC
SELECT cron.schedule(
  'cleanup-refresh-sessions',
  '0 3 * * *',
  $$DELETE FROM identity.refresh_session WHERE expires_at < NOW()$$
);
```

---

<a id="cleanup-email-verification-tokens"></a>
### `identity.email_verification_token`

24-hour TTL single-use tokens. Unverified tokens accumulate if user never clicks the link.

```sql
-- daily at 03:05 UTC
SELECT cron.schedule(
  'cleanup-email-verification-tokens',
  '5 3 * * *',
  $$DELETE FROM identity.email_verification_token WHERE expires_at < NOW()$$
);
```

---

<a id="cleanup-password-reset-tokens"></a>
### `identity.password_reset_token`

60-minute TTL single-use tokens. Both expired-unused and used tokens can be cleaned.

```sql
-- daily at 03:10 UTC
SELECT cron.schedule(
  'cleanup-password-reset-tokens',
  '10 3 * * *',
  $$DELETE FROM identity.password_reset_token WHERE expires_at < NOW()$$
);
```

---

<a id="stock-reservation"></a>
### `inventory.stock_reservation`

Active reservations expire after 15 minutes if checkout is not completed. Stock must be returned when a reservation expires, **and a `inventory.reservation_expired` Kafka event must be emitted for each expired hold** so downstream consumers (search index, notifications) react. Stock release, status update, and outbox insert must all be atomic — implemented as a PostgreSQL function using the same per-row LOOP pattern as `lift_expired_suspensions`.

The former `reservation-expiry.scheduler.ts` worker (which emitted the event but did not release stock) is **removed** — this function now owns the full lifecycle. See [module-architecture.md §scheduled-tasks](./module-architecture.md#scheduled-tasks).

```sql
CREATE OR REPLACE FUNCTION inventory.expire_reservations() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT id, offer_id, quantity
    FROM inventory.stock_reservation
    WHERE status = 'ACTIVE' AND expires_at < NOW()
  LOOP
    -- Release reserved stock
    UPDATE inventory.stock
    SET reserved_qty = reserved_qty - r.quantity,
        updated_at = NOW()
    WHERE offer_id = r.offer_id;

    -- Mark reservation expired
    UPDATE inventory.stock_reservation
    SET status = 'EXPIRED', updated_at = NOW()
    WHERE id = r.id;

    -- Emit outbox event (same tx) — relay ships to Kafka as inventory.reservation_expired
    INSERT INTO platform.outbox_event (
      aggregate_type, aggregate_id, topic, event_type, event_version,
      payload, correlation_id, occurred_at, publication_status, attempt_count
    ) VALUES (
      'stock_reservation', r.id,
      'inventory.reservation_expired', 'inventory.reservation_expired', 1,
      jsonb_build_object(
        'reservation_id', r.id,
        'offer_id', r.offer_id,
        'released_qty', r.quantity
      ),
      gen_random_uuid(), NOW(), 'PENDING', 0
    );
  END LOOP;
END;
$$;

-- every 5 minutes
SELECT cron.schedule(
  'expire-stock-reservations',
  '*/5 * * * *',
  $$SELECT inventory.expire_reservations()$$
);
```

Old terminal-state rows (EXPIRED / CONSUMED / RELEASED) deleted after 30 days:

```sql
-- daily at 03:15 UTC
SELECT cron.schedule(
  'cleanup-old-stock-reservations',
  '15 3 * * *',
  $$
  DELETE FROM inventory.stock_reservation
  WHERE status IN ('EXPIRED', 'CONSUMED', 'RELEASED')
    AND updated_at < NOW() - INTERVAL '30 days'
  $$
);
```

---

<a id="cleanup-idempotency-keys"></a>
### `orders.idempotency_key`

Checkout idempotency keys have an `expires_at` retention limit. Stale keys waste storage and may cause false-duplicate blocks if reused.

```sql
-- daily at 03:20 UTC
SELECT cron.schedule(
  'cleanup-idempotency-keys',
  '20 3 * * *',
  $$DELETE FROM orders.idempotency_key WHERE expires_at < NOW()$$
);
```

---

<a id="cleanup-outbox-events"></a>
### `platform.outbox_event`

Published events are only needed for relay debugging. Delete after 7 days.

```sql
-- daily at 03:25 UTC
SELECT cron.schedule(
  'cleanup-outbox-events',
  '25 3 * * *',
  $$
  DELETE FROM platform.outbox_event
  WHERE publication_status = 'PUBLISHED'
    AND published_at < NOW() - INTERVAL '7 days'
  $$
);
```

---

<a id="cleanup-processed-events"></a>
### `platform.processed_event`

Consumer idempotency dedup window. Kafka default retention is 7 days; processed_event rows older than that can never be replayed.

```sql
-- daily at 03:30 UTC
SELECT cron.schedule(
  'cleanup-processed-events',
  '30 3 * * *',
  $$DELETE FROM platform.processed_event WHERE processed_at < NOW() - INTERVAL '7 days'$$
);
```

---

<a id="cleanup-fx-rates"></a>
### `pricing.fx_rate`

FX rate table is a display cache, not a financial ledger. Historical rates older than 90 days are not needed for display. Order snapshots (`fx_rate_used_at_capture` on `fulfillment_item`) are immutable columns, not FK references — deleting old `fx_rate` rows does not affect historical orders.

```sql
-- weekly on Sunday at 04:00 UTC
SELECT cron.schedule(
  'cleanup-fx-rates',
  '0 4 * * 0',
  $$DELETE FROM pricing.fx_rate WHERE created_at < NOW() - INTERVAL '90 days'$$
);
```

---

<a id="lift-expired-suspensions"></a>
### `seller.seller_profile` — timed suspension expiry

`suspended_until` is a non-null timestamp when suspension is temporary. This job lifts expired suspensions and publishes a Kafka event via the outbox. Profile update and outbox insert must be atomic — implemented as a PostgreSQL function.

```sql
CREATE OR REPLACE FUNCTION seller.lift_expired_suspensions() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT id FROM seller.seller_profile
    WHERE suspension_status = 'SUSPENDED'
      AND suspended_until IS NOT NULL
      AND suspended_until < NOW()
  LOOP
    UPDATE seller.seller_profile
    SET suspension_status = 'ACTIVE',
        suspended_until = NULL,
        updated_at = NOW()
    WHERE id = r.id;

    INSERT INTO platform.outbox_event (
      aggregate_type, aggregate_id, topic, event_type, event_version,
      payload, correlation_id, occurred_at, publication_status, attempt_count
    ) VALUES (
      'seller_profile', r.id, 'seller.suspension_expired', 'seller.suspension_expired', 1,
      jsonb_build_object('seller_profile_id', r.id),
      gen_random_uuid(), NOW(), 'PENDING', 0
    );
  END LOOP;
END;
$$;

-- every hour at :00
SELECT cron.schedule(
  'lift-expired-suspensions',
  '0 * * * *',
  $$SELECT seller.lift_expired_suspensions()$$
);
```
