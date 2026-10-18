# ADR-0022: The seller's refund reason is stored on the fulfillment and carried on `fulfillment.refunded`

**Status:** Accepted
**Date:** 2026-10-18
**Affects:** `phase-1/technical-design/kafka-events.md` (§ 2.7), `phase-1/technical-design/api-design/seller.md` (Issue refund), `phase-1/technical-design/data-model-erd.md` (`orders.fulfillment`), `phase-1/technical-design/consumer-field-matrix.md` (§ 4, ET-04 row), `phase-1/requirements/user-stories/email-templates.md` (ET-04)
**Implemented by:** aliceut-ecom-backend (PR linked in `spec-compliance.md`)

## Context

`POST /seller/orders/:fulfillmentId/refund` requires a `reason` (max 500
chars, US-S-07:144) "so the buyer is told why". The handler validated it and
then dropped it: `orders.fulfillment` had no column for it, the § 2.7
`fulfillment.refunded` schema had no field for it, and ET-04 had no place to
show it. The cancel path does carry its reason (`fulfillment.cancelled`
`reason`, ET-16). The user decided on 2026-10-18 that the refund reason is
carried in the event, as the cancel reason is.

## Decision

1. **Storage.** `orders.fulfillment` gains a nullable `refund_reason TEXT`
   with `CHECK (char_length(refund_reason) <= 500)`. The refund handler writes
   it in the same `UPDATE` that sets `status = 'REFUNDED'`.
2. **Event.** § 2.7 gains `reason`, `["null","string"]` with `default: null`.
   Adding an optional field with a default is `BACKWARD`-compatible, so
   `event_version` stays 1 and the subject registers as a new version through
   the existing CI and `schema-init` paths (ADR-0012); no infra change is
   needed. The handler writes the value in the outbox row inside the refund
   transaction.
3. **Consumer.** The `notification.fulfillment-refunded` group renders ET-04
   with a "Seller's reason" block taken from `payload.reason`, and omits the
   block when it is null. It never reads `orders.*`.
4. **Scope.** `fulfillment.refund_suspended_seller` is unchanged: the
   auto-refund has no seller-typed reason. `refund_reason` stays null for it.
5. **Replay.** A refund replay against an already-`REFUNDED` fulfillment
   changes nothing, including the stored reason; no second event is written.

## Consequences

- **Audit masking.** `platform.audit` writes this payload to `activity_events`
  through the shared `maskSensitive` list. `reason` is seller-authored free
  text about the seller's own action, as `reason` on `fulfillment.cancelled`
  is, and is not on the list, so it is stored unmasked. No other field is
  added.
- **Free text reaches the buyer.** The reason is shown verbatim in an email.
  Plain-text rendering is the only output encoding in V1; an HTML email
  would have to escape it.
- **Events published before this change** have no `reason`. A reader decodes
  null and omits the block. Every database was rebuilt (ADR-0014), so the
  migration carries no backfill.
- The missing `offer_id` / `product_id` on `RefundedItem` is a separate gap and
  is untouched here.

## Alternatives considered

**Leave the reason unstored.** The status quo: the seller is made to type a
sentence that goes nowhere. Rejected by the user.

**Let the notification consumer read `orders.fulfillment`.** Avoids a schema
change but makes a consumer read another module's table, which the consumer
contract forbids. Rejected.

**A required field.** Not `BACKWARD`-compatible, and it would break replay of
events already in the topic.
