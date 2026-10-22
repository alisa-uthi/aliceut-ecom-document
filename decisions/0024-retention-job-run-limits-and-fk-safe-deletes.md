# ADR-0024: Retention jobs are throttled and capped, and deletes are foreign-key safe

**Status:** Accepted
**Date:** 2026-10-22
**Affects:** `phase-1/technical-design/cleanup-jobs.md` (Job conventions, `identity.refresh_session`, `orders.idempotency_key`), `phase-1/technical-design/data-model-erd.md` (`identity.refresh_session`, `orders.order`, `orders.payment_attempt`, `platform.processed_event`), `phase-1/technical-design/docker-compose-topology.md` (env), `conventions/database-migrations.md` (SQL rules), `conventions/backend-coding-standards.md` (§ 6.2)
**Implemented by:** aliceut-ecom-backend (migrations 0021–0028, `apps/workers` cleanup scheduler), aliceut-ecom-infra (workers env)

## Context

Seven retention deletes in `cleanup-jobs.md` had no implementation
(`spec-compliance.md`, entry 3). Building them to the letter of the spec and
reviewing the result against the real schema found four defects in the design
itself, not in the code:

1. **`orders.idempotency_key` could never be cleaned.** `orders.order` and
   `orders.payment_attempt` reference it with plain `NO ACTION` foreign keys,
   and every checkout sets those columns. The first expired key that belonged
   to a placed order made the batch fail with a foreign-key violation, so the
   job deleted nothing, every night.
2. **`identity.refresh_session` could wedge the same way.** `replaced_by_id` is
   a self-referencing `NO ACTION` foreign key. A batch that deleted a successor
   but left its ancestor failed. Ordering the batch by `revoked_at` does not
   prevent it: reuse detection and logout-all revoke a whole family with one
   `UPDATE`, so the rows share a `revoked_at` and the `LIMIT` can cut between
   them.
3. **Predicates had no index.** Without one, each batch is a sequential scan and
   the final short batch scans the whole table to prove nothing else is due.
   `processed_event` (one row per consumed event per group) and
   `refresh_session` are the large tables. The foreign keys above were also
   unindexed on the referencing side, so each deleted row cost a scan of
   `orders.order`.
4. **A run was unbounded.** Batching bounds one statement, not a run: batches
   ran back to back for as long as rows were due, sustaining WAL and I/O, and a
   `CLEANUP_BATCH_SIZE` of `0` made "fewer than the batch size" unreachable, so
   the loop never ended.

Fixing (3) needed `CREATE INDEX CONCURRENTLY` on populated tables, which
`database-migrations.md` said to run with `migration:run --transaction none`.
That flag removes the atomic "SQL plus history row" step from every migration
in the run, not only the one that needs it.

## Decision

1. **Both foreign keys into `orders.idempotency_key` become `ON DELETE SET NULL`**
   (migration 0021). The order is an immutable financial record; the key is a
   replay guard that expires. `replaced_by_id` becomes `ON DELETE SET NULL`
   (migration 0028): it is lineage metadata for investigation, and
   `cleanup-jobs.md` already says family revocation does not walk it. Deletion
   order no longer matters, so the refresh-session delete stays the spec's single
   `OR` statement.
2. **Indexes** (migrations 0022–0027): the three foreign-key probe columns
   (`refresh_session.replaced_by_id`, `order.idempotency_key_id`,
   `payment_attempt.idempotency_key_id`, each partial on `IS NOT NULL`),
   `processed_event (processed_at)`, and one partial index per refresh-session
   arm (`revoked_at`, and `expires_at WHERE revoked_at IS NULL`). The tables
   whose cleanup reads a bounded or small set (`email_verification_token`,
   `password_reset_token`, `stock_reservation`, `in_app_notification`) get none
   at V1 volume.
3. **A run is throttled and capped.** `CLEANUP_BATCH_PAUSE_MS` (default 50,
   minimum 0) is slept between batches and not after the last.
   `CLEANUP_MAX_BATCHES_PER_RUN` (default 1000, minimum 1) ends a run, which logs
   `capped: true` and leaves the rest for the next tick. `CLEANUP_BATCH_SIZE` is
   validated 1–10000.
4. **The failure log carries `deleted` and `batches`** for every job, as the
   Failed row of the observability table already required. And a failed
   `pg_advisory_unlock` destroys the lock connection instead of returning a
   session that still holds the lock to the pool.
5. **Migrations run in `each` mode.** The phase-1 DataSource sets
   `migrationsTransactionMode: 'each'`. A migration that cannot be transactional
   sets `public transaction = false` on its class; `--transaction none` is not
   used. `migration:revert` ignores the class flag, so every down is
   transaction-safe (plain `DROP INDEX IF EXISTS`). `CREATE INDEX CONCURRENTLY`
   is preceded by a separate `DROP INDEX CONCURRENTLY IF EXISTS`, so a failed
   build cannot leave an `INVALID` index that `IF NOT EXISTS` would skip.
   `0021` and `0028` split `ADD … NOT VALID` from `VALIDATE CONSTRAINT` so the
   scan holds only `SHARE UPDATE EXCLUSIVE`.
6. **`JWT_REFRESH_TTL_SECONDS` is a `workers` setting** and must equal the `api`
   value. Compose passes it explicitly.

## Consequences

- Expiring an idempotency key, or deleting a session, loses the pointer from the
  surviving row. An investigator can no longer walk a token family past a
  deleted ancestor, which the retention window already bounded.
- Six new indexes cost writes. `ix_refresh_revoked_at` stops rotation's
  `revoked_at` update being a HOT update; `ix_processed_event_processed_at`
  adds an append-only index to the hottest insert path. Accepted: the
  alternative is a full scan of the largest table every night.
- A run against a large backlog takes longer in wall-clock terms and may need
  several ticks to drain. The spec already allowed that.
- The `down` of `0021` and `0028` re-adds the foreign key and validates it in
  one transaction (revert always wraps), holding the heavier lock through the
  scan. Accepted on the revert path.
- Not enforced in code: `PROCESSED_EVENT_RETENTION_DAYS` strictly greater than
  Kafka log retention remains a documented rule only.
- No real-Postgres automated test of the retention SQL exists; the repo has no
  testcontainers setup yet (`testing-guidelines.md` § 4.2). The CI `migrations`
  job asserts the three foreign keys are `SET NULL` and validated after apply.

## Alternatives considered

- **Skip referenced keys (`AND NOT EXISTS`) in the idempotency delete.** Keeps
  the foreign key strict, but a key with an order is never deleted, so the table
  grows with orders, and it needs the same two indexes anyway.
- **Order the refresh-session batch and guard against surviving pointers.**
  Works only if no two rows share a `revoked_at`, which one family revocation
  breaks; with a guard it peels one link per batch and "short batch means
  drained" stops being true.
- **Leave `--transaction none` global.** Smaller change, but every migration
  loses its atomic history record, and a crash between the SQL committing and
  the history insert leaves a migration applied but unrecorded.
- **No throttle or cap.** Matches the spec as it stood. Rejected because the
  first run against a long-accumulated table would saturate the primary and
  replicas.
