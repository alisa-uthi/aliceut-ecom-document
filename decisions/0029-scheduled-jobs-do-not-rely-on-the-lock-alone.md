# ADR-0029: Scheduled jobs that send or emit do not rely on the advisory lock alone

**Status:** Accepted
**Date:** 2026-11-21
**Affects:** `phase-1/requirements/user-stories/platform.md` (US-P-15, US-P-16), `phase-1/technical-design/backend-module-architecture.md` (§ Scheduled tasks), `phase-1/technical-design/cleanup-jobs.md` (Job conventions, "Stores with no job here"), `phase-1/technical-design/data-model-erd.md` (`notifications.pending_listing_removal_digest`)
**Implemented by:** aliceut-ecom-backend (`workers` schedulers)

## Context

Every scheduled job takes a `pg_advisory_lock` keyed on its name, so a second
`workers` replica skips a run it cannot lock. [cleanup-jobs.md](../phase-1/technical-design/cleanup-jobs.md#job-conventions)
specifies that guard in full for the eleven retention jobs. For the other four
(the ET-09 digest, the FX refresh, the delivery mock and the suspended-seller
auto-refund) the specs said only that the lock exists, and for three of them the
lock was the **only** thing stopping a double effect:

- The digest "deletes exactly the rows it sent", but nothing said the rows are
  claimed before the send. Two overlapping runs could read the same rows and
  email a seller twice. Email is at-least-once already, so no consumer catches it.
- US-P-15 and US-P-16 call their jobs idempotent without saying the status change
  is conditional on the prior status. An unconditional `UPDATE` run twice writes
  two outbox rows. They get different `event_id`s, so consumer dedupe does not
  help, and a doubled `fulfillment.refund_suspended_seller` makes the inventory
  consumer restore stock twice.
- The four jobs had no named lock key, and nothing checked that the fifteen job
  names hash to distinct `hashtext` values.

A session-level advisory lock is not a guarantee: it is not held through a
connection pooler in transaction mode, `hashtext` is a 32-bit hash, and a
connection returned dirty keeps a lock it should have dropped.

## Decision

**The lock stays the first guard; the write must be safe without it.** A job that
sends mail or writes an outbox row also makes that write conditional on the state
it expects to find.

1. **Delivery mock (US-P-15)** transitions a fulfillment with
   `UPDATE orders.fulfillment SET status = 'DELIVERED', delivered_at = now(), updated_at = now() WHERE id = :id AND status = 'SHIPPED' RETURNING …`.
   The `fulfillment.delivered` outbox row is written in the same transaction and
   **only when the statement returned a row**.
2. **Auto-refund (US-P-16)** does the same with `WHERE id = :id AND status = 'PENDING'`
   and `refunded_at`; `fulfillment.refund_suspended_seller` is written only when a
   row was returned.
3. **Digest (ET-09)** claims before it sends. Per `seller_profile_id`, in one
   transaction: `SELECT … FROM notifications.pending_listing_removal_digest WHERE seller_profile_id = :id FOR UPDATE SKIP LOCKED`,
   send the email, `DELETE` exactly the claimed `id`s, commit. A second runner skips
   the locked rows. If the send fails the transaction rolls back and the rows wait
   for the next run. A crash between the send and the commit can still send a
   duplicate; that is the same at-least-once email contract every other
   notification has, and it is accepted.
4. **Lock keys are named.** The four jobs get the job names below, and every job
   name, retention and non-retention alike, is the string passed to
   `hashtext(:jobName)`. The scheduler registry asserts at boot that the names are
   unique and that their `hashtext` values are distinct, and fails startup if not.

   | Job | Lock key |
   |---|---|
   | ET-09 digest | `send-listing-removal-digest` |
   | FX refresh | `refresh-fx-rates` |
   | Delivery mock | `mock-delivery` |
   | Auto-refund | `auto-refund-suspended-sellers` |

The FX refresh needs no claim. It upserts in place on `(base_currency_code, quote_currency_code)`,
so an overlapping run writes the same rates. Each run still emits four
`fx_rate.updated` events; a duplicate pair costs extra reindexes, not wrong data,
and is accepted.

## Consequences

- The behaviour is stated once in each place that owns it: the two user stories,
  the ERD's digest table, § Scheduled tasks and cleanup-jobs.md. The code builds
  to those statements; nothing here needs a schema change.
- Holding a transaction open across an SMTP send is acceptable at V1 volume (one
  digest per affected seller per day). A slow SMTP server holds that seller's
  rows, not the table.
- Accepted risk: a duplicate digest after a crash between send and commit.

## Alternatives considered

**Rely on the advisory lock alone, as before.** Rejected: the lock fails open in
three ways listed above, and three of the four jobs then double-send or
double-emit with no second line of defence.

**Claim digest rows with `DELETE … RETURNING` before sending.** Rejected: a send
that fails after the delete loses the day's digest for that seller, which is worse
than an occasional duplicate.

**Add a `digest_sent_at` marker column.** Rejected for V1: it needs a migration
and a second sweep for the unmarked rows, to close a duplicate-on-crash window the
rest of the notification path already accepts.
