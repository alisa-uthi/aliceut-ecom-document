# Data Lifecycle & Cleanup Jobs

Cross-phase convention for time-bounded data cleanup.

Phase-specific job inventory, schedules and retention windows: [phase-1/technical-design/cleanup-jobs.md](../phase-1/technical-design/cleanup-jobs.md)

---

## Summary

- [Convention](#convention)

<a id="convention"></a>
## Convention

- **Scheduling lives in the application, not in the database.** There is no in-database scheduler: PostgreSQL runs a stock image with no `pg_cron` and no scheduling extension, and no cleanup rule may require one. Adding an extension would mean maintaining a custom Postgres image for the sake of a crontab.
- Every job is an `@nestjs/schedule` declaration (`@Cron` or `@Interval`) hosted by the `workers` process.
- **Every job takes a `pg_advisory_lock` keyed on its own name** before doing work and releases it afterwards. Correctness therefore does not depend on `workers` running at a single replica; a run that fails to acquire the lock logs and returns rather than waiting.
- Business-logic cleanups — those that must update related rows, or publish an event, in the same transaction as the delete — call the exported application service of the module that owns the table. A scheduler never writes another module's schema directly.
- Retention deletes are batched and idempotent: each predicate is evaluated against the current clock, no cursor is persisted, and an interrupted run simply resumes on the next tick.
- No schedule, TTL or batch size is a literal. Each is read from an environment variable with the documented default as its fallback.
- Retention windows are chosen to cover the relevant TTL + a safety buffer for debugging.
- MongoDB collections are expired by their own TTL indexes rather than by a job. The TTL index is the single retention mechanism for those collections; a job issuing the same deletes would race the TTL monitor.
