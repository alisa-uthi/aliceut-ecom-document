# ADR-0029: `seller.reinstated` carries `admin_user_id`

**Status:** Accepted
**Date:** 2026-10-23
**Affects:** `phase-1/technical-design/kafka-events.md` (§ 2.15), `phase-1/technical-design/consumer-field-matrix.md` (`seller.reinstated` row), `phase-1/technical-design/api-design/admin.md` (reinstate seller sequence)
**Implemented by:** aliceut-ecom-backend, not yet written: `libs/contracts/avro/seller.reinstated.avsc`, the reinstate command's outbox payload (admin module), the `platform.audit` consumer

## Context

Every other event that names the acting admin calls the field `admin_user_id`:
`seller.suspended` (§ 2.3), `moderation.listing.removed` (§ 2.14), `listing.flagged`,
`seller.suspension_amended`. `seller.reinstated` alone calls it `admin_id`.
The consumer-field matrix lists the field per event, so the audit consumer
needs a special case for this one event, and a reader of the catalog cannot
tell whether `admin_id` is a user id or an admin-profile id. It is a user id
(`identity.user`), as in every peer.

The subject `seller.reinstated` is already registered by CI under BACKWARD
compatibility ([ADR-0012](0012-avro-subjects-registered-by-ci-and-schema-init.md),
`conventions/kafka-events.md`). A rename is a removal plus an addition, so it
cannot be made in place.

## Decision

1. `SellerReinstatedPayload` gains `admin_user_id` (`string`, UUID of
   `identity.user`, the admin who lifted the suspension). It is the audit
   document's `actor_id`.
2. `admin_id` stays in the schema, retyped `["null","string"]` with
   `default null` and documented DEPRECATED (this ADR). Both changes are
   BACKWARD-compatible: a union that contains the old type reads old data, and
   a defaulted field reads data written without it. The same pattern as
   `buyer_business_logo_url` ([ADR-0023](0023-event-logos-carry-an-object-key-the-consumer-presigns.md)).
3. `admin_user_id` is declared `["null","string"]` with `default null`,
   because a field added to a registered subject needs a default; a record
   written before this change reads it as null. The producer always sets it,
   so a record produced after this change never carries null. For the
   transition the producer also writes the same id into `admin_id`.
   Consumers read `admin_user_id`, and use `admin_id` only when it is null.
4. `admin_id` is removed by a later ADR, once consumers have been drained off
   it (consumer-first, per the schema-revision rules). Nothing in this ADR
   removes it.
5. `consumer-field-matrix.md` lists `payload.admin_user_id` as the
   `seller.reinstated` actor. `admin.md` names `admin_user_id` in the outbox
   payload.

## Consequences

- `libs/contracts/avro/seller.reinstated.avsc` changes with `kafka-events.md`
  § 2.15; the backend schema test compares them and fails until both agree.
- Events already in the topic, or in `platform.outbox_event` unsent, carry only
  `admin_id`. The audit consumer falls back to `admin_id` when `admin_user_id` is null,
  until the topic's retention window has passed; the fallback is deleted with
  the field.
- The generated clients are not affected: this is an event, not an API shape.
- No migration. The outbox payload is JSON built in application code.

## Alternatives considered

**Rename in place.** Rejected: breaks BACKWARD for the registered subject.

**New `event_version` or new topic.** Rejected: a second topic and a second
consumer group for one field name.

**Rename the peers to `admin_id`.** Rejected: four registered subjects to
change instead of one, and `admin_user_id` states which id it is.

**Keep the divergence.** Rejected: it is a standing special case in the audit
consumer for no benefit.
