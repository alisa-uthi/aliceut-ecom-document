# ADR-0020: `confirmedPrices[]` is mandatory on every `POST /orders` submission

**Status:** Accepted
**Date:** 2026-10-18
**Affects:** `phase-1/technical-design/api-design/orders.md` (Place order: request body, Price revalidation, Errors, sequence), `phase-1/ui-design/buyer-portal.md` (§ checkout submit)
**Implemented by:** aliceut-ecom-backend (checkout DTO and service), aliceut-ecom-frontend (generated client and checkout caller)

## Context

`confirmedPrices[]` was the buyer's acknowledgement after a `409
PRICE_CHANGED`, and was omitted on a first submission. `cart_item` stores no
price the buyer was shown, so a line with no `confirmedPrices` entry had
nothing to compare against: a first checkout charged whatever the price
resolved to at submit time, with no `PRICE_CHANGED` check. A price that moved
between the cart view and the click was charged silently, which US-B-09:210-211
forbids ("an order is never created at a price the buyer has not seen").
`spec-compliance.md` recorded the gap and named two options: snapshot the
shown price in the cart, or make `confirmedPrices` mandatory.

## Decision

The user chose to make it mandatory. **Every** `POST /orders` submission, the
first included, carries a `confirmedPrices[]` entry `{ offerId, amount,
currency }` for **every** `cartItems` line: the unit price the buyer was
shown, as the server rendered it. The server re-resolves each line and
compares within `CHECKOUT_PRICE_TOLERANCE`; a difference, or a different
currency, is the existing `409 PRICE_CHANGED`, and the client re-submits with
the acknowledged amounts and the same `Idempotency-Key`.

- A `cartItems` line with no entry is `400` in the api-conventions error shape
  with an `errors[]` entry whose `field` is `confirmedPrices` and whose message
  names the offer. An absent, empty or malformed `confirmedPrices` is `400`
  from request validation. No order is created.
- The entry is keyed by `offerId`. Lines skipped as stale (offer no longer
  `ACTIVE`) still need an entry: the check is on the submitted lines, before
  the skip, because the client cannot know a line is stale at the moment a
  race makes it so.
- An entry whose `offerId` matches no `cartItems` line is **ignored**, as the
  existing Price revalidation text already says ("matches no re-resolved line
  ... is treated as unconfirmed"): it confirms nothing and is not an error.
  Two entries for the same `offerId` are `400`.
- Idempotency is unchanged. The request body is already hashed, so a body
  with `confirmedPrices` is simply a different body from one without.

## Consequences

**No unchecked first checkout.** The price a buyer saw is the price compared,
on every submit.

**The request grows a required field.** The generated client changes shape;
the buyer app sends entries from the cart's `effectivePrice` for all lines.

**Old clients break.** A client that omitted the field now gets `400`. Every
database and client is in this repo set, so none is expected in the wild.

**No cart schema change.** The cart still stores no shown price; the client
is the source of the shown amount, the server the judge.

## Alternatives considered

**Snapshot the shown price on the cart item.** Rejected by the user: a new
column and write path, and the cart's price can still drift from what the
page rendered.

**Optional but defaulting to the cart's current price.** Rejected: that
compares the price to itself and checks nothing.
