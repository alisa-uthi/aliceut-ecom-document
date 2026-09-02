# Data Lifecycle & Cleanup Jobs

Cross-phase convention for time-bounded data cleanup using `pg_cron`.

**Source of truth:** [BRD v1.1](../phase-1/requirements/BRD.md), [data-model-erd](../phase-1/technical-design/data-model-erd.md), [auth-jwt-design](./auth-jwt-design.md)

---

## Convention

- All time-bounded rows are cleaned via `pg_cron` jobs — not application-layer cron.
- Business-logic cleanups (those that must update related rows in the same transaction) use a dedicated PostgreSQL function called by `pg_cron`.
- Simple deletes run inline SQL via `pg_cron`.
- Retention windows are chosen to cover the relevant TTL + a safety buffer for debugging.
